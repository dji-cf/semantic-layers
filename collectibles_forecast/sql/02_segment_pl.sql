-- =============================================================================
-- FC Forecast semantic layer -- segment P&L views
-- Grain: version x fiscal month x leaf management sub-segment. Amounts in $M.
-- Deck-tie rule set (verified 2026-10-20, see memory fc-forecast-pl-reconciliation):
--   * Source CARDPLN_PL_BY_LOB_V2, MONTH rows, CHANNEL = 'Total Channel',
--     leaf (LOB, INTERCOMPANY) pairs from FC_DIM_MGMT_SEGMENT.
--   * COGS  = 8 ACX_ lines (incl. ACX_Compensation, which CARDPLN's own layout omits).
--   * Opex  = AC_50000 @ CC_30000 (parent cost center; deck SG&A total).
--   * Marketing = AC_60001 @ CC_30000.
--   * Key Litigation = AC_61002 @ CC_40313, moved out of its owning LOB.
--   Do NOT use CARDPLN_PL_BY_LOB.ACX_EBITDA -- different hierarchy, does not tie.
-- =============================================================================

CREATE OR REPLACE VIEW ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_BASE_V
COMMENT = 'FC segment P&L, one row per version x month x leaf sub-segment, current-version measures only ($M)'
AS
WITH src AS (
    SELECT
        s.SCENARIO                                                                    AS VERSION_CODE,
        TO_DATE('20' || SUBSTR(s.FISCAL_YEAR, 3, 2) || '-' || s.PERIOD || '-01', 'YYYY-MON-DD') AS PERIOD_DATE,
        s.LOB,
        s.INTERCOMPANY,
        CASE
            WHEN s.ACCOUNT = 'ACX_Net Revenue'                                  THEN 'NET_REVENUE'
            WHEN s.ACCOUNT = 'ACX_Manufacturing'                                THEN 'MANUFACTURING'
            WHEN s.ACCOUNT = 'ACX_Royalties'                                    THEN 'ROYALTIES'
            WHEN s.ACCOUNT = 'ACX_Autos & Relics'                               THEN 'AUTOS_RELICS'
            WHEN s.ACCOUNT = 'ACX_Product Development'                          THEN 'PRODUCT_DEVELOPMENT'
            WHEN s.ACCOUNT = 'ACX_Net Freight Expense'                          THEN 'NET_FREIGHT'
            WHEN s.ACCOUNT = 'ACX_MG Shortfall'                                 THEN 'MG_SHORTFALL'
            WHEN s.ACCOUNT = 'ACX_Obsolescence'                                 THEN 'OBSOLESCENCE'
            WHEN s.ACCOUNT = 'ACX_Compensation'                                 THEN 'COGS_COMPENSATION'
            WHEN s.ACCOUNT = 'AC_50000' AND s.COST_CENTER = 'CC_30000'          THEN 'OPEX_TOTAL'
            WHEN s.ACCOUNT = 'AC_60001' AND s.COST_CENTER = 'CC_30000'          THEN 'MARKETING'
            WHEN s.ACCOUNT = 'AC_61002' AND s.COST_CENTER = 'CC_40313'          THEN 'KEY_LITIGATION'
        END                                                                           AS LINE,
        s.AMOUNT / 1e6                                                                AS AMT
    FROM ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LOB_V2 s
    WHERE s.PERIOD_TYPE = 'MONTH'
      AND s.CHANNEL = 'Total Channel'
),
mapped AS (
    -- regular lines stay with their LOB; key-litigation legal is removed from the owning LOB's opex
    SELECT src.VERSION_CODE, src.PERIOD_DATE, d.SUB_SEGMENT,
           IFF(src.LINE = 'KEY_LITIGATION', 'OPEX_TOTAL', src.LINE) AS LINE,
           IFF(src.LINE = 'KEY_LITIGATION', -src.AMT, src.AMT)      AS AMT
    FROM src
    JOIN ORACLE_DATA_PROD.SANDBOX.FC_DIM_MGMT_SEGMENT d
      ON d.SOURCE_LOB = src.LOB AND d.SOURCE_INTERCOMPANY = src.INTERCOMPANY
    WHERE src.LINE IS NOT NULL
    UNION ALL
    -- ...and re-added as its own Emerging Services segment
    SELECT src.VERSION_CODE, src.PERIOD_DATE, 'Key Litigation', 'OPEX_TOTAL', src.AMT
    FROM src
    JOIN ORACLE_DATA_PROD.SANDBOX.FC_DIM_MGMT_SEGMENT d
      ON d.SOURCE_LOB = src.LOB AND d.SOURCE_INTERCOMPANY = src.INTERCOMPANY
    WHERE src.LINE = 'KEY_LITIGATION'
),
pivoted AS (
    SELECT
        VERSION_CODE, PERIOD_DATE, SUB_SEGMENT,
        SUM(IFF(LINE = 'NET_REVENUE',         AMT, 0)) AS NET_REVENUE,
        SUM(IFF(LINE = 'MANUFACTURING',       AMT, 0)) AS MANUFACTURING,
        SUM(IFF(LINE = 'ROYALTIES',           AMT, 0)) AS ROYALTIES,
        SUM(IFF(LINE = 'AUTOS_RELICS',        AMT, 0)) AS AUTOS_RELICS,
        SUM(IFF(LINE = 'PRODUCT_DEVELOPMENT', AMT, 0)) AS PRODUCT_DEVELOPMENT,
        SUM(IFF(LINE = 'NET_FREIGHT',         AMT, 0)) AS NET_FREIGHT,
        SUM(IFF(LINE = 'MG_SHORTFALL',        AMT, 0)) AS MG_SHORTFALL,
        SUM(IFF(LINE = 'OBSOLESCENCE',        AMT, 0)) AS OBSOLESCENCE,
        SUM(IFF(LINE = 'COGS_COMPENSATION',   AMT, 0)) AS COGS_COMPENSATION,
        SUM(IFF(LINE = 'MARKETING',           AMT, 0)) AS MARKETING,
        SUM(IFF(LINE = 'OPEX_TOTAL',          AMT, 0)) AS SGA_TOTAL
    FROM mapped
    GROUP BY 1, 2, 3
)
SELECT
    VERSION_CODE, PERIOD_DATE, SUB_SEGMENT,
    NET_REVENUE,
    MANUFACTURING, ROYALTIES, AUTOS_RELICS, PRODUCT_DEVELOPMENT, NET_FREIGHT,
    MG_SHORTFALL, OBSOLESCENCE, COGS_COMPENSATION,
    MANUFACTURING + ROYALTIES + AUTOS_RELICS + PRODUCT_DEVELOPMENT + NET_FREIGHT
      + MG_SHORTFALL + OBSOLESCENCE + COGS_COMPENSATION                         AS COGS,
    NET_REVENUE - (MANUFACTURING + ROYALTIES + AUTOS_RELICS + PRODUCT_DEVELOPMENT + NET_FREIGHT
      + MG_SHORTFALL + OBSOLESCENCE + COGS_COMPENSATION)                        AS GROSS_MARGIN,
    MARKETING,
    NET_REVENUE - (MANUFACTURING + ROYALTIES + AUTOS_RELICS + PRODUCT_DEVELOPMENT + NET_FREIGHT
      + MG_SHORTFALL + OBSOLESCENCE + COGS_COMPENSATION) - MARKETING            AS CONTRIBUTION_MARGIN,
    SGA_TOTAL - MARKETING                                                       AS OTHER_SGA,
    SGA_TOTAL,
    NET_REVENUE - (MANUFACTURING + ROYALTIES + AUTOS_RELICS + PRODUCT_DEVELOPMENT + NET_FREIGHT
      + MG_SHORTFALL + OBSOLESCENCE + COGS_COMPENSATION) - SGA_TOTAL            AS ADJ_EBITDA
FROM pivoted;


-- -----------------------------------------------------------------------------
-- FC_SEGMENT_PL_V : semantic-view base. Adds version/period/segment attributes,
-- A/F flags, and pre-aligned comparison columns (PFC, Budget, PY) on the same row
-- so vs-PFC / vs-Budget / vs-PY never need a self-join.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
COMMENT = 'FC forecast segment P&L for Cortex Analyst: version x month x sub-segment with PFC/Budget/PY columns ($M)'
AS
WITH b AS (SELECT * FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_BASE_V),
v AS (SELECT * FROM ORACLE_DATA_PROD.SANDBOX.FC_DIM_VERSION),
lv AS (SELECT MAX(IFF(IS_LATEST_FC, VERSION_LABEL, NULL)) AS LATEST_FC_LABEL FROM v),
ver_years AS (SELECT DISTINCT VERSION_CODE, YEAR(PERIOD_DATE) AS FY FROM b),
spine AS (
    SELECT VERSION_CODE, PERIOD_DATE, SUB_SEGMENT FROM b
    UNION   -- rows that exist only in the PFC
    SELECT v.VERSION_CODE, p.PERIOD_DATE, p.SUB_SEGMENT
    FROM b p JOIN v ON v.PFC_VERSION_CODE = p.VERSION_CODE
    JOIN ver_years y ON y.VERSION_CODE = v.VERSION_CODE AND y.FY = YEAR(p.PERIOD_DATE)
    UNION   -- rows that exist only in the Budget
    SELECT y.VERSION_CODE, p.PERIOD_DATE, p.SUB_SEGMENT
    FROM b p JOIN ver_years y ON p.VERSION_CODE = 'Plan_' || y.FY AND YEAR(p.PERIOD_DATE) = y.FY
    UNION   -- rows that exist only in the prior year
    SELECT y.VERSION_CODE, DATEADD(YEAR, 1, p.PERIOD_DATE), p.SUB_SEGMENT
    FROM b p JOIN ver_years y ON p.VERSION_CODE = 'Actual' AND YEAR(p.PERIOD_DATE) + 1 = y.FY
)
SELECT
    -- version
    s.VERSION_CODE,
    v.VERSION_LABEL,
    v.VERSION_TYPE,
    v.CYCLE_MONTH,
    v.ACTUALS_THROUGH_DATE,
    v.PFC_VERSION_CODE,
    pv.VERSION_LABEL                                                            AS PFC_VERSION_LABEL,
    v.IS_LATEST_FC,
    v.IS_PRIOR_FC,
    lv.LATEST_FC_LABEL,
    -- time
    s.PERIOD_DATE,
    LAST_DAY(s.PERIOD_DATE)                                                     AS PERIOD_END_DATE,
    YEAR(s.PERIOD_DATE)                                                         AS FISCAL_YEAR,
    'Q' || QUARTER(s.PERIOD_DATE)                                               AS FISCAL_QUARTER,
    IFF(QUARTER(s.PERIOD_DATE) <= 2, 'H1', 'H2')                                AS FISCAL_HALF,
    MONTH(s.PERIOD_DATE)                                                        AS MONTH_NUMBER,
    TO_CHAR(s.PERIOD_DATE, 'MON')                                               AS MONTH_NAME,
    CASE
        WHEN v.VERSION_TYPE = 'Budget'                                 THEN 'Plan'
        WHEN LAST_DAY(s.PERIOD_DATE) <= v.ACTUALS_THROUGH_DATE         THEN 'A'
        ELSE 'F'
    END                                                                         AS AF_FLAG,
    CASE
        WHEN v.VERSION_TYPE <> 'Monthly Forecast'                      THEN NULL
        WHEN LAST_DAY(s.PERIOD_DATE) <= pv.ACTUALS_THROUGH_DATE        THEN 'Actual in both'
        WHEN LAST_DAY(s.PERIOD_DATE) <= v.ACTUALS_THROUGH_DATE         THEN 'Closed since PFC'
        ELSE 'Forecast in both'
    END                                                                         AS AF_TRANSITION_VS_PFC,
    -- segment
    s.SUB_SEGMENT,
    d.SEGMENT,
    d.REVENUE_SEGMENT,
    d.WEEKLY_SEGMENT,
    d.SEGMENT_GROUP,
    d.IS_EMERGING_SERVICES,
    d.GAAP_BUSINESS_UNIT,
    d.SEGMENT_SORT,
    d.BU_PAGE,
    d.BU_DETAIL,
    d.IN_BU_BASIS,
    -- current version
    COALESCE(c.NET_REVENUE, 0)          AS NET_REVENUE,
    COALESCE(c.MANUFACTURING, 0)        AS MANUFACTURING,
    COALESCE(c.ROYALTIES, 0)            AS ROYALTIES,
    COALESCE(c.AUTOS_RELICS, 0)         AS AUTOS_RELICS,
    COALESCE(c.PRODUCT_DEVELOPMENT, 0)  AS PRODUCT_DEVELOPMENT,
    COALESCE(c.NET_FREIGHT, 0)          AS NET_FREIGHT,
    COALESCE(c.MG_SHORTFALL, 0)         AS MG_SHORTFALL,
    COALESCE(c.OBSOLESCENCE, 0)         AS OBSOLESCENCE,
    COALESCE(c.COGS_COMPENSATION, 0)    AS COGS_COMPENSATION,
    COALESCE(c.COGS, 0)                 AS COGS,
    COALESCE(c.GROSS_MARGIN, 0)         AS GROSS_MARGIN,
    COALESCE(c.MARKETING, 0)            AS MARKETING,
    COALESCE(c.CONTRIBUTION_MARGIN, 0)  AS CONTRIBUTION_MARGIN,
    COALESCE(c.OTHER_SGA, 0)            AS OTHER_SGA,
    COALESCE(c.SGA_TOTAL, 0)            AS SGA_TOTAL,
    COALESCE(c.ADJ_EBITDA, 0)           AS ADJ_EBITDA,
    -- prior forecast cycle (PFC)
    COALESCE(p.NET_REVENUE, 0)          AS PFC_NET_REVENUE,
    COALESCE(p.MANUFACTURING, 0)        AS PFC_MANUFACTURING,
    COALESCE(p.ROYALTIES, 0)            AS PFC_ROYALTIES,
    COALESCE(p.AUTOS_RELICS, 0)         AS PFC_AUTOS_RELICS,
    COALESCE(p.PRODUCT_DEVELOPMENT, 0)  AS PFC_PRODUCT_DEVELOPMENT,
    COALESCE(p.NET_FREIGHT, 0)          AS PFC_NET_FREIGHT,
    COALESCE(p.COGS_COMPENSATION, 0)    AS PFC_COGS_COMPENSATION,
    COALESCE(p.COGS, 0)                 AS PFC_COGS,
    COALESCE(p.GROSS_MARGIN, 0)         AS PFC_GROSS_MARGIN,
    COALESCE(p.MARKETING, 0)            AS PFC_MARKETING,
    COALESCE(p.CONTRIBUTION_MARGIN, 0)  AS PFC_CONTRIBUTION_MARGIN,
    COALESCE(p.OTHER_SGA, 0)            AS PFC_OTHER_SGA,
    COALESCE(p.ADJ_EBITDA, 0)           AS PFC_ADJ_EBITDA,
    -- budget for the same fiscal year
    COALESCE(bu.NET_REVENUE, 0)         AS BUDGET_NET_REVENUE,
    COALESCE(bu.GROSS_MARGIN, 0)        AS BUDGET_GROSS_MARGIN,
    COALESCE(bu.MARKETING, 0)           AS BUDGET_MARKETING,
    COALESCE(bu.CONTRIBUTION_MARGIN, 0) AS BUDGET_CONTRIBUTION_MARGIN,
    COALESCE(bu.OTHER_SGA, 0)           AS BUDGET_OTHER_SGA,
    COALESCE(bu.ADJ_EBITDA, 0)          AS BUDGET_ADJ_EBITDA,
    -- prior-year actual, same month
    COALESCE(py.NET_REVENUE, 0)         AS PY_NET_REVENUE,
    COALESCE(py.GROSS_MARGIN, 0)        AS PY_GROSS_MARGIN,
    COALESCE(py.MARKETING, 0)           AS PY_MARKETING,
    COALESCE(py.CONTRIBUTION_MARGIN, 0) AS PY_CONTRIBUTION_MARGIN,
    COALESCE(py.OTHER_SGA, 0)           AS PY_OTHER_SGA,
    COALESCE(py.ADJ_EBITDA, 0)          AS PY_ADJ_EBITDA
FROM spine s
JOIN v                     ON v.VERSION_CODE = s.VERSION_CODE
LEFT JOIN v pv             ON pv.VERSION_CODE = v.PFC_VERSION_CODE
CROSS JOIN lv
JOIN ORACLE_DATA_PROD.SANDBOX.FC_DIM_MGMT_SEGMENT d ON d.SUB_SEGMENT = s.SUB_SEGMENT
LEFT JOIN b c              ON c.VERSION_CODE = s.VERSION_CODE      AND c.PERIOD_DATE = s.PERIOD_DATE  AND c.SUB_SEGMENT = s.SUB_SEGMENT
LEFT JOIN b p              ON p.VERSION_CODE = v.PFC_VERSION_CODE  AND p.PERIOD_DATE = s.PERIOD_DATE  AND p.SUB_SEGMENT = s.SUB_SEGMENT
LEFT JOIN b bu             ON bu.VERSION_CODE = 'Plan_' || YEAR(s.PERIOD_DATE)
                          AND bu.PERIOD_DATE = s.PERIOD_DATE AND bu.SUB_SEGMENT = s.SUB_SEGMENT
LEFT JOIN b py             ON py.VERSION_CODE = 'Actual'
                          AND py.PERIOD_DATE = DATEADD(YEAR, -1, s.PERIOD_DATE) AND py.SUB_SEGMENT = s.SUB_SEGMENT;
