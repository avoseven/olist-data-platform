# 6. よく使うコマンド

コマンドの一覧と実行の手順は、リポジトリの [README.md](../../README.md) の「よく使う dbt のコマンド」を参照。
この章では、**実行したときに裏で何が起きているか**を見る。コマンドは `dbt` フォルダの中で、先頭に `uv run` を付けて実行する。

## dbt build で起きていること

```
① 読み込む     profiles.yml、dbt_project.yml、yml、SQL、パッケージ
② 組み立てる   {{ }} を書き換えて、ただの SQL にする
               ref() / source() から依存関係の図を作る
③ 実行する     図の順番に「モデルを作る → そのテスト」を繰り返す
```

このプロジェクトの依存関係の図:

```
raw (source)
  └→ staging 7 つ (互いに依存しない → threads: 4 で最大 4 つ同時に作る)
       └→ fct_delivered_orders
            └→ customer_features
```

- 順番は、`ref()` から dbt が自動で決める。ファイル名やフォルダの並びとは関係ない。
- テストが error で失敗すると、そのモデルより後ろはスキップされる (第5章)。

## BigQuery に実際に送られる SQL を見る

`dbt/target/` フォルダに、2 種類の SQL が保存される。

| 場所 | 中身 | 作られるタイミング |
|---|---|---|
| `target/compiled/` | `{{ }}` を書き換えた後の SELECT 文 | `dbt compile`、`dbt build` など |
| `target/run/` | 実際に BigQuery に送った SQL (`CREATE` 付き) | `dbt build`、`dbt run` など |

`target/run/` の中身 (実際の記録):

```sql
-- stg_orders (view の設定)
create or replace view `olist-data-platform-511008`.`olist_staging`.`stg_orders`
OPTIONS()
as -- 1 行 = 1 注文
...
with source as (
    select * from `olist-data-platform-511008`.`olist_raw`.`olist_orders_dataset`
),
...

-- customer_features (table の設定)
create or replace table `olist-data-platform-511008`.`olist_mart`.`customer_features`
...
```

- 自分で書いた SELECT 文が、`create or replace view ... as` または `create or replace table ... as` で包まれている。第1章の「モデル = テーブル 1 つ分の定義」が、ここで実際の命令になる。
- **`create or replace` のため、毎回まるごと作り直す。** 何度実行しても結果は同じで、途中の状態が残らない。
- SQL でエラーが出たときや、dbt が何をしたのかを知りたいときは、ここを見る。
- `target/` は実行のたびに上書きされる作業用のフォルダのため、git には入れない。

## コマンドごとに、BigQuery に何をするか

| コマンド | BigQuery にすること | 使う場面 |
|---|---|---|
| `dbt build` | モデルを作る + テストする | 普段はこれ |
| `dbt run` | モデルを作るだけ | テストを飛ばして早く作りたいとき |
| `dbt test` | テストの SELECT を実行するだけ (何も作らない) | モデルはそのままで、テストだけやり直したいとき |
| `dbt compile` | 何も作らない (SQL を組み立てて `target/compiled/` に保存するだけ) | `{{ }}` がどう書き換わるか確かめたいとき |
| `dbt show --inline "<SQL>"` | その SELECT を実行して結果を表示する (何も作らない) | ちょっとデータを見たいとき |
| `dbt list` | 何もしない (対象になるものを一覧で出すだけ) | `-s` の指定が合っているか確かめたいとき |

## 対象を絞る: -s (select)

`dbt build -s ...` のように使う。結果は `dbt list -s ... --resource-type model` で確かめたもの。

| 書き方 | 対象 | 実際の結果 |
|---|---|---|
| `-s fct_delivered_orders` | そのモデルだけ | `fct_delivered_orders` |
| `-s fct_delivered_orders+` | そのモデルと、**後ろ** (それを使うモデル) すべて | `fct_delivered_orders`、`customer_features` |
| `-s +fct_delivered_orders` | そのモデルと、**前** (それが使うモデル) すべて | staging 5 つ、`fct_delivered_orders` |
| `-s staging` | `models/staging/` フォルダのモデル | staging 7 つ |

`+` を付けた側に、依存関係をたどって広げる。

- **モデルを直したときは `-s モデル名+` が基本。** 例えば `fct_delivered_orders.sql` を直したら、それを元に作る `customer_features` も古くなるため、一緒に作り直す。
- `-s` で選んだモデルに関係するテストも、一緒に実行される。

## モデルを直すときの流れ (例)

```
1. SQL を直す
2. uv run dbt compile -s モデル名              ← {{ }} の書き換えと文法を確認 (何も作らない)
3. uv run dbt show --inline "select ... from {{ ref('モデル名') }} limit 10"
                                              ← 必要なら中身を確認
4. uv run dbt build -s モデル名+               ← 直したモデルと後ろを作り直してテスト
5. uv run dbt build                           ← 最後に全体を通して、warn の件数が変わっていないか確認
```

最後の `dbt build` の結果 (このプロジェクトでは `118 success | 15 warn`) が前と同じなら、ほかの部分に影響が出ていないことの目安になる。

## まとめ

```
dbt build = 読み込む → {{ }} を書き換えて依存関係の図を作る → 図の順に「作る → テスト」
target/compiled/ : 書き換えた後の SELECT 文
target/run/      : 実際に送った SQL (create or replace view/table ... as SELECT)
-s モデル名+      : 直したモデルと、その後ろを作り直す
compile / show / list は何も作らないため、確認に気軽に使える
```
