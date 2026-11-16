---
name: FC Segment P&L
description: Monthly Forecast segment P&L questions answered from FP&A Forecast Q&A.fc_segment_pl - forecast revenue, COGS, gross margin, contribution margin, marketing, SG&A, Adj. EBITDA and margin by segment, month and quarter for the latest forecast, prior forecast (PFC), a named forecast cycle, budget / plan and prior year; BU P&L forecast pages (North America, NASE, GCP, International, Digital, Fanatics Collect), YTD actual vs year-to-go forecast, true-up vs re-forecast.
---

> **Scope:** applies only to forecast questions answered with the **FP&A Forecast Q&A** semantic project (`FP&A Forecast Q&A.fc_segment_pl`, `FP&A Forecast Q&A.fc_license_revenue`, `FP&A Forecast Q&A.fc_product_sku`). These models are purpose-built for Monthly Forecast Q&A and reconciled to the forecast deck; they are not the official system of record. For official reported results, use the official finance reporting sources, not this project.

# Scope and units
- Use the `FP&A Forecast Q&A.fc_segment_pl` model (FC Segment P&L) for management P&L questions: revenue -> COGS lines -> gross margin -> marketing -> contribution margin -> SG&A -> Adj. EBITDA, by segment and month, for Actual, Budget and Monthly Forecast versions.
- Grain: one row per `version_code` x month (`period_date`) x leaf `sub_segment`. There are no total rows; totals are sums over segments.
- All amounts are USD millions ($M). Fiscal year = calendar year; "FY26" = `fiscal_year = 2026`.
- Display: show $M to one decimal and percentages to one decimal. Percent measures (`*_pct`, `bu_ebitda_margin`) are already x100; `*_bps_*` measures are basis points.

# Version selection (always exactly one version)
- Never sum across versions. Every query filters to exactly one version, or compares versions explicitly by grouping / pivoting on `version_label`.
- "latest / current / this forecast", or no version named -> `is_latest_fc = TRUE`.
- "prior forecast / PFC / last month's forecast" as a version -> `is_prior_fc = TRUE`.
- A named cycle ("the Jun forecast") -> `version_code = '<MON><YY>RF'`; YY = the year of the latest cycle unless the user gives one.
- "budget / plan" -> `version_type = 'Budget'` (i.e. `version_code = 'Plan_' || fiscal_year`). Booked actuals -> `version_code = 'Actual'`.
- Which cycle is latest is decided by the data (`is_latest_fc`), never by this guide. Never assume a month.
- Always return `version_label` with any version-based figure, plus `pfc_version_label` when using PFC measures, or the comparison cycle's label, so the answer names its versions.
- Headline shortcuts pinned to a version (safe without a version filter, but still need a fiscal_year filter): `latest_fc_net_revenue`, `latest_fc_adj_ebitda`, `prior_fc_net_revenue`, `budget_version_net_revenue`, `actual_net_revenue`.

# Fiscal year (always exactly one)
- Always filter to one `fiscal_year`. Forecast versions include preliminary next-year months (a cycle can span three fiscal years); summing across them is meaningless.
- If no year is named, default to the fiscal year of the latest forecast cycle (the year of `cycle_month` where `is_latest_fc`).
- Span years only if the question asks for several years, and then group by `fiscal_year`.
- Next-year months inside a Monthly Forecast are a preliminary view, not a budget; label them so.

# Measures to use
- Lines: `total_net_revenue`, `total_cogs` (and component lines such as `total_royalties`), `total_gross_margin`, `total_marketing`, `total_contribution_margin`, `total_other_sga`, `total_sga_total`, `total_adj_ebitda`.
- Comparison bases on the same rows: `total_pfc_*`, `total_budget_*`, `total_py_*`.
- Variances ($M): `<line>_vs_pfc`, `<line>_vs_budget`, `<line>_vs_py` for net_revenue, gross_margin, contribution_margin, marketing, other_sga and adj_ebitda. Growth %: `<line>_vs_pfc_pct`, `net_revenue_vs_budget_pct`, `net_revenue_vs_py_pct`, `adj_ebitda_vs_budget_pct`, `adj_ebitda_vs_py_pct`.
- Margins (percent): `gross_margin_pct`, `contribution_margin_pct`, `ebitda_margin_pct`, `marketing_pct`, with `pfc_` and `budget_` versions. Margin changes are in bps: `gross_margin_bps_vs_pfc`, `ebitda_margin_bps_vs_budget`, etc.
- Margins are ratios of sums (SUM(numerator) / SUM(net_revenue)); never average row-level ratios.
- Generic "EBITDA" = `total_adj_ebitda` over ALL segments (incl. Emerging Services).
- Report growth % as NM (not meaningful) when the comparison base is <= 0.

# Comparisons
- vs prior forecast / vs PFC / since last month: with `is_latest_fc = TRUE` (or the chosen version), use the `*_vs_pfc` measures, or the current and `total_pfc_*` measures side by side. Return `pfc_version_label`.
- vs a NAMED cycle ("vs the Aug forecast", "Jun vs May forecast"): do NOT use any pfc_* measure (PFC is only the cycle immediately before). Filter `version_code IN (<latest code>, '<NAMED>')` (or `is_latest_fc = TRUE OR version_code = '<NAMED>'`), use the plain measures (`total_net_revenue`, `total_adj_ebitda`...), and group or pivot by `version_label`; then compute the difference between the two columns. For a pair where neither side is latest, filter both named codes.
- vs budget / plan: `*_vs_budget` measures on the forecast rows. Budget exists only where a Plan_<fiscal_year> is loaded (zero for FY27+).
- vs prior year / YoY: `*_vs_py` measures. PY is always the prior-year ACTUAL.
- Forecast trend across cycles: filter `version_type = 'Monthly Forecast'` and one fiscal_year, group by `version_label` and `cycle_month`, order by `cycle_month`. This is the one place where many versions appear, one per row.

# Segments
- Revenue by segment / revenue mix -> group by `revenue_segment` (North America shown net of Topps Eliminations).
- EBITDA, margins, costs, SG&A by segment -> group by `segment` (Eliminations is its own row; North America excludes it).
- Revenue AND EBITDA by segment together -> group by `segment` and also return revenue; note that deck revenue for North America = North America + Eliminations.
- Weekly Finance Update grouping -> `weekly_segment` (Other = Corporate + Key Litigation + TCG).
- "Total" / total company = all rows. "Total ex-ES" / "excl. Emerging Services" -> `is_emerging_services = FALSE`. "Total Physical Cards" -> `segment_group = 'Total Physical Cards'`.
- "Collect" = Fanatics Collect (Live + Marketplace). "domestic" / "US" = North America. "NASE" -> `bu_detail = 'NASE'` (BU P&L, below).
- List segments in deck order (sort by `segment_sort`, an internal helper).

# BU P&L (Drillable P&L pages)
- Triggers: BU P&L, drill-down, "NA P&L", "North America P&L", "International P&L", NASE, GCP, COGS mix or COGS buckets.
- Filter `bu_page` = North America, International, Digital or Fanatics Collect. Corporate, Eliminations, Key Litigation and TCG have no BU page; answer those with `segment`.
- Use the BU measures: `bu_net_sales`, `total_bu_cogs`, `total_bu_std_mfg`, `total_bu_royalties`, `total_bu_mg_shortfall`, `total_bu_autos_relics`, `total_bu_other_cogs`, `total_bu_gross_margin`, `total_bu_marketing`, `total_bu_other_sga`, `total_bu_adj_ebitda`, and `total_pfc_bu_*` / `total_budget_bu_*` / `total_py_bu_*` to compare.
- BU Net Sales = `bu_net_sales` (SUM of net_revenue under the bu_page filter), NOT `total_bu_gross_revenue`. For North America it includes Topps Eliminations, which every bu_* line excludes.
- BU % measures (`bu_gross_profit_pct`, `bu_ebitda_margin`, `bu_marketing_pct`, `bu_other_sga_pct`, `bu_cogs_pct`, COGS bucket %s) all divide by BU Net Sales and are in percent.
- North America page: show NASE, GCP and the NA total (group by `bu_detail`, plus a total without it).
  - NASE % rows (COGS buckets, SG&A %, EBITDA margin) use NASE Net Sales (`bu_detail = 'NASE'`).
  - NA-total % rows (Gross Profit %, Marketing %, EBITDA margin) use all of the North America page.
  - COGS buckets on the NA page are NASE-only; GCP COGS is one line.
  - NEVER report a GCP %, margin or bucket % (GCP revenue nets to about zero).
  - NA BU Gross Profit % is lower than the consolidated NA GM % by design (Topps Eliminations in the denominator).
- Consolidated segment questions (no BU / drill-down / NASE / GCP wording) keep using `segment` / `revenue_segment`.

# Actual vs forecast
- `af_flag = 'A'` months are booked actuals inside the forecast; `'F'` months are still forecast; `'Plan'` for Budget. A total spanning A and F months is a forecast.
- YTD actual -> `actual_months_net_revenue`; year-to-go / remaining -> `forecast_months_net_revenue`; share actual -> `actual_months_revenue_pct`; months left -> `forecast_month_count`.
- When listing months or quarters, also show `af_flag` so the reader sees which are actual.

# True-up vs re-forecast
- To split a change vs PFC, group the `*_vs_pfc` measures by `af_transition_vs_pfc`:
  - "Closed since PFC" = true-up to actuals (forecast in the PFC, actual now).
  - "Forecast in both" = re-forecast of months still in forecast.
  - "Actual in both" should be about zero.

# Out of scope (say so, don't guess)
- Not in this model: Weekly Latest Outlook / last-week (LW) figures, Risks & Opportunities, the hedge, revenue by license / sport, SKU / channel / product-release detail, free cash flow, headcount, Collect GMV, inventory, FX impacts.
- The model holds numbers, not narrative. Answer "why" questions with the quantified line-item drivers (revenue, COGS components, marketing, SG&A) and note that commentary lives in the forecast deck.

# Example questions
- "What is our FY26 revenue, EBITDA and EBITDA margin in the latest forecast, and how did they change versus the prior forecast?"
- "Which segments drove the change in FY26 revenue versus the Aug forecast?"
- "How does the current forecast compare to the 2026 budget for revenue and EBITDA by segment?"
- "Show me the North America P&L for FY26 in the latest forecast, split NASE, GCP and total."
- "How much of FY26 revenue is already actual versus still forecast, by segment?"
