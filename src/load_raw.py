"""Olist の CSV を BigQuery の raw データセットに読み込むスクリプト.

- 対象: ADR 001 で選定した 7 テーブル
- 入力: ``data/raw/*.csv``
- 出力: BigQuery の raw データセット (既定: ``olist_raw``、ロケーション: US)

ADR 002 の方針に従い、CSV に手を加えずに読み込む。

- テーブル名は CSV のファイル名 (拡張子を除く) をそのまま使う
- 全列を STRING として読み込む (型の変換は staging で行う)
- 列名は CSV の見出し行から取る

BigQuery サンドボックスではテーブルが 60 日で削除されるため (ADR 004)、
何度実行しても同じ結果になるよう、テーブルは毎回上書きする。

認証には、``gcloud auth application-default login`` で作成した
認証情報 (Application Default Credentials) を使う。

Usage:
    python src/load_raw.py
    python src/load_raw.py --project my-project --dataset olist_raw
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

from google.cloud import bigquery

# プロジェクトルート (このファイルの 1 つ上の階層) を基準にパスを解決する。
PROJECT_ROOT: Path = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR: Path = PROJECT_ROOT / "data" / "raw"

DEFAULT_DATASET: str = "olist_raw"
# raw / staging / mart のデータセットは同じロケーションにそろえる必要がある
LOCATION: str = "US"

# ADR 001 で選定したテーブル (CSV のファイル名から拡張子を除いたもの)
TABLES: tuple[str, ...] = (
    "olist_customers_dataset",
    "olist_orders_dataset",
    "olist_order_items_dataset",
    "olist_products_dataset",
    "olist_order_payments_dataset",
    "olist_order_reviews_dataset",
    "product_category_name_translation",
)


@dataclass(frozen=True)
class LoadResult:
    """1 テーブル分の読み込み結果.

    Attributes:
        table: テーブル名。
        csv_records: CSV のレコード数 (見出し行を除く)。
        loaded_rows: 読み込み後の BigQuery テーブルの行数。
    """

    table: str
    csv_records: int
    loaded_rows: int

    @property
    def ok(self) -> bool:
        """CSV と BigQuery で件数が一致しているか."""
        return self.csv_records == self.loaded_rows


def read_csv_header(path: Path) -> list[str]:
    """CSV の見出し行 (列名) を読み込む.

    Args:
        path: CSV ファイルのパス。

    Returns:
        列名のリスト。
    """
    # product_category_name_translation.csv は先頭に BOM があり、
    # utf-8 で読むと最初の列名に BOM が混ざるため、utf-8-sig で読む
    with path.open(newline="", encoding="utf-8-sig") as f:
        return next(csv.reader(f))


def count_csv_records(path: Path) -> int:
    """CSV のレコード数 (見出し行を除く) を数える.

    値の中に改行を含むレコードがあるため、ファイルの行数ではなく、
    CSV として解釈したレコード数を数える。

    Args:
        path: CSV ファイルのパス。

    Returns:
        レコード数。
    """
    with path.open(newline="", encoding="utf-8-sig") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def ensure_dataset(client: bigquery.Client, dataset_id: str) -> None:
    """データセットが無ければ作成する.

    既に存在する場合は、ロケーションが想定と一致するかを確認する。

    Args:
        client: BigQuery クライアント。
        dataset_id: ``<project>.<dataset>`` 形式のデータセット ID。

    Raises:
        SystemExit: 既存のデータセットのロケーションが想定と異なる場合。
    """
    dataset = bigquery.Dataset(dataset_id)
    dataset.location = LOCATION
    dataset = client.create_dataset(dataset, exists_ok=True)

    # exists_ok=True では、既存のデータセットのロケーションは検証されない
    if dataset.location != LOCATION:
        raise SystemExit(
            f"データセット {dataset_id} のロケーションが {dataset.location} です"
            f" (想定: {LOCATION})"
        )


def load_csv(client: bigquery.Client, path: Path, table_id: str) -> bigquery.Table:
    """CSV を全列 STRING のテーブルとして読み込む.

    Args:
        client: BigQuery クライアント。
        path: CSV ファイルのパス。
        table_id: ``<project>.<dataset>.<table>`` 形式のテーブル ID。

    Returns:
        読み込み後のテーブル。
    """
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        # 自動検出を使うと郵便番号が数値になり、先頭の 0 が消えるため、スキーマを明示する
        schema=[bigquery.SchemaField(name, "STRING") for name in read_csv_header(path)],
        skip_leading_rows=1,
        # order_reviews のレビュー本文には、引用符で囲まれた改行が含まれる
        allow_quoted_newlines=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    with path.open("rb") as f:
        job = client.load_table_from_file(f, table_id, job_config=job_config, location=LOCATION)
    job.result()  # 読み込みの完了を待つ。失敗した場合は例外が送出される
    return client.get_table(table_id)


def parse_args() -> argparse.Namespace:
    """コマンドライン引数を解析する."""
    parser = argparse.ArgumentParser(description="Olist の CSV を BigQuery の raw データセットに読み込む。")
    parser.add_argument(
        "--project",
        default=None,
        help="GCP プロジェクト ID (default: gcloud の設定から取得)",
    )
    parser.add_argument(
        "--dataset",
        default=DEFAULT_DATASET,
        help=f"読み込み先のデータセット (default: {DEFAULT_DATASET})",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help=f"CSV が置かれたディレクトリ (default: {DEFAULT_DATA_DIR})",
    )
    return parser.parse_args()


def main() -> None:
    """エントリポイント. 全テーブルを読み込み、件数を検証する."""
    args = parse_args()

    # 存在しない CSV があれば、BigQuery を操作する前に止める
    missing = [t for t in TABLES if not (args.data_dir / f"{t}.csv").exists()]
    if missing:
        raise SystemExit(f"CSV が見つかりません: {', '.join(missing)} ({args.data_dir})")

    client = bigquery.Client(project=args.project)
    dataset_id = f"{client.project}.{args.dataset}"
    print(f"読み込み先: {dataset_id} ({LOCATION})")
    ensure_dataset(client, dataset_id)

    results: list[LoadResult] = []
    for table in TABLES:
        path = args.data_dir / f"{table}.csv"
        loaded = load_csv(client, path, f"{dataset_id}.{table}")
        result = LoadResult(table=table, csv_records=count_csv_records(path), loaded_rows=loaded.num_rows)
        results.append(result)
        status = "OK" if result.ok else "NG"
        print(f"  {status}  {table:<40} csv={result.csv_records:>8,}  bigquery={result.loaded_rows:>8,}")

    if not all(r.ok for r in results):
        raise SystemExit("CSV と BigQuery で件数が一致しないテーブルがあります")


if __name__ == "__main__":
    main()
