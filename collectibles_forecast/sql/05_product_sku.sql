-- =============================================================================
-- FC Forecast semantic layer -- SKU x channel x product-release view (North America only)
-- Sources: GMPLN_REVENUE_FORECAST_HISTORY (grain BY_CHANNEL_SKU = leaf; other grains are rollups),
--          GMPLN_BUDGET (Plan_2026, same grain), GMPLN_PL_BY_SKU_CHANNEL_V (SKU -> COA),
--          PRODUCT_RELEASE_BY_COA_V (product name / street dates per forecast vintage).
-- Perimeter: Topps Domestic (NA physical) only -- ties to FC_SEGMENT_PL North America within ~$2M.
--   No International, Digital or Fanatics Collect detail exists at SKU grain.
-- PY is deliberately NOT exposed (PRODUCT_RELEASE PY_NETREV is broken upstream).
-- Latest / prior / PFC are computed from the forecast cycles present in THIS source (the SKU history can
-- lag CARDPLN by a cycle), so is_latest_fc is always the newest SKU cycle and pfc_* always exists here.
-- =============================================================================
CREATE OR REPLACE VIEW ORACLE_DATA_PROD.SANDBOX.FC_PRODUCT_SKU_V
COMMENT = 'FC NA forecast by version x month x SKU x channel with product release attributes and PFC/Budget columns ($M)'
AS
WITH fc AS (
    SELECT FORECAST_ASOF AS VERSION_CODE, PERIOD_DATE, SKU, CHANNEL, MAX(CHANNEL_DESC) AS CHANNEL_DESC,
           SUM(NET_REV_EX_INTERCO) / 1e6 AS NET_REVENUE, SUM(CM) / 1e6 AS CM, SUM(VOLUME_CASES) AS VOLUME_CASES
    FROM ORACLE_DATA_PROD.FCT_EPM.GMPLN_REVENUE_FORECAST_HISTORY
    WHERE GRAIN = 'BY_CHANNEL_SKU' AND PERIOD_DATE IS NOT NULL
      AND FORECAST_ASOF RLIKE '^[A-Z]{3}[0-9]{2}RF$'
      AND (NET_REV_EX_INTERCO <> 0 OR CM <> 0)
    GROUP BY 1, 2, 3, 4
),
bud AS (
    SELECT BUDGET_VERSION AS VERSION_CODE, PERIOD_DATE, SKU, CHANNEL, MAX(CHANNEL_DESC) AS CHANNEL_DESC,
           SUM(NET_REV_EX_INTERCO) / 1e6 AS NET_REVENUE, SUM(CM) / 1e6 AS CM, SUM(VOLUME_CASES) AS VOLUME_CASES
    FROM ORACLE_DATA_PROD.FCT_EPM.GMPLN_BUDGET
    WHERE GRAIN = 'BY_CHANNEL_SKU' AND PERIOD_DATE IS NOT NULL
      AND (NET_REV_EX_INTERCO <> 0 OR CM <> 0)
    GROUP BY 1, 2, 3, 4
),
b AS (SELECT * FROM fc UNION ALL SELECT * FROM bud),
dv AS (SELECT * FROM ORACLE_DATA_PROD.SANDBOX.FC_DIM_VERSION),
sv AS (
    SELECT VERSION_CODE,
           LAG(VERSION_CODE)  OVER (ORDER BY CYCLE_MONTH)      AS PFC_VERSION_CODE,
           LAG(VERSION_LABEL) OVER (ORDER BY CYCLE_MONTH)      AS PFC_VERSION_LABEL,
           ROW_NUMBER()       OVER (ORDER BY CYCLE_MONTH DESC) AS RECENCY_RANK
    FROM dv
    WHERE VERSION_TYPE = 'Monthly Forecast' AND VERSION_CODE IN (SELECT DISTINCT VERSION_CODE FROM fc)
),
v AS (
    SELECT dv.VERSION_CODE, dv.VERSION_LABEL, dv.VERSION_TYPE, dv.CYCLE_MONTH, dv.ACTUALS_THROUGH_DATE,
           sv.PFC_VERSION_CODE, sv.PFC_VERSION_LABEL,
           COALESCE(sv.RECENCY_RANK = 1, FALSE)                              AS IS_LATEST_FC,
           COALESCE(sv.RECENCY_RANK = 2, FALSE)                              AS IS_PRIOR_FC,
           MAX(IFF(sv.RECENCY_RANK = 1, dv.VERSION_LABEL, NULL)) OVER ()     AS LATEST_FC_LABEL
    FROM dv LEFT JOIN sv ON sv.VERSION_CODE = dv.VERSION_CODE
),
ver_years AS (SELECT DISTINCT VERSION_CODE, YEAR(PERIOD_DATE) AS FY FROM b),
spine AS (
    SELECT VERSION_CODE, PERIOD_DATE, SKU, CHANNEL FROM b
    UNION
    SELECT v.VERSION_CODE, p.PERIOD_DATE, p.SKU, p.CHANNEL
    FROM b p JOIN v ON v.PFC_VERSION_CODE = p.VERSION_CODE
    JOIN ver_years y ON y.VERSION_CODE = v.VERSION_CODE AND y.FY = YEAR(p.PERIOD_DATE)
    UNION
    SELECT y.VERSION_CODE, p.PERIOD_DATE, p.SKU, p.CHANNEL
    FROM bud p JOIN ver_years y ON p.VERSION_CODE = 'Plan_' || y.FY AND YEAR(p.PERIOD_DATE) = y.FY
),
sku_coa AS (
    SELECT SKU, MAX(COA) AS COA
    FROM ORACLE_DATA_PROD.FCT_EPM.GMPLN_PL_BY_SKU_CHANNEL_V
    WHERE COA IS NOT NULL
    GROUP BY SKU
),
chan AS (SELECT CHANNEL, MAX(CHANNEL_DESC) AS CHANNEL_DESC FROM b GROUP BY CHANNEL),
prod AS (
    SELECT FORECAST_ASOF, COA, PRODUCT_NAME, STREET_DATE, PFC_STREET_DATE, BUDGET_STREET_DATE
    FROM ORACLE_DATA_PROD.FCT_EPM.PRODUCT_RELEASE_BY_COA_V
),
prod_latest AS (
    SELECT COA, PRODUCT_NAME
    FROM prod
    WHERE PRODUCT_NAME IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY COA ORDER BY TRY_TO_DATE('01' || LEFT(FORECAST_ASOF, 5), 'DDMONYY') DESC NULLS LAST) = 1
)
SELECT
    s.VERSION_CODE,
    v.VERSION_LABEL,
    v.VERSION_TYPE,
    v.CYCLE_MONTH,
    v.PFC_VERSION_CODE,
    v.PFC_VERSION_LABEL,
    v.IS_LATEST_FC,
    v.IS_PRIOR_FC,
    v.LATEST_FC_LABEL,
    s.PERIOD_DATE,
    YEAR(s.PERIOD_DATE)                                                          AS FISCAL_YEAR,
    'Q' || QUARTER(s.PERIOD_DATE)                                                AS FISCAL_QUARTER,
    MONTH(s.PERIOD_DATE)                                                         AS MONTH_NUMBER,
    CASE WHEN v.VERSION_TYPE = 'Budget' THEN 'Plan'
         WHEN LAST_DAY(s.PERIOD_DATE) <= v.ACTUALS_THROUGH_DATE THEN 'A' ELSE 'F' END AS AF_FLAG,
    s.SKU,
    s.CHANNEL,
    ch.CHANNEL_DESC,
    CASE
        WHEN ch.CHANNEL_DESC ILIKE '%Input%' OR s.CHANNEL ILIKE '%_Input' OR s.CHANNEL = 'No Channel' THEN 'Planning input / unassigned'
        WHEN ch.CHANNEL_DESC ILIKE 'Hobby%' OR s.CHANNEL IN ('Breaker', 'HNW - Concierge')               THEN 'Hobby & Breakers'
        WHEN ch.CHANNEL_DESC ILIKE 'Retail%'                                                            THEN 'Retail'
        WHEN ch.CHANNEL_DESC IN ('Topps.com', 'Fanatics.com', 'Amazon.Com', 'Walmart.com', 'TikTok Shop',
                                 'Topps on Collect', 'Instant Wax')                                    THEN 'eCommerce / DTC'
        WHEN ch.CHANNEL_DESC ILIKE 'Internal%'                                                          THEN 'Internal / Intercompany'
        ELSE 'Other'
    END                                                                          AS CHANNEL_GROUP,
    sc.COA,
    COALESCE(pc.PRODUCT_NAME, pl.PRODUCT_NAME,
             IFF(sc.COA IS NULL, 'Unmapped SKU ' || s.SKU, 'COA ' || sc.COA))   AS PRODUCT_NAME,
    REGEXP_SUBSTR(COALESCE(pc.PRODUCT_NAME, pl.PRODUCT_NAME), '^[0-9]{4}(/[0-9]{2})?') AS PRODUCT_YEAR,
    sc.COA RLIKE '^[A-Z]{3}[0-9]{4}$'                                            AS IS_RELEASE_COA,
    pc.STREET_DATE,
    pc.PFC_STREET_DATE,
    pc.BUDGET_STREET_DATE,
    YEAR(pc.STREET_DATE)                                                         AS STREET_YEAR,
    CASE
        WHEN pc.STREET_DATE IS NULL OR pc.PFC_STREET_DATE IS NULL THEN NULL
        WHEN pc.STREET_DATE < pc.PFC_STREET_DATE THEN 'SD Accelerated'
        WHEN pc.STREET_DATE > pc.PFC_STREET_DATE THEN 'SD Delayed'
        ELSE 'No change'
    END                                                                          AS STREET_DATE_MOVE_VS_PFC,
    COALESCE(c.NET_REVENUE, 0)   AS NET_REVENUE,
    COALESCE(c.CM, 0)            AS CONTRIBUTION_MARGIN,
    COALESCE(c.VOLUME_CASES, 0)  AS VOLUME_CASES,
    COALESCE(p.NET_REVENUE, 0)   AS PFC_NET_REVENUE,
    COALESCE(p.CM, 0)            AS PFC_CONTRIBUTION_MARGIN,
    COALESCE(p.VOLUME_CASES, 0)  AS PFC_VOLUME_CASES,
    COALESCE(bu.NET_REVENUE, 0)  AS BUDGET_NET_REVENUE,
    COALESCE(bu.CM, 0)           AS BUDGET_CONTRIBUTION_MARGIN,
    COALESCE(bu.VOLUME_CASES, 0) AS BUDGET_VOLUME_CASES
FROM spine s
JOIN v                 ON v.VERSION_CODE = s.VERSION_CODE
LEFT JOIN chan ch      ON ch.CHANNEL = s.CHANNEL
LEFT JOIN sku_coa sc   ON sc.SKU = s.SKU
LEFT JOIN prod pc      ON pc.FORECAST_ASOF = s.VERSION_CODE AND pc.COA = sc.COA
LEFT JOIN prod_latest pl ON pl.COA = sc.COA
LEFT JOIN b c          ON c.VERSION_CODE = s.VERSION_CODE AND c.PERIOD_DATE = s.PERIOD_DATE AND c.SKU = s.SKU AND c.CHANNEL = s.CHANNEL
LEFT JOIN b p          ON p.VERSION_CODE = v.PFC_VERSION_CODE AND p.PERIOD_DATE = s.PERIOD_DATE AND p.SKU = s.SKU AND p.CHANNEL = s.CHANNEL
LEFT JOIN bud bu       ON bu.VERSION_CODE = 'Plan_' || YEAR(s.PERIOD_DATE) AND bu.PERIOD_DATE = s.PERIOD_DATE
                      AND bu.SKU = s.SKU AND bu.CHANNEL = s.CHANNEL;
