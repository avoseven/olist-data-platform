"""Olist の生データ (CSV) を初期確認するスクリプト.

``data/raw`` 配下の各 CSV について、以下を一覧表示する。

- 行数
- カラム名
- データ型 (pandas が推論した dtype)
- 欠損数・欠損率
- ID カラム (``*_id``) のユニーク数・重複数

Usage:
    python src/inspect_data.py
    python src/inspect_data.py --data-dir path/to/csv_dir
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

# プロジェクトルート (このファイルの 1 つ上の階層) を基準にパスを解決する。
# 実行時のカレントディレクトリに依存しないようにするため。
PROJECT_ROOT: Path = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR: Path = PROJECT_ROOT / "data" / "raw"

# Olist のデータセットでは ID カラムはすべてこの接尾辞で命名されている
ID_COLUMN_SUFFIX: str = "_id"


@dataclass(frozen=True)
class CsvSummary:
    """1 つの CSV ファイルに対する確認結果.

    Attributes:
        name: ファイル名 (拡張子なし)。
        n_rows: 行数 (ヘッダ行を除く)。
        columns: カラムごとの情報 (column / dtype / missing / missing_rate)。
        ids: ID カラムごとの情報 (column / unique / duplicated)。
            ID カラムが無い場合は空の DataFrame。
    """

    name: str
    n_rows: int
    columns: pd.DataFrame
    ids: pd.DataFrame


def summarize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """DataFrame の各カラムについてデータ型と欠損状況をまとめる.

    Args:
        df: 対象の DataFrame。

    Returns:
        1 行 = 1 カラムの DataFrame。列は以下の通り。

        - ``column``: カラム名
        - ``dtype``: pandas の dtype
        - ``missing``: 欠損数
        - ``missing_rate``: 欠損率 (%)
    """
    missing = df.isna().sum()
    # 0 行の CSV でもゼロ除算にならないよう分母を 1 以上にする
    missing_rate = missing / max(len(df), 1) * 100

    return pd.DataFrame(
        {
            "column": df.columns,
            "dtype": df.dtypes.astype(str).to_numpy(),
            "missing": missing.to_numpy(),
            "missing_rate": missing_rate.round(2).to_numpy(),
        }
    )


def summarize_ids(df: pd.DataFrame) -> pd.DataFrame:
    """ID カラム (``*_id``) ごとにユニーク数と重複数をまとめる.

    重複数は「2 回目以降に出現した行の数」(= 非欠損行数 - ユニーク数) とする。
    重複数が 0 であれば、そのカラムは単独で主キーになり得る。

    Args:
        df: 対象の DataFrame。

    Returns:
        1 行 = 1 ID カラムの DataFrame。列は以下の通り。

        - ``column``: カラム名
        - ``unique``: ユニーク数 (欠損は除く)
        - ``duplicated``: 重複数 (欠損は除く)
    """
    id_columns = [c for c in df.columns if c.endswith(ID_COLUMN_SUFFIX)]
    rows = []
    for col in id_columns:
        values = df[col].dropna()
        n_unique = values.nunique()
        rows.append(
            {"column": col, "unique": n_unique, "duplicated": len(values) - n_unique}
        )
    return pd.DataFrame(rows, columns=["column", "unique", "duplicated"])


def inspect_csv(path: Path) -> CsvSummary:
    """CSV を読み込み、行数・カラム情報・ID 情報を集計する.

    Args:
        path: CSV ファイルのパス。

    Returns:
        集計結果。
    """
    df = pd.read_csv(path)
    return CsvSummary(
        name=path.stem,
        n_rows=len(df),
        columns=summarize_columns(df),
        ids=summarize_ids(df),
    )


def print_summary(summary: CsvSummary) -> None:
    """集計結果を標準出力に表示する.

    Args:
        summary: :func:`inspect_csv` の戻り値。
    """
    print("=" * 80)
    print(f"{summary.name}")
    print(f"  rows: {summary.n_rows:,} / columns: {len(summary.columns)}")
    print("-" * 80)
    print(summary.columns.to_string(index=False))
    if not summary.ids.empty:
        print("-" * 80)
        print(summary.ids.to_string(index=False))
    print()


def parse_args() -> argparse.Namespace:
    """コマンドライン引数を解析する."""
    parser = argparse.ArgumentParser(description="Olist の生データ CSV を初期確認する。")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help=f"CSV が置かれたディレクトリ (default: {DEFAULT_DATA_DIR})",
    )
    return parser.parse_args()


def main() -> None:
    """エントリポイント. 指定ディレクトリ内の全 CSV を確認して表示する."""
    args = parse_args()
    data_dir: Path = args.data_dir

    csv_paths = sorted(data_dir.glob("*.csv"))
    if not csv_paths:
        raise SystemExit(f"CSV が見つかりません: {data_dir}")

    summaries = [inspect_csv(path) for path in csv_paths]
    for summary in summaries:
        print_summary(summary)

    # 最後にファイル単位の概要をまとめて表示する
    overview = pd.DataFrame(
        {
            "file": [s.name for s in summaries],
            "rows": [s.n_rows for s in summaries],
            "columns": [len(s.columns) for s in summaries],
            "total_missing": [int(s.columns["missing"].sum()) for s in summaries],
        }
    )
    print("=" * 80)
    print("Overview")
    print("-" * 80)
    print(overview.to_string(index=False))


if __name__ == "__main__":
    main()
