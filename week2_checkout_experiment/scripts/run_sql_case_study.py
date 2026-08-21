"""Execute and validate the checkout experiment SQL analytics layer."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

import pandas as pd


EXPERIMENT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = EXPERIMENT_ROOT / "data" / "raw"
SQL_DIR = EXPERIMENT_ROOT / "sql"

RAW_TABLES = (
    "users",
    "experiment_assignments",
    "events",
    "orders",
)

SQL_PIPELINE = (
    "02_funnel_analysis.sql",
    "03_experiment_outcome_metrics.sql",
    "04_experiment_quality_assertions.sql",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rebuild the mature checkout experiment population and validate "
            "funnel, conversion, device, revenue, and guardrail metrics."
        )
    )
    parser.add_argument(
        "--export-dir",
        type=Path,
        help="Optional directory for CSV exports of the SQL summary tables.",
    )
    return parser.parse_args()


def load_raw_tables(connection: sqlite3.Connection) -> pd.DataFrame:
    audit_rows: list[dict[str, int | str]] = []

    for table_name in RAW_TABLES:
        source_path = RAW_DATA_DIR / f"{table_name}.csv"
        frame = pd.read_csv(source_path)
        frame.to_sql(table_name, connection, index=False, if_exists="replace")
        audit_rows.append({"table_name": table_name, "rows": len(frame)})

    return pd.DataFrame(audit_rows)


def execute_sql_pipeline(connection: sqlite3.Connection) -> None:
    for script_name in SQL_PIPELINE:
        script_path = SQL_DIR / script_name
        connection.executescript(script_path.read_text(encoding="utf-8"))


def read_outputs(connection: sqlite3.Connection) -> dict[str, pd.DataFrame]:
    return {
        "experiment_outcome_summary": pd.read_sql_query(
            """
            SELECT *
            FROM experiment_outcome_summary
            ORDER BY experiment_group;
            """,
            connection,
        ),
        "device_conversion_summary": pd.read_sql_query(
            """
            SELECT *
            FROM device_conversion_summary
            ORDER BY device, experiment_group;
            """,
            connection,
        ),
        "guardrail_summary": pd.read_sql_query(
            """
            SELECT
                metric,
                experiment_group,
                event_users,
                eligible_users,
                metric_rate,
                denominator_definition
            FROM guardrail_summary
            ORDER BY metric_order, experiment_group;
            """,
            connection,
        ),
        "outcome_comparison": pd.read_sql_query(
            """
            SELECT
                metric,
                metric_type,
                control_value,
                treatment_value,
                treatment_minus_control,
                relative_lift
            FROM outcome_comparison
            ORDER BY metric_order;
            """,
            connection,
        ),
        "sql_quality_checks": pd.read_sql_query(
            """
            SELECT *
            FROM sql_quality_checks
            ORDER BY check_category, check_name;
            """,
            connection,
        ),
    }


def validate_quality_checks(quality_checks: pd.DataFrame) -> None:
    failures = quality_checks.loc[quality_checks["passed"].ne(1)]
    if not failures.empty:
        raise RuntimeError(
            "SQL regression checks failed:\n"
            + failures.to_string(index=False)
        )


def export_outputs(
    outputs: dict[str, pd.DataFrame],
    export_dir: Path,
) -> None:
    resolved_dir = export_dir.expanduser().resolve()
    resolved_dir.mkdir(parents=True, exist_ok=True)

    for output_name, frame in outputs.items():
        frame.to_csv(resolved_dir / f"{output_name}.csv", index=False)

    print(f"\nExported SQL outputs to: {resolved_dir}")


def main() -> None:
    args = parse_args()

    with sqlite3.connect(":memory:") as connection:
        raw_table_audit = load_raw_tables(connection)
        execute_sql_pipeline(connection)
        outputs = read_outputs(connection)

    validate_quality_checks(outputs["sql_quality_checks"])

    print("Raw input audit")
    print(raw_table_audit.to_string(index=False))

    print("\nExperiment outcome summary")
    print(outputs["experiment_outcome_summary"].to_string(index=False))

    print("\nDevice conversion summary")
    print(outputs["device_conversion_summary"].to_string(index=False))

    print("\nGuardrail summary")
    print(outputs["guardrail_summary"].to_string(index=False))

    print("\nDescriptive treatment-control comparison")
    print(outputs["outcome_comparison"].to_string(index=False))

    print(
        "\nSQL validation passed: "
        f"{len(outputs['sql_quality_checks'])} of "
        f"{len(outputs['sql_quality_checks'])} checks passed."
    )

    if args.export_dir is not None:
        export_outputs(outputs, args.export_dir)


if __name__ == "__main__":
    main()
