# 5. テスト

[_marts.yml](../../dbt/models/marts/_marts.yml) と、[tests/](../../dbt/tests/) フォルダの SQL を見る。
テストの基本 (おかしい行を探す SELECT 文、`where`、`severity`) は、第2章を参照。

## テストは 2 種類ある

どちらも中身は「**おかしい行を探す SELECT 文**」で、結果が 0 行なら合格。違うのは、書き方と書く場所。

| | generic test (汎用のテスト) | singular test (個別のテスト) |
|---|---|---|
| 書く場所 | yml (`_staging.yml`、`_marts.yml`) | `tests/` フォルダの SQL ファイル |
| 書き方 | テストの名前と引数だけ (`unique`、`not_null` など) | SELECT 文を自分で全部書く |
| 向いていること | 1 つの表の中の、決まった形のチェック (重複、NULL、範囲) | 複数の表にまたがるチェック、集計どうしの比較 |
| このプロジェクトの数 | 多数 (列ごと) | 7 つ |

`tests/` フォルダは、dbt_project.yml の `test-paths: ["tests"]` で指定している。ファイル名がそのままテスト名になる。名前は自由で、`assert_` (〜であることを確かめる) で始めるのは、このプロジェクトの習慣。

## generic test: モデル全体のテスト

列ごとのテストは第2章で見た。`customer_features` では、**複数の列の関係**をモデル全体のテストとして書いている。

```yaml
- name: customer_features
  data_tests:
    - dbt_utils.expression_is_true:
        arguments:
          expression: "days_since_first_purchase >= days_since_last_purchase"   # 最初の購入は最後の購入より前
    - dbt_utils.expression_is_true:
        arguments:
          expression: "purchase_day_count <= order_count"                     # 購入日数は注文数を超えない
    - dbt_utils.expression_is_true:
        arguments:
          expression: "is_repeat_customer = (purchase_day_count >= 2)"        # リピーターの判定が定義どおり
```

これらは「論理的に必ず成り立つはずの関係」。SQL を書き間違えると崩れるため、計算ミスの検知に使える。

**注意した点 (`freight_ratio`):** `freight_ratio` は「0 以上 1 未満」。`accepted_range` の `inclusive` (境界を含むか) は上限と下限の両方に効くため、「0 は含み、1 は含まない」を 1 つでは書けない。そこで `accepted_range` (0〜1、境界を含む) と `expression_is_true` (`freight_ratio < 1`) の 2 つに分けている。

## singular test: 3 つのタイプ

7 つのテストは、目的で 3 つに分けられる。

### (a) 複数の表にまたがるルール

| テスト | 確かめること |
|---|---|
| `assert_review_created_on_or_after_purchase` | レビューの作成日が、注文の購入日より前になっていない (レビューと注文の 2 つの表) |
| `assert_shared_review_id_is_consistent` | 複数の注文に付いた同じレビューが、同じ人・同じスコアである |

2 つ目は、第4章の「レビューの重複を `select distinct` で除く」処理の**前提**を確かめるテスト。同じ `review_id` でスコアが違えば、重複を除いたときに情報が消える。

```sql
select review_id, ...
from {{ ref('fct_delivered_orders') }}
where review_id is not null
group by review_id
having count(distinct customer_unique_id) > 1     -- 人が 2 人以上 → おかしい
    or count(distinct review_score) > 1            -- スコアが 2 種類以上 → おかしい
```

singular test でも、`ref()` で表を指定する。

### (b) 突き合わせ (合計が一致するか)

| テスト | 比べるもの |
|---|---|
| `assert_fct_delivered_orders_matches_staging` | staging の delivered の注文 ⇔ `fct_delivered_orders` (注文数、金額、送料) |
| `assert_customer_features_matches_fct` | `fct_delivered_orders` ⇔ `customer_features` (顧客数、注文数、金額) |

第3章・第4章の「**二重計上**」を見つけるためのテスト。結合で行が増えると合計が元より大きくなるため、ここで不合格になる。

```sql
with fct as (
    select count(distinct customer_unique_id) as customer_count,
           count(*) as order_count, sum(items_amount) as items_amount
    from {{ ref('fct_delivered_orders') }}
),
features as (
    select count(*) as customer_count,
           sum(order_count) as order_count, sum(total_items_amount) as items_amount
    from {{ ref('customer_features') }}
)
select ...
from fct cross join features
where fct.customer_count != features.customer_count
   or fct.order_count    != features.order_count
   or fct.items_amount   != features.items_amount      -- どれか 1 つでも違えば 1 行返る → 不合格
```

### (c) 独立した再計算 (別の書き方で計算して一致するか)

| テスト | 確かめる列 |
|---|---|
| `assert_top_category_matches_recomputation` | `top_category`、`distinct_category_count` |
| `assert_main_payment_type_matches_recomputation` | `main_payment_type` |
| `assert_purchase_day_count_matches_recomputation` | `purchase_day_count` |

代表値のように計算が複雑な列は、モデルの結果を正解とみなすとテストにならない。そこで、**モデルとは別の道筋で同じ値を計算し**、全員分を比べる。

| | モデル (`customer_features.sql`) | テスト (`assert_top_category_...`) |
|---|---|---|
| 読む表 | `fct_delivered_orders` | staging から直接 |
| 代表値の取り方 | `array_agg(... limit 1)[offset(0)]` | `row_number() ... = 1` |

同じ間違いを両方でする可能性を下げるため、わざと書き方を変えている。

比べるところでは、`is distinct from` を使う。

```sql
where features.top_category is distinct from expected.top_category
```

- `!=` は、どちらかが NULL だと結果が NULL になり、「違う」と判定されない。
- `is distinct from` は NULL も値として比べる (NULL と NULL は「同じ」、NULL と 'books' は「違う」)。
- カテゴリがない人は `top_category` が NULL のため、NULL どうしを「一致」と扱うためにこちらを使う。

## severity: warn と dbt build の動き

| severity | 不合格のとき | `dbt build` の動き |
|---|---|---|
| error (何も書かないとこちら) | エラー | そのモデルより後ろのモデル (それを `ref()` しているもの) は作られず、スキップされる |
| warn | 警告 | 止まらずに続ける |

- `dbt build` は「モデルを作る → そのモデルのテスト → 次のモデル」の順に進む。例えば `stg_orders` の `unique` が失敗すると、壊れた可能性のあるデータの上に mart を作らないように、`fct_delivered_orders` 以降が止まる。
- 元データの既知の例外 (日時の欠け、カテゴリの欠けなど) は warn にしている。`dbt build` の結果の「15 warn」はこれ。
- **warn の件数は、データと SQL が変わらなければ毎回同じ**。件数が変わったら、どちらかに変化があった合図になる。
- singular test で warn にするときは、SQL ファイルの先頭に書く。

  ```sql
  {{ config(severity='warn') }}
  ```

## まとめ

```
テストはすべて「おかしい行を探す SELECT 文」。0 行なら合格
generic test (yml)     : 名前と引数だけで書く。列ごと、またはモデル全体 (列どうしの関係)
singular test (tests/) : SELECT を自分で書く。このプロジェクトでは 3 タイプ
   (a) 複数の表にまたがるルール
   (b) 突き合わせ      … 合計が一致するか (二重計上の検知)
   (c) 独立した再計算  … 別の道筋で計算して一致するか (is distinct from で NULL も比べる)
severity: error は後ろのモデルを止める、warn は既知の例外として続ける
```
