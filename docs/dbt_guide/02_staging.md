# 2. staging のモデル

staging のモデルの例として、[stg_orders.sql](../../dbt/models/staging/stg_orders.sql) と、その説明・テストを書いた [_staging.yml](../../dbt/models/staging/_staging.yml) を見る。
ほかの 6 つの staging のモデルも、同じ書き方になっている。

## staging の役割

raw のテーブルは、CSV を全列 STRING (文字列) のまま読み込んだもの。staging では、**型と名前を整えるだけ**の加工をする。

| やること | やらないこと (mart で行う) |
|---|---|
| 型の変換 (文字列 → 日時など)、列名をそろえる | 行を絞る、別のテーブルと結合する、集計する |

そのため、raw と staging は 1:1 で、行数も変わらない。層ごとの役割は [ADR 002](../decisions/002_layer_architecture.md) を参照。

## stg_orders.sql の構成

```sql
with source as (
    select * from {{ source('olist', 'orders') }}   -- ① 元データを取ってくる
),

renamed as (
    select                                          -- ② 型と名前を整える
        order_id,
        customer_id,
        order_status,
        cast(order_purchase_timestamp as datetime) as order_purchased_at,
        ...
    from source
)

select * from renamed                               -- ③ 最後の結果を返す
```

- **書くのは SELECT 文だけ。** `CREATE VIEW` は dbt が付ける (第1章の「用語: モデル」)。staging は view の設定のため、BigQuery には `olist_staging.stg_orders` というビューができる。
- **「取ってくる → 加工する → 最後に `select *`」は、dbt でよく使われる型。** 元のテーブルへの参照を ① の 1 か所にまとめると、② の加工の部分が読みやすくなる。

### CTE (共通テーブル式)

`with 名前 as (...)` は CTE と呼ばれ、SELECT 文に名前を付けて、後の段階で使えるようにする書き方。

```sql
with 名前1 as (SELECT 文),
     名前2 as (SELECT 文),   -- 2 つ目以降はカンマでつなぐ (with は最初に 1 回だけ)
     ...
select ... from 名前2         -- 最後に、普通の SELECT 文が 1 つ必要
```

- かっこの中には、どんな SELECT 文でも書ける (列の抜き出しだけでなく、結合・集計・絞り込みも)。
- 後の CTE は、前の CTE の名前を使える (`renamed` の中の `from source`)。
- CTE は、その SQL 文の中だけで使える一時的な名前。BigQuery にテーブルとして保存されるわけではない。
- 上から順に読めば、処理の流れが分かる。

### source() は SQL ではなく dbt の関数

`{{ }}` で囲まれた部分は Jinja (dbt が使うテンプレートの書き方)。**dbt が BigQuery に送る前に、実際のテーブル名に書き換える**ため、BigQuery が `source` という文字を見ることはない。

```sql
-- 書いたもの (stg_orders.sql)
select * from {{ source('olist', 'orders') }}

-- dbt が書き換えて BigQuery に送るもの (dbt/target/compiled/ に保存される)
select * from `olist-data-platform-511008`.`olist_raw`.`olist_orders_dataset`
```

- `source()` は dbt の外で作られたテーブル (raw)、`ref()` は dbt で作ったモデルを読むときに使う (第1章の「source() と ref()」)。
- staging は raw だけを読むため、`source()` だけを使う。`ref()` は第3章の mart で使う。
- **紛らわしい点:** `with source as (...)` の `source` は、CTE に付けた**ただの名前**で、`source()` 関数とは関係ない。「元データ」の意味で付けるのが dbt でよくある習慣で、別の名前でも動く。

## 型の変換

| 元の列 (STRING) | 変換後 | ポイント |
|---|---|---|
| `order_purchase_timestamp` | `order_purchased_at` (DATETIME) | 日時の列は、名前の最後を `_at` にそろえる |
| `order_approved_at`、`order_delivered_carrier_date`、`order_delivered_customer_date` | `order_approved_at`、`order_delivered_carrier_at`、`order_delivered_customer_at` (DATETIME) | 同上 |
| `order_estimated_delivery_date` | `order_estimated_delivery_date` (DATE) | 時刻が常に 00:00:00 のため日付にする。日付の列は、名前の最後を `_date` にそろえる |

- **TIMESTAMP ではなく DATETIME にする理由:** 元データの日時には、タイムゾーンの情報がない。BigQuery の TIMESTAMP は「UTC の絶対時刻」のため、ブラジルの時刻を UTC と解釈してしまい、意味がずれる。DATETIME は「カレンダーと時計の表示そのまま」の型で、元の意味を保てる。
- **`cast` を 2 回重ねる理由:** 元の値は `"2017-10-18 00:00:00"` のような時刻付きの文字列で、BigQuery はこの形を直接 DATE に変換できない。いったん DATETIME にしてから DATE にする。

```sql
cast(cast(order_estimated_delivery_date as datetime) as date) as order_estimated_delivery_date
```

## _staging.yml: 説明とテスト

SQL と同じフォルダに置き、モデルごとに説明とテストを書く。

```yaml
version: 2
models:
  - name: stg_orders          # SQL のファイル名 (モデル名) と一致させる
    description: 1 行 = 1 注文。
    data_tests: [...]         # モデル全体のテスト (複数の列にまたがる条件)
    columns:
      - name: order_id
        description: 注文 ID。主キー。
        data_tests:           # 列ごとのテスト
          - unique
          - not_null
```

- **`description`**: ドキュメント用の説明。`dbt docs` で作る説明ページに表示される。処理の結果には影響しない。
- **`data_tests`**: テスト。`dbt build` では、モデルを作った直後に実行される。

### テストの正体は「おかしい行を探す SELECT 文」

テストの名前を書くと、dbt がそれを SQL に変換して実行する。**結果が 0 行なら合格、1 行以上なら不合格**。以下は、`dbt compile` で確認した実際の SQL。

`not_null` (`order_id` に NULL がない):

```sql
select order_id
from `olist-data-platform-511008`.`olist_staging`.`stg_orders`
where order_id is null
```

`unique` (`order_id` に重複がない):

```sql
with dbt_test__target as (
  select order_id as unique_field
  from `olist-data-platform-511008`.`olist_staging`.`stg_orders`
  where order_id is not null
)

select unique_field, count(*) as n_records
from dbt_test__target
group by unique_field
having count(*) > 1
```

### このファイルで使っているテスト

| テスト | 提供元 | 確かめること | 例 |
|---|---|---|---|
| `unique` | dbt 標準 | 重複がない | `stg_orders.order_id` |
| `not_null` | dbt 標準 | NULL がない | `stg_orders.order_purchased_at` |
| `accepted_values` | dbt 標準 | 決められた値しか入っていない | `order_status` が 8 種類のどれか |
| `relationships` | dbt 標準 | 相手のテーブルに同じ値がある (結合先がある) | `stg_orders.customer_id` が `stg_customers` にある |
| `dbt_utils.expression_is_true` | dbt_utils | 書いた式が、すべての行で成り立つ | 承認日時 ≥ 購入日時 |
| `dbt_utils.accepted_range` | dbt_utils | 値が範囲内にある | `stg_order_items.price` > 0 |
| `dbt_utils.unique_combination_of_columns` | dbt_utils | 複数の列の組み合わせで重複がない (複合キー) | `stg_order_items` の (`order_id`, `order_item_id`) |

テストに渡す値 (式、値のリスト、相手のテーブルなど) は、`arguments:` の下に書く。

```yaml
- accepted_values:
    arguments:
      values: [delivered, shipped, canceled, unavailable, invoiced, processing, created, approved]
```

### config の where と severity

```yaml
- name: order_approved_at
  data_tests:
    - not_null:
        config:
          where: "order_status = 'delivered'"   # 配達済みの注文だけを対象にする
          severity: warn                         # 不合格でも、警告にとどめる
```

- **`where`**: テストする行を絞る。承認日時は、未承認の注文では NULL が正常のため、「配達済みなら必ずあるはず」という条件でテストする。変換後の SQL では、次のように絞り込みが入る。

  ```sql
  select order_approved_at
  from (select * from `...`.`olist_staging`.`stg_orders` where order_status = 'delivered') dbt_subquery
  where order_approved_at is null
  ```

- **`severity: warn`**: 不合格でも、エラーで止めずに警告にする。元データには、配達済みなのに日時が欠けている注文など、既知の例外がある ([data_notes.md](../data_notes.md))。staging では行を消さない方針のため、警告にして、例外の扱いは mart で決める。`dbt build` の結果の「warn」は、こうした既知の例外。

## dbt_utils: 追加のパッケージ

dbt_utils は、dbt Labs (dbt の開発元) が公開している、**よく使うマクロとテストを集めた追加パッケージ**。dbt の本体にないテストを使えるようになる。

1. [packages.yml](../../dbt/packages.yml) に、使うパッケージとバージョンの範囲を書く (手で書く)。

   ```yaml
   packages:
     - package: dbt-labs/dbt_utils
       version: [">=1.3.0", "<2.0.0"]
   ```

2. `uv run dbt deps` で、公開場所 (dbt Package Hub) からダウンロードする。`dbt/dbt_packages/dbt_utils/` に置かれる。自動で作られるため、git には入れない。
3. 実際に入ったバージョン (今は 1.4.1) が、package-lock.yml に記録される。ほかの人が `dbt deps` しても同じバージョンになるように、こちらは git に入れる。

テストの名前の前に `dbt_utils.` を付けると、dbt はこのパッケージの中から探す。テストの中身は `dbt_packages/dbt_utils/macros/generic_tests/` にある。

## まとめ

```
stg_orders.sql   source() で raw を読み、型と列名だけを整える (行は減らさない)
                 CTE で「取ってくる → 加工する → select *」の順に書く
_staging.yml     モデルと列の説明 + テスト
                 テストは「おかしい行を探す SELECT 文」に変換され、0 行なら合格
                 where で対象の行を絞り、既知の例外は severity: warn にする
packages.yml     dbt_utils などの追加パッケージ (dbt deps でダウンロード)
```
