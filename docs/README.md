# docs

このプロジェクトのドキュメントの目次。

## 仕様

| ファイル | 内容 |
|---|---|
| [data_notes.md](data_notes.md) | 元データの仕様と注意点 (テーブルの粒度、主キー、リレーション、欠損、不整合など) |
| [customer_features.md](customer_features.md) | 顧客特徴量 (`customer_features`) の定義の一覧 |

## 設計の判断の記録 (ADR)

何を、何と比べて、なぜ決めたかを残したもの。決定済みの ADR の本文は書き換えず、判断が変わった場合は新しい ADR を追加する。

| ADR | 決めたこと |
|---|---|
| [001](decisions/001_table_selection.md) | BigQuery に取り込むテーブルを 7 つに絞る (`sellers` と `geolocation` は取り込まない) |
| [002](decisions/002_layer_architecture.md) | raw → staging → mart の 3 層に分け、層ごとの責務を決める |
| [003](decisions/003_transformation_tool.md) | 変換ツールに dbt を使う (dbt Core の部分は 005 で置き換え) |
| [004](decisions/004_bigquery_sandbox.md) | BigQuery サンドボックスで、費用をかけずに運用する |
| [005](decisions/005_dbt_v2.md) | dbt v2 の標準版を使う |
| [006](decisions/006_mart_design.md) | mart の設計方針 (対象の注文、金額、レビュー、基準日、不整合、テーブル名) |
| [007](decisions/007_customer_feature_principles.md) | 顧客単位の特徴量の設計原則 (集約の単位、平均の取り方、NULL、代表値) |

## 調査

| ファイル | 内容 |
|---|---|
| [../notebooks/01_order_reviews_duplicates.ipynb](../notebooks/01_order_reviews_duplicates.ipynb) | `order_reviews` の 2 種類の重複についての調査 |
