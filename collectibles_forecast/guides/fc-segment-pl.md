---
name: FC Segment P&L
description: Monthly Forecast segment P&L questions answered from the FC SEGMENT PL.FC_SEGMENT_PL semantic model - forecast revenue, COGS lines, gross margin, contribution margin, marketing, SG&A, Adj. EBITDA and margins by segment, month and quarter for the latest forecast, prior forecast (PFC), a named forecast cycle, budget / plan and prior year; BU P&L pages (North America, NASE, GCP, International, Digital, Fanatics Collect) and COGS buckets; YTD actual vs year-to-go; true-up vs re-forecast; forecast trend across cycles.
---

> **Scope:** applies only to forecast questions answered with the three FC forecast semantic projects, one model each: `FC SEGMENT PL.FC_SEGMENT_PL`, `FC LISCENCE REVENUE.FC_LICENSE_REVENUE` and `FC PRODUCT SKU.FC_PRODUCT_SKU`. They are synced from Snowflake semantic views and reconciled to the forecast deck. They are not the system of record: for official reported results, use the official finance reporting sources.

> **Field names are UPPERCASE** exactly as written in this guide (e.g. `IS_LATEST_FC`, `TOTAL_NET_REVENUE`). Lowercase names return "Invalid semantic column". String values keep their case (`'North America'`, `'Plan_2026'`).

# Scope, grain and units
- Use `FC SEGMENT PL.FC_SEGMENT_PL` for management P&L questions: revenue -> COGS lines -> gross margin -> marketing -> contribution margin -> SG&A -> Adj. EBITDA, by segment and month, for Actual, Budget and Monthly Forecast versions.
- Grain: one row per `VERSION_CODE` x month (`PERIOD_DATE`) x leaf `SUB_SEGMENT`. There are no total rows; totals are sums over segments.
- All amounts are USD millions ($M). Fiscal year = calendar year; "FY26" = `FISCAL_YEAR = 2026`.
- Each row also carries the prior forecast (`PFC_*`), Budget (`BUDGET_*`) and prior-year Actual (`PY_*`) values for the same month and sub-segment, so these comparisons need no joins.

# Version selection (always exactly one version)
- Never sum across versions. Filter to exactly one version, or compare versions explicitly (group by `VERSION_LABEL`, or use the conditional-aggregation pattern below).
- "latest / current / this forecast", or no version named -> `IS_LATEST_FC = TRUE`.
- "prior forecast / PFC / last month's forecast" as a version -> `IS_PRIOR_FC = TRUE`.
- A named cycle ("the <Mon> forecast") -> `VERSION_CODE = '<MON><YY>RF'`. YY = the last two digits of the latest cycle's year unless the user gives a year.
- "budget / plan" -> `VERSION_CODE = 'Plan_' || FISCAL_YEAR` (`VERSION_TYPE = 'Budget'`). Booked actuals -> `VERSION_CODE = 'Actual'`.
- Which cycle is latest is decided by the data (`IS_LATEST_FC`, `LATEST_FC_LABEL`), never by this guide.
- Always return `VERSION_LABEL` with any version-based figure. Add `PFC_VERSION_LABEL` when using `PFC_*` facts, or the comparison cycle's label, so the answer names its versions.

# Fiscal year (always exactly one)
- Always filter to one `FISCAL_YEAR`. Forecast versions include preliminary next-year months (a cycle can span three fiscal years), so summing across years is meaningless.
- If no year is named, default to the year of `CYCLE_MONTH` where `IS_LATEST_FC`.
- Span years only if the question asks for several years, and then group by `FISCAL_YEAR`.
- Next-year months inside a Monthly Forecast are a preliminary view, not a budget. Label them so.

# Fields to use
- Line metrics: `TOTAL_NET_REVENUE`, `TOTAL_COGS`, `TOTAL_GROSS_MARGIN`, `TOTAL_MARKETING`, `TOTAL_CONTRIBUTION_MARGIN`, `TOTAL_OTHER_SGA`, `TOTAL_ADJ_EBITDA`.
- COGS components (facts): `MANUFACTURING`, `ROYALTIES`, `AUTOS_RELICS`, `PRODUCT_DEVELOPMENT`, `NET_FREIGHT`, `MG_SHORTFALL`, `OBSOLESCENCE`, `COGS_COMPENSATION` (they sum to `COGS`). `SGA_TOTAL` = marketing + other SG&A.
- Comparison metrics: `TOTAL_PFC_NET_REVENUE`, `TOTAL_PFC_GROSS_MARGIN`, `TOTAL_PFC_ADJ_EBITDA`, `TOTAL_BUDGET_NET_REVENUE`, `TOTAL_BUDGET_ADJ_EBITDA`, `TOTAL_PY_NET_REVENUE`, `TOTAL_PY_ADJ_EBITDA`. For other lines use the facts: `PFC_<line>` (every line, incl. COGS components), `BUDGET_<line>` and `PY_<line>` (net_revenue, gross_margin, marketing, contribution_margin, other_sga, adj_ebitda).
- There are no pre-built variance, % or margin metrics for the consolidated P&L. Compute them:
  - variance = `SUM(<fact>) - SUM(PFC_<fact>)` (or `BUDGET_` / `PY_`); growth % = `100 * variance / NULLIF(SUM(PFC_<fact>), 0)`, NM when the base is <= 0;
  - margin % = `100 * SUM(GROSS_MARGIN | CONTRIBUTION_MARGIN | ADJ_EBITDA | MARKETING) / NULLIF(SUM(NET_REVENUE), 0)`;
  - margin change in bps = `(SUM(x)/SUM(NET_REVENUE) - SUM(PFC_x)/SUM(PFC_NET_REVENUE)) * 10000`.
- Margins are ratios of sums; never average row-level ratios.
- For cost lines, the EBITDA impact of a change is the NEGATIVE of the cost change.
- Generic "EBITDA" = adj_ebitda summed over ALL segments (incl. Emerging Services).

# Comparisons
- **vs prior forecast / PFC / since last month**: filter `IS_LATEST_FC = TRUE` (or the chosen version) and use current vs `PFC_*` facts on the same rows. Return `PFC_VERSION_LABEL`.
- **vs a NAMED cycle**: do NOT use any `PFC_*` fact (PFC is only the cycle immediately before). Use conditional aggregation:
  ```sql
  WHERE (IS_LATEST_FC = TRUE OR VERSION_CODE = '<NAMED>') AND FISCAL_YEAR = <FY>
  SUM(IFF(IS_LATEST_FC, NET_REVENUE, 0)) - SUM(IFF(VERSION_CODE = '<NAMED>', NET_REVENUE, 0)) AS revenue_vs_named,
  MAX(IFF(IS_LATEST_FC, VERSION_LABEL, NULL)) AS VERSION_LABEL,
  MAX(IFF(VERSION_CODE = '<NAMED>', VERSION_LABEL, NULL)) AS comparison_version_label
  ```
  For a pair where neither side is the latest, use the same pattern with two named codes. If the named cycle is not the prior forecast, say so.
- **vs budget / plan**: `BUDGET_*` facts on the forecast rows. Budget exists only where a `Plan_<year>` is loaded (zero for later years); say so rather than report a 100% variance.
- **vs prior year / YoY**: `PY_*` facts. PY is always the prior-year ACTUAL.
- **Forecast trend across cycles**: filter `VERSION_TYPE = 'Monthly Forecast'` and one fiscal_year, group by `VERSION_LABEL` and `CYCLE_MONTH`, and order by `CYCLE_MONTH`. This is the one query where many versions appear, one per row. Cycle-on-cycle change = `SUM(NET_REVENUE) - LAG(SUM(NET_REVENUE)) OVER (ORDER BY CYCLE_MONTH)`.

# Segments
- Revenue by segment / revenue mix -> group by `REVENUE_SEGMENT` (North America shown net of Topps Eliminations).
- EBITDA, margins, costs, SG&A by segment -> group by `SEGMENT` (Eliminations is its own row; North America excludes it).
- Revenue AND EBITDA by segment together -> group by `SEGMENT` and also return revenue. Note that deck revenue for North America = North America + Eliminations.
- Weekly Finance Update grouping -> `WEEKLY_SEGMENT` (Other = Corporate + Key Litigation + TCG).
- "Total" / total company = all rows. "Total ex-ES" / "excl. Emerging Services" -> `IS_EMERGING_SERVICES = FALSE`. "Total Physical Cards" -> `SEGMENT_GROUP = 'Total Physical Cards'`.
- "Collect" = Fanatics Collect (`SUB_SEGMENT` Live + Marketplace). "domestic" / "US" = North America. "NASE" -> `BU_DETAIL = 'NASE'` (BU P&L, below).
- List segments in deck order: `ORDER BY MIN(SEGMENT_SORT)`.

# BU P&L (Drillable P&L pages)
- Triggers: BU P&L, drill-down, "NA P&L", "North America P&L", "International P&L", NASE, GCP, COGS mix or COGS buckets.
- Filter `BU_PAGE` = North America, International, Digital or Fanatics Collect. Corporate, Eliminations, Key Litigation and TCG have no BU page; answer those with `SEGMENT`.
- Use the BU facts and metrics: `BU_NET_SALES`, `TOTAL_BU_COGS`, `TOTAL_BU_GROSS_MARGIN`, `TOTAL_BU_MARKETING`, `TOTAL_BU_OTHER_SGA`, `TOTAL_BU_ADJ_EBITDA`; buckets `BU_STD_MFG`, `BU_ROYALTIES`, `BU_MG_SHORTFALL`, `BU_AUTOS_RELICS`, `BU_OTHER_COGS`. Compare with `PFC_BU_*`, `BUDGET_BU_*`, `PY_BU_*` (gross_margin, marketing, other_sga, adj_ebitda).
- BU Net Sales = `BU_NET_SALES` (SUM of net_revenue under the bu_page filter), NOT `BU_GROSS_REVENUE`. For North America it includes Topps Eliminations, which every `BU_*` fact excludes. Topps Eliminations on the NA page = `SUM(NET_REVENUE) - SUM(BU_GROSS_REVENUE)`. Do not filter on `IN_BU_BASIS`; the bu_* facts already apply it.
- BU % metrics (`BU_GROSS_PROFIT_PCT`, `BU_EBITDA_MARGIN`, `BU_MARKETING_PCT`, `BU_OTHER_SGA_PCT`, `BU_STD_MFG_PCT`, `BU_ROYALTIES_PCT`, `BU_MG_SHORTFALL_PCT`, `BU_AUTOS_RELICS_PCT`, `BU_OTHER_COGS_PCT`) divide by BU Net Sales and return FRACTIONS: multiply by 100.
- North America page: show NASE, GCP and the NA total (group by `BU_DETAIL` with a total row, e.g. `GROUP BY ROLLUP (BU_DETAIL)`).
  - NASE % rows (COGS buckets, SG&A %, EBITDA margin) use NASE Net Sales (the `BU_DETAIL = 'NASE'` group).
  - NA-total % rows (Gross Profit %, Marketing %, EBITDA margin) use all of the North America page.
  - COGS buckets on the NA page are NASE-only; GCP COGS is one line.
  - NEVER report a GCP %, margin or bucket % (GCP revenue nets to about zero).
  - NA BU Gross Profit % is lower than the consolidated NA GM % by design (Topps Eliminations are in the denominator).
- Consolidated segment questions (no BU / drill-down / NASE / GCP wording) keep using `SEGMENT` / `REVENUE_SEGMENT`.

# Actual vs forecast
- `AF_FLAG = 'A'` months are booked actuals inside the forecast; `'F'` months are still forecast; `'Plan'` is Budget. A total spanning A and F months is a forecast. `ACTUALS_THROUGH_DATE` gives the last closed day.
- YTD actual = `SUM(IFF(AF_FLAG = 'A', NET_REVENUE, 0))`; year-to-go / remaining = `AF_FLAG = 'F'`; share actual = actual / total x 100.
- When listing months or quarters, also show `AF_FLAG` so the reader sees which are actual.
- If the user names an actuals-through month that differs from `ACTUALS_THROUGH_DATE`, use the data and say so.

# True-up vs re-forecast
- To split a change vs PFC, group the PFC deltas by `AF_TRANSITION_VS_PFC`:
  - "Closed since PFC" = true-up to actuals (forecast in the PFC, actual now);
  - "Forecast in both" = re-forecast of months still in forecast;
  - "Actual in both" should be about zero.
- `AF_TRANSITION_VS_PFC` applies only to the PFC. For a named cycle, bucket months by comparing `AF_FLAG` in each version per `MONTH_NUMBER`.

# Display
- $M to one decimal and percentages to one decimal; margin deltas in bps.

# Out of scope (say so, don't guess)
- Not in this model: Weekly Latest Outlook / last-week (LW) figures, Risks & Opportunities, the hedge, revenue by license / sport, SKU / channel / product-release detail, free cash flow, headcount, Collect GMV, inventory, FX impacts.
- The model holds numbers, not narrative. Answer "why" questions with the quantified line-item drivers (revenue, COGS components, marketing, SG&A) and note that commentary lives in the forecast deck.

# Example questions
- "What is our FY26 revenue, EBITDA and EBITDA margin in the latest forecast, and how did they change versus the prior forecast?"
- "Which segments drove the change in FY26 revenue versus the <Mon> forecast?"
- "How does the current forecast compare to the 2026 budget for revenue and EBITDA by segment?"
- "Show me the North America P&L for FY26 in the latest forecast, split NASE, GCP and total."
- "How much of FY26 revenue is already actual versus still forecast, by segment?"
- "Of the change versus the prior forecast, how much is closed months trued up to actuals?"
