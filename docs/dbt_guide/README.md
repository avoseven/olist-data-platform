# dbt の読み方ガイド

このプロジェクトの `dbt/` フォルダの中身を、初めて dbt を読む人向けに、順番に説明する。
仕組み → 実際の加工 → テストの順に、実際のファイルを見ながら進める。

| 章 | 見るもの | 分かること |
|---|---|---|
| [1. 接続とプロジェクトの設定](01_project_setup.md) | `profiles.yml`、`dbt_project.yml`、マクロ、`_sources.yml` | dbt がどこに接続し、どのデータセットに何を作るか |
| 2. staging のモデル (作成予定) | `stg_orders.sql`、`_staging.yml` | `ref` / `source` の使い方、型変換、テストの書き方 |
| 3. 注文単位の mart (作成予定) | `fct_delivered_orders.sql` | CTE の組み立て方、注文単位に集約してから結合する理由 |
| 4. 顧客単位の mart (作成予定) | `customer_features.sql` | 顧客単位の集計、代表値の選び方 |
| 5. テスト (作成予定) | `_marts.yml`、`tests/` | 組み込みのテストと自作のテストの違い、警告 (warn) の使い方 |
| 6. よく使うコマンド (作成予定) | `dbt build` など | 実行の流れ、実際に BigQuery に送られる SQL の見方 |

dbt の環境構築と実行の手順は、リポジトリの [README.md](../../README.md) を参照。
