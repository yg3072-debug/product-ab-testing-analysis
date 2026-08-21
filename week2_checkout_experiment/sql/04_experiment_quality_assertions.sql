-- ============================================================
-- CHECKOUT EXPERIMENT SQL REGRESSION CHECKS
-- ============================================================
-- Dependencies: execute 02_funnel_analysis.sql and
-- 03_experiment_outcome_metrics.sql in the same SQLite connection.
--
-- Expected values are frozen portfolio results. They are used only as
-- regression checks; calculations remain data-driven in the preceding
-- SQL scripts.

DROP TABLE IF EXISTS sql_quality_checks;

CREATE TEMP TABLE sql_quality_checks AS
WITH integrity_checks AS (
    SELECT
        'grain' AS check_category,
        'mature exposed user rows' AS check_name,
        1.0 * (SELECT COUNT(*) FROM user_outcome_metrics) AS observed_value,
        15467.0 AS expected_value,
        0.0 AS tolerance

    UNION ALL

    SELECT
        'grain',
        'unique mature exposed users',
        1.0 * (SELECT COUNT(DISTINCT user_id) FROM user_outcome_metrics),
        15467.0,
        0.0

    UNION ALL

    SELECT
        'grain',
        'matched attributed orders',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE order_id IS NOT NULL
        ),
        4415.0,
        0.0

    UNION ALL

    SELECT
        'grain',
        'attributed purchasers with mature order follow-up',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_purchase = 1
              AND mature_order_followup = 1
        ),
        4415.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'duplicate user outcome rows',
        1.0 * (
            SELECT COUNT(*) - COUNT(DISTINCT user_id)
            FROM user_outcome_metrics
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'users without an exposure session mapping',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics u
            LEFT JOIN exposure_sessions s
                ON u.user_id = s.user_id
            WHERE s.user_id IS NULL
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'cross-assigned users in the mature population',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics u
            JOIN cross_assigned_users c
                ON u.user_id = c.user_id
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'ineligible users in the mature population',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics o
            JOIN users u
                ON o.user_id = u.user_id
            WHERE COALESCE(u.is_employee, 0) <> 0
               OR COALESCE(u.is_test_account, 0) <> 0
               OR COALESCE(u.is_bot, 0) <> 0
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'exposures before assignment',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE datetime(exposure_timestamp)
                  < datetime(assignment_timestamp)
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'payment attempts outside the attribution window',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_payment_attempt = 1
              AND (
                    payment_attempt_timestamp IS NULL
                 OR datetime(payment_attempt_timestamp)
                    < datetime(exposure_timestamp)
                 OR datetime(payment_attempt_timestamp)
                    > datetime(exposure_timestamp, '+24 hours')
              )
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'purchases outside the ordered attribution window',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_purchase = 1
              AND (
                    purchase_timestamp IS NULL
                 OR payment_attempt_timestamp IS NULL
                 OR datetime(purchase_timestamp)
                    < datetime(payment_attempt_timestamp)
                 OR datetime(purchase_timestamp)
                    > datetime(exposure_timestamp, '+24 hours')
              )
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'purchases without a qualifying payment attempt',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_purchase = 1
              AND reached_payment_attempt <> 1
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'attributed purchases without a matched order',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_purchase = 1
              AND order_id IS NULL
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'non-purchasers with a matched attributed order',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE reached_purchase = 0
              AND order_id IS NOT NULL
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'users with missing guardrail flags',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE had_payment_failure IS NULL
               OR had_checkout_error IS NULL
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'users with missing exposure dimensions',
        1.0 * (
            SELECT COUNT(*)
            FROM user_outcome_metrics
            WHERE device_at_exposure IS NULL
               OR traffic_source_at_exposure IS NULL
               OR user_type IS NULL
        ),
        0.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'device summary rows',
        1.0 * (SELECT COUNT(*) FROM device_conversion_summary),
        6.0,
        0.0

    UNION ALL

    SELECT
        'integrity',
        'guardrail summary rows',
        1.0 * (SELECT COUNT(*) FROM guardrail_summary),
        6.0,
        0.0
),
actual_results AS (
    SELECT
        experiment_group || ' exposed users' AS check_name,
        1.0 * exposed_users AS observed_value
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group || ' payment attempts',
        1.0 * payment_attempt_users
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group || ' purchases',
        1.0 * purchase_users
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group || ' purchase conversion',
        ROUND(purchase_conversion, 4)
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        experiment_group || ' retained revenue per exposed user',
        ROUND(retained_revenue_per_exposed_user, 2)
    FROM experiment_outcome_summary

    UNION ALL

    SELECT
        device || ' ' || experiment_group || ' conversion',
        ROUND(purchase_conversion, 4)
    FROM device_conversion_summary

    UNION ALL

    SELECT
        experiment_group || ' '
        || CASE metric
               WHEN 'payment_failure' THEN 'payment failure rate'
               WHEN 'checkout_error' THEN 'checkout error rate'
               WHEN 'refund_or_cancellation'
                   THEN 'refund or cancellation rate'
           END,
        ROUND(metric_rate, 4)
    FROM guardrail_summary

    UNION ALL

    SELECT
        'absolute purchase conversion lift',
        ROUND(treatment_minus_control, 4)
    FROM outcome_comparison
    WHERE metric = 'purchase_conversion'

    UNION ALL

    SELECT
        'relative purchase conversion lift',
        ROUND(relative_lift, 4)
    FROM outcome_comparison
    WHERE metric = 'purchase_conversion'
),
expected_results (
    check_category,
    check_name,
    expected_value,
    tolerance
) AS (
    VALUES
        ('population', 'control exposed users', 7754.0, 0.0),
        ('population', 'treatment exposed users', 7713.0, 0.0),
        ('funnel', 'control payment attempts', 5844.0, 0.0),
        ('funnel', 'treatment payment attempts', 6004.0, 0.0),
        ('funnel', 'control purchases', 2130.0, 0.0),
        ('funnel', 'treatment purchases', 2285.0, 0.0),
        ('conversion', 'control purchase conversion', 0.2747, 0.0000001),
        ('conversion', 'treatment purchase conversion', 0.2963, 0.0000001),
        ('conversion', 'absolute purchase conversion lift', 0.0216, 0.0000001),
        ('conversion', 'relative purchase conversion lift', 0.0785, 0.0000001),
        ('revenue', 'control retained revenue per exposed user', 24.52, 0.0000001),
        ('revenue', 'treatment retained revenue per exposed user', 26.33, 0.0000001),
        ('device', 'desktop control conversion', 0.2799, 0.0000001),
        ('device', 'desktop treatment conversion', 0.2966, 0.0000001),
        ('device', 'mobile control conversion', 0.2703, 0.0000001),
        ('device', 'mobile treatment conversion', 0.2949, 0.0000001),
        ('device', 'tablet control conversion', 0.2848, 0.0000001),
        ('device', 'tablet treatment conversion', 0.3072, 0.0000001),
        ('guardrail', 'control payment failure rate', 0.0536, 0.0000001),
        ('guardrail', 'treatment payment failure rate', 0.0513, 0.0000001),
        ('guardrail', 'control checkout error rate', 0.0307, 0.0000001),
        ('guardrail', 'treatment checkout error rate', 0.0349, 0.0000001),
        ('guardrail', 'control refund or cancellation rate', 0.0568, 0.0000001),
        ('guardrail', 'treatment refund or cancellation rate', 0.0648, 0.0000001)
),
result_checks AS (
    SELECT
        e.check_category,
        e.check_name,
        a.observed_value,
        e.expected_value,
        e.tolerance
    FROM expected_results e
    LEFT JOIN actual_results a
        ON e.check_name = a.check_name
),
all_checks AS (
    SELECT * FROM integrity_checks
    UNION ALL
    SELECT * FROM result_checks
)
SELECT
    check_category,
    check_name,
    observed_value,
    expected_value,
    tolerance,
    CASE
        WHEN observed_value IS NOT NULL
         AND ABS(observed_value - expected_value) <= tolerance
        THEN 1 ELSE 0
    END AS passed
FROM all_checks;

SELECT
    check_category,
    check_name,
    observed_value,
    expected_value,
    tolerance,
    passed
FROM sql_quality_checks
ORDER BY check_category, check_name;
