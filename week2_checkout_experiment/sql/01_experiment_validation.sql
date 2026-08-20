-- ============================================================
-- 1. TABLE GRAIN AND PRIMARY-KEY CHECKS
-- ============================================================

-- users: expected grain = one row per user

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT user_id) AS unique_users
FROM users;

-- experiment_assignments:
-- expected raw grain = one row per assignment record

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT assignment_id) AS unique_assignment_ids,
    COUNT(DISTINCT user_id) AS unique_users
FROM experiment_assignments;

-- events:
-- expected raw grain = one row per event record

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT event_id) AS unique_event_ids,
    COUNT(DISTINCT user_id) AS unique_users
FROM events;

-- orders:
-- expected grain = one row per order

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(DISTINCT user_id) AS unique_purchasers
FROM orders;

-- ============================================================
-- 2. DUPLICATE ASSIGNMENT RECORDS
-- ============================================================

SELECT
    assignment_id,
    COUNT(*) AS record_count
FROM experiment_assignments
GROUP BY assignment_id
HAVING COUNT(*) > 1
ORDER BY record_count DESC, assignment_id;

SELECT
    assignment_id,
    user_id,
    experiment_group,
    assignment_timestamp,
    COUNT(*) AS record_count
FROM experiment_assignments
GROUP BY
    assignment_id,
    user_id,
    experiment_group,
    assignment_timestamp
HAVING COUNT(*) > 1
ORDER BY record_count DESC;

-- ============================================================
-- 3. CROSS-GROUP ASSIGNMENT CHECK
-- ============================================================

SELECT
    user_id,
    COUNT(DISTINCT experiment_group) AS group_count,
    MIN(assignment_timestamp) AS first_assignment,
    MAX(assignment_timestamp) AS last_assignment
FROM experiment_assignments
GROUP BY user_id
HAVING COUNT(DISTINCT experiment_group) > 1
ORDER BY user_id;

-- ============================================================
-- 4. DUPLICATE EVENT RECORDS
-- ============================================================

SELECT
    event_id,
    COUNT(*) AS record_count
FROM events
GROUP BY event_id
HAVING COUNT(*) > 1
ORDER BY record_count DESC, event_id;

-- ============================================================
-- 5. CANONICAL ASSIGNMENT RECORDS
-- ============================================================

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number

    FROM experiment_assignments
)

SELECT *
FROM ranked_assignments
WHERE assignment_row_number = 1;

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT *
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
)

SELECT *
FROM cross_assigned_users;

-- ============================================================
-- 6. INVALID / INTERNAL TRAFFIC
-- ============================================================

SELECT
    SUM(CASE WHEN is_employee = 1 THEN 1 ELSE 0 END) AS employees,
    SUM(CASE WHEN is_test_account = 1 THEN 1 ELSE 0 END) AS test_accounts,
    SUM(CASE WHEN is_bot = 1 THEN 1 ELSE 0 END) AS bots
FROM users;

SELECT
    COUNT(*) AS eligible_users
FROM users
WHERE is_employee = 0
  AND is_test_account = 0
  AND is_bot = 0;

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
)

SELECT *
FROM canonical_assignments;

-- ============================================================
-- 7. TEMPORAL CONSISTENCY CHECK
-- ============================================================

-- Validate that a user is not assigned to the experiment
-- before the user is first observed on the platform.
--
-- This check is performed after assignment deduplication and
-- removal of cross-assigned users to avoid inflated counts.

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
)

SELECT
    COUNT(*) AS assignment_before_first_seen
FROM canonical_assignments a
JOIN users u
    ON a.user_id = u.user_id
WHERE datetime(a.assignment_timestamp)
    < datetime(u.first_seen_timestamp);


-- ============================================================
-- 8. PRE-ASSIGNMENT CHECKOUT EVENTS
-- ============================================================

-- Raw event data intentionally contain checkout events that
-- occur before assignment. These events must not be treated
-- as valid experiment exposure.

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

deduplicated_events AS (

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
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
)

SELECT
    COUNT(*) AS checkout_events_before_assignment
FROM canonical_assignments a
JOIN deduplicated_events e
    ON a.user_id = e.user_id
WHERE e.event_name = 'checkout_view'
  AND datetime(e.event_timestamp)
      < datetime(a.assignment_timestamp);


-- ============================================================
-- 9. FIRST VALID EXPERIMENT EXPOSURE
-- ============================================================

-- Valid exposure definition:
--
-- 1. user has a valid canonical experiment assignment;
-- 2. user is not employee/test/bot traffic;
-- 3. duplicate raw events are removed;
-- 4. event is a checkout_view;
-- 5. checkout_view occurs after experiment assignment;
-- 6. event group matches assigned experiment group.
--
-- The first valid checkout_view becomes the user's exposure.

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT
        user_id,
        first_seen_timestamp,
        user_type
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

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
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

first_valid_exposure AS (

    SELECT
        user_id,
        experiment_group,
        assignment_timestamp,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
)

SELECT
    COUNT(*) AS valid_exposed_users
FROM first_valid_exposure;


-- ============================================================
-- 10. COMPLETE 24-HOUR OBSERVATION WINDOW
-- ============================================================

-- Primary conversion attribution window = 24 hours.
--
-- Event data are available through:
-- 2026-07-15 12:00:00
--
-- Therefore a user must have:
--
-- exposure_timestamp + 24 hours <= event data cutoff
--
-- to be included in the mature primary analysis population.

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT
        user_id,
        first_seen_timestamp,
        user_type
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

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
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

first_valid_exposure AS (

    SELECT
        user_id,
        experiment_group,
        assignment_timestamp,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
),

mature_experiment_population AS (

    SELECT *
    FROM first_valid_exposure
    WHERE datetime(
        exposure_timestamp,
        '+24 hours'
    ) <= datetime('2026-07-15 12:00:00')
)

SELECT
    COUNT(*) AS mature_exposed_users
FROM mature_experiment_population;


-- ============================================================
-- 11. TREATMENT-CONTROL SAMPLE SIZE BALANCE
-- ============================================================

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT
        user_id,
        first_seen_timestamp,
        user_type
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

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
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

first_valid_exposure AS (

    SELECT
        user_id,
        experiment_group,
        assignment_timestamp,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
),

mature_experiment_population AS (

    SELECT *
    FROM first_valid_exposure
    WHERE datetime(
        exposure_timestamp,
        '+24 hours'
    ) <= datetime('2026-07-15 12:00:00')
)

SELECT
    experiment_group,
    COUNT(*) AS users,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_population
FROM mature_experiment_population
GROUP BY experiment_group
ORDER BY experiment_group;


-- ============================================================
-- 12. PRE-TREATMENT / EXPOSURE-LEVEL BALANCE CHECKS
-- ============================================================

-- The following CTE constructs the final mature experiment
-- population once conceptually. Each balance query below can
-- be run independently using the same CTE chain.

-- ------------------------------------------------------------
-- 12A. NEW VS RETURNING USER BALANCE
-- ------------------------------------------------------------

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT
        user_id,
        first_seen_timestamp,
        user_type
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

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
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

first_valid_exposure AS (

    SELECT
        user_id,
        experiment_group,
        assignment_timestamp,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
),

mature_experiment_population AS (

    SELECT *
    FROM first_valid_exposure
    WHERE datetime(
        exposure_timestamp,
        '+24 hours'
    ) <= datetime('2026-07-15 12:00:00')
)

SELECT
    p.experiment_group,
    u.user_type,
    COUNT(*) AS users,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (
            PARTITION BY p.experiment_group
        ),
        2
    ) AS pct_within_group
FROM mature_experiment_population p
JOIN users u
    ON p.user_id = u.user_id
GROUP BY
    p.experiment_group,
    u.user_type
ORDER BY
    p.experiment_group,
    u.user_type;


-- ------------------------------------------------------------
-- 12B. DEVICE BALANCE
-- ------------------------------------------------------------

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT
        user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT user_id
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

    SELECT *
    FROM (

        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY event_id
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

mature_experiment_population AS (

    SELECT
        user_id,
        experiment_group,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
      AND datetime(
          event_timestamp,
          '+24 hours'
      ) <= datetime('2026-07-15 12:00:00')
)

SELECT
    experiment_group,
    device_at_exposure,
    COUNT(*) AS users,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (
            PARTITION BY experiment_group
        ),
        2
    ) AS pct_within_group
FROM mature_experiment_population
GROUP BY
    experiment_group,
    device_at_exposure
ORDER BY
    experiment_group,
    device_at_exposure;


-- ------------------------------------------------------------
-- 12C. TRAFFIC-SOURCE BALANCE
-- ------------------------------------------------------------

WITH ranked_assignments AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY assignment_id
            ORDER BY assignment_timestamp
        ) AS assignment_row_number
    FROM experiment_assignments
),

deduplicated_assignments AS (

    SELECT
        assignment_id,
        experiment_name,
        user_id,
        experiment_group,
        assignment_timestamp
    FROM ranked_assignments
    WHERE assignment_row_number = 1
),

cross_assigned_users AS (

    SELECT user_id
    FROM deduplicated_assignments
    GROUP BY user_id
    HAVING COUNT(DISTINCT experiment_group) > 1
),

canonical_assignments AS (

    SELECT da.*
    FROM deduplicated_assignments da
    LEFT JOIN cross_assigned_users ca
        ON da.user_id = ca.user_id
    WHERE ca.user_id IS NULL
),

eligible_users AS (

    SELECT user_id
    FROM users
    WHERE is_employee = 0
      AND is_test_account = 0
      AND is_bot = 0
),

deduplicated_events AS (

    SELECT *
    FROM (

        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY event_id
                ORDER BY event_timestamp
            ) AS event_row_number

        FROM events
    )

    WHERE event_row_number = 1
),

valid_checkout_events AS (

    SELECT
        a.user_id,
        a.experiment_group,
        a.assignment_timestamp,
        e.event_timestamp,
        e.device,
        e.traffic_source
    FROM canonical_assignments a

    JOIN eligible_users u
        ON a.user_id = u.user_id

    JOIN deduplicated_events e
        ON a.user_id = e.user_id

    WHERE e.event_name = 'checkout_view'
      AND datetime(e.event_timestamp)
          >= datetime(a.assignment_timestamp)
      AND e.experiment_group = a.experiment_group
),

ranked_exposures AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS exposure_rank
    FROM valid_checkout_events
),

mature_experiment_population AS (

    SELECT
        user_id,
        experiment_group,
        event_timestamp AS exposure_timestamp,
        device AS device_at_exposure,
        traffic_source AS traffic_source_at_exposure
    FROM ranked_exposures
    WHERE exposure_rank = 1
      AND datetime(
          event_timestamp,
          '+24 hours'
      ) <= datetime('2026-07-15 12:00:00')
)

SELECT
    experiment_group,
    traffic_source_at_exposure,
    COUNT(*) AS users,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (
            PARTITION BY experiment_group
        ),
        2
    ) AS pct_within_group
FROM mature_experiment_population
GROUP BY
    experiment_group,
    traffic_source_at_exposure
ORDER BY
    experiment_group,
    traffic_source_at_exposure;