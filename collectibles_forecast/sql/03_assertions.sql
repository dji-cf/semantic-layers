-- =============================================================================
-- FC Forecast semantic layer -- assertion suite. Every query returns 0 rows when healthy.
-- Tolerance: $0.05M for internal identities; $1M for deck tie-outs (independent rounding).
-- =============================================================================

-- A1. Grain uniqueness: one row per version x month x sub-segment
SELECT VERSION_CODE, PERIOD_DATE, SUB_SEGMENT, COUNT(*) n
FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
GROUP BY 1, 2, 3 HAVING COUNT(*) > 1;

-- A2. Leaf revenue = CARDPLN rollup (ex-ES + Collect), hard gate on FY2025-FY2026 only.
--     Known, accepted differences outside that window (2026-10-20):
--       * Actual FY23 +23.1 / FY24 +7.5 (leaf EBITDA 241/363 ties Board history 240/362 -> leaf is deck basis)
--       * Oct/Nov/Dec25RF and Actual, Jan-Jun 2025: monthly phasing only, H1 nets to <= $0.1M
--       * FY27 Q4 (Jul/Aug/Sep26RF): +/-25M phasing in preliminary next-year months
--       * A7: Corporate Q2 -27.4 vs deck -25, Q3 -35.6 vs -38 (offsetting; FY -123.3 ties -123)
WITH leaf AS (
    SELECT VERSION_CODE, PERIOD_DATE, SUM(NET_REVENUE) rev
    FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_BASE_V
    WHERE YEAR(PERIOD_DATE) BETWEEN 2025 AND 2026 AND PERIOD_DATE >= '2025-07-01'
    GROUP BY 1, 2),
roll AS (
    SELECT SCENARIO VERSION_CODE, PERIOD_DATE, SUM(AMOUNT) / 1e6 rev
    FROM ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LOB
    WHERE PERIOD_TYPE = 'MONTH' AND PL_LINE = 'ACX_Net Revenue'
      AND LOB_SEGMENT IN ('Total - ex. Emerging Services', 'Total - Fanatics Live and Collect')
    GROUP BY 1, 2)
SELECT l.VERSION_CODE, l.PERIOD_DATE, l.rev leaf_rev, r.rev rollup_rev
FROM leaf l LEFT JOIN roll r USING (VERSION_CODE, PERIOD_DATE)
WHERE ABS(l.rev - COALESCE(r.rev, 0)) > 0.05;

-- A3. Closed months inside a forecast version equal Actual (revenue and Adj. EBITDA)
SELECT f.VERSION_CODE, f.PERIOD_DATE,
       SUM(f.NET_REVENUE) fc_rev, SUM(a.NET_REVENUE) act_rev,
       SUM(f.ADJ_EBITDA) fc_ebitda, SUM(a.ADJ_EBITDA) act_ebitda
FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V f
JOIN ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_BASE_V a
  ON a.VERSION_CODE = 'Actual' AND a.PERIOD_DATE = f.PERIOD_DATE AND a.SUB_SEGMENT = f.SUB_SEGMENT
WHERE f.VERSION_TYPE = 'Monthly Forecast' AND f.AF_FLAG = 'A' AND f.FISCAL_YEAR >= 2026
GROUP BY 1, 2
HAVING ABS(SUM(f.NET_REVENUE) - SUM(a.NET_REVENUE)) > 0.05 OR ABS(SUM(f.ADJ_EBITDA) - SUM(a.ADJ_EBITDA)) > 0.05;

-- A4. P&L identities on every row
SELECT VERSION_CODE, PERIOD_DATE, SUB_SEGMENT
FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
WHERE ABS(NET_REVENUE - COGS - GROSS_MARGIN) > 0.001
   OR ABS(GROSS_MARGIN - MARKETING - CONTRIBUTION_MARGIN) > 0.001
   OR ABS(CONTRIBUTION_MARGIN - OTHER_SGA - ADJ_EBITDA) > 0.001
   OR ABS(PFC_GROSS_MARGIN - PFC_MARKETING - PFC_CONTRIBUTION_MARGIN) > 0.001;

-- A5. PFC columns equal the PFC version's own rows (FY totals)
SELECT c.VERSION_CODE, c.FISCAL_YEAR, c.pfc_rev, p.rev
FROM (SELECT VERSION_CODE, PFC_VERSION_CODE, FISCAL_YEAR, SUM(PFC_NET_REVENUE) pfc_rev, SUM(PFC_ADJ_EBITDA) pfc_e
      FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V WHERE PFC_VERSION_CODE IS NOT NULL GROUP BY 1, 2, 3) c
JOIN (SELECT VERSION_CODE, FISCAL_YEAR, SUM(NET_REVENUE) rev, SUM(ADJ_EBITDA) e
      FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V GROUP BY 1, 2) p
  ON p.VERSION_CODE = c.PFC_VERSION_CODE AND p.FISCAL_YEAR = c.FISCAL_YEAR
WHERE ABS(c.pfc_rev - p.rev) > 0.05 OR ABS(c.pfc_e - p.e) > 0.05;

-- A6. Deck tie-out: Sep 2026 FC monthly revenue / Adj. EBITDA (Foundation App. A.4, +/- $1M)
WITH deck AS (
    SELECT column1 m, column2 rev, column3 ebitda FROM VALUES
     (1,324,141),(2,319,103),(3,228,57),(4,567,264),(5,524,243),(6,495,193),
     (7,456,167),(8,521,220),(9,495,188),(10,492,166),(11,594,240),(12,408,118))
SELECT d.m, d.rev, ROUND(SUM(v.NET_REVENUE), 1) rev_v, d.ebitda, ROUND(SUM(v.ADJ_EBITDA), 1) ebitda_v
FROM deck d JOIN ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V v
  ON v.VERSION_CODE = 'SEP26RF' AND v.FISCAL_YEAR = 2026 AND v.MONTH_NUMBER = d.m
GROUP BY d.m, d.rev, d.ebitda
HAVING ABS(SUM(v.NET_REVENUE) - d.rev) > 1 OR ABS(SUM(v.ADJ_EBITDA) - d.ebitda) > 1;

-- A7. Deck tie-out: Sep 2026 FC quarterly segment EBITDA (Foundation App. A.2, +/- $1M)
WITH deck AS (
    SELECT column1 seg, column2 q, column3 ebitda FROM VALUES
     ('North America','Q1',286),('North America','Q2',674),('North America','Q3',568),('North America','Q4',507),
     ('International','Q1',40),('International','Q2',74),('International','Q3',69),('International','Q4',67),
     ('Eliminations','Q1',3),('Eliminations','Q2',-2),('Eliminations','Q3',1),('Eliminations','Q4',1),
     ('Digital','Q1',1),('Digital','Q2',1),('Digital','Q3',1),('Digital','Q4',2),
     ('Corporate','Q1',-15),('Corporate','Q2',-25),('Corporate','Q3',-38),('Corporate','Q4',-45),
     ('Fanatics Collect','Q1',-3),('Fanatics Collect','Q2',-5),('Fanatics Collect','Q3',-6),('Fanatics Collect','Q4',5),
     ('Key Litigation','Q1',-10),('Key Litigation','Q2',-14),('Key Litigation','Q3',-17),('Key Litigation','Q4',-7))
SELECT d.seg, d.q, d.ebitda, ROUND(SUM(v.ADJ_EBITDA), 1) ebitda_v
FROM deck d LEFT JOIN ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V v
  ON v.VERSION_CODE = 'SEP26RF' AND v.FISCAL_YEAR = 2026 AND v.FISCAL_QUARTER = d.q AND v.SEGMENT = d.seg
GROUP BY 1, 2, 3
HAVING ABS(COALESCE(SUM(v.ADJ_EBITDA), 0) - d.ebitda) > 1;

-- A8. BU-page identities, every version x month. BU EBITDA (current and PFC; Topps Eliminations excluded by
--     IN_BU_BASIS) equals the consolidated segment row; BU Net Sales (all page rows, Topps included) equals the
--     revenue_segment row -- for North America that is NA net of eliminations.
WITH v AS (SELECT * FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V),
bu AS (
    SELECT VERSION_CODE, PERIOD_DATE, BU_PAGE,
           SUM(IFF(IN_BU_BASIS, ADJ_EBITDA, 0))     bu_ebitda,
           SUM(IFF(IN_BU_BASIS, PFC_ADJ_EBITDA, 0)) bu_pfc_ebitda,
           SUM(NET_REVENUE)                         bu_net_sales
    FROM v WHERE BU_PAGE IS NOT NULL GROUP BY 1, 2, 3),
seg AS (
    SELECT VERSION_CODE, PERIOD_DATE, SEGMENT, SUM(ADJ_EBITDA) ebitda, SUM(PFC_ADJ_EBITDA) pfc_ebitda
    FROM v GROUP BY 1, 2, 3),
rev AS (
    SELECT VERSION_CODE, PERIOD_DATE, REVENUE_SEGMENT, SUM(NET_REVENUE) net_revenue
    FROM v GROUP BY 1, 2, 3)
SELECT b.VERSION_CODE, b.PERIOD_DATE, b.BU_PAGE,
       b.bu_ebitda, s.ebitda, b.bu_pfc_ebitda, s.pfc_ebitda, b.bu_net_sales, r.net_revenue
FROM bu b
LEFT JOIN seg s ON s.VERSION_CODE = b.VERSION_CODE AND s.PERIOD_DATE = b.PERIOD_DATE AND s.SEGMENT = b.BU_PAGE
LEFT JOIN rev r ON r.VERSION_CODE = b.VERSION_CODE AND r.PERIOD_DATE = b.PERIOD_DATE AND r.REVENUE_SEGMENT = b.BU_PAGE
WHERE ABS(b.bu_ebitda - COALESCE(s.ebitda, 0)) > 0.05
   OR ABS(b.bu_pfc_ebitda - COALESCE(s.pfc_ebitda, 0)) > 0.05
   OR ABS(b.bu_net_sales - COALESCE(r.net_revenue, 0)) > 0.05;

-- A9. Dashboard tie-out: Drillable P&L North America page, SEP26RF FY26 (drillable-pnl-dash queries.BU_NA_NASE
--     comment; STG source, +/- $1M).
WITH dash AS (
    SELECT column1 bu_line, column2 line, column3 amt FROM VALUES
     ('NASE', 'COGS', 1824.9), ('GCP', 'COGS', -34.9), ('North America', 'COGS', 1790.0),
     ('NASE', 'SGA_EX_MKT', 314.5), ('GCP', 'SGA_EX_MKT', 12.4), ('North America', 'SGA_EX_MKT', 326.9),
     ('NASE', 'EBITDA', 2011.7), ('GCP', 'EBITDA', 22.6), ('North America', 'EBITDA', 2034.3)),
v AS (
    SELECT IFF(GROUPING(BU_DETAIL) = 1, 'North America', BU_DETAIL) bu_line,
           SUM(IFF(IN_BU_BASIS, COGS, 0))       cogs,
           SUM(IFF(IN_BU_BASIS, OTHER_SGA, 0))  sga_ex_mkt,
           SUM(IFF(IN_BU_BASIS, ADJ_EBITDA, 0)) ebitda
    FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
    WHERE VERSION_CODE = 'SEP26RF' AND FISCAL_YEAR = 2026 AND BU_PAGE = 'North America'
    GROUP BY ROLLUP (BU_DETAIL)),
vl AS (
    SELECT bu_line, 'COGS' line, cogs amt FROM v UNION ALL
    SELECT bu_line, 'SGA_EX_MKT', sga_ex_mkt FROM v UNION ALL
    SELECT bu_line, 'EBITDA', ebitda FROM v)
SELECT d.bu_line, d.line, d.amt dash_amt, ROUND(vl.amt, 1) layer_amt
FROM dash d LEFT JOIN vl ON vl.bu_line = d.bu_line AND vl.line = d.line
WHERE ABS(COALESCE(vl.amt, 0) - d.amt) > 1;

-- A10. Each view has exactly ONE latest forecast, its LATEST_FC_LABEL matches it, and the latest is not made
--      up only of reconciling rows (license view: a cycle in CARDPLN but not yet in the league cube).
WITH f AS (
    SELECT 'FC_SEGMENT_PL_V' vw, VERSION_CODE, VERSION_LABEL, IS_LATEST_FC, LATEST_FC_LABEL, FALSE AS IS_RECONCILING
    FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
    UNION ALL
    SELECT 'FC_LICENSE_REVENUE_V', VERSION_CODE, VERSION_LABEL, IS_LATEST_FC, LATEST_FC_LABEL, IS_RECONCILING
    FROM ORACLE_DATA_PROD.SANDBOX.FC_LICENSE_REVENUE_V
    UNION ALL
    SELECT 'FC_PRODUCT_SKU_V', VERSION_CODE, VERSION_LABEL, IS_LATEST_FC, LATEST_FC_LABEL, FALSE
    FROM ORACLE_DATA_PROD.SANDBOX.FC_PRODUCT_SKU_V)
SELECT vw,
       COUNT(DISTINCT IFF(IS_LATEST_FC, VERSION_CODE, NULL))            latest_versions,
       COUNT(DISTINCT LATEST_FC_LABEL)                                  latest_labels,
       MAX(IFF(IS_LATEST_FC, VERSION_LABEL, NULL))                      flagged_label,
       MAX(LATEST_FC_LABEL)                                             label_col,
       COUNT_IF(IS_LATEST_FC AND NOT IS_RECONCILING)                    latest_non_reconciling_rows
FROM f GROUP BY vw
HAVING latest_versions <> 1 OR latest_labels <> 1 OR flagged_label IS DISTINCT FROM label_col
    OR latest_non_reconciling_rows = 0;

-- A11. Every PFC_VERSION_CODE exists as a version in the SAME view (pfc_* can never point at an unloaded cycle).
WITH f AS (
    SELECT 'FC_SEGMENT_PL_V' vw, VERSION_CODE, PFC_VERSION_CODE FROM ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V
    UNION ALL
    SELECT 'FC_LICENSE_REVENUE_V', VERSION_CODE, PFC_VERSION_CODE FROM ORACLE_DATA_PROD.SANDBOX.FC_LICENSE_REVENUE_V
    UNION ALL
    SELECT 'FC_PRODUCT_SKU_V', VERSION_CODE, PFC_VERSION_CODE FROM ORACLE_DATA_PROD.SANDBOX.FC_PRODUCT_SKU_V),
pairs AS (SELECT DISTINCT vw, VERSION_CODE, PFC_VERSION_CODE FROM f WHERE PFC_VERSION_CODE IS NOT NULL),
vers AS (SELECT DISTINCT vw, VERSION_CODE FROM f)
SELECT p.vw, p.VERSION_CODE, p.PFC_VERSION_CODE
FROM pairs p LEFT JOIN vers v ON v.vw = p.vw AND v.VERSION_CODE = p.PFC_VERSION_CODE
WHERE v.VERSION_CODE IS NULL;
