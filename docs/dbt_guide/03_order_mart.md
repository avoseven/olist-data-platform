# 3. 注文単位の mart

[fct_delivered_orders.sql](../../dbt/models/marts/fct_delivered_orders.sql) を見る。staging の 5 つのテーブルを結合して、注文単位の表を作るモデル。
列の定義は [customer_features.md](../customer_features.md) の「fct_delivered_orders の列」、処理の方針は [ADR 006](../decisions/006_mart_design.md) を参照。

## このモデルの役割

配達済み (delivered) の注文について、**1 行 = 1 注文**の表を作る。注文ごとの金額・支払い・レビュー・配送日数を 1 行にまとめる。
第4章の `customer_features` (顧客単位) は、この表を元に集計する。

```
stg_orders ─────────┐
stg_customers ──────┤
stg_order_items ────┼──→ fct_delivered_orders ──→ customer_features
stg_order_payments ─┤        (1 行 = 1 注文)        (1 行 = 1 顧客)
stg_order_reviews ──┘
```

- staging (dbt で作ったモデル) を読むため、`source()` ではなく **`ref()`** を使う (例: `{{ ref('stg_orders') }}`)。
- dbt は `ref()` を見て、「staging を先に作り、その後にこのモデルを作る」という順番を自動で決める。
- mart は table の設定のため、計算した結果が `olist_mart.fct_delivered_orders` に保存される。

## CTE の流れ

```
orders              配達済みの注文だけに絞る           (1 行 = 1 注文)
customers           必要な列だけ取る                   (1 行 = 1 customer_id)
items_per_order     明細を注文ごとに集計する           (1 行 = 1 注文)
payments_per_order  支払いを注文ごとに集計する         (1 行 = 1 注文)
valid_reviews       紐付けがおかしいレビューを除く
adopted_reviews     1 注文につきレビューを 1 件選ぶ    (1 行 = 1 注文)
final               orders を軸に全部つなぎ、計算した列を足す
```

**結合する前に、すべてを「1 行 = 1 注文」にそろえている。** 各 CTE の先頭に `-- 1 行 = 1 注文` のコメントがあるのはそのため。

## 先に集計してから結合する理由 (二重計上の防止)

明細と支払いは、どちらも 1 つの注文に複数行あり得る。そのまま結合すると、行が掛け算で増える。

実データの注文 `03ecec245220b63fd7f68c1737ba99ba` (明細 2 行、支払い 2 回) の例:

| 結合のしかた | 行数 | 価格の合計 |
|---|---:|---:|
| 明細と支払いを、そのまま結合して合計 | 2 × 2 = **4 行** | **597.80** (2 倍になる) |
| 明細を先に注文ごとに集計してから結合 (このモデル) | 1 行 | **298.90** (正しい) |

明細の 1 行ごとに支払いの 2 行がくっつくため、同じ明細が 2 回数えられる。
そこで、`items_per_order` と `payments_per_order` で先に `group by order_id` して 1 注文 1 行にしてから結合する。

## 集計で使っている関数

```sql
-- items_per_order
count(*)            as item_count        -- 明細の行数
sum(price)          as items_amount      -- 価格の合計
sum(freight_value)  as freight_amount    -- 送料の合計

-- payments_per_order
logical_or(payment_type = 'credit_card') as has_credit_card_payment
max(
    case
        when payment_type = 'credit_card' and payment_installments >= 1
            then payment_installments
    end
) as max_card_installments
```

- **`logical_or(条件)`**: グループの中で、条件が 1 行でも TRUE なら TRUE。「カード払いが 1 回でもあったか」を表す。
- **`max(case when ... then 値 end)`**: 条件に合う行の値だけを残し (合わない行は NULL)、その最大値を取る。`max` は NULL を無視するため、「条件に合う行の中での最大」になる。ここでは「分割回数が 1 以上のカード払いの、最大の分割回数」。

### dbt の関数と、BigQuery の SQL の関数の違い

`logical_or()` は SQL の関数で、`source()` や `ref()` (dbt の関数) とは別物。

| | `source()`、`ref()` | `logical_or()` |
|---|---|---|
| 正体 | dbt (Jinja) の関数 | BigQuery の SQL の関数 (集計関数) |
| 誰が処理するか | dbt が、送る前に書き換える | BigQuery が実行する |
| BigQuery に送る SQL に残るか | 残らない (テーブル名に置き換わる) | そのまま残る |
| 見分け方 | `{{ }}` の中にある | `{{ }}` の外にある |

SQL には、どの製品にも共通の基本部分 (`select`、`sum`、`count`、`join` など) と、製品ごとの独自の関数や書き方 (方言) がある。`logical_or` は BigQuery の方言で、同じ処理でも製品によって名前が違う。

| 製品 | 「1 行でも TRUE なら TRUE」の関数 |
|---|---|
| BigQuery | `logical_or` |
| PostgreSQL | `bool_or` |
| Snowflake | `boolor_agg` |

このモデルでは、`qualify`、`date_diff(..., day)`、`` `プロジェクト`.`データセット`.`テーブル` `` の書き方も BigQuery の方言。別の製品に移すときは、SQL の書き換えが必要になる。

## レビューを 1 件に絞る (qualify row_number())

1 つの注文に、レビューが複数付くことがある。2 段階で 1 件に絞る。

1. **`valid_reviews`**: 作成日が購入日より前のレビューは、注文との紐付けが疑わしいため除く。購入日を使うため、ここだけ `orders` と `inner join` している。その結果、配達済みの注文のレビューだけが残る。
2. **`adopted_reviews`**: 注文ごとに、最新の回答を 1 件選ぶ。

```sql
qualify row_number() over (
    partition by order_id                                        -- 注文ごとに分けて
    order by review_answered_at desc nulls last, review_id asc   -- 新しい順に並べ
) = 1                                                            -- 1 番目だけ残す
```

- **`row_number() over (partition by ... order by ...)`** はウィンドウ関数。行をまとめずに、グループの中での順位 (1, 2, 3, …) を各行に付ける。
- **`qualify`** は、ウィンドウ関数の結果で行を絞る BigQuery の書き方。`where` ではウィンドウ関数を使えないため、こう書く。
- `review_id asc` は、回答日時が同じだったときに、毎回同じ 1 件が選ばれるようにするための並べ方。

## 結合 (final) と、LEFT JOIN にする理由

```sql
from orders
left join customers
    on orders.customer_id = customers.customer_id
left join items_per_order as items
    on orders.order_id = items.order_id
left join payments_per_order as payments
    on orders.order_id = payments.order_id
left join adopted_reviews as reviews
    on orders.order_id = reviews.order_id
```

- **`orders` を軸にして、ほかを横にくっつける。** どの相手も 1 注文 1 行のため、行は増えない。
- **LEFT JOIN は、相手がない注文も残す (相手の列は NULL になる)。** レビューのない注文や、支払いのレコードがない注文 (実データで 1 件) も、注文としては残したいため LEFT JOIN にする。INNER JOIN にすると、そうした注文が消える。

## 計算で足す列

```sql
date(orders.order_purchased_at)                         as order_purchase_date
items.items_amount + items.freight_amount               as total_amount
date_diff(配達日, 購入日, day)                            as delivery_days
date_diff(配達日, 配送予定日, day)                        as delivery_delay_days   -- プラスなら遅れ
date(配達日時) > orders.order_estimated_delivery_date    as is_late_delivery
```

- 時刻を落として日付どうしで差を取るため、「何日かかったか」が日単位でそろう。
- 配達日時がない注文 (配達済みなのに欠けている例外) では、結果が自動的に NULL になる。NULL を含む計算は NULL になるため。
- `is_late_delivery` のように、比較の結果 (TRUE / FALSE) をそのまま列にもできる。

## _marts.yml のテスト

書き方は第2章と同じ。このモデルで特に意味があるのは次の 2 つ。

- **`order_id` の `unique`**: 結合で行が増えていない (1 行 = 1 注文が守られている) ことの確認になる。二重計上が起きると、ここで不合格になる。
- **`has_credit_card_payment` の `not_null` (warn)**: 支払いのレコードがない 1 件の注文は既知の例外のため、警告にしている ([data_notes.md](../data_notes.md))。

## まとめ

```
ref() で staging を読む (dbt が作る順番を決める)
結合する前に、明細・支払い・レビューを「1 行 = 1 注文」に集計する (二重計上を防ぐ)
レビューは qualify row_number() で 1 件に絞る
orders を軸に LEFT JOIN し、相手がない注文も残す
order_id の unique テストで「1 行 = 1 注文」を確認する
{{ }} の中は dbt の関数、外は BigQuery の SQL (方言を含む)
```
