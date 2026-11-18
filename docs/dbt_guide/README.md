# dbt の読み方ガイド

このプロジェクトの `dbt/` フォルダの中身を、初めて dbt を読む人向けに、順番に説明する。
仕組み → 実際の加工 → テストの順に、実際のファイルを見ながら進める。

| 章 | 見るもの | 分かること |
|---|---|---|
| [1. 接続とプロジェクトの設定](01_project_setup.md) | `profiles.yml`、`dbt_project.yml`、マクロ、`_sources.yml` | dbt がどこに接続し、どのデータセットに何を作るか |
| [2. staging のモデル](02_staging.md) | `stg_orders.sql`、`_staging.yml`、`packages.yml` | CTE と `source()` の書き方、型変換、テストの書き方、追加パッケージ |
| [3. 注文単位の mart](03_order_mart.md) | `fct_delivered_orders.sql` | `ref()` の使い方、注文単位に集約してから結合する理由、ウィンドウ関数、LEFT JOIN、dbt の関数と SQL の関数の違い |
| [4. 顧客単位の mart](04_customer_mart.md) | `customer_features.sql` | 粒度をそろえてから結合する理由、代表値の選び方 (`array_agg`)、平均と割合の計算、NULL の扱い |
| [5. テスト](05_tests.md) | `_marts.yml`、`tests/` | generic test と singular test の違い、突き合わせと再計算のテスト、警告 (warn) の使い方 |
| [6. よく使うコマンド](06_commands.md) | `dbt build` など | 実行の流れ、実際に BigQuery に送られる SQL の見方、対象の絞り方 (`-s`) |

dbt の環境構築と実行の手順は、リポジトリの [README.md](../../README.md) を参照。
