"""Kohortová retence: % uživatelů z měsíční registrační kohorty,
kteří dokončili aspoň jednu completed objednávku v offsetu 0-3 měsíců.

Optimalizováno: CommonInterface, memory-efficient dtypes, usecols filtering.
"""
from __future__ import annotations

import pandas as pd
from keboola.component import CommonInterface

COHORT_OFFSETS = [0, 1, 2, 3]


def build_cohort_retention(users: pd.DataFrame, orders: pd.DataFrame) -> pd.DataFrame:
    """Vrátí DataFrame: cohort_month, cohort_size,
    month_{k}_users a month_{k}_retention_pct pro k v COHORT_OFFSETS."""

    # Kohorty: user_id -> kalendářní měsíc registrace
    users["cohort_month"] = pd.to_datetime(users["registered_at"]).dt.to_period("M")
    cohort_size = (
        users.groupby("cohort_month")["user_id"]
        .nunique()
        .rename("cohort_size")
        .reset_index()
    )

    # Completed objednávky bez nejasných statusů + měsíc objednávky
    completed = orders[
        (orders["status"] == "completed")
        & (orders["is_status_unknown"].astype(str) == "0")
    ].copy()
    completed["order_month"] = pd.to_datetime(completed["order_date"]).dt.to_period("M")

    # Offset v měsících od registrace (vektorizovaně přes year*12+month)
    merged = completed.merge(users[["user_id", "cohort_month"]], on="user_id")
    merged["period_index"] = (
        (merged["order_month"].dt.year - merged["cohort_month"].dt.year) * 12
        + (merged["order_month"].dt.month - merged["cohort_month"].dt.month)
    )
    merged = merged[merged["period_index"].isin(COHORT_OFFSETS)]

    # Pivot: unikátní aktivní uživatelé na (kohorta, offset)
    active = (
        merged.groupby(["cohort_month", "period_index"])["user_id"]
        .nunique()
        .unstack(fill_value=0)
        .reindex(columns=COHORT_OFFSETS, fill_value=0)
    )
    active.columns = [f"month_{k}_users" for k in COHORT_OFFSETS]

    result = cohort_size.merge(active.reset_index(), on="cohort_month", how="left").fillna(0)

    # Retence v %
    for k in COHORT_OFFSETS:
        users_col = f"month_{k}_users"
        result[users_col] = result[users_col].astype(int)
        result[f"month_{k}_retention_pct"] = (
            result[users_col] / result["cohort_size"] * 100
        ).round(2)

    result["cohort_month"] = result["cohort_month"].astype(str)
    return result.sort_values("cohort_month").reset_index(drop=True)


def main() -> None:
    ci = CommonInterface()

    # Load only required columns with optimized dtypes
    users = pd.read_csv(
        ci.get_input_table_definition_by_name("user_segments").full_path,
        usecols=["user_id", "registered_at"],
        dtype={"user_id": "str", "registered_at": "str"}
    )
    
    orders = pd.read_csv(
        ci.get_input_table_definition_by_name("stg_orders").full_path,
        usecols=["user_id", "order_date", "status", "is_status_unknown"],
        dtype={"user_id": "str", "order_date": "str", "status": "category", "is_status_unknown": "str"}
    )
    
    print(f"Načteno: users={len(users)}, orders={len(orders)}")

    result = build_cohort_retention(users, orders)
    print(f"Výsledek: {len(result)} kohort")

    # Write output using CommonInterface
    out_table = ci.create_out_table_definition(
        "cohort_retention",
        primary_key=["cohort_month"],
        incremental=False
    )
    result.to_csv(out_table.full_path, index=False)
    
    print(f"OK: {len(result)} kohort zapsáno.")

main()
