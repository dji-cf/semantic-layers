---
name: FC license revenue (GRL)
description: Forecast revenue by license / league (GRL) answered from FP&A Forecast Q&A.fc_license_revenue for North America, International and Digital - MLB, NBA, NFL, soccer, UEFA, EPL, Disney, Marvel, Star Wars, TKO, WWE, UFC, F1, NIL; the hedge / holdback, hedged vs unhedged forecast revenue, license mix vs prior forecast or budget.
---

> **Scope:** applies only to forecast questions answered with the **FP&A Forecast Q&A** semantic project (`FP&A Forecast Q&A.fc_segment_pl`, `FP&A Forecast Q&A.fc_license_revenue`, `FP&A Forecast Q&A.fc_product_sku`). These models are purpose-built for Monthly Forecast Q&A and reconciled to the forecast deck; they are not the official system of record. For official reported results, use the official finance reporting sources, not this project.

# Canonical Metrics & Interpretation Rules
- Use the `FP&A Forecast Q&A.fc_license_revenue` model for all revenue-by-license questions. Amounts are $M.
- Always restrict to exactly ONE version and ONE fiscal_year. Default: `is_latest_fc = TRUE` and the fiscal year of
  the latest cycle (or `latest_fc_license_revenue`). Summing across versions double counts.
- `is_latest_fc` / `is_prior_fc` are the newest / second-newest cycles loaded in THIS league cube. Never assume a
  month; always return `version_label` (and the comparison side's label) so the answer is labelled from the result.
  The league cube can lag the segment P&L by a cycle; if the user needs a cycle not loaded here, say so.
- Headline license revenue is HEDGED: `total_license_revenue` (net_revenue). When asked about the hedge, show
  `total_hedge` and `total_unhedged_revenue` alongside it (unhedged = revenue - hedge; hedge is negative when held back).
- Use `license` for the deck GRL line and `sub_license` for detail.
  - MLB = Baseball; NBA = Basketball; NFL = Football.
  - soccer = Total Soccer (UEFA, EPL, Club Exclusives, Bundesliga, MLS, UEFA Euro).
  - Disney = Total Disney (Disney, Marvel, Star Wars); TKO = Total TKO (WWE + UFC).
- Segment filter: `segment` in North America / International / Digital.

# Comparisons
- There are NO pfc columns in this model. Every two-version comparison filters rows to both versions and aggregates
  conditionally. Never self-join.
- vs prior forecast / since last month: filter `is_latest_fc OR is_prior_fc`, one fiscal_year. Use
  `latest_fc_license_revenue`, `prior_fc_license_revenue` and `license_revenue_vs_prior_fc` (also
  `latest_fc_hedge` / `prior_fc_hedge`), grouped by license.
- vs a named cycle ('<MON><YY>RF'): filter `version_code` to the latest cycle's code and the named code, and pivot
  `total_license_revenue` by `version_label`; difference = latest minus named. If the named cycle is not loaded, say so.
- vs budget: same pattern with `version_code IN (<latest code>, 'Plan_' || fiscal_year)`, pivot by `version_label`.

# License mix / share
- There is no mix measure. For "share of revenue by license", compute `total_license_revenue` by license for one
  version, segment set and fiscal_year, then divide each row by the column total (×100, name it *_pct). Include the
  Unallocated row in the denominator so shares tie to segment revenue, and say so.

# Unallocated row
- `license = 'Unallocated (not in license cube)'` (`is_reconciling = TRUE`) closes the gap between the license cube
  and segment revenue. Include it in totals so they tie to segment revenue, and mention it whenever it appears.
  Exclude it only when the user asks for allocated licenses only.

# Formatting
- $M to one decimal, % to one decimal. Always state the version label used.

# Domain-Specific Risk Areas / Out of Scope
- Revenue by license only. No gross margin, contribution margin or EBITDA by license, no Fanatics Collect, no GMV,
  no FX, no GCP manufacturing or eliminations. Say so instead of guessing; route margin questions to the segment P&L.
- License figures are planning-cube basis and can differ from the printed deck GRL page by ~1%; say so if asked to
  tie to the deck.
- Older cycles' license splits may not match their deck build; prefer the latest forecast.

# Example Questions
- "What is FY revenue by license in the latest forecast?"
- "How much of International revenue is the hedge, by license?"
- "Which licenses make up Digital revenue and how did they change versus the prior forecast?"
- "How did MLB revenue change versus the <MON><YY>RF forecast?"
- "What share of North America revenue is soccer?"
