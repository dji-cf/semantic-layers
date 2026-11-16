-- =============================================================================
-- FC Forecast semantic layer -- dimensions
-- Target: ORACLE_DATA_PROD.SANDBOX   Source: ORACLE_DATA_PROD.FCT_EPM
-- =============================================================================

-- -----------------------------------------------------------------------------
-- FC_DIM_MGMT_SEGMENT
-- Maps CARDPLN_PL_BY_LOB_V2 leaf members (LOB x INTERCOMPANY) to the FY2026
-- management segment hierarchy used in the Monthly Forecast / Weekly decks.
-- Only these member combinations are leaves; every other V2 combination is a
-- parent or a duplicate slice and must not be summed.
-- KEY_LITIGATION is synthetic: AC_61002 @ CC_40313 carved out of its owning LOB.
-- BU_PAGE / BU_DETAIL / IN_BU_BASIS reproduce the Drillable P&L dashboard's BU
-- pages (drillable-pnl-dash queries.BU_DEFS, BU_NA_NASE, BU_NA_GCP): a page's
-- members are its consolidated EBITDA row's. The one exception is Topps
-- Eliminations: on the North America page it is in Net Sales only (NASE Net
-- Sales = LB_302 + Topps elims), so it carries BU_PAGE but IN_BU_BASIS = FALSE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ORACLE_DATA_PROD.SANDBOX.FC_DIM_MGMT_SEGMENT (
    SOURCE_LOB            VARCHAR  COMMENT 'CARDPLN_PL_BY_LOB_V2.LOB member',
    SOURCE_INTERCOMPANY   VARCHAR  COMMENT 'CARDPLN_PL_BY_LOB_V2.INTERCOMPANY member that is the leaf for this LOB',
    SUB_SEGMENT           VARCHAR  COMMENT 'Leaf management unit (row grain of FC_SEGMENT_PL_V)',
    SEGMENT               VARCHAR  COMMENT 'Deck EBITDA-exhibit segment (Eliminations shown separately)',
    REVENUE_SEGMENT       VARCHAR  COMMENT 'Deck revenue-exhibit segment (Topps Eliminations folded into North America)',
    WEEKLY_SEGMENT        VARCHAR  COMMENT 'Weekly Finance Update segment (Other = Corporate + Key Litigation + TCG)',
    SEGMENT_GROUP         VARCHAR  COMMENT 'Total Physical Cards / Digital / Corporate / Emerging Services',
    IS_EMERGING_SERVICES  BOOLEAN  COMMENT 'TRUE for Fanatics Collect, Key Litigation, TCG',
    GAAP_BUSINESS_UNIT    VARCHAR  COMMENT 'GAAP FS-package business unit label',
    SEGMENT_SORT          NUMBER   COMMENT 'Deck display order',
    BU_PAGE               VARCHAR  COMMENT 'Drillable P&L BU drill-down page (North America / International / Digital / Fanatics Collect); NULL = no BU page',
    BU_DETAIL             VARCHAR  COMMENT 'Line block within the BU page: NASE / GCP on North America, else = BU_PAGE',
    IN_BU_BASIS           BOOLEAN  COMMENT 'TRUE if the row counts in BU COGS / GM / SG&A / EBITDA; Topps Eliminations FALSE (Net Sales only); NULL = no BU page'
) COMMENT = 'Leaf LOB -> management segment mapping for FC forecast semantic layer';

INSERT INTO ORACLE_DATA_PROD.SANDBOX.FC_DIM_MGMT_SEGMENT VALUES
 ('LB_302',                     'Total Intercompany', 'Topps Domestic',                          'North America',    'North America',    'North America',    'Total Physical Cards', FALSE, 'Topps Physical Collectibles Domestic',      10, 'North America',    'NASE',             TRUE),
 ('LB_304',                     'Total Intercompany', 'GCP Manufacturing',                       'North America',    'North America',    'North America',    'Total Physical Cards', FALSE, 'Manufacturing and Packaging',               11, 'North America',    'GCP',              TRUE),
 ('LB_394',                     'ICP_31005',          'GCP Intercompany Eliminations',           'North America',    'North America',    'North America',    'Total Physical Cards', FALSE, 'Elims',                                     12, 'North America',    'GCP',              TRUE),
 ('LB_303',                     'Total Intercompany', 'Topps International',                     'International',    'International',    'International',    'Total Physical Cards', FALSE, 'Topps Physical Collectibles International', 20, 'International',    'International',    TRUE),
 ('LB_392',                     'ICP_32002',          'International Intercompany Eliminations', 'International',    'International',    'International',    'Total Physical Cards', FALSE, 'Elims',                                     21, 'International',    'International',    TRUE),
 ('Total - Topps Eliminations', 'Total Intercompany', 'Topps Eliminations',                      'Eliminations',     'North America',    'North America',    'Total Physical Cards', FALSE, 'Elims',                                     30, 'North America',    'NASE',             FALSE),
 ('LB_305',                     'Total Intercompany', 'Digital',                                 'Digital',          'Digital',          'Digital',          'Digital',              FALSE, 'Digital Collectibles',                      40, 'Digital',          'Digital',          TRUE),
 ('LB_301',                     'Total Intercompany', 'Corporate OH',                            'Corporate',        'Corporate',        'Other',            'Corporate',            FALSE, 'Collectibles Corporate OH',                 50, NULL,               NULL,               NULL),
 ('LB_306',                     'Total Intercompany', 'Fanatics Live (incl. Instant Rips)',      'Fanatics Collect', 'Fanatics Collect', 'Fanatics Collect', 'Emerging Services',    TRUE,  'Fanatics Live',                             60, 'Fanatics Collect', 'Fanatics Collect', TRUE),
 ('LB_307',                     'Total Intercompany', 'Marketplace',                             'Fanatics Collect', 'Fanatics Collect', 'Fanatics Collect', 'Emerging Services',    TRUE,  'Fanatics Live',                             61, 'Fanatics Collect', 'Fanatics Collect', TRUE),
 ('KEY_LITIGATION',             NULL,                 'Key Litigation',                          'Key Litigation',   'Key Litigation',   'Other',            'Emerging Services',    TRUE,  'Collectibles Corporate OH',                 70, NULL,               NULL,               NULL),
 ('LB_308',                     'Total Intercompany', 'TCG',                                     'TCG',              'TCG',              'Other',            'Emerging Services',    TRUE,  'Collectibles Corporate OH',                 80, NULL,               NULL,               NULL);

-- -----------------------------------------------------------------------------
-- FC_DIM_VERSION
-- One row per scenario in CARDPLN. Derived (view) so new monthly cycles appear
-- automatically. Rules verified 2026-10-20 against Actual:
--   <MON><YY>RF holds actuals through the last day of the month BEFORE the cycle
--   month (SEP26RF = Jan-Aug A, Sep-Dec F). PFC = previous cycle.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW ORACLE_DATA_PROD.SANDBOX.FC_DIM_VERSION
COMMENT = 'Forecast/plan/actual version metadata for FC forecast semantic layer'
AS
WITH v AS (
    SELECT DISTINCT SCENARIO AS VERSION_CODE, VERSION AS VERSION_STATUS
    FROM ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LOB_V2
),
last_actual AS (
    SELECT LAST_DAY(MAX(TO_DATE('20' || SUBSTR(FISCAL_YEAR, 3, 2) || '-' || PERIOD || '-01', 'YYYY-MON-DD'))) AS LAST_ACTUAL_DATE
    FROM ORACLE_DATA_PROD.FCT_EPM.CARDPLN_PL_BY_LOB_V2
    WHERE SCENARIO = 'Actual' AND PERIOD_TYPE = 'MONTH'
      AND ACCOUNT = 'ACX_Net Revenue' AND AMOUNT <> 0
),
typed AS (
    SELECT
        v.VERSION_CODE,
        v.VERSION_STATUS,
        CASE
            WHEN v.VERSION_CODE = 'Actual'                     THEN 'Actual'
            WHEN v.VERSION_CODE ILIKE 'Plan_%'                 THEN 'Budget'
            WHEN v.VERSION_CODE RLIKE '^[A-Z]{3}[0-9]{2}RF$'   THEN 'Monthly Forecast'
            WHEN v.VERSION_CODE = 'Rolling Forecast'           THEN 'Rolling Forecast (Working)'
            ELSE 'Other'
        END AS VERSION_TYPE,
        IFF(v.VERSION_CODE RLIKE '^[A-Z]{3}[0-9]{2}RF$',
            TO_DATE('20' || SUBSTR(v.VERSION_CODE, 4, 2) || '-' || LEFT(v.VERSION_CODE, 3) || '-01', 'YYYY-MON-DD'),
            NULL) AS CYCLE_MONTH,
        IFF(v.VERSION_CODE ILIKE 'Plan_%', TRY_TO_NUMBER(RIGHT(v.VERSION_CODE, 4)), NULL) AS PLAN_YEAR,
        la.LAST_ACTUAL_DATE
    FROM v CROSS JOIN last_actual la
)
SELECT
    VERSION_CODE,
    VERSION_TYPE,
    CASE VERSION_TYPE
        WHEN 'Monthly Forecast' THEN INITCAP(LEFT(VERSION_CODE, 3)) || ' 20' || SUBSTR(VERSION_CODE, 4, 2) || ' FC'
        WHEN 'Budget'           THEN 'Budget ' || PLAN_YEAR
        WHEN 'Actual'           THEN 'Actual'
        ELSE VERSION_CODE
    END AS VERSION_LABEL,
    VERSION_STATUS,
    CYCLE_MONTH,
    PLAN_YEAR,
    CASE VERSION_TYPE
        WHEN 'Monthly Forecast'           THEN LAST_DAY(DATEADD(MONTH, -1, CYCLE_MONTH))
        WHEN 'Actual'                     THEN LAST_ACTUAL_DATE
        WHEN 'Rolling Forecast (Working)' THEN LAST_ACTUAL_DATE
        ELSE NULL
    END AS ACTUALS_THROUGH_DATE,
    IFF(VERSION_TYPE = 'Monthly Forecast',
        LAG(VERSION_CODE) OVER (PARTITION BY VERSION_TYPE ORDER BY CYCLE_MONTH),
        NULL) AS PFC_VERSION_CODE,
    -- latest / prior = newest and second-newest LOADED cycles (rank, not month arithmetic, so a skipped
    -- cycle cannot leave the prior forecast empty)
    COALESCE(VERSION_TYPE = 'Monthly Forecast'
             AND DENSE_RANK() OVER (PARTITION BY VERSION_TYPE ORDER BY CYCLE_MONTH DESC) = 1, FALSE) AS IS_LATEST_FC,
    COALESCE(VERSION_TYPE = 'Monthly Forecast'
             AND DENSE_RANK() OVER (PARTITION BY VERSION_TYPE ORDER BY CYCLE_MONTH DESC) = 2, FALSE) AS IS_PRIOR_FC,
    VERSION_TYPE <> 'Rolling Forecast (Working)' AS IS_CERTIFIED
FROM typed;
