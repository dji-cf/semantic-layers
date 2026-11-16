---
name: FC license revenue (GRL)
description: Forecast revenue by license / league (GRL) answered from the FC LISCENCE REVENUE.FC_LICENSE_REVENUE semantic model for North America, International and Digital - MLB, NBA, NFL, soccer, UEFA, EPL, Disney, Marvel, Star Wars, TKO, WWE, UFC, F1, NIL; the hedge / holdback, hedged vs unhedged revenue, license mix and license changes vs the prior forecast, a named cycle or budget.
---

> **Scope:** applies only to forecast questions answered with the three FC forecast semantic projects, one model each: `FC SEGMENT PL.FC_SEGMENT_PL`, `FC LISCENCE REVENUE.FC_LICENSE_REVENUE` and `FC PRODUCT SKU.FC_PRODUCT_SKU`. They are synced from Snowflake semantic views and reconciled to the forecast deck. They are not the system of record: for official reported results, use the official finance reporting sources.

> **Field names are UPPERCASE** exactly as written in this guide (e.g. `IS_LATEST_FC`, `TOTAL_NET_REVENUE`). Lowercase names return "Invalid semantic column". String values keep their case (`'North America'`, `'Plan_2026'`).

# Canonical metrics and interpretation rules
- Use `FC LISCENCE REVENUE.FC_LICENSE_REVENUE` for all revenue-by-license questions. Grain: one row per `VERSION_CODE` x month x `SEGMENT` x `SUB_LICENSE`. Amounts are $M.
- Always restrict to exactly ONE version and ONE `FISCAL_YEAR`. Default: `IS_LATEST_FC = TRUE` and the fiscal year of the latest cycle. Summing across versions double counts.
- `IS_LATEST_FC` / `IS_PRIOR_FC` are the newest / second-newest cycles loaded in THIS league cube (`LATEST_FC_LABEL`). The cube can lag the segment P&L by a cycle: if the user needs a cycle that isn't loaded here, say so. Never assume a month. Always return `VERSION_LABEL` (and the comparison side's label) so the answer is labelled from the result.
- Headline license revenue is HEDGED: `TOTAL_LICENSE_REVENUE` (SUM of `NET_REVENUE`). For hedge questions, show `TOTAL_HEDGE` and `TOTAL_UNHEDGED_REVENUE` alongside it (unhedged = revenue - hedge; the hedge is negative when revenue is held back).
- Use `LICENSE` for the deck GRL line and `SUB_LICENSE` for detail:
  - MLB = Baseball; NBA = Basketball; NFL = Football;
  - soccer = Total Soccer (UEFA, EPL, Club Exclusives, Bundesliga, MLS, UEFA Euro);
  - Disney = Total Disney (Disney, Marvel, Star Wars); TKO = Total TKO (WWE + UFC).
- Segment filter: `SEGMENT` in North America / International / Digital.

# Comparisons (this model has NO pfc, budget or variance columns)
Every two-version comparison filters rows to both versions and aggregates conditionally. Never self-join.
```sql
WHERE (IS_LATEST_FC = TRUE OR <other>) AND FISCAL_YEAR = <FY>
SUM(IFF(IS_LATEST_FC, NET_REVENUE, 0)) - SUM(IFF(<other>, NET_REVENUE, 0)) AS revenue_vs_comparison,
MAX(IFF(IS_LATEST_FC, VERSION_LABEL, NULL)) AS VERSION_LABEL,
MAX(IFF(<other>, VERSION_LABEL, NULL))      AS comparison_version_label
-- grouped by LICENSE (or SUB_LICENSE / SEGMENT)
```
- vs prior forecast / since last month: `<other>` = `IS_PRIOR_FC`.
- vs a named cycle: `<other>` = `VERSION_CODE = '<MON><YY>RF'`. If the named cycle is not loaded here, say so.
- vs budget: `<other>` = `VERSION_CODE = 'Plan_' || FISCAL_YEAR`.
- The same pattern works for `HEDGE_REVENUE` and `UNHEDGED_NET_REVENUE`.

# License mix / share
- There is no mix metric. For "share of revenue by license", compute `TOTAL_LICENSE_REVENUE` by license for one version, segment set and fiscal_year, then divide each row by the column total (x100). Include the Unallocated row in the denominator so shares tie to segment revenue, and say so.

# Unallocated row
- `LICENSE = 'Unallocated (not in license cube)'` (`IS_RECONCILING = TRUE`) closes the gap between the license cube and segment revenue. Include it in totals so they tie to segment revenue, and mention it whenever it appears. Exclude it only when the user asks for allocated licenses only.

# Formatting
- $M to one decimal, % to one decimal. Always state the version label used.

# Risk areas / out of scope
- Revenue by license only. There is no gross margin, contribution margin or EBITDA by license, no Fanatics Collect, no GMV, no FX translation, no GCP manufacturing and no eliminations. Say so instead of guessing, and route margin questions to `FC SEGMENT PL.FC_SEGMENT_PL`.
- FX: the hedge is the only currency / timing lever here. If asked for FX impact, say FX translation isn't available and quantify the hedge instead.
- License figures are on a planning-cube basis and can differ from the printed deck GRL page by ~1%. Say so if asked to tie to the deck.
- Older cycles' license splits may not match their deck build, so prefer the latest forecast.

# Example questions
- "What is FY26 revenue by license in the latest forecast?"
- "How much of International revenue is the hedge, by license?"
- "Which licenses make up Digital revenue and how did they change versus the prior forecast?"
- "How did MLB revenue change versus the <MON><YY>RF forecast?"
- "What share of North America revenue is soccer?"
