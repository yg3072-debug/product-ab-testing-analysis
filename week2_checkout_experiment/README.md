# Checkout A/B Testing Case Study

## Project Overview

This case study evaluates a simplified single-page checkout against an existing multi-step flow. It demonstrates an end-to-end product experimentation workflow using simulated event, assignment, user, and order data.

The analysis maintains one consistent primary definition throughout the project:

- **Population:** eligible users with a first valid checkout exposure and a complete 24-hour observation window
- **Analysis grain:** one row per mature exposed user
- **Primary metric:** attributed purchase conversion within 24 hours
- **Funnel:** `checkout_view → payment_attempt → purchase`
- **Treatment effect:** treatment conversion minus control conversion

All data are simulated and contain no real personal information.

## Final Readout

The treatment increased purchase conversion from **27.47% to 29.63%**, an absolute lift of **+2.16 percentage points** and a relative lift of **+7.85%**. The two-sided p-value was **0.0030**, with a 95% confidence interval of **+0.73 to +3.58 percentage points**.

Retained revenue per exposed user increased from **$24.52 to $26.33**, but checkout-error and refund/cancellation intervals did not rule out meaningful harm. No segment dimension showed confirmed treatment-effect heterogeneity after correction.

**Decision: Need more data before full launch.**

- [View the interactive executive dashboard](https://public.tableau.com/views/checkoutsimplificationABTest/ExecutiveDashboard?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)
- [Download the Power BI executive report](https://github.com/yg3072-debug/analytics-dashboard-portfolio/blob/main/powerbi/checkout_ab_test_executive_dashboard.pbix)
- [Open the dashboard portfolio repository](https://github.com/yg3072-debug/analytics-dashboard-portfolio)
- [Read the one-page experiment readout](experiment_readout.md)

## Analysis Workflow

| Stage | Deliverable |
|---|---|
| Experiment design | [`01_experiment_design.ipynb`](notebooks/01_experiment_design.ipynb) |
| Data preparation and simulation | [`02_data_preparation.ipynb`](notebooks/02_data_preparation.ipynb) |
| SQL validation and balance | [`03_sql_validation.ipynb`](notebooks/03_sql_validation.ipynb), [`01_experiment_validation.sql`](sql/01_experiment_validation.sql) |
| Ordered funnel analysis | [`04_funnel_analysis.ipynb`](notebooks/04_funnel_analysis.ipynb), [`02_funnel_analysis.sql`](sql/02_funnel_analysis.sql) |
| Primary statistical inference | [`05_statistical_inference.ipynb`](notebooks/05_statistical_inference.ipynb) |
| Exploratory segment analysis | [`06_segment_analysis.ipynb`](notebooks/06_segment_analysis.ipynb) |
| Secondary metrics, guardrails, and decision | [`07_secondary_guardrail_analysis.ipynb`](notebooks/07_secondary_guardrail_analysis.ipynb), [experiment readout](experiment_readout.md) |
| Tableau-ready data layer and analysis views | [`08_tableau_data_preparation.ipynb`](notebooks/08_tableau_data_preparation.ipynb), [`checkout_ab_test_dashboard.twbx`](tableau/checkout_ab_test_dashboard.twbx), [Tableau documentation](tableau/README.md) |
| Power BI semantic and reporting layer | [`powerbi/`](powerbi/), [Power BI documentation](powerbi/README.md) |
| Executive presentation | [Interactive Tableau dashboard](https://public.tableau.com/views/checkoutsimplificationABTest/ExecutiveDashboard?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link), [Power BI report](https://github.com/yg3072-debug/analytics-dashboard-portfolio/blob/main/powerbi/checkout_ab_test_executive_dashboard.pbix), [dashboard portfolio](https://github.com/yg3072-debug/analytics-dashboard-portfolio) |

The workflow is designed to be read as:

```text
business problem → experiment design → data validation → funnel
→ statistical inference → segment analysis → guardrails → recommendation
```

## Key Analytical Decisions

- The randomization and analysis units are both users.
- Exposure begins at the first valid checkout view after assignment.
- Purchases must occur after a qualifying payment attempt and within 24 hours of exposure.
- Users without a complete observation window are excluded from the mature analysis.
- Pooled standard errors are used for two-proportion null-hypothesis tests; unpooled standard errors are used for risk-difference confidence intervals.
- Segment findings are exploratory and use multiplicity adjustments plus direct heterogeneity tests.
- A non-significant guardrail difference is not treated as evidence of equivalence or safety.

## Reproducing the Analysis

Run the notebooks in numerical order. Their path-resolution logic supports execution from either:

- the repository root; or
- `week2_checkout_experiment/notebooks`.

The notebooks rebuild their analysis tables from the versioned CSV files and use an in-memory SQLite database, so no generated database file is required.

The Tableau preparation notebook exports a validated user-level source and a separate funnel summary to `data/processed`. The files are intentionally kept at different grains rather than joined. The final executive dashboard is maintained in the separate presentation repository, while the analysis definitions and reproducible data layer remain here.

## Tools

- Python and pandas
- SQLite and SQL window functions
- SciPy and standard statistical formulas
- Matplotlib
- Jupyter Notebook
- Tableau Public
- Power BI Desktop and DAX
