-- =====================================================
-- ClearPort Analytics on Snowflake
-- Run each block one at a time in a Snowsight SQL worksheet
-- (highlight the block, then Ctrl+Enter)
-- =====================================================

-- STEP 1: Set up the warehouse, database and schema
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
CREATE DATABASE IF NOT EXISTS CLEARPORT;
CREATE SCHEMA IF NOT EXISTS CLEARPORT.ANALYTICS;
USE SCHEMA CLEARPORT.ANALYTICS;

-- STEP 2: Create the raw table (all text, so nothing fails on load)
CREATE OR REPLACE TABLE RAW_SHIPMENTS (
    shipment_id                 VARCHAR,
    port                        VARCHAR,
    shipping_line               VARCHAR,
    cargo_type                  VARCHAR,
    container_type              VARCHAR,
    num_containers              VARCHAR,
    arrival_date                VARCHAR,
    clearance_date              VARCHAR,
    clearance_days              VARCHAR,
    free_days                   VARCHAR,
    demurrage_rate_usd_per_day  VARCHAR,
    demurrage_cost_usd          VARCHAR,
    cargo_value_usd             VARCHAR,
    duty_paid_usd               VARCHAR,
    documentation_status        VARCHAR,
    delay_cause                 VARCHAR,
    clearing_agent              VARCHAR,
    status                      VARCHAR
);

-- >>> Load the data: run clearport_load_ALL.sql (INSERT OVERWRITE of all 3,025 rows) <<<

-- STEP 3: Check the load. Expect 3025 rows (3000 real + 25 duplicates)
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT shipment_id) AS unique_shipments
FROM RAW_SHIPMENTS;

-- See the messy port names
SELECT port, COUNT(*) FROM RAW_SHIPMENTS GROUP BY port ORDER BY 2 DESC;

-- STEP 4: Clean view (dedupe, fix port names, convert types, handle blanks)
CREATE OR REPLACE VIEW SHIPMENTS_CLEAN AS
SELECT
    shipment_id,
    CASE
        WHEN UPPER(port) LIKE 'APAPA%' THEN 'Apapa'
        WHEN REPLACE(REPLACE(UPPER(port), '-', ''), ' ', '') LIKE 'TINCAN%' THEN 'Tin Can Island'
        ELSE port
    END                                                AS port,
    shipping_line,
    cargo_type,
    container_type,
    TRY_TO_NUMBER(num_containers)                      AS num_containers,
    COALESCE(TRY_TO_DATE(arrival_date, 'YYYY-MM-DD'),
             TRY_TO_DATE(arrival_date, 'DD/MM/YYYY'))  AS arrival_date,   -- 60 dates were DD/MM/YYYY
    TRY_TO_DATE(clearance_date, 'YYYY-MM-DD')          AS clearance_date,
    TRY_TO_DECIMAL(clearance_days, 10, 1)              AS clearance_days,
    TRY_TO_NUMBER(free_days)                           AS free_days,
    TRY_TO_NUMBER(demurrage_rate_usd_per_day)          AS demurrage_rate_usd_per_day,
    TRY_TO_DECIMAL(demurrage_cost_usd, 14, 2)          AS demurrage_cost_usd,
    TRY_TO_DECIMAL(cargo_value_usd, 14, 2)             AS cargo_value_usd,
    TRY_TO_DECIMAL(duty_paid_usd, 14, 2)               AS duty_paid_usd,
    documentation_status,
    NULLIF(NULLIF(delay_cause, 'None'), '')            AS delay_cause,
    COALESCE(NULLIF(clearing_agent, ''), 'Unassigned') AS clearing_agent,
    status
FROM RAW_SHIPMENTS
QUALIFY ROW_NUMBER() OVER (PARTITION BY shipment_id ORDER BY arrival_date) = 1;

-- Check: expect 3000 rows and only 5 ports
SELECT COUNT(*) FROM SHIPMENTS_CLEAN;
SELECT port, COUNT(*) FROM SHIPMENTS_CLEAN GROUP BY port ORDER BY 2 DESC;

-- =====================================================
-- STEP 5: Analysis queries (each one becomes a dashboard tile)
-- =====================================================

-- Q1. Headline KPIs
SELECT
    COUNT(*)                                                    AS shipments,
    ROUND(AVG(clearance_days), 1)                               AS avg_clearance_days,
    ROUND(SUM(demurrage_cost_usd), 0)                           AS total_demurrage_usd,
    ROUND(100 * AVG(IFF(clearance_days > free_days, 1, 0)), 1)  AS pct_over_free_days
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared';

-- Q2. Port performance
SELECT
    port,
    COUNT(*)                          AS shipments,
    ROUND(AVG(clearance_days), 1)     AS avg_clearance_days,
    ROUND(SUM(demurrage_cost_usd), 0) AS total_demurrage_usd
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared'
GROUP BY port
ORDER BY avg_clearance_days DESC;

-- Q3. What delay causes cost the most
SELECT
    COALESCE(delay_cause, 'No delay')  AS delay_cause,
    COUNT(*)                           AS shipments,
    ROUND(AVG(clearance_days), 1)      AS avg_clearance_days,
    ROUND(SUM(demurrage_cost_usd), 0)  AS total_demurrage_usd
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared'
GROUP BY 1
ORDER BY total_demurrage_usd DESC;

-- Q4. Documentation status vs clearance time
SELECT
    documentation_status,
    COUNT(*)                          AS shipments,
    ROUND(AVG(clearance_days), 1)     AS avg_clearance_days,
    ROUND(AVG(demurrage_cost_usd), 0) AS avg_demurrage_usd
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared'
GROUP BY documentation_status
ORDER BY avg_clearance_days DESC;

-- Q5. Clearing agent ranking (window function)
SELECT
    clearing_agent,
    COUNT(*)                                          AS shipments,
    ROUND(AVG(clearance_days), 1)                     AS avg_clearance_days,
    RANK() OVER (ORDER BY AVG(clearance_days) ASC)    AS speed_rank
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared'
GROUP BY clearing_agent
ORDER BY speed_rank;

-- Q6. Monthly trend
SELECT
    DATE_TRUNC('month', arrival_date)  AS month,
    COUNT(*)                           AS shipments,
    ROUND(AVG(clearance_days), 1)      AS avg_clearance_days,
    ROUND(SUM(demurrage_cost_usd), 0)  AS demurrage_usd
FROM SHIPMENTS_CLEAN
WHERE status = 'Cleared'
GROUP BY 1
ORDER BY 1;

-- Q7. Shipments still in progress (operations watchlist)
SELECT shipment_id, port, shipping_line, arrival_date, clearing_agent, documentation_status
FROM SHIPMENTS_CLEAN
WHERE status = 'In Progress'
ORDER BY arrival_date;
