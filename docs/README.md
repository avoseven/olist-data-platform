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
| [008](decisions/008_feature_selection.md) | クラスタリングに使う特徴量を 8 つ選ぶ (採用・保留・不採用と、次の段階で確認すること。入力する特徴量は 010 で置き換え) |
| [009](decisions/009_clustering_preprocessing.md) | クラスタリングの前処理 (NULL がある顧客は学習から外す、金額と件数は対数変換してから標準化) |
| [010](decisions/010_rule_flags_and_clustering_scope.md) | リピーターと遅延経験者はフラグで分け、それ以外の顧客を金額・最近性 (・レビュー) でクラスタリングする (一部を 011 で置き換え) |
| [011](decisions/011_segmentation_purpose_and_roles.md) | セグメンテーションの目的 (購買傾向と購入体験の理解、改善機会の探索) と、分類に使う指標・比べる指標の分担 |
| [012](decisions/012_segment_definition.md) | セグメントの定義 (リピーターと、単発購入を金額 50 / 150 で 3 つに区切った計 4 つ) |

## 調査

| ファイル | 内容 |
|---|---|
| [../notebooks/01_order_reviews_duplicates.ipynb](../notebooks/01_order_reviews_duplicates.ipynb) | `order_reviews` の 2 種類の重複についての調査 |
| [../notebooks/02_feature_selection.ipynb](../notebooks/02_feature_selection.ipynb) | 特徴量の NULL・分布・相関の確認と、クラスタリングに使う特徴量の選定 |
| [../notebooks/03_clustering.ipynb](../notebooks/03_clustering.ipynb) | K-means の基準となる結果 (クラスタ数ごとの評価と、何で顧客が分かれたかの確認) |
| [../notebooks/04_clustering_after_flags.ipynb](../notebooks/04_clustering_after_flags.ipynb) | リピーターと遅延経験者をフラグで分けたあとの顧客のクラスタリング (金額・最近性、＋レビュー) |
| [../notebooks/05_segmentation.ipynb](../notebooks/05_segmentation.ipynb) | 単発購入の顧客の金額の区切り方の比較と、セグメントの割り当て |
