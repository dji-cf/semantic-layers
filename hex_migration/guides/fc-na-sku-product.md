  ---
  name: FC North America SKU & product forecast
  description: North America SKU, channel and product-release forecast questions answered from FP&A Forecast Q&A.fc_product_sku - SKU, hobby, breaker, retail, Topps.com, Fanatics.com, Amazon, product release, COA, product name, street date moves (SD delayed / accelerated), cases, forecast vs budget or prior forecast, reconciling North America to the SKU forecast.
  ---

  > **Scope:** applies only to forecast questions answered with the **FP&A Forecast Q&A** semantic project (`FP&A Forecast Q&A.fc_segment_pl`, `FP&A Forecast Q&A.fc_license_revenue`, `FP&A Forecast Q&A.fc_product_sku`). These models are purpose-built for Monthly Forecast Q&A and reconciled to the forecast deck; they are not the official system of record. For official reported results, use the official finance reporting sources, not this project.

  # Canonical Metrics & Interpretation Rules
  - Use the `FP&A Forecast Q&A.fc_product_sku` model. Amounts are $M; volume in cases. North America physical cards only.
  - Always restrict to exactly ONE version and ONE fiscal_year. Default: `is_latest_fc = TRUE` and the fiscal year of
    the latest cycle. Summing across versions double counts.
  - `is_latest_fc` / `is_prior_fc` are the newest / second-newest cycles loaded in THIS SKU history (see
    `latest_fc_label`); it can lag the segment P&L by a cycle. Never assume a month. Always return `version_label`,
    plus `pfc_version_label` whenever pfc measures are used.
  - Revenue: `total_sku_revenue`; CM: `total_sku_cm`; volume: `total_volume_cases`; `sku_count`; `release_count`.
  - NA totals tie to the segment P&L North America revenue (net of eliminations) within ~$2M for the same cycle.

  # Comparisons
  - vs prior forecast / since last month: stay on the latest version and use the pfc measures carried on each row:
    `total_sku_pfc_revenue`, `sku_revenue_vs_pfc`, `sku_revenue_vs_pfc_pct`, `sku_cm_vs_pfc`, `volume_cases_vs_pfc`.
    Never self-join.
  - vs budget: `total_sku_budget_revenue`, `sku_revenue_vs_budget`, `sku_cm_vs_budget`, `volume_cases_vs_budget`.
  - vs a NAMED cycle ('<MON><YY>RF'): do NOT use pfc measures. Filter `version_code` to the latest cycle's code and
    the named code, and pivot `total_sku_revenue` (or CM / volume) by `version_label`; difference = latest minus
    named. If the named cycle is not loaded in the SKU history, say so.
  - Rank variances by absolute size.

  # Products, years and dates
  - Product questions: group by `coa` AND `product_name`. Similar names are different products.
  - `is_release_coa = TRUE` limits to lettered, named product releases (vs general / Topps NOW / hedge buckets).
  - A year mentioned with a product ("2025 Topps Chrome") is part of `product_name` / `product_year`, NOT the street
    date and NOT `fiscal_year`. A '2025' product can street in 2026.
  - `fiscal_year`, `fiscal_quarter`, `month_number` and `period_date` refer to the REVENUE month.
  - Release timing: `street_date` (this version), `pfc_street_date`, `budget_street_date`, `street_year`. Take the MIN
    per product. Street-date moves: `street_date_move_vs_pfc` in ('SD Accelerated', 'SD Delayed'), with
    `sku_revenue_vs_pfc` for the revenue that moved.

  # Channels
  - `channel_desc` for channel detail (Hobby Shop, Breaker, Topps.com, Amazon.Com, ...); `channel_group` for summaries
    (Hobby & Breakers, Retail, eCommerce / DTC, Internal / Intercompany, ...).

  # Formatting
  - $M to one decimal, % to one decimal. Volume in whole cases. Always state the version label(s) used.

  # Domain-Specific Risk Areas / Out of Scope
  - NORTH AMERICA ONLY. No International, Digital or Fanatics Collect SKU data. Route license / league questions to
    the license revenue model and segment questions to the segment P&L.
  - No prior-year (PY) product comparison, no GMV and no EBITDA at SKU grain. Say so instead of guessing.

  # Example Questions
  - "What is total North America revenue in the SKU forecast for FY in the latest forecast?"
  - "Which product releases have the largest forecast-to-budget variance?"
  - "Which channels drove the change in North America revenue versus the prior forecast?"
  - "Which product releases moved street date versus the prior forecast and what revenue moved with them?"
  - "How much Breaker revenue is in the latest forecast vs <MON><YY>RF?"
