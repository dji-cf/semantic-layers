---
name: FC North America SKU & product forecast
description: North America SKU, channel and product-release forecast questions answered from the FC PRODUCT SKU.FC_PRODUCT_SKU semantic model - SKU, hobby, breaker, retail, Topps.com, Fanatics.com, Amazon, product release, COA, product name, street date moves (SD delayed / accelerated), cases, forecast vs budget or prior forecast, reconciling North America to the SKU forecast.
---

> **Scope:** applies only to forecast questions answered with the three FC forecast semantic projects, one model each: `FC SEGMENT PL.FC_SEGMENT_PL`, `FC LISCENCE REVENUE.FC_LICENSE_REVENUE` and `FC PRODUCT SKU.FC_PRODUCT_SKU`. They are synced from Snowflake semantic views and reconciled to the forecast deck. They are not the system of record: for official reported results, use the official finance reporting sources.

> **Field names are UPPERCASE** exactly as written in this guide (e.g. `IS_LATEST_FC`, `TOTAL_NET_REVENUE`). Lowercase names return "Invalid semantic column". String values keep their case (`'North America'`, `'Plan_2026'`).

# Canonical metrics and interpretation rules
- Use `FC PRODUCT SKU.FC_PRODUCT_SKU`. Grain: one row per `VERSION_CODE` x month x `SKU` x `CHANNEL_DESC`. Amounts are $M; volume is in cases. North America physical cards only.
- Versions: Monthly Forecasts and Budget only (no `Actual` version; booked months show `AF_FLAG = 'A'` inside a forecast).
- Always restrict to exactly ONE version and ONE `FISCAL_YEAR`. Default: `IS_LATEST_FC = TRUE` and the fiscal year of the latest cycle. Summing across versions double counts.
- `IS_LATEST_FC` / `IS_PRIOR_FC` are the newest / second-newest cycles loaded in THIS SKU history (`LATEST_FC_LABEL`), which can lag the segment P&L by a cycle. Never assume a month. Always return `VERSION_LABEL`, plus `PFC_VERSION_LABEL` whenever `PFC_*` facts are used.
- Metrics: revenue `TOTAL_SKU_REVENUE`; CM `TOTAL_SKU_CM`; distinct SKUs `SKU_COUNT`. Volume = `SUM(VOLUME_CASES)`. Releases = `COUNT(DISTINCT COA)` with `IS_RELEASE_COA = TRUE`.
- NA totals tie to the segment P&L North America revenue (net of eliminations) within ~$2M for the same cycle.

# Comparisons
- vs prior forecast / since last month: stay on the latest version and subtract the pfc facts carried on each row: `SUM(NET_REVENUE) - SUM(PFC_NET_REVENUE)` (metric `TOTAL_SKU_PFC_REVENUE`), `SUM(CONTRIBUTION_MARGIN) - SUM(PFC_CONTRIBUTION_MARGIN)`, `SUM(VOLUME_CASES) - SUM(PFC_VOLUME_CASES)`. % = `100 * delta / NULLIF(SUM(PFC_NET_REVENUE), 0)`. Never self-join.
- vs budget: `BUDGET_NET_REVENUE` (metric `TOTAL_SKU_BUDGET_REVENUE`), `BUDGET_CONTRIBUTION_MARGIN`, `BUDGET_VOLUME_CASES`, the same way.
- vs a NAMED cycle (`'<MON><YY>RF'`): do NOT use pfc facts. Filter `(IS_LATEST_FC = TRUE OR VERSION_CODE = '<NAMED>')` and aggregate conditionally: `SUM(IFF(IS_LATEST_FC, NET_REVENUE, 0)) - SUM(IFF(VERSION_CODE = '<NAMED>', NET_REVENUE, 0))`, with `MAX(IFF(..., VERSION_LABEL, NULL))` for each side's label. If the named cycle is not loaded in the SKU history, say so.
- Rank variances by absolute size (`ORDER BY ABS(delta) DESC`).

# Products, years and dates
- Product questions: group by `COA` AND `PRODUCT_NAME`. Similar names are different products.
- `IS_RELEASE_COA = TRUE` limits results to lettered, named product releases (excluding general / Topps NOW / hedge buckets).
- A year mentioned with a product ("2025 Topps Chrome") is part of `PRODUCT_NAME` / `PRODUCT_YEAR`. It is NOT the street date and NOT `FISCAL_YEAR`; a '2025' product can street in 2026.
- `FISCAL_YEAR`, `FISCAL_QUARTER`, `MONTH_NUMBER` and `PERIOD_DATE` refer to the REVENUE month.
- Release timing: `STREET_DATE` (this version), `PFC_STREET_DATE`, `BUDGET_STREET_DATE`, `STREET_YEAR`. Take the MIN per product.
- Street-date moves: `STREET_DATE_MOVE_VS_PFC` IN ('SD Accelerated', 'SD Delayed'), with `SUM(NET_REVENUE) - SUM(PFC_NET_REVENUE)` for the revenue that moved.

# Channels
- `CHANNEL_DESC` for channel detail (Hobby Shop, Hobby Distributor, Breaker, Topps.com, Fanatics.com, Amazon.Com, Retail Distributor - ...). `CHANNEL_GROUP` for summaries (Hobby & Breakers, Retail, eCommerce / DTC, Internal / Intercompany, Planning input / unassigned, Other).

# Formatting
- $M to one decimal, % to one decimal. Volume in whole cases. Always state the version label(s) used.

# Risk areas / out of scope
- NORTH AMERICA ONLY. There is no International, Digital or Fanatics Collect SKU data. Route license / league questions to `FC LISCENCE REVENUE.FC_LICENSE_REVENUE` and segment questions to `FC SEGMENT PL.FC_SEGMENT_PL`.
- There is no prior-year (PY) product comparison, no GMV and no EBITDA at SKU grain. Say so instead of guessing.

# Example questions
- "What is total North America revenue in the SKU forecast for FY26 in the latest forecast?"
- "Which product releases have the largest forecast-to-budget variance?"
- "Which channels drove the change in North America revenue versus the prior forecast?"
- "Which product releases moved street date versus the prior forecast and what revenue moved with them?"
- "How much Breaker revenue is in the latest forecast vs <MON><YY>RF?"
