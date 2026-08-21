# SQL Analytics Layer — Checkout A/B Test

## Purpose

This SQL layer reconstructs the checkout experiment from raw assignment, user, event, and order tables. It provides a reproducible path from canonical population construction to funnel, conversion, device, retained-revenue, and guardrail outputs.

The SQL implementation complements the statistical notebooks and dashboard layers. Hypothesis tests and confidence intervals remain in the statistical inference notebooks; the SQL outputs focus on population construction, descriptive metrics, explicit denominators, and data-quality controls.

## Source Tables

| Table | Grain | Role |
|---|---|---|
| `users` | One row per user | Eligibility and user type |
| `experiment_assignments` | One row per raw assignment record | Variant assignment and assignment time |
| `events` | One row per raw event record | Exposure, funnel progression, and event guardrails |
| `orders` | One row per order | Order value and seven-day outcome status |

All source data are simulated and contain no real personal information.

## Analytical Definitions

- **Population:** eligible users with a first valid checkout exposure and a complete 24-hour observation window
- **Primary grain:** one row per mature exposed user
- **Purchase attribution:** first purchase after a qualifying payment attempt and within 24 hours of exposure
- **Device:** device recorded at first valid exposure
- **Retained revenue:** completed-order revenue; refunded and cancelled orders contribute zero
- **Payment failure denominator:** users with a qualifying payment attempt
- **Checkout error denominator:** mature exposed users
- **Refund/cancellation denominator:** attributed purchasers with complete seven-day order follow-up

## Execution Order

| Script | Responsibility |
|---|---|
| [`01_experiment_validation.sql`](01_experiment_validation.sql) | Source-grain, duplicate, assignment, eligibility, and temporal audits |
| [`02_funnel_analysis.sql`](02_funnel_analysis.sql) | Canonical mature population and ordered cumulative funnel |
| [`03_experiment_outcome_metrics.sql`](03_experiment_outcome_metrics.sql) | User-level outcome table plus experiment, device, revenue, and guardrail summaries |
| [`04_experiment_quality_assertions.sql`](04_experiment_quality_assertions.sql) | Regression checks against the frozen portfolio results |

`03_experiment_outcome_metrics.sql` depends on the temporary tables created by `02_funnel_analysis.sql`. `04_experiment_quality_assertions.sql` depends on both preceding scripts.

## Reproduction

From the repository root, run:

```bash
python week2_checkout_experiment/scripts/run_sql_case_study.py
```

The runner loads the four raw CSV files into an in-memory SQLite database, executes the SQL pipeline in dependency order, and fails if any frozen-result check does not pass.

Optional CSV exports can be written outside the repository or to a temporary working directory:

```bash
python week2_checkout_experiment/scripts/run_sql_case_study.py --export-dir <output-directory>
```

## Validated Results

| Metric | Control | Treatment |
|---|---:|---:|
| Mature exposed users | 7,754 | 7,713 |
| Purchase conversion | 27.47% | 29.63% |
| Retained revenue per exposed user | $24.52 | $26.33 |
| Payment failure | 5.36% | 5.13% |
| Checkout error | 3.07% | 3.49% |
| Refund/cancellation | 5.68% | 6.48% |

Device conversion is also reproduced at the exposure-device grain:

| Device | Control | Treatment |
|---|---:|---:|
| Desktop | 27.99% | 29.66% |
| Mobile | 27.03% | 29.49% |
| Tablet | 28.48% | 30.72% |

The treatment-minus-control purchase conversion difference is **+2.16 percentage points**, with a relative lift of **+7.85%**. Statistical significance and confidence intervals are maintained in [`05_statistical_inference.ipynb`](../notebooks/05_statistical_inference.ipynb).

## SQL Capabilities Demonstrated

- Window-based assignment and event deduplication
- Temporal joins and bounded attribution windows
- Ordered cumulative funnel construction
- Conditional aggregation with metric-specific denominators
- User-, experiment-, device-, and metric-level grains
- Reusable temporary tables and targeted indexes
- Automated regression checks for analytical consistency
