# 4. 顧客単位の mart

[customer_features.sql](../../dbt/models/marts/customer_features.sql) を見る。第3章の `fct_delivered_orders` (1 行 = 1 注文) を元に、顧客単位の特徴量を作るモデル。
列の定義は [customer_features.md](../customer_features.md)、設計の原則 (以下の「原則 1〜4」) は [ADR 007](../decisions/007_customer_feature_principles.md) を参照。

## このモデルの役割

**1 行 = 1 人**の特徴量の表を作る。セグメント分けや分析の入力になる。

- 「人」は `customer_unique_id` で数える。`customer_id` は注文ごとに発行されるため、人を数えるのには使えない。
- 対象は、delivered の注文を 1 件以上持つ人。

## CTE の流れ: 粒度をそろえてから結合する

第3章と同じ考え方を、一段上の「顧客単位」で繰り返している。

```
orders                   fct_delivered_orders を読む          (1 行 = 1 注文)
reference                基準日 (最後の購入日)                 (1 行だけ)

category_items           明細 + 商品 + カテゴリ名              (1 行 = 明細 1 行)
customer_categories      顧客 × カテゴリごとに集計             (1 行 = 顧客 × カテゴリ)
category_features        カテゴリ数、いちばん多いカテゴリ       (1 行 = 1 人)

customer_payment_types   顧客 × 支払い方法ごとに集計           (1 行 = 顧客 × 支払い方法)
payment_type_features    いちばん多い支払い方法                (1 行 = 1 人)

customer_reviews         同じレビューの重複を除く               (1 行 = 顧客 × レビュー)
review_features          レビューの平均                        (1 行 = 1 人)

order_features           注文単位の値を顧客ごとに集計          (1 行 = 1 人)
final                    order_features を軸に全部つなぐ
```

### カテゴリなどを別の流れで集計する理由

注文の数や金額を数える部分と、カテゴリを数える部分は、別々の流れになっている。

```
orders (1 行 = 1 注文)
  │
  ├─→ order_features        注文の数、金額 など      ← 明細を結合しない
  │
  └─→ category_items        明細を結合する
        → customer_categories
        → category_features  カテゴリ数、いちばん多いカテゴリ
```

`order_features` の中で明細も結合し、1 回の `group by` で全部を計算しない理由を、例で示す。ある人の注文が 2 件あるとする。

| 注文 | 明細 | 注文の金額 (`items_amount`) |
|---|---|---:|
| A | 本 30、本 30 | 60 |
| B | おもちゃ 40 | 40 |

正しい値は、注文の数 2、金額の合計 100。カテゴリを知るために明細を結合すると、行が明細の数 (3 行) に増える。

| 注文 | `items_amount` | 明細のカテゴリ |
|---|---:|---|
| A | 60 | 本 |
| A | 60 | 本 |
| B | 40 | おもちゃ |

この 3 行のまま集計すると、注文 A が 2 回数えられる。

| 計算 | 結果 | 正しい値 |
|---|---:|---:|
| `count(*)` (注文の数のつもり) | 3 | 2 |
| `sum(items_amount)` (金額の合計のつもり) | 60 + 60 + 40 = 160 | 100 |

第3章の「明細 × 支払い」の二重計上と同じ問題。そこで次のように分けている (原則 1)。

- **`order_features`**: 明細を結合せず、注文の表のまま集計する。注文の数と金額が正しくなる。
- **`category_items` → `customer_categories` → `category_features`**: 明細を結合して、カテゴリ専用に集計し、最後に 1 人 1 行にする。
- **`final`**: 1 人 1 行どうしになった両方を結合する。行は増えない。

支払い方法・レビューも、同じ理由で別の流れにしている。

## 代表値の選び方: array_agg(... order by ... limit 1)[offset(0)]

「いちばん多く買ったカテゴリ」のような代表値は、次のように書く。

```sql
array_agg(
    category_name
    order by order_count desc, items_amount desc, product_category_name asc
    limit 1
)[offset(0)] as top_category
```

`array_agg()` は BigQuery の SQL の集計関数で、**グループの中の値を 1 つの配列 (値のリスト) にまとめる**。

ある人の `customer_categories` が次のようだったとする。

| category_name | order_count | items_amount |
|---|---:|---:|
| toys | 1 | 40 |
| books | 2 | 60 |
| garden | 1 | 80 |

指定を少しずつ足していくと、結果は次のように変わる。

| 書き方 | 結果 |
|---|---|
| `array_agg(category_name)` | `[toys, books, garden]` (順番は決まらない) |
| `array_agg(category_name order by order_count desc, items_amount desc, ...)` | `[books, garden, toys]` (注文が多い順。toys と garden は注文数が同じため、金額が多い garden が先) |
| `... limit 1)` | `[books]` (先頭の 1 つだけの配列) |
| `...)[offset(0)]` | `books` (配列から取り出した、ただの値) |

- **`[offset(0)]`** は、配列の 0 番目の要素を取り出す書き方。番号は 0 から数える (1 から数える `[ordinal(1)]` という書き方もある)。配列のままでは列の値として扱いにくいため、最後に中身を 1 つ取り出す。
- **`max()` では求められない。** `max(category_name)` は名前の辞書順で最大のもの (例では toys) を返すだけで、注文数を見ない。この書き方なら、「別の列で並べた先頭の値」を `group by` の集計の中で取れる。
- **並べ方を 3 段階まで書く理由:** 注文数が同じカテゴリが 2 つあると、どちらを選ぶかが実行のたびに変わる可能性がある。同数のときの決め方まで指定して、結果が毎回同じになるようにする (原則 4)。

第3章の `qualify row_number() ... = 1` でも同じ結果を出せる。`qualify` は行を絞る書き方 (レビューの行を 1 件だけ残したいとき)、`array_agg` は集計の中で値を 1 つ取る書き方 (ほかの集計と一緒に `group by` で計算したいとき) と使い分ける。

`customer_state` (最後の注文の州) と `main_payment_type` (いちばん多い支払い方法) も、同じ書き方。

## 数え方: count(*) と count(distinct ...)

```sql
count(*)                             as order_count          -- 注文の数 (行の数)
count(distinct order_purchase_date)  as purchase_day_count   -- 購入した「日」の数
```

- `count(distinct 列)` は、重複を除いた値の種類の数を数える。
- 同じ日に 2 件の注文 (出品者ごとに分かれた 1 回の買い物) がある人は、`order_count = 2`、`purchase_day_count = 1` になる。リピーターの判定には後者を使う ([ADR 013](../decisions/013_repeat_customer_definition.md))。

  ```sql
  order_features.purchase_day_count >= 2 as is_repeat_customer
  ```

- `customer_categories` の `count(distinct order_id)` も同じ理由。1 つの注文に同じカテゴリの明細が 2 つあっても、注文は 1 回と数える。

## 平均の取り方は 2 通りある (原則 2)

```sql
avg(items_amount)                     as avg_order_items_amount  -- 注文ごとの金額の平均
sum(items_amount) / sum(item_count)   as avg_item_price          -- 合計どうしの比
```

例: 注文 A (商品 1 個、100)、注文 B (商品 4 個、合計 100) の人の、平均単価。

| 計算 | 結果 | 意味 |
|---|---:|---|
| 注文ごとの平均単価 (100 と 25) の平均 | 62.5 | 注文を 1 票ずつ数える |
| 合計の金額 ÷ 合計の個数 = 200 ÷ 5 | 40 | 商品を 1 個ずつ数える |

どちらも「平均単価」と呼べるが、結果が違う。そのため、どの単位を基準にするかを決めて、コメントに書いている。

## NULL の扱いと、TRUE / FALSE を割合にする方法 (原則 3)

```sql
avg(cast(is_late_delivery as int64))  as late_delivery_ratio   -- 遅延した注文の割合
logical_or(has_voucher_payment)       as has_used_voucher      -- 1 回でも使ったか
```

- **`cast(TRUE/FALSE as int64)`** で TRUE を 1、FALSE を 0 にしてから平均を取ると、「TRUE の割合」になる。例: 3 注文のうち 1 件が遅延なら、(1 + 0 + 0) / 3 = 0.33。
- **`avg` や `logical_or` は NULL を無視する。** 配達日時がない注文は除いて計算され、すべての注文が NULL なら結果も NULL になる。0 として数えると割合が下がるため、この動きのままにしている。

## レビューの重複を除く (select distinct)

```sql
select distinct customer_unique_id, review_id, review_score
from orders
where review_id is not null
```

1 つのレビュー (アンケート回答) が、同じ人の複数の注文に紐づくことがある。そのまま平均すると、同じ回答が 2 回数えられる。`select distinct` で「顧客 × レビュー」を 1 行にしてから平均する。

## 基準日と cross join

```sql
reference as (
    select max(order_purchase_date) as reference_date from orders   -- 1 行だけの表
),
...
from order_features
cross join reference      -- 全員の行に、同じ基準日をくっつける
```

- `cross join` は結合条件なしで、すべての組み合わせを作る。相手が 1 行だけのため、全員の行に同じ基準日が付くだけになる。
- 基準日は、最後の購入からの日数 (`days_since_last_purchase`) などの計算に使う。今日の日付を使うと実行する日によって値が変わるため、データの最終日を基準にする ([ADR 006](../decisions/006_mart_design.md) の D)。

## 結合 (final)

```sql
from order_features                   -- 全員がいる (delivered の注文を持つ人)
cross join reference
left join category_features ...       -- カテゴリがわかる商品を買っていない人はいない
left join payment_type_features ...   -- 支払いのレコードがない人はいない
left join review_features ...         -- レビューがない人はいない
```

第3章と同じく、全員がそろっている `order_features` を軸にして LEFT JOIN する。相手にいない人は、その列が NULL になる (例: レビューがない人の `avg_review_score`)。

## まとめ

```
fct_delivered_orders (1 行 = 1 注文) から、1 行 = 1 人 を作る
明細やカテゴリなど細かい粒度の情報は、別の流れで集計し、1 人 1 行にしてから結合する
代表値は array_agg(... order by ... limit 1)[offset(0)] で、同数のときの順番まで決める
count(distinct) で重複を除いて数える (購入日数、カテゴリの注文数)
平均は「注文ごとの平均」と「合計どうしの比」を使い分ける
TRUE/FALSE は int64 にして平均すると割合になる。NULL は除いて計算する
基準日はデータの最終日 (1 行) を cross join で全員に付ける
```
