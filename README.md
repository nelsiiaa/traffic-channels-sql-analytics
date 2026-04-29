# Traffic & Channels SQL Analytics
### Google Merchandise Store · GA4 BigQuery · 2025

Analysis of traffic channel performance using Google Analytics 4 event-level data in BigQuery.
Part of a Big Data group project — I owned the **Traffic & Channels** area.

---

## Key findings

| Finding | Data |
|---|---|
| Search bounce rate | 25.7% — 3× higher than Social (7.69%) |
| Search conversion rate | 1.9% — 5.5× higher than Social (0.35%) |
| Direct traffic loyalty | Lowest return rate: avg 1.32 visits |
| Search loyalty | Highest: avg 2.09 visits + $236k total revenue |
| Email engagement | Longest sessions: avg 280s vs 59s for Social |

**The Search paradox:** Search has a higher bounce rate than Social — but converts at 5.5× the rate.
Users from Search arrive with purchase intent. Social drives clicks without commitment.

---

## Views built

```
views/
├── 01_table_base.sql               # event → session level transformation
├── 02_traffic_channels.sql         # bounce rate, conversion, revenue by channel
├── 03_channel_device_breakdown.sql # channel × device segmentation
├── 04_traffic_weekly_trends.sql    # weekly performance over time
└── 05_new_vs_returning.sql         # new vs returning users by channel
```

---

## SQL highlights

**Unified channel grouping** — one consistent CASE WHEN definition used across all views:

```sql
CASE
  WHEN traffic_source IN ('google', 'bing', 'yahoo')
    AND traffic_medium = 'cpc'             THEN 'Search'
  WHEN traffic_medium = 'organic'          THEN 'Organic'
  WHEN traffic_source LIKE '%facebook%'
    OR  traffic_source LIKE '%youtube%'    THEN 'Social media'
  WHEN traffic_medium = 'email'            THEN 'Email'
  WHEN traffic_source = '(direct)'
    AND traffic_medium = '(none)'          THEN 'Direct'
  ELSE 'Other'
END AS source_category
```

**Bounce rate definition** — single-page sessions with under 10 seconds engagement:

```sql
ROUND(
  100.0 * SUM(CASE WHEN pageview_count = 1
    AND engagement_time_sec < 10 THEN 1 ELSE 0 END)
  / COUNT(*), 2
) AS bounce_rate_pct
```

---

## Dataset

`bigquery-public-data.ga4_obfuscated_sample_ecommerce` — Google's public GA4 sample dataset.
Period: November 2020 – January 2021.

---

## Tech stack

`BigQuery` `SQL` `GA4` `Google Analytics` `Web Analytics`

---

## AI disclosure

AI was used as a technical helper for SQL syntax and as a language assistant for the report.
All hypotheses, analytical logic, and business interpretations are original work,
manually verified against database output.
