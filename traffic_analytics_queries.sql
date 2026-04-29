-- ============================================================
-- 01_table_base.sql
-- Event-level → session-level transformation
-- Run this FIRST — all other views depend on it
-- ============================================================

CREATE OR REPLACE VIEW `web-analytics-494818.web_analitycs.table_base` AS

WITH raw_events AS (
  SELECT
    user_pseudo_id,
    COALESCE(
      (SELECT ep.value.int_value
       FROM UNNEST(event_params) ep
       WHERE ep.key = 'ga_session_id'), 0
    )                                                  AS session_id,
    event_name,
    event_timestamp,
    event_date,
    COALESCE(
      (SELECT ep.value.string_value FROM UNNEST(event_params) ep
       WHERE ep.key = 'source'), '(direct)'
    )                                                  AS traffic_source,
    COALESCE(
      (SELECT ep.value.string_value FROM UNNEST(event_params) ep
       WHERE ep.key = 'medium'), '(none)'
    )                                                  AS traffic_medium,
    COALESCE(
      (SELECT ep.value.int_value FROM UNNEST(event_params) ep
       WHERE ep.key = 'engagement_time_msec'), 0
    ) / 1000.0                                         AS engagement_time_sec,
    CASE WHEN event_name = 'purchase' THEN
      COALESCE(
        (SELECT ep.value.double_value FROM UNNEST(event_params) ep
         WHERE ep.key = 'value'), 0)
    ELSE 0 END                                         AS event_revenue,
    device.category                                    AS device_category
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)

SELECT
  user_pseudo_id,
  session_id,
  traffic_source,
  traffic_medium,
  device_category,
  event_date,
  COUNT(DISTINCT CASE WHEN event_name = 'page_view'
    THEN event_timestamp END)                          AS pageview_count,
  SUM(engagement_time_sec)                             AS engagement_time_sec,
  MAX(CASE WHEN event_name = 'purchase'
    THEN 1 ELSE 0 END)                                 AS purchase_done,
  COALESCE(SUM(event_revenue), 0)                      AS session_revenue
FROM raw_events
WHERE session_id != 0
GROUP BY
  user_pseudo_id, session_id,
  traffic_source, traffic_medium,
  device_category, event_date;


-- ============================================================
-- 02_traffic_channels.sql
-- Bounce rate, conversion rate, revenue by source category
-- ============================================================

CREATE OR REPLACE VIEW
  `web-analytics-494818.web_analitycs.traffic_channels` AS

WITH channel_grouped AS (
  SELECT
    *,
    CASE
      WHEN traffic_source IN ('google', 'bing', 'yahoo')
        AND  traffic_medium = 'cpc'              THEN 'Search'
      WHEN traffic_medium = 'organic'             THEN 'Organic'
      WHEN traffic_source LIKE '%facebook%'
        OR   traffic_source LIKE '%youtube%'
        OR   traffic_source LIKE '%instagram%'   THEN 'Social media'
      WHEN traffic_medium = 'email'               THEN 'Email'
      WHEN traffic_source = '(direct)'
        AND  traffic_medium = '(none)'            THEN 'Direct'
      ELSE 'Other'
    END AS source_category
  FROM `web-analytics-494818.web_analitycs.table_base`
)

SELECT
  source_category,
  traffic_source,
  traffic_medium,
  COUNT(DISTINCT session_id)                         AS total_sessions,
  COUNT(DISTINCT user_pseudo_id)                     AS unique_users,
  ROUND(AVG(pageview_count), 2)                      AS avg_pages,
  ROUND(AVG(engagement_time_sec), 1)                 AS avg_engagement_sec,
  ROUND(100.0 * SUM(CASE WHEN pageview_count = 1
    AND engagement_time_sec < 10 THEN 1 ELSE 0 END)
    / COUNT(*), 2)                                   AS bounce_rate_pct,
  ROUND(100.0 * SUM(purchase_done) / COUNT(*), 2)    AS conversion_rate_pct,
  SUM(session_revenue)                               AS total_revenue,
  ROUND(AVG(CASE WHEN purchase_done = 1
    THEN session_revenue END), 2)                    AS avg_order_value
FROM channel_grouped
GROUP BY source_category, traffic_source, traffic_medium
ORDER BY total_sessions DESC;


-- ============================================================
-- 03_channel_device_breakdown.sql
-- Channel × device segmentation
-- ============================================================

CREATE OR REPLACE VIEW
  `web-analytics-494818.web_analitycs.channel_device_breakdown` AS

SELECT
  CASE
    WHEN traffic_source IN ('google', 'bing')
      AND  traffic_medium = 'cpc'             THEN 'Search'
    WHEN traffic_source LIKE '%facebook%'
      OR   traffic_source LIKE '%youtube%'    THEN 'Social'
    WHEN traffic_medium = 'email'             THEN 'Email'
    WHEN traffic_source = '(direct)'          THEN 'Direct'
    ELSE 'Other'
  END                                         AS source_category,
  device_category,
  COUNT(DISTINCT session_id)                  AS sessions,
  ROUND(AVG(engagement_time_sec), 1)          AS avg_engagement_sec,
  ROUND(100.0 * SUM(purchase_done)
    / COUNT(*), 2)                            AS conversion_pct,
  ROUND(AVG(CASE WHEN purchase_done = 1
    THEN session_revenue END), 2)             AS avg_order_value
FROM `web-analytics-494818.web_analitycs.table_base`
GROUP BY source_category, device_category
ORDER BY source_category, sessions DESC;


-- ============================================================
-- 04_traffic_weekly_trends.sql
-- Weekly channel performance over time
-- ============================================================

CREATE OR REPLACE VIEW
  `web-analytics-494818.web_analitycs.traffic_weekly_trends` AS

SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
  CASE
    WHEN traffic_source IN ('google', 'bing')
      AND  traffic_medium = 'cpc'              THEN 'Search'
    WHEN traffic_source LIKE '%facebook%'
      OR   traffic_source LIKE '%youtube%'     THEN 'Social'
    WHEN traffic_medium = 'email'              THEN 'Email'
    WHEN traffic_source = '(direct)'           THEN 'Direct'
    ELSE 'Other'
  END                                          AS source_category,
  COUNT(DISTINCT session_id)                   AS sessions,
  SUM(session_revenue)                         AS weekly_revenue,
  ROUND(100.0 * SUM(purchase_done)
    / COUNT(*), 2)                             AS conversion_pct,
  ROUND(AVG(engagement_time_sec), 1)           AS avg_engagement_sec
FROM `web-analytics-494818.web_analitycs.table_base`
GROUP BY week_start, source_category
ORDER BY week_start, sessions DESC;


-- ============================================================
-- 05_new_vs_returning.sql
-- New vs returning users segmented by channel
-- ============================================================

CREATE OR REPLACE VIEW
  `web-analytics-494818.web_analitycs.new_vs_returning_by_channel` AS

WITH user_channel_history AS (
  SELECT
    user_pseudo_id,
    CASE
      WHEN traffic_source IN ('google', 'bing')
        AND  traffic_medium = 'cpc'             THEN 'Search'
      WHEN traffic_source LIKE '%facebook%'
        OR   traffic_source LIKE '%youtube%'    THEN 'Social'
      WHEN traffic_medium = 'email'             THEN 'Email'
      WHEN traffic_source = '(direct)'          THEN 'Direct'
      ELSE 'Other'
    END                                         AS source_category,
    COUNT(DISTINCT session_id)                  AS total_sessions,
    MIN(PARSE_DATE('%Y%m%d', event_date))       AS first_seen
  FROM `web-analytics-494818.web_analitycs.table_base`
  GROUP BY user_pseudo_id, source_category
)

SELECT
  source_category,
  CASE WHEN total_sessions = 1
    THEN 'New' ELSE 'Returning'
  END                                           AS user_type,
  COUNT(DISTINCT user_pseudo_id)                AS users,
  ROUND(
    100.0 * COUNT(DISTINCT user_pseudo_id)
    / SUM(COUNT(DISTINCT user_pseudo_id))
        OVER (PARTITION BY source_category),
  1)                                            AS share_pct
FROM user_channel_history
GROUP BY source_category, user_type
ORDER BY source_category, user_type;
