# olist-data-platform

Olist Data Platform — EC データ分析基盤の構築

ブラジルの EC マーケットプレイス「Olist」の公開データを使って、BigQuery 上にデータ基盤を作り、**顧客セグメンテーション** (顧客をいくつかのグループに分ける分析) をすることを目指すプロジェクトです。

## 全体像

データは、次の 3 つの段階 (層) を順に通って加工されます。

```
Olist の CSV (手元の PC)
   │  src/load_raw.py で読み込む
   ▼
┌──────────────────────────┐
│ raw      (olist_raw)     │  CSV をそのまま入れた層 (全列が文字列)
└────────────┬─────────────┘
             │  dbt で加工する
             ▼
┌──────────────────────────┐
│ staging  (olist_staging) │  型や列名を整えた層 (行は 1 行も消さない)
└────────────┬─────────────┘
             │  dbt で加工する
             ▼
┌──────────────────────────┐
│ mart     (olist_mart)    │  分析の目的に合わせて結合・集計した層 (作成予定)
└────────────┬─────────────┘
             ▼
      顧客セグメンテーション
```

かっこ内は、BigQuery 上のデータセット (テーブルを入れるフォルダのようなもの) の名前です。
なぜこの構成にしたのかは [docs/decisions/](docs/decisions/) にまとめています。

### 使っている道具

| 道具 | 何に使うか |
|---|---|
| [BigQuery](https://cloud.google.com/bigquery) | Google Cloud のデータベース。データを保存し、SQL で加工する |
| [dbt](https://docs.getdbt.com/) | SQL の加工処理を、ファイルとして管理・実行・テストするツール (v2 を使用) |
| [uv](https://docs.astral.sh/uv/) | Python と、Python のパッケージ (dbt など) を管理するツール |
| [gcloud](https://cloud.google.com/sdk/docs) | 手元の PC から Google Cloud にログイン・操作するためのツール |

## データ

| CSV | ざっくり何のデータ？ | BigQuery に取り込むか |
| --- | --- | :---: |
| `customers` | 顧客情報 | ○ |
| `orders` | 注文情報・注文日時・配送日時 | ○ |
| `order_items` | 注文された商品・価格・送料 | ○ |
| `order_payments` | 支払い情報 | ○ |
| `order_reviews` | レビュー・評価 | ○ |
| `products` | 商品情報 | ○ |
| `sellers` | 販売者情報 | - |
| `geolocation` | 郵便番号・緯度経度 | - |
| `product_category_name_translation` | 商品カテゴリの英訳 | ○ |

`sellers` と `geolocation` を取り込まない理由は [ADR 001](docs/decisions/001_table_selection.md) を参照してください。
データの仕様や注意点 (欠損、不整合など) は [docs/data_notes.md](docs/data_notes.md) にまとめています。

## フォルダ構成

```
olist-data-platform/
├── data/raw/          元データの CSV を置く場所 (git では管理しない)
├── src/               Python のスクリプト
│   ├── inspect_data.py         CSV の中身を確認する (行数・型・欠損など)
│   ├── check_relationships.py  テーブル同士のつながりを確認する
│   └── load_raw.py             CSV を BigQuery に読み込む
├── dbt/               dbt のプロジェクト (BigQuery 上の加工処理)
│   ├── models/staging/         staging 層の SQL と、その説明・テスト
│   ├── tests/                  複数のテーブルにまたがるテスト
│   ├── macros/                 dbt の動きを調整する部品
│   ├── dbt_project.yml         dbt プロジェクトの設定
│   ├── profiles.yml            BigQuery への接続設定
│   └── packages.yml            dbt の追加パッケージ (dbt_utils)
├── notebooks/         調査に使った Jupyter notebook
├── docs/
│   ├── data_notes.md           データの仕様と注意点
│   └── decisions/              設計の判断の記録 (ADR)
└── pyproject.toml     Python の依存パッケージ (uv で管理)
```

## セットアップ (最初に 1 回だけ)

手順はすべて **Linux (WSL の Ubuntu を含む) のターミナル** で実行する前提です。

### 1. uv をインストールする

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

インストール後、ターミナルを開き直してから `uv --version` を実行し、バージョンが表示されれば OK です。

### 2. Python のパッケージをインストールする

リポジトリのフォルダに移動して、次を実行します。

```bash
uv sync
```

`pyproject.toml` に書かれたパッケージ (pandas、dbt など) が、`.venv` というフォルダにまとめてインストールされます。
PC 全体の Python には影響しません。

### 3. データをダウンロードする

1. Kaggle の [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) を開き、データをダウンロードします (Kaggle のアカウントが必要です)。
2. ダウンロードした zip を展開し、中の CSV (9 ファイル) を `data/raw/` に置きます。

```
data/raw/
├── olist_customers_dataset.csv
├── olist_orders_dataset.csv
└── ... (9 ファイル)
```

CSV は容量が大きいため、git では管理していません (`.gitignore` で除外しています)。

### 4. Google Cloud のプロジェクトを用意する

1. [Google Cloud コンソール](https://console.cloud.google.com/) を開き、新しいプロジェクトを作ります。
2. 作成後に表示される **プロジェクト ID** を控えておきます。

> **注意: プロジェクトの「名前」と「ID」は別物です。**
> ID は世界で 1 つしか使えないため、名前と同じ ID が既に使われていると、末尾に番号が付きます (例: 名前 `olist-data-platform` → ID `olist-data-platform-511008`)。
> 以降の手順で使うのは **ID** のほうです。

このプロジェクトは、**BigQuery サンドボックス** (クレジットカードの登録なしで無料で使える仕組み) で動かしています。
プロジェクトに請求先アカウントを紐付けなければ、自動的にサンドボックスになり、料金は一切かかりません。

> サンドボックスでは、**テーブルが作成から 60 日で自動的に消えます**。
> 消えても、下の「実行のしかた」の手順をもう一度実行すれば作り直せます ([ADR 004](docs/decisions/004_bigquery_sandbox.md))。

### 5. gcloud をインストールして、ログインする

gcloud をインストールします (Ubuntu の場合)。

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

ログインして、使うプロジェクトを設定します。`<プロジェクト ID>` は手順 4 で控えた ID に置き換えてください。

```bash
gcloud auth login
gcloud config set project <プロジェクト ID>
gcloud auth application-default login
gcloud auth application-default set-quota-project <プロジェクト ID>
```

ログインのコマンドが 2 種類あるのは、使う側が違うためです。

- `gcloud auth login` … `gcloud` や `bq` などの **コマンド** が使うログイン
- `gcloud auth application-default login` … **プログラム** (`load_raw.py` や dbt) が使うログイン

ブラウザが自動で開かない場合は、ターミナルに表示される URL をブラウザにコピーして開いてください。

ログインの情報はホームフォルダ (`~/.config/gcloud/`) に保存されます。リポジトリの外なので、git に入ることはありません。

### 6. dbt にプロジェクト ID を教える (自分のプロジェクトを使う場合)

dbt の接続設定 ([dbt/profiles.yml](dbt/profiles.yml)) には、このリポジトリの作者のプロジェクト ID が書かれています。
**自分のプロジェクトで動かす場合は**、環境変数で ID を指定してください。

```bash
export GCP_PROJECT_ID=<プロジェクト ID>
```

ターミナルを開き直すと消えるので、毎回入力するか、`~/.bashrc` に書いておきます。

### 7. つながるか確認する

```bash
cd dbt
uv run dbt deps    # dbt の追加パッケージ (dbt_utils) をダウンロードする
uv run dbt debug   # BigQuery につながるか確認する
```

`dbt debug` の最後に `All checks passed!` と表示されれば、セットアップは完了です。

## 実行のしかた

データを BigQuery に入れて、加工するまでの流れです。
初めて動かすときや、サンドボックスの 60 日の期限でテーブルが消えたときは、この手順を上から実行します。

### 1. CSV を BigQuery に読み込む (raw 層)

リポジトリのフォルダで実行します。

```bash
uv run python src/load_raw.py
```

7 つの CSV が、BigQuery の `olist_raw` データセットに読み込まれます。
CSV の件数と BigQuery の件数を比べて、すべて `OK` と表示されれば成功です。

```
読み込み先: <プロジェクト ID>.olist_raw (US)
  OK  olist_customers_dataset                  csv=  99,441  bigquery=  99,441
  ...
```

何度実行しても、テーブルが上書きされるだけなので問題ありません。

### 2. dbt で加工する (staging 層)

**dbt のコマンドは、`dbt` フォルダの中で実行します。**

```bash
cd dbt
uv run dbt build
```

`dbt build` は、次の 2 つをまとめて実行します。

1. **モデルを作る**: `models/` の SQL を BigQuery で実行し、ビューやテーブルを作ります。
2. **テストする**: データがルール通りか (ID が重複していないか、など) を確認します。

最後に次のような表示が出れば成功です。

```
Processed: 7 models | 67 tests
Summary: 74 total | 62 success | 12 warn
```

> **`warn` (警告) が出ても問題ありません。**
> 警告は、元データにもともとある不整合 (例: 配達済みなのに配達日時がない注文が 8 件) を知らせるものです。
> どの警告も原因がわかっていて、[docs/data_notes.md](docs/data_notes.md) に記録しています。
> 問題があるのは `error` が出た場合 (テストが失敗した、SQL が実行できなかった) です。

## よく使う dbt のコマンド

どれも `dbt` フォルダの中で、先頭に `uv run` を付けて実行します (例: `uv run dbt build`)。

| コマンド | 何をするか |
|---|---|
| `dbt build` | モデルを作って、テストする (普段はこれだけで OK) |
| `dbt run` | モデルを作るだけ (テストはしない) |
| `dbt test` | テストするだけ |
| `dbt build -s stg_orders` | `-s` (select) で、対象を絞る。この例では `stg_orders` だけ |
| `dbt show --inline "<SQL>"` | その場で書いた SQL を実行して、結果を表示する (何も作らない) |
| `dbt debug` | BigQuery につながるか確認する |
| `dbt deps` | 追加パッケージをダウンロードする |
| `dbt lint` | SQL の書き方をチェックする |

`dbt show` の例 (注文の件数を数える):

```bash
uv run dbt show --inline "select count(*) from {{ ref('stg_orders') }}"
```

`{{ ref('モデル名') }}` と書くと、dbt が BigQuery 上の正しいテーブル名に置き換えてくれます。

毎回 `uv run` を付けるのが面倒な場合は、リポジトリのフォルダで `source .venv/bin/activate` を実行しておくと、`dbt build` のように `uv run` なしで実行できます。

## 困ったとき

| 症状 | 原因と対処 |
|---|---|
| `Permission denied` や `does not have permission` と出る | プロジェクト **名** を ID の代わりに指定している可能性があります。`gcloud projects list` で ID を確認し、`gcloud config set project <ID>` で設定し直してください |
| `dbt debug` で接続に失敗する | `gcloud auth application-default login` をもう一度実行してください。自分のプロジェクトを使う場合は、`GCP_PROJECT_ID` を設定したかも確認してください |
| dbt のコマンドで `dbt_project.yml` が見つからないと言われる | `dbt` フォルダの中で実行しているか確認してください (`cd dbt`) |
| `dbt_utils` が見つからないと言われる | `uv run dbt deps` を実行してください |
| BigQuery のテーブルが消えた | サンドボックスの 60 日の期限です。「実行のしかた」の手順をもう一度実行してください |

## Jupyter notebook を開く

`notebooks/` の notebook は、VS Code で開けます。

1. VS Code に拡張機能「Jupyter」と「Python」を入れます。
2. notebook を開き、右上の **Select Kernel** → **Python Environments** → **`.venv`** を選びます。

## ドキュメント

| ファイル | 内容 |
|---|---|
| [docs/data_notes.md](docs/data_notes.md) | データの仕様と注意点 (テーブルの粒度、主キー、欠損、不整合など) |
| [docs/decisions/](docs/decisions/) | 設計の判断の記録 (ADR)。何を、何と比べて、なぜ決めたか |
| [notebooks/01_order_reviews_duplicates.ipynb](notebooks/01_order_reviews_duplicates.ipynb) | レビューの重複についての調査 |
