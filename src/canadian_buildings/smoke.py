"""Smoke helpers that keep the Python gates permanently active."""

from __future__ import annotations

import duckdb


def select_one() -> int:
    """Return DuckDB's result for an in-memory ``SELECT 1``."""
    row = duckdb.sql("SELECT 1").fetchone()
    if row is None:
        raise RuntimeError("DuckDB returned no rows for SELECT 1")
    return int(row[0])
