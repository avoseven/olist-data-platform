"""Olist データのキー制約とテーブル間リレーションを検証するスクリプト.

以下の 3 点を確認する。

1. 主キー (複合キーを含む) の一意性・非欠損
2. 外部キーの参照整合性 (子テーブルのキーが親テーブルに存在するか)
3. リレーションのカーディナリティ (1:1 / 1:N) が想定通りか

検証対象のキーやリレーションは ``PRIMARY_KEYS`` と ``RELATIONSHIPS`` に
宣言的に定義している。想定が変わった場合はそこを編集する。

Usage:
    python src/check_relationships.py
    python src/check_relationships.py --data-dir path/to/csv_dir
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path

import pandas as pd

# プロジェクトルート (このファイルの 1 つ上の階層) を基準にパスを解決する。
PROJECT_ROOT: Path = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR: Path = PROJECT_ROOT / "data" / "raw"

# テーブルの短縮名 -> CSV ファイル名
TABLE_FILES: dict[str, str] = {
    "customers": "olist_customers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}


class Cardinality(str, Enum):
    """親 1 行に対して子が何行対応するかの想定."""

    ONE_TO_ONE = "1:1"
    ONE_TO_MANY = "1:N"


@dataclass(frozen=True)
class Relationship:
    """2 テーブル間のリレーション (外部キー) の定義.

    Attributes:
        child: 参照する側のテーブル名。
        child_columns: 参照する側のキー列。
        parent: 参照される側のテーブル名。
        parent_columns: 参照される側のキー列 (``child_columns`` と同じ順序)。
        cardinality: 親 1 行に対する子の行数の想定。``None`` の場合は
            カーディナリティを検証しない (親側のキーが一意でない場合など)。
    """

    child: str
    child_columns: tuple[str, ...]
    parent: str
    parent_columns: tuple[str, ...]
    cardinality: Cardinality | None

    def __str__(self) -> str:
        return (
            f"{self.child}({', '.join(self.child_columns)})"
            f" -> {self.parent}({', '.join(self.parent_columns)})"
        )


# 各テーブルの主キーの想定。geolocation は郵便番号ごとに複数の緯度経度を
# 持つため主キーが無く、対象外としている。
PRIMARY_KEYS: dict[str, tuple[str, ...]] = {
    "customers": ("customer_id",),
    "orders": ("order_id",),
    "order_items": ("order_id", "order_item_id"),
    "order_payments": ("order_id", "payment_sequential"),
    "order_reviews": ("review_id", "order_id"),
    "products": ("product_id",),
    "sellers": ("seller_id",),
    "category_translation": ("product_category_name",),
}

# テーブル間リレーションの想定。
RELATIONSHIPS: list[Relationship] = [
    # customer_id は注文ごとに発行されるため、注文と 1:1 になる想定
    Relationship("orders", ("customer_id",), "customers", ("customer_id",), Cardinality.ONE_TO_ONE),
    Relationship("order_items", ("order_id",), "orders", ("order_id",), Cardinality.ONE_TO_MANY),
    Relationship("order_items", ("product_id",), "products", ("product_id",), Cardinality.ONE_TO_MANY),
    Relationship("order_items", ("seller_id",), "sellers", ("seller_id",), Cardinality.ONE_TO_MANY),
    Relationship("order_payments", ("order_id",), "orders", ("order_id",), Cardinality.ONE_TO_MANY),
    # 業務上は「1 注文に 1 レビュー」を想定
    Relationship("order_reviews", ("order_id",), "orders", ("order_id",), Cardinality.ONE_TO_ONE),
    Relationship(
        "products",
        ("product_category_name",),
        "category_translation",
        ("product_category_name",),
        Cardinality.ONE_TO_MANY,
    ),
    # geolocation 側の郵便番号は一意でないため、参照整合性のみ確認する
    Relationship(
        "customers",
        ("customer_zip_code_prefix",),
        "geolocation",
        ("geolocation_zip_code_prefix",),
        None,
    ),
    Relationship(
        "sellers",
        ("seller_zip_code_prefix",),
        "geolocation",
        ("geolocation_zip_code_prefix",),
        None,
    ),
]


@dataclass(frozen=True)
class PrimaryKeyResult:
    """主キー検証の結果.

    Attributes:
        table: テーブル名。
        key: 主キー列 (カンマ区切り)。
        rows: 行数。
        null_rows: キー列のいずれかが欠損している行数。
        duplicated_rows: キーが重複している行数 (2 回目以降の出現数)。
    """

    table: str
    key: str
    rows: int
    null_rows: int
    duplicated_rows: int

    @property
    def ok(self) -> bool:
        """欠損も重複も無ければ主キーとして成立する."""
        return self.null_rows == 0 and self.duplicated_rows == 0


@dataclass(frozen=True)
class IntegrityResult:
    """参照整合性検証の結果.

    Attributes:
        relationship: リレーションの表記。
        child_rows: 子テーブルのうち外部キーが欠損していない行数。
        orphan_rows: 親に存在しないキーを参照している行数。
        orphan_keys: 親に存在しないキーのユニーク数。
    """

    relationship: str
    child_rows: int
    orphan_rows: int
    orphan_keys: int

    @property
    def ok(self) -> bool:
        """孤立した行が無ければ参照整合性が保たれている."""
        return self.orphan_rows == 0


@dataclass(frozen=True)
class CardinalityResult:
    """カーディナリティ検証の結果.

    Attributes:
        relationship: リレーションの表記。
        expected: 想定したカーディナリティ。
        actual: 実データのカーディナリティ (子の最大件数が 1 以下なら 1:1)。
        max_children: 親 1 行あたりの子の最大件数。
        parents_with_many: 子を 2 件以上持つ親の数。
        parents_without_child: 子を 1 件も持たない親の数。
    """

    relationship: str
    expected: str
    actual: str
    max_children: int
    parents_with_many: int
    parents_without_child: int

    @property
    def ok(self) -> bool:
        """実データが想定に収まっているか.

        1:N の想定は 1:1 の実データも許容する (子が 1 件ずつでも矛盾はしない)。
        """
        return self.expected == Cardinality.ONE_TO_MANY.value or self.actual == self.expected


def _key_index(df: pd.DataFrame, columns: tuple[str, ...]) -> pd.MultiIndex:
    """指定列の値の組を MultiIndex に変換する (単一列・複合キーを同じ扱いにするため)."""
    return pd.MultiIndex.from_frame(df[list(columns)])


def load_tables(data_dir: Path) -> dict[str, pd.DataFrame]:
    """検証に必要な列だけを各 CSV から読み込む.

    キー同士を比較するため、すべての列を文字列として読み込む。数値として
    読むと、郵便番号の先頭 0 が落ちたり、欠損を含む整数列が float になったり
    して、値が一致しなくなるため。

    Args:
        data_dir: CSV が置かれたディレクトリ。

    Returns:
        テーブル名 -> DataFrame の辞書。検証に使わないテーブルは含まない。
    """
    needed: dict[str, set[str]] = {table: set() for table in TABLE_FILES}
    for table, columns in PRIMARY_KEYS.items():
        needed[table].update(columns)
    for rel in RELATIONSHIPS:
        needed[rel.child].update(rel.child_columns)
        needed[rel.parent].update(rel.parent_columns)

    return {
        table: pd.read_csv(data_dir / TABLE_FILES[table], usecols=sorted(columns), dtype=str)
        for table, columns in needed.items()
        if columns
    }


def check_primary_key(table: str, df: pd.DataFrame, key: tuple[str, ...]) -> PrimaryKeyResult:
    """主キーが一意かつ非欠損であるかを検証する.

    Args:
        table: テーブル名。
        df: 対象テーブル。
        key: 主キー列。

    Returns:
        検証結果。
    """
    key_df = df[list(key)]
    return PrimaryKeyResult(
        table=table,
        key=", ".join(key),
        rows=len(df),
        null_rows=int(key_df.isna().any(axis=1).sum()),
        duplicated_rows=int(key_df.duplicated().sum()),
    )


def check_referential_integrity(
    rel: Relationship, child: pd.DataFrame, parent: pd.DataFrame
) -> IntegrityResult:
    """子テーブルの外部キーがすべて親テーブルに存在するかを検証する.

    外部キーが欠損している行は「参照なし」とみなし、検証対象から除く。

    Args:
        rel: 検証するリレーション。
        child: 子テーブル。
        parent: 親テーブル。

    Returns:
        検証結果。
    """
    child_keys = _key_index(child.dropna(subset=list(rel.child_columns)), rel.child_columns)
    parent_keys = _key_index(parent, rel.parent_columns)

    orphans = child_keys[~child_keys.isin(parent_keys)]
    return IntegrityResult(
        relationship=str(rel),
        child_rows=len(child_keys),
        orphan_rows=len(orphans),
        orphan_keys=orphans.nunique(),
    )


def check_cardinality(
    rel: Relationship, child: pd.DataFrame, parent: pd.DataFrame
) -> CardinalityResult:
    """親 1 行あたりの子の件数を集計し、想定したカーディナリティと比較する.

    親側のキーが一意であること (主キーであること) を前提とする。

    Args:
        rel: 検証するリレーション。``cardinality`` が ``None`` でないこと。
        child: 子テーブル。
        parent: 親テーブル。

    Returns:
        検証結果。
    """
    if rel.cardinality is None:
        raise ValueError(f"cardinality が定義されていません: {rel}")

    child_keys = _key_index(child.dropna(subset=list(rel.child_columns)), rel.child_columns)
    parent_keys = _key_index(parent, rel.parent_columns)

    # 親に存在しないキー (孤立行) は参照整合性の検証で扱うため、ここでは除く
    children_per_parent = child_keys[child_keys.isin(parent_keys)].value_counts()
    max_children = int(children_per_parent.max()) if len(children_per_parent) else 0

    actual = Cardinality.ONE_TO_ONE if max_children <= 1 else Cardinality.ONE_TO_MANY
    return CardinalityResult(
        relationship=str(rel),
        expected=rel.cardinality.value,
        actual=actual.value,
        max_children=max_children,
        parents_with_many=int((children_per_parent > 1).sum()),
        parents_without_child=int((~parent_keys.isin(child_keys)).sum()),
    )


def to_report(
    results: list[PrimaryKeyResult] | list[IntegrityResult] | list[CardinalityResult],
) -> pd.DataFrame:
    """検証結果のリストを、判定列 (OK / NG) 付きの DataFrame に変換する."""
    return pd.DataFrame(
        [{"status": "OK" if r.ok else "NG", **asdict(r)} for r in results]
    )


def print_section(title: str, report: pd.DataFrame) -> None:
    """見出し付きで検証結果を表示する."""
    print("=" * 100)
    print(title)
    print("-" * 100)
    print(report.to_string(index=False))
    print()


def parse_args() -> argparse.Namespace:
    """コマンドライン引数を解析する."""
    parser = argparse.ArgumentParser(
        description="Olist データのキー制約とテーブル間リレーションを検証する。"
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DEFAULT_DATA_DIR,
        help=f"CSV が置かれたディレクトリ (default: {DEFAULT_DATA_DIR})",
    )
    return parser.parse_args()


def main() -> None:
    """エントリポイント. 3 種類の検証を順に実行して結果を表示する."""
    args = parse_args()
    tables = load_tables(args.data_dir)

    pk_results = [
        check_primary_key(table, tables[table], key) for table, key in PRIMARY_KEYS.items()
    ]
    integrity_results = [
        check_referential_integrity(rel, tables[rel.child], tables[rel.parent])
        for rel in RELATIONSHIPS
    ]
    cardinality_results = [
        check_cardinality(rel, tables[rel.child], tables[rel.parent])
        for rel in RELATIONSHIPS
        if rel.cardinality is not None
    ]

    print_section("1. Primary keys", to_report(pk_results))
    print_section("2. Referential integrity", to_report(integrity_results))
    print_section("3. Cardinality", to_report(cardinality_results))


if __name__ == "__main__":
    main()
