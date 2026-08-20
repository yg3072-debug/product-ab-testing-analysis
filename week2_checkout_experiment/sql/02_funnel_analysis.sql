-- ============================================================
-- WEEK 2 DAY 11: EXPERIMENT FUNNEL ANALYSIS
-- ============================================================
-- Business question:
-- Does the simplified checkout flow move more mature, eligible
-- exposed users through checkout_view -> payment_attempt -> purchase?
--
-- Analysis grain: one row per mature exposed user.
-- Attribution window: [first valid checkout exposure, +24 hours].
-- Purchase is cumulative: it must occur after a qualifying payment
-- attempt and within 24 hours of the first valid exposure.

DROP TABLE IF EXISTS funnel_comparison;
DROP TABLE IF EXISTS funnel_by_step;
DROP TABLE IF EXISTS funnel_summary;
DROP TABLE IF EXISTS user_level_funnel;
DROP TABLE IF EXISTS first_purchase_after_payment;
DROP TABLE IF EXISTS first_payment_attempt;
DROP TABLE IF EXISTS mature_experiment_population;
DROP TABLE IF EXISTS first_valid_exposure;
DROP TABLE IF EXISTS ranked_exposures;
DROP TABLE IF EXISTS valid_checkout_events;
DROP TABLE IF EXISTS deduplicated_events;
DROP TABLE IF EXISTS eligible_users;
DROP TABLE IF EXISTS canonical_assignments;
DROP TABLE IF EXISTS cross_assigned_users;
DROP TABLE IF EXISTS deduplicated_assignments;
DROP TABLE IF EXISTS ranked_assignments;

-- ------------------------------------------------------------
-- 1. REBUILD THE DAY 10 CANONICAL POPULATION
-- ------------------------------------------------------------

CREATE TEMP TABLE ranked_assignments AS
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY assignment_id
        ORDER BY datetime(assignment_timestamp)
    ) AS assignment_row_number
FROM experiment_assignments;

CREATE TEMP TABLE deduplicated_assignments AS
SELECT
    assignment_id,
    experiment_name,
    user_id,
    experiment_group,
    assignment_timestamp
FROM ranked_assignments
WHERE assignment_row_number = 1;

CREATE TEMP TABLE cross_assigned_users AS
SELECT user_id
FROM deduplicated_assignments
GROUP BY user_id
HAVING COUNT(DISTINCT experiment_group) > 1;

CREATE TEMP TABLE canonical_assignments AS
SELECT da.*
FROM deduplicated_assignments da
LEFT JOIN cross_assigned_users ca
    ON da.user_id = ca.user_id
WHERE ca.user_id IS NULL;

CREATE INDEX canonical_assignments_user_idx
    ON canonical_assignments(user_id);

CREATE TEMP TABLE eligible_users AS
SELECT
    user_id,
    first_seen_timestamp,
    user_type
FROM users
WHERE is_employee = 0
  AND is_test_account = 0
  AND is_bot = 0;

CREATE INDEX eligible_users_user_idx
    ON eligible_users(user_id);

CREATE TEMP TABLE deduplicated_events AS
SELECT
    event_id,
    user_id,
    event_timestamp,
    event_name,
    experiment_group,
    device,
    traffic_source,
    session_id
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY event_id
            ORDER BY datetime(event_timestamp)
        ) AS event_row_number
    FROM events
)
WHERE event_row_number = 1;

CREATE INDEX deduplicated_events_funnel_idx
    ON deduplicated_events(
        user_id,
        experiment_group,
        event_name,
        event_timestamp
    );

CREATE TEMP TABLE valid_checkout_events AS
SELECT
    a.user_id,
    a.experiment_group,
    a.assignment_timestamp,
    u.user_type,
    e.event_id AS exposure_event_id,
    e.event_timestamp,
    e.device,
    e.traffic_source
FROM canonical_assignments a
JOIN eligible_users u
    ON a.user_id = u.user_id
JOIN deduplicated_events e
    ON a.user_id = e.user_id
WHERE e.event_name = 'checkout_view'
  AND datetime(e.event_timestamp) >= datetime(a.assignment_timestamp)
  AND e.experiment_group = a.experiment_group;

CREATE TEMP TABLE ranked_exposures AS
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY user_id
        ORDER BY datetime(event_timestamp), exposure_event_id
    ) AS exposure_rank
FROM valid_checkout_events;

CREATE TEMP TABLE first_valid_exposure AS
SELECT
    user_id,
    experiment_group,
    assignment_timestamp,
    user_type,
    event_timestamp AS exposure_timestamp,
    device AS device_at_exposure,
    traffic_source AS traffic_source_at_exposure
FROM ranked_exposures
WHERE exposure_rank = 1;

CREATE TEMP TABLE mature_experiment_population AS
SELECT *
FROM first_valid_exposure
WHERE datetime(exposure_timestamp, '+24 hours')
      <= datetime('2026-07-15 12:00:00');

CREATE UNIQUE INDEX mature_population_user_idx
    ON mature_experiment_population(user_id);

-- ------------------------------------------------------------
-- 2. BUILD ORDERED, CUMULATIVE FUNNEL STEPS
-- ------------------------------------------------------------
-- A payment attempt qualifies only when it occurs on or after the
-- first valid exposure and no later than 24 hours after exposure.

CREATE TEMP TABLE first_payment_attempt AS
SELECT
    p.user_id,
    MIN(e.event_timestamp) AS payment_attempt_timestamp
FROM mature_experiment_population p
JOIN deduplicated_events e
    ON p.user_id = e.user_id
   AND e.experiment_group = p.experiment_group
WHERE e.event_name = 'payment_attempt'
  AND datetime(e.event_timestamp) >= datetime(p.exposure_timestamp)
  AND datetime(e.event_timestamp)
      <= datetime(p.exposure_timestamp, '+24 hours')
GROUP BY p.user_id;

CREATE UNIQUE INDEX first_payment_attempt_user_idx
    ON first_payment_attempt(user_id);

-- A purchase qualifies only when it occurs after a qualifying payment
-- attempt and remains inside the same 24-hour exposure window.

CREATE TEMP TABLE first_purchase_after_payment AS
SELECT
    p.user_id,
    MIN(e.event_timestamp) AS purchase_timestamp
FROM mature_experiment_population p
JOIN first_payment_attempt pa
    ON p.user_id = pa.user_id
JOIN deduplicated_events e
    ON p.user_id = e.user_id
   AND e.experiment_group = p.experiment_group
WHERE e.event_name = 'purchase'
  AND datetime(e.event_timestamp) >= datetime(pa.payment_attempt_timestamp)
  AND datetime(e.event_timestamp)
      <= datetime(p.exposure_timestamp, '+24 hours')
GROUP BY p.user_id;

CREATE UNIQUE INDEX first_purchase_user_idx
    ON first_purchase_after_payment(user_id);

CREATE TEMP TABLE user_level_funnel AS
SELECT
    p.user_id,
    p.experiment_group,
    p.assignment_timestamp,
    p.exposure_timestamp,
    p.device_at_exposure,
    p.traffic_source_at_exposure,
    p.user_type,
    pa.payment_attempt_timestamp,
    pu.purchase_timestamp,
    1 AS reached_checkout_view,
    CASE
        WHEN pa.user_id IS NOT NULL THEN 1
        ELSE 0
    END AS reached_payment_attempt,
    CASE
        WHEN pu.user_id IS NOT NULL THEN 1
        ELSE 0
    END AS reached_purchase
FROM mature_experiment_population p
LEFT JOIN first_payment_attempt pa
    ON p.user_id = pa.user_id
LEFT JOIN first_purchase_after_payment pu
    ON p.user_id = pu.user_id;

CREATE UNIQUE INDEX user_level_funnel_user_idx
    ON user_level_funnel(user_id);

CREATE INDEX user_level_funnel_group_idx
    ON user_level_funnel(experiment_group);

-- ------------------------------------------------------------
-- 3. GROUP-LEVEL FUNNEL METRICS
-- ------------------------------------------------------------

CREATE TEMP TABLE funnel_summary AS
SELECT
    experiment_group,
    COUNT(*) AS exposed_users,
    SUM(reached_payment_attempt) AS payment_attempt_users,
    SUM(reached_purchase) AS purchase_users,
    ROUND(
        1.0 * SUM(reached_payment_attempt) / COUNT(*),
        4
    ) AS checkout_to_payment_conversion,
    ROUND(
        1.0 * SUM(reached_purchase)
        / NULLIF(SUM(reached_payment_attempt), 0),
        4
    ) AS payment_to_purchase_conversion,
    ROUND(
        1.0 * SUM(reached_purchase) / COUNT(*),
        4
    ) AS checkout_to_purchase_conversion
FROM user_level_funnel
GROUP BY experiment_group;

CREATE TEMP TABLE funnel_by_step AS
SELECT
    experiment_group,
    1 AS step_order,
    'checkout_view' AS funnel_step,
    COUNT(*) AS step_users,
    COUNT(*) AS previous_step_users,
    1.0 AS step_to_step_conversion,
    1.0 AS conversion_from_exposure
FROM user_level_funnel
GROUP BY experiment_group

UNION ALL

SELECT
    experiment_group,
    2 AS step_order,
    'payment_attempt' AS funnel_step,
    SUM(reached_payment_attempt) AS step_users,
    COUNT(*) AS previous_step_users,
    ROUND(
        1.0 * SUM(reached_payment_attempt) / COUNT(*),
        4
    ) AS step_to_step_conversion,
    ROUND(
        1.0 * SUM(reached_payment_attempt) / COUNT(*),
        4
    ) AS conversion_from_exposure
FROM user_level_funnel
GROUP BY experiment_group

UNION ALL

SELECT
    experiment_group,
    3 AS step_order,
    'purchase' AS funnel_step,
    SUM(reached_purchase) AS step_users,
    SUM(reached_payment_attempt) AS previous_step_users,
    ROUND(
        1.0 * SUM(reached_purchase)
        / NULLIF(SUM(reached_payment_attempt), 0),
        4
    ) AS step_to_step_conversion,
    ROUND(
        1.0 * SUM(reached_purchase) / COUNT(*),
        4
    ) AS conversion_from_exposure
FROM user_level_funnel
GROUP BY experiment_group;

-- Descriptive treatment-control differences only. Statistical inference
-- is intentionally deferred to Day 12.

CREATE TEMP TABLE funnel_comparison AS
WITH metric_long AS (
    SELECT
        experiment_group,
        1 AS metric_order,
        'checkout_to_payment_conversion' AS metric,
        1.0 * payment_attempt_users / exposed_users AS metric_value
    FROM funnel_summary

    UNION ALL

    SELECT
        experiment_group,
        2 AS metric_order,
        'payment_to_purchase_conversion' AS metric,
        1.0 * purchase_users
        / NULLIF(payment_attempt_users, 0) AS metric_value
    FROM funnel_summary

    UNION ALL

    SELECT
        experiment_group,
        3 AS metric_order,
        'checkout_to_purchase_conversion' AS metric,
        1.0 * purchase_users / exposed_users AS metric_value
    FROM funnel_summary
),
metric_wide AS (
    SELECT
        metric_order,
        metric,
        MAX(
            CASE WHEN experiment_group = 'control'
                 THEN metric_value END
        ) AS control_rate,
        MAX(
            CASE WHEN experiment_group = 'treatment'
                 THEN metric_value END
        ) AS treatment_rate
    FROM metric_long
    GROUP BY metric_order, metric
)
SELECT
    metric_order,
    metric,
    ROUND(control_rate, 4) AS control_rate,
    ROUND(treatment_rate, 4) AS treatment_rate,
    ROUND(treatment_rate - control_rate, 4) AS absolute_difference,
    ROUND(
        treatment_rate / NULLIF(control_rate, 0) - 1.0,
        4
    ) AS relative_lift
FROM metric_wide;

-- ------------------------------------------------------------
-- 4. PORTFOLIO OUTPUTS
-- ------------------------------------------------------------

SELECT *
FROM funnel_by_step
ORDER BY experiment_group, step_order;

SELECT *
FROM funnel_summary
ORDER BY experiment_group;

SELECT
    metric,
    control_rate,
    treatment_rate,
    absolute_difference,
    relative_lift
FROM funnel_comparison
ORDER BY metric_order;
