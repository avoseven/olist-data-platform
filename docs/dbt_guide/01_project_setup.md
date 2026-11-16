# 1. 接続とプロジェクトの設定

dbt が「どこに接続し、どのデータセットに何を作るか」を決めている 4 つのファイルを見る。
その前に、dbt のプロジェクトの始め方と、どのファイルが必須かを確認する。

## dbt プロジェクトの始め方

ファイルをゼロから全部手で書くわけではない。`dbt init` で雛形を作り、プロジェクトに合わせて書き換え・書き足していく。

| 手順 | やること | このプロジェクトでは |
|---|---|---|
| 1. インストール | dbt を入れる | `uv add dbt` |
| 2. 雛形を作る | `dbt init` を実行する。プロジェクト名や接続先を聞かれ、フォルダと設定ファイルが作られる | `dbt/` フォルダ |
| 3. 接続を確かめる | `dbt debug` で、データベースにつながるかを確認する | [README.md](../../README.md) のセットアップ手順 |
| 4. 構成を決める | `dbt_project.yml` に、層ごとのデータセットや作り方 (view / table) を書く | staging / marts |
| 5. 元データを登録する | sources の yml を書く | `_sources.yml` |
| 6. モデルを書く | SQL を書いて `dbt run` (または `dbt build`) で作る | staging 7 つ、mart 2 つ |
| 7. テストと説明を書く | yml にテストと列の説明を書く | `_staging.yml`、`_marts.yml`、`tests/` |
| 8. 必要ならパッケージを入れる | `packages.yml` を書いて `dbt deps` を実行する | `dbt_utils` |

### ファイルごとの作り方と、必須かどうか

| ファイル・フォルダ | 作り方 | 必須か | 補足 |
|---|---|---|---|
| `dbt_project.yml` | `dbt init` が作る → 手で直す | **必須** | このファイルがあるフォルダが、dbt のプロジェクトとみなされる |
| `profiles.yml` | `dbt init` の質問に答えると作られる → 手で直す | **必須** | 標準ではホームの `~/.dbt/` に作られる。このプロジェクトでは、秘密情報を含まないため `dbt/` に置いて Git で管理している |
| `models/` の SQL | 手で書く (`dbt init` が作る例のモデルは消して書き直す) | **必須** (1 つ以上) | |
| `_sources.yml` | 手で書く | 任意 (実質は推奨) | なくてもテーブル名を直接書けば動く。ただし、[下で説明する](#source-と-ref-テーブルの指定のしかた) 2 つの利点を失う |
| `_staging.yml`、`_marts.yml` | 手で書く | 任意 | テストと列の説明を書くファイル。なくても動くが、品質の確認と説明の記録に欠かせない |
| `tests/` の SQL | 手で書く | 任意 | 自作のテスト |
| `macros/` | 手で書く | 任意 | dbt の動きを変えたいときだけ |
| `packages.yml` | 手で書く | 任意 | パッケージを使うときだけ |
| `package-lock.yml` | `dbt deps` が作る | - | 入れたパッケージのバージョンを固定する記録。Git で管理する |
| `dbt_packages/` | `dbt deps` が作る | - | ダウンロードしたパッケージ。Git の管理対象外 |
| `target/`、`logs/` | dbt を実行するたびに作られる | - | Git の管理対象外。`target/` には実際に送られた SQL が入る |
| `.sqlfluff` | 手で書く | 任意 | SQL の書き方のチェック (lint) の設定 |

- **必須なのは 3 つ**: `dbt_project.yml`、`profiles.yml`、モデルの SQL。最初の 2 つは `dbt init` が雛形を作る。
- **自分で書くのが中心になるのは**、モデルの SQL と yml (元データの登録、テスト、説明)。
- **dbt が自動で作るもの** (`target/`、`logs/`、`dbt_packages/`) は Git に入れない。

### 名前が固定のものと、自由なもの

dbt が名前で探しにいくファイルは固定で、中身から読み取るファイルは自由。

| ファイル・名前 | 固定 / 自由 | 補足 |
|---|---|---|
| `dbt_project.yml` | 固定 | このファイルがあるフォルダが、dbt のプロジェクトとみなされる |
| `profiles.yml` | ファイル名は固定、置き場所は変えられる | dbt は「`--profiles-dir` の指定や環境変数 `DBT_PROFILES_DIR` → 今いるフォルダ → `~/.dbt/`」の順に探す。このプロジェクトは `dbt/` フォルダで実行するため、`dbt/profiles.yml` が見つかる |
| `packages.yml`、`package-lock.yml` | 固定 | `dbt deps` が読む・作る |
| `.sqlfluff` | 固定 | SQLFluff (lint のツール) が探す |
| 標準のマクロを上書きするマクロの名前 | 固定 | 上書きするには、標準と同じ名前 (例: `generate_schema_name`) にする。ファイル名は自由 |
| モデルの SQL のファイル名 | 自由 | **ファイル名がそのままモデル名になる**。`stg_orders.sql` は `ref('stg_orders')` で呼び、BigQuery 上も `stg_orders` という名前で作られる。プロジェクトの中で重複は不可 |
| yml のファイル名 (`_sources.yml` など) | 自由 | dbt は `models/` フォルダの中の yml をすべて読む。先頭の `_` は、フォルダの中で一番上に並べ、SQL と区別しやすくするための慣習 |
| `tests/` の SQL のファイル名 | 自由 | ファイル名がテスト名になる |
| フォルダ名 (`staging/`、`marts/`) | 自由 | `dbt_project.yml` の `models:` の下に書く名前と一致させる |
| `models/`、`macros/`、`tests/` | 標準の名前 | `dbt_project.yml` の `model-paths` などで変えられる。このプロジェクトは標準のまま、明示的に書いている |
| profiles.yml の中の接続設定の名前 (`olist`)、target の名前 (`dev`) | 自由 | 接続設定の名前は、`dbt_project.yml` の `profile:` と一致させる |

**一致させる必要がある組**:

- `profiles.yml` の `olist:` と、`dbt_project.yml` の `profile: olist`
- フォルダ名 `models/staging/` と、`dbt_project.yml` の `staging:`
- モデルのファイル名 `stg_orders.sql` と、`ref('stg_orders')`

| ファイル | 役割 |
|---|---|
| [profiles.yml](../../dbt/profiles.yml) | **どこに接続するか** (BigQuery のどのプロジェクトに、どうログインするか) |
| [dbt_project.yml](../../dbt/dbt_project.yml) | **何をどう作るか** (どのフォルダのモデルを、どのデータセットに、ビューとテーブルのどちらで作るか) |
| [generate_schema_name.sql](../../dbt/macros/generate_schema_name.sql) | データセット名の決め方を、このプロジェクト用に変える |
| [_sources.yml](../../dbt/models/staging/_sources.yml) | dbt の外で作った raw のテーブルを、dbt に登録する |

## 用語: database と schema

dbt は、ほかのデータベース製品に合わせた呼び方を使う。BigQuery では次のように対応する。

| dbt の呼び方 | BigQuery の呼び方 | このプロジェクトの例 |
|---|---|---|
| database | プロジェクト | `olist-data-platform-511008` |
| schema | データセット | `olist_raw`、`olist_staging`、`olist_mart` |

## profiles.yml: 接続の設定

```yaml
olist:              # 接続設定の名前 (dbt_project.yml の profile: olist と対応)
  target: dev       # 既定で使う接続先
  outputs:
    dev:
      type: bigquery
      method: oauth                 # gcloud でログインした認証情報 (ADC) を使う
      database: "{{ env_var('GCP_PROJECT_ID', 'olist-data-platform-511008') }}"
      schema: olist_staging         # 既定のデータセット
      location: US
      threads: 4                    # 同時に実行するモデルの数
```

- **`method: oauth`**: パスワードや鍵のファイルを書かず、`gcloud auth application-default login` で保存された認証情報 (ADC) を使う。秘密情報が入らないため、このファイルは Git で管理している。サービスアカウントの鍵のファイルを使う方法に変える場合は、このファイルを Git の管理対象から外す。
- **`{{ env_var(...) }}`**: `{{ }}` は **Jinja** (ジンジャ) というテンプレートの書き方。dbt は SQL や YAML を実行する前に、この部分を値に置き換える。ここでは、環境変数 `GCP_PROJECT_ID` があればその値を、なければ `olist-data-platform-511008` を使う。
- **`target: dev`**: 接続先の名前。本番用 (`prod`) などの接続先を増やしたときに、`dbt build --target prod` のように切り替える。今は `dev` の 1 つだけ。
- **`schema: olist_staging`**: 既定のデータセット。モデルは `dbt_project.yml` で層ごとのデータセットを指定するため、指定のないもの (テストの結果の保存先など) だけがここに作られる。
- **`threads: 4`**: 互いに依存しないモデル (例: staging の 7 つ) は、最大 4 つまで同時に作る。

## dbt_project.yml: プロジェクトの設定

```yaml
name: olist
profile: olist          # profiles.yml の「olist」の接続を使う

models:
  olist:                # このプロジェクト (name: olist) のモデル
    staging:            # models/staging/ フォルダ
      +schema: olist_staging
      +materialized: view
    marts:              # models/marts/ フォルダ
      +schema: olist_mart
      +materialized: table
```

- **フォルダごとに設定を書ける。** `staging:` は `models/staging/` フォルダを指す。
- **`+` が付いた設定は、そのフォルダの中のすべてのモデルに適用される。** モデルのファイルに 1 つずつ書く必要はない。
- **`materialized`** (実体化の方法) で、モデルを BigQuery 上で何として作るかを決める。

| | view (ビュー) | table (テーブル) |
|---|---|---|
| 中身 | SQL だけを保存する。参照されるたびに計算する | 計算した結果を保存する |
| 向いている場面 | 処理が軽く、常に最新の元データを反映したいとき | 集計が重く、何度も読むとき |
| このプロジェクト | staging (型変換だけで軽い) | mart (結合や集計が多く、notebook から何度も読む) |

層ごとの役割は [ADR 002](../decisions/002_layer_architecture.md) を参照。

## マクロ: データセット名の決め方を変える

`+schema: olist_mart` と書いても、dbt の標準の動きでは、データセット名が **`olist_staging_olist_mart`** になる (profiles.yml の `schema` と、指定した名前をつなげる)。
これは、複数の開発者が同じプロジェクトで作業しても、データセットがぶつからないようにするための仕組みである。

このプロジェクトは 1 人で作業するため、指定した名前をそのまま使うように、標準のマクロを上書きした。

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}              -- 指定がなければ profiles.yml の schema (olist_staging)
    {%- else -%}
        {{ custom_schema_name | trim }}  -- 指定があればその名前 (olist_mart など) をそのまま使う
    {%- endif -%}
{%- endmacro %}
```

- **マクロ**は、Jinja で書く関数のようなもの。dbt は SQL を組み立てるときにマクロを呼び出す。
- dbt の標準のマクロと同じ名前 (`generate_schema_name`) で `macros/` フォルダに置くと、dbt はこちらを使う。
- `{%- -%}` の `-` は、前後の空白や改行を取り除く指定。データセット名に余計な空白が入らないようにしている。

### 上書きが効く範囲

| 観点 | 範囲 |
|---|---|
| いつ | `macros/` フォルダ (dbt_project.yml の `macro-paths`) に置いてあれば、このプロジェクトで dbt を実行するたびに毎回効く (`dbt build`、`dbt run`、`dbt compile` など)。オン・オフの設定はない |
| 何に | dbt が作るもの全部 (モデル、seed、snapshot)。`+schema` を指定していないモデルにも呼ばれ、そのときは `custom_schema_name` が `none` になる |
| 何に効かないか | source (raw のテーブル)。source のデータセット名は `_sources.yml` に直接書いた名前を使い、このマクロは通らない |
| どのプロジェクト | このプロジェクトだけ。同じ PC のほかの dbt プロジェクトには影響しない |

- 上書きをやめたいときは、ファイルを消すか、マクロの名前を変える。
- 環境ごとに動きを変えたいときは、マクロの中で分岐させる。例えば `target.name` (profiles.yml の target の名前) を見て、開発用 (`dev`) では標準の「つなげる」動きにし、本番用 (`prod`) では指定した名前をそのまま使う、という書き方がよく使われる。このプロジェクトは target が 1 つなので、分岐していない。

## _sources.yml: raw のテーブルを登録する

raw 層は dbt ではなく、`src/load_raw.py` で CSV から作った。dbt から使えるように、場所と名前を登録しているのがこのファイル。

```yaml
sources:
  - name: olist              # source のグループ名
    schema: olist_raw        # raw のデータセット
    tables:
      - name: orders                         # dbt の中で使う名前
        identifier: olist_orders_dataset     # BigQuery 上の実際のテーブル名
```

`identifier` で、CSV のファイル名そのままの長いテーブル名を、短い名前に付け替えている。

## source() と ref(): テーブルの指定のしかた

モデルの SQL では、テーブル名を直接書かず、関数で指定する。

| 関数 | 指すもの |
|---|---|
| `{{ source('グループ名', 'テーブル名') }}` | dbt の外で作ったテーブル (raw) |
| `{{ ref('モデル名') }}` | dbt で作ったモデル (staging、mart) |

dbt がどう書き換えるかは、`dbt compile --inline` で確かめられる (`dbt/` フォルダで実行)。

```bash
uv run dbt compile --inline "select * from {{ source('olist', 'orders') }}"
uv run dbt compile --inline "select * from {{ ref('stg_orders') }}"
```

| モデルの SQL での書き方 | dbt が書き換えた結果 |
|---|---|
| `{{ source('olist', 'orders') }}` | `` `olist-data-platform-511008`.`olist_raw`.`olist_orders_dataset` `` |
| `{{ ref('stg_orders') }}` | `` `olist-data-platform-511008`.`olist_staging`.`stg_orders` `` |

関数で書く理由は 2 つある。

1. **接続先が変わっても、SQL を書き換えずに済む。** プロジェクト ID やデータセット名は、設定 (profiles.yml、dbt_project.yml、マクロ) から自動で埋められる。
2. **dbt がモデルの依存関係を知ることができる。** 例えば `fct_delivered_orders` は `ref('stg_orders')` を使っているため、dbt は「`stg_orders` を先に作る」という順番を自動で決める。

## まとめ

```
profiles.yml        どこに接続するか (プロジェクト、認証、ロケーション)
      │
dbt_project.yml     どのフォルダのモデルを、どのデータセットに、何として作るか
      │
マクロ              データセット名の決め方 (指定した名前をそのまま使う)
      │
_sources.yml        raw のテーブルの場所と名前

→ モデルの SQL では source() と ref() でテーブルを指定し、dbt が実際の名前に書き換える
```
