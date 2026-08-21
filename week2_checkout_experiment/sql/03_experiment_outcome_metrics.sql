-- ============================================================
-- CHECKOUT EXPERIMENT OUTCOME METRICS
-- ============================================================
-- Business question:
-- Beyond funnel progression, how did the checkout treatment affect
-- conversion, retained revenue, device performance, and guardrails?
--
-- Dependency: execute 02_funnel_analysis.sql in the same SQLite
-- connection before this script. That script defines the canonical
-- mature population and the user_level_funnel table.
--
-- Primary grain: one row per mature exposed user.
-- Purchase attribution window: first valid exposure through +24 hours.
-- Order follow-up window: seven days after the attributed purchase.
-- Order data cutoff: 2026-07-22 23:59:59.

DROP TABLE IF EXISTS outcome_comparison;
DROP TABLE IF EXISTS guardrail_summary;
DROP TABLE IF EXISTS device_conversion_summary;
DROP TABLE IF EXISTS experiment_outcome_summary;
DROP TABLE IF EXISTS user_outcome_metrics;
DROP TABLE IF EXISTS user_guardrail_flags;
DROP TABLE IF EXISTS exposure_sessions;

-- ------------------------------------------------------------
-- 1. IDENTIFY THE FIRST VALID EXPOSURE SESSION
-- ------------------------------------------------------------

CREATE TEMP TABLE exposure_sessions AS
SELECT
    f.user_id,
    MIN(e.session_id) AS exposure_session_id
FROM user_level_funnel f
JOIN deduplicated_events e
    ON f.user_id = e.user_id
   AND f.experiment_group = e.experiment_group
   AND e.event_name = 'checkout_view'
   AND e.event_timestamp = f.exposure_timestamp
GROUP BY f.user_id;

CREATE UNIQUE INDEX exposure_sessions_user_idx
    ON exposure_sessions(user_id);

-- ------------------------------------------------------------
-- 2. BUILD USER-LEVEL GUARDRAIL FLAGS
-- ------------------------------------------------------------
-- Payment failure is evaluated among users with a qualifying payment
-- attempt and inside the 24-hour attribution window.
--
-- Checkout error is evaluated for all exposed users and restricted to
-- the first valid exposure session.

CREATE TEMP TABLE user_guardrail_flags AS
SELECT
    f.user_id,
    MAX(
        CASE
            WHEN e.event_name = 'payment_failure'
             AND f.payment_attempt_timestamp IS NOT NULL
             AND datetime(e.event_timestamp)
                 >= datetime(f.payment_attempt_timestamp)
             AND datetime(e.event_timestamp)
                 <= datetime(f.exposure_timestamp, '+24 hours')
            THEN 1 ELSE 0
        END
    ) AS had_payment_failure,
    MAX(
        CASE
            WHEN e.event_name = 'checkout_error'
             AND e.session_id = s.exposure_session_id
             AND datetime(e.event_timestamp)
                 >= datetime(f.exposure_timestamp)
            THEN 1 ELSE 0
        END
    ) AS had_checkout_error
FROM user_level_funnel f
JOIN exposure_sessions s
    ON f.user_id = s.user_id
LEFT JOIN deduplicated_events e
    ON f.user_id = e.user_id
   AND f.experiment_group = e.experiment_group
GROUP BY f.user_id;

CREATE UNIQUE INDEX user_guardrail_flags_user_idx
    ON user_guardrail_flags(user_id);

-- ------------------------------------------------------------
-- 3. BUILD THE REUSABLE USER-LEVEL OUTCOME TABLE
-- ------------------------------------------------------------

CREATE TEMP TABLE user_outcome_metrics AS
SELECT
    f.user_id,
    f.experiment_group,
    f.assignment_timestamp,
    f.exposure_timestamp,
    f.device_at_exposure,
    f.traffic_source_at_exposure,
    f.user_type,
    f.payment_attempt_timestamp,
    f.purchase_timestamp,
    f.reached_checkout_view,
    f.reached_payment_attempt,
    f.reached_purchase,
    g.had_payment_failure,
    g.had_checkout_error,
    CASE
        WHEN f.reached_payment_attempt = 1
        THEN 1 - g.had_payment_failure
    END AS payment_succeeded,
    o.order_id,
    o.order_amount,
    o.order_status,
    CASE
        WHEN f.purchase_timestamp IS NOT NULL
         AND datetime(f.purchase_timestamp, '+7 days')
             <= datetime('2026-07-22 23:59:59')
        THEN 1 ELSE 0
    END AS mature_order_followup,
    CASE
        WHEN o.order_status = 'completed' THEN o.order_amount
        ELSE 0
    END AS retained_revenue,
    CASE
        WHEN o.order_status IN ('refunded', 'cancelled') THEN 1
        ELSE 0
    END AS refunded_or_cancelled
FROM user_level_funnel f
LEFT JOIN user_guardrail_flags g
    ON f.user_id = g.user_id
LEFT JOIN orders o
    ON f.user_id = o.user_id
   AND f.experiment_group = o.experiment_group
   AND f.purchase_timestamp = o.purchase_timestamp;

CREATE UNIQUE INDEX user_outcome_metrics_user_idx
    ON user_outcome_metrics(user_id);

CREATE INDEX user_outcome_metrics_group_idx
    ON user_outcome_metrics(experiment_group);

CREATE INDEX user_outcome_metrics_device_idx
    ON user_outcome_metrics(device_at_exposure, experiment_group);

-- ------------------------------------------------------------
-- 4. EXPERIMENT-LEVEL OUTCOME SUMMARY
-- ------------------------------------------------------------

CREATE TEMP TABLE experiment_outcome_summary AS
SELECT
    experiment_group,
    COUNT(*) AS exposed_users,
    SUM(reached_payment_attempt) AS payment_attempt_users,
    SUM(reached_purchase) AS purchase_users,
    ROUND(
        1.0 * SUM(reached_purchase) / COUNT(*),
        6
    ) AS purchase_conversion,
    ROUND(
        1.0 * SUM(retained_revenue) / COUNT(*),
        6
    ) AS retained_revenue_per_exposed_user,
    SUM(had_payment_failure) AS payment_failure_users,
    ROUND(
        1.0 * SUM(had_payment_failure)
        / NULLIF(SUM(reached_payment_attempt), 0),
        6
    ) AS payment_failure_rate,
    SUM(had_checkout_error) AS checkout_error_users,
    ROUND(
        1.0 * SUM(had_checkout_error) / COUNT(*),
        6
    ) AS checkout_error_rate,
    SUM(
        CASE
            WHEN reached_purchase = 1
             AND mature_order_followup = 1
            THEN 1 ELSE 0
        END
    ) AS mature_purchasers,
    SUM(
        CASE
            WHEN reached_purchase = 1
             AND mature_order_followup = 1
            THEN refunded_or_cancelled ELSE 0
        END
    ) AS refund_cancel_users,
    ROUND(
        1.0 * SUM(
            CASE
                WHEN reached_purchase = 1
                 AND mature_order_followup = 1
                THEN refunded_or_cancelled ELSE 0
            END
        )
        / NULLIF(
            SUM(
                CASE
                    WHEN reached_purchase = 1
                     AND mature_order_followup = 1
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        6
    ) AS refund_cancel_rate
FROM user_outcome_metrics
GROUP BY experiment_group;

-- ------------------------------------------------------------
-- 5. DEVICE CONVERSION SUMMARY
-- ------------------------------------------------------------

CREATE TEMP TABLE device_conversion_summary AS
SELECT
    device_at_exposure AS device,
    experiment_group,
    COUNT(*) AS exposed_users,
    SUM(reached_purchase) AS purchase_users,
    ROUND(
        1.0 * SUM(reached_purchase) / COUNT(*),
        6
    ) AS purchase_conversion
FROM user_outcome_metrics
GROUP BY device_at_exposure, experiment_group;

-- ------------------------------------------------------------
-- 6. LONG-FORM GUARDRAIL SUMMARY WITH EXPLICIT DENOMINATORS
-- ------------------------------------------------------------

CREATE TEMP TABLE guardrail_summary AS
SELECT
    1 AS metric_order,
    'payment_failure' AS metric,
    experiment_group,
    SUM(had_payment_failure) AS event_users,
    SUM(reached_payment_attempt) AS eligible_users,
    ROUND(
        1.0 * SUM(had_payment_failure)
        / NULLIF(SUM(reached_payment_attempt), 0),
        6
    ) AS metric_rate,
    'users with a qualifying payment attempt' AS denominator_definition
FROM user_outcome_metrics
GROUP BY experiment_group

UNION ALL

SELECT
    2 AS metric_order,
    'checkout_error' AS metric,
    experiment_group,
    SUM(had_checkout_error) AS event_users,
    COUNT(*) AS eligible_users,
    ROUND(
        1.0 * SUM(had_checkout_error) / COUNT(*),
        6
    ) AS metric_rate,
    'mature exposed users' AS denominator_definition
FROM user_outcome_metrics
GROUP BY experiment_group

UNION ALL

SELECT
    3 AS metric_order,
    'refund_or_cancellation' AS metric,
    experiment_group,
    SUM(
        CASE
            WHEN reached_purchase = 1
             AND mature_order_followup = 1
            THEN refunded_or_cancelled ELSE 0
        END
    ) AS event_users,
    SUM(
        CASE
            WHEN reached_purchase = 1
             AND mature_order_followup = 1
            THEN 1 ELSE 0
        END
    ) AS eligible_users,
    ROUND(
        1.0 * SUM(
            CASE
                WHEN reached_purchase = 1
                 AND mature_order_followup = 1
                THEN refunded_or_cancelled ELSE 0
            END
        )
        / NULLIF(
            SUM(
                CASE
                    WHEN reached_purchase = 1
                     AND mature_order_followup = 1
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        6
    ) AS metric_rate,
    'attributed purchasers with seven-day follow-up' AS denominator_definition
FROM user_outcome_metrics
GROUP BY experiment_group;

-- ------------------------------------------------------------
-- 7. DESCRIPTIVE TREATMENT-CONTROL COMPARISON
-- ------------------------------------------------------------
-- Statistical inference remains in 05_statistical_inference.ipynb and
-- 07_secondary_guardrail_analysis.ipynb. This table intentionally
-- reports descriptive differences only.

CREATE TEMP TABLE outcome_comparison AS
WITH metric_long AS (
    SELECT
        experiment_group,
        1 AS metric_order,
        'purchase_conversion' AS metric,
        'rate' AS metric_type,
        purchase_conversion AS metric_value
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group,
        2 AS metric_order,
        'retained_revenue_per_exposed_user' AS metric,
        'currency' AS metric_type,
        retained_revenue_per_exposed_user AS metric_value
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group,
        3 AS metric_order,
        'payment_failure_rate' AS metric,
        'rate' AS metric_type,
        payment_failure_rate AS metric_value
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group,
        4 AS metric_order,
        'checkout_error_rate' AS metric,
        'rate' AS metric_type,
        checkout_error_rate AS metric_value
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group,
        5 AS metric_order,
        'refund_cancel_rate' AS metric,
        'rate' AS metric_type,
        refund_cancel_rate AS metric_value
    FROM experiment_outcome_summary
),
metric_wide AS (
    SELECT
        metric_order,
        metric,
        metric_type,
        MAX(
            CASE
                WHEN experiment_group = 'control' THEN metric_value
            END
        ) AS control_value,
        MAX(
            CASE
                WHEN experiment_group = 'treatment' THEN metric_value
            END
        ) AS treatment_value
    FROM metric_long
    GROUP BY metric_order, metric, metric_type
)
SELECT
    metric_order,
    metric,
    metric_type,
    control_value,
    treatment_value,
    ROUND(treatment_value - control_value, 6) AS treatment_minus_control,
    CASE
        WHEN metric = 'purchase_conversion'
        THEN ROUND(
            treatment_value / NULLIF(control_value, 0) - 1.0,
            6
        )
    END AS relative_lift
FROM metric_wide;

-- ------------------------------------------------------------
-- 8. PORTFOLIO OUTPUTS
-- ------------------------------------------------------------

SELECT *
FROM experiment_outcome_summary
ORDER BY experiment_group;

SELECT *
FROM device_conversion_summary
ORDER BY device, experiment_group;

SELECT
    metric,
    experiment_group,
    event_users,
    eligible_users,
    metric_rate,
    denominator_definition
FROM guardrail_summary
ORDER BY metric_order, experiment_group;

SELECT
    metric,
    metric_type,
    control_value,
    treatment_value,
    treatment_minus_control,
    relative_lift
FROM outcome_comparison
ORDER BY metric_order;
