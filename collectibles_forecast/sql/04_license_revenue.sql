-- =============================================================================
-- FC Forecast semantic layer -- license (league) revenue view
-- Source: ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LEAGUE_V (planning cube by league; MAIN product groups
--   only, league mapped via CARDPLN_LEAGUE_MAP, matching hedge product groups in its HEDGE column).
-- Basis caveats (verified 2026-10-20):
--   * Product groups are a parent/child hierarchy: PG_10000 = all Sports, PG_50000 = all Entertainment;
--     named leagues are children. 'Sports - Other' / 'Entertainment - Other' = parent minus named children.
--   * CARDPLN_LEAGUE_MAP has duplicate parents (PG_20002 Basketball/NBA, PG_20001 Football/NFL); the source
--     view dedupes them.
--   * Hedge product groups (role HEDGE, PG_105xx) sit OUTSIDE the parents and are added per league, so
--     NET_REVENUE = AMOUNT + HEDGE. The source view's UNHEDGED column (AMOUNT - HEDGE) is a different basis
--     and is not used. Hedges with no MAIN row for their league are dropped by the source view (MAR26RF
--     Tennis Dec -0.09, MAY26RF Bundesliga Oct -0.07); they fall into the Unallocated row instead.
--   * The cube does not fully cover segment revenue (Sep FC Intl ~$120M short). A per-LOB
--     'Unallocated (not in license cube)' row closes the gap so totals tie to FC_SEGMENT_PL_BASE_V.
--   * Revenue only: license CM in the cube is on a different basis from the deck and is not exposed.
--   * Sep 2026 FC ties to deck GRL within ~1% per major license; Aug 2026 FC does not (different build).
--   * Only versions present in the league cube are exposed (a cycle loaded into CARDPLN but not yet into the
--     cube would otherwise appear as 100% 'Unallocated' with a $0 hedge). Latest / prior / PFC are computed
--     from the cube's own Monthly Forecast cycles, so the cube can lag the segment P&L without mislabelling.
-- =============================================================================
CREATE OR REPLACE VIEW ORACLE_DATA_PROD.SANDBOX.FC_LICENSE_REVENUE_V
COMMENT = 'FC forecast revenue by license/league x segment x month x version, planning-cube basis ($M)'
AS
WITH raw AS (
    SELECT
        l.SCENARIO                                                                             AS VERSION_CODE,
        TO_DATE('20' || SUBSTR(l.FISCAL_YEAR, 3, 2) || '-' || l.PERIOD || '-01', 'YYYY-MON-DD') AS PERIOD_DATE,
        l.LOB,
        l.LEAGUE,
        SUM(l.AMOUNT) / 1e6                                                                    AS REV,
        SUM(l.HEDGE) / 1e6                                                                     AS HEDGE
    FROM ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LEAGUE_V l
    WHERE l.PERIOD_TYPE = 'MONTH' AND l.PL_LINE = 'ACX_Net Revenue'
      AND l.LOB IN ('LB_302', 'LB_303', 'LB_305')
    GROUP BY 1, 2, 3, 4
),
children AS (
    SELECT VERSION_CODE, PERIOD_DATE, LOB,
           SUM(IFF(LEAGUE IN ('Disney', 'Marvel', 'Star Wars', 'GPK', 'NFTs'), REV, 0)) AS ENT_CHILDREN,
           SUM(IFF(LEAGUE NOT IN ('Disney', 'Marvel', 'Star Wars', 'GPK', 'NFTs', 'Sports - Other',
                                  'Entertainment - Other', 'All Other', 'Contingency'), REV, 0)) AS SPORT_CHILDREN
    FROM raw
    GROUP BY 1, 2, 3
),
leaf AS (
    SELECT VERSION_CODE, PERIOD_DATE, LOB, LEAGUE, REV + HEDGE AS REV, HEDGE
    FROM raw WHERE LEAGUE NOT IN ('Sports - Other', 'Entertainment - Other')
    UNION ALL
    SELECT r.VERSION_CODE, r.PERIOD_DATE, r.LOB, 'Sports - Other', r.REV - COALESCE(c.SPORT_CHILDREN, 0), 0
    FROM raw r LEFT JOIN children c USING (VERSION_CODE, PERIOD_DATE, LOB)
    WHERE r.LEAGUE = 'Sports - Other'
    UNION ALL
    SELECT r.VERSION_CODE, r.PERIOD_DATE, r.LOB, 'Entertainment - Other', r.REV - COALESCE(c.ENT_CHILDREN, 0), 0
    FROM raw r LEFT JOIN children c USING (VERSION_CODE, PERIOD_DATE, LOB)
    WHERE r.LEAGUE = 'Entertainment - Other'
),
seg AS (
    SELECT VERSION_CODE, PERIOD_DATE,
           CASE SUB_SEGMENT WHEN 'Topps Domestic' THEN 'LB_302' WHEN 'Topps International' THEN 'LB_303' ELSE 'LB_305' END AS LOB,
           SUM(NET_REVENUE) AS REV
    FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_BASE_V
    WHERE SUB_SEGMENT IN ('Topps Domestic', 'Topps International', 'Digital')
      AND VERSION_CODE IN (SELECT DISTINCT VERSION_CODE FROM raw)
    GROUP BY 1, 2, 3
),
cube_tot AS (SELECT VERSION_CODE, PERIOD_DATE, LOB, SUM(REV) AS REV FROM leaf GROUP BY 1, 2, 3),
unioned AS (
    SELECT VERSION_CODE, PERIOD_DATE, LOB, LEAGUE, REV, HEDGE, FALSE AS IS_RECONCILING FROM leaf
    UNION ALL
    SELECT s.VERSION_CODE, s.PERIOD_DATE, s.LOB, 'Unallocated (not in license cube)',
           s.REV - COALESCE(c.REV, 0), 0, TRUE
    FROM seg s LEFT JOIN cube_tot c USING (VERSION_CODE, PERIOD_DATE, LOB)
    WHERE ABS(s.REV - COALESCE(c.REV, 0)) > 0.0005
),
agg AS (
    SELECT VERSION_CODE, PERIOD_DATE, LOB, LEAGUE, IS_RECONCILING, SUM(REV) AS NET_REVENUE, SUM(HEDGE) AS HEDGE_REVENUE
    FROM unioned GROUP BY 1, 2, 3, 4, 5
),
dv AS (SELECT * FROM ORACLE_DATA_PROD.SANDBOX.FC_DIM_VERSION),
sv AS (
    SELECT VERSION_CODE,
           LAG(VERSION_CODE)  OVER (ORDER BY CYCLE_MONTH)      AS PFC_VERSION_CODE,
           LAG(VERSION_LABEL) OVER (ORDER BY CYCLE_MONTH)      AS PFC_VERSION_LABEL,
           ROW_NUMBER()       OVER (ORDER BY CYCLE_MONTH DESC) AS RECENCY_RANK
    FROM dv
    WHERE VERSION_TYPE = 'Monthly Forecast' AND VERSION_CODE IN (SELECT DISTINCT VERSION_CODE FROM raw)
),
v AS (
    SELECT dv.VERSION_CODE, dv.VERSION_LABEL, dv.VERSION_TYPE, dv.CYCLE_MONTH, dv.ACTUALS_THROUGH_DATE,
           sv.PFC_VERSION_CODE, sv.PFC_VERSION_LABEL,
           COALESCE(sv.RECENCY_RANK = 1, FALSE)                              AS IS_LATEST_FC,
           COALESCE(sv.RECENCY_RANK = 2, FALSE)                              AS IS_PRIOR_FC,
           MAX(IFF(sv.RECENCY_RANK = 1, dv.VERSION_LABEL, NULL)) OVER ()     AS LATEST_FC_LABEL
    FROM dv LEFT JOIN sv ON sv.VERSION_CODE = dv.VERSION_CODE
)
SELECT
    a.VERSION_CODE,
    v.VERSION_LABEL,
    v.VERSION_TYPE,
    v.CYCLE_MONTH,
    v.PFC_VERSION_CODE,
    v.PFC_VERSION_LABEL,
    v.IS_LATEST_FC,
    v.IS_PRIOR_FC,
    v.LATEST_FC_LABEL,
    a.PERIOD_DATE,
    YEAR(a.PERIOD_DATE)                                       AS FISCAL_YEAR,
    'Q' || QUARTER(a.PERIOD_DATE)                             AS FISCAL_QUARTER,
    MONTH(a.PERIOD_DATE)                                      AS MONTH_NUMBER,
    CASE WHEN v.VERSION_TYPE = 'Budget' THEN 'Plan'
         WHEN LAST_DAY(a.PERIOD_DATE) <= v.ACTUALS_THROUGH_DATE THEN 'A' ELSE 'F' END AS AF_FLAG,
    CASE a.LOB WHEN 'LB_302' THEN 'North America' WHEN 'LB_303' THEN 'International' ELSE 'Digital' END AS SEGMENT,
    CASE
        WHEN a.LEAGUE IN ('UEFA', 'EPL', 'Club Exclusives', 'Bundesliga', 'MLS', 'UEFA Euro', 'CLC') THEN 'Total Soccer'
        WHEN a.LEAGUE IN ('Disney', 'Marvel', 'Star Wars')  THEN 'Total Disney'
        WHEN a.LEAGUE IN ('WWE', 'UFC')                     THEN 'Total TKO'
        WHEN a.LEAGUE = 'NBA'                               THEN 'Basketball'
        WHEN a.LEAGUE = 'NFL'                               THEN 'Football'
        WHEN a.LEAGUE IN ('GPK', 'NFTs')                    THEN 'Entertainment - Other'
        WHEN a.LEAGUE = 'OEB'                               THEN 'Sports - Other'
        ELSE a.LEAGUE
    END                                                       AS LICENSE,
    CASE a.LEAGUE WHEN 'NBA' THEN 'NBA' WHEN 'NFL' THEN 'NFL' ELSE a.LEAGUE END AS SUB_LICENSE,
    a.IS_RECONCILING,
    a.NET_REVENUE,
    a.HEDGE_REVENUE,
    a.NET_REVENUE - a.HEDGE_REVENUE                           AS UNHEDGED_NET_REVENUE
FROM agg a
JOIN v ON v.VERSION_CODE = a.VERSION_CODE;
