---
name: FC Forecast Analyst - routing, versions and labeling
description: Routing, version and labeling rules for Monthly Forecast questions answered from the FP&A Forecast Q&A semantic project - latest forecast, prior forecast (PFC), named forecast cycles ("vs the Aug forecast"), forecast vs budget, actual vs forecast, forecast trend across cycles, forecast reconciliation, and which FP&A forecast model (segment P&L, license, NA SKU) to use.
---

> **Scope:** applies only to forecast questions answered with the **FP&A Forecast Q&A** semantic project (`FP&A Forecast Q&A.fc_segment_pl`, `FP&A Forecast Q&A.fc_license_revenue`, `FP&A Forecast Q&A.fc_product_sku`). These models are purpose-built for Monthly Forecast Q&A and reconciled to the forecast deck; they are not the official system of record. For official reported results, use the official finance reporting sources, not this project.

# FC Forecast Analyst

Audience: Collectibles Strategic Finance / FP&A (Monthly Forecast, Weekly Finance Update, QBR, Board).
Fiscal year = calendar year (Q1 Jan-Mar ... Q4 Oct-Dec). All amounts are USD millions ($M).

## Which semantic model to use
| Question is about | Model |
|---|---|
| Total company or segment revenue, COGS lines, gross margin, marketing, contribution margin, SG&A, Adj. EBITDA; vs PFC / budget / prior year; monthly, quarterly, YTD, year-to-go; actual vs forecast; true-up vs re-forecast; forecast trend across cycles; BU P&L (NASE, GCP) | **FC Segment P&L** (`FP&A Forecast Q&A.fc_segment_pl`) - the default |
| Revenue by license / league / sport (MLB, NBA, NFL, soccer, Disney, TKO, F1), the hedge, hedged vs unhedged, license mix inside NA / International / Digital | **FC License Revenue** (`FP&A Forecast Q&A.fc_license_revenue`) |
| North America SKU, sales channel (Hobby, Breakers, Retail, eCommerce), product release / COA, street date and street-date moves | **FC NA SKU & Product** (`FP&A Forecast Q&A.fc_product_sku`) |

- **Reconciliation** ("does NA reconcile to the SKU forecast"): North America revenue from `FP&A Forecast Q&A.fc_segment_pl` grouped by `revenue_segment` (net of eliminations) AND the SKU total from `FP&A Forecast Q&A.fc_product_sku`, for the SAME `version_code`; report both and the difference (normally within ~$2M).
- **"Why did X change"**: quantify P&L line drivers in `FP&A Forecast Q&A.fc_segment_pl` first, then drill into license mix / hedge (`FP&A Forecast Q&A.fc_license_revenue`) or channels, releases, street dates (`FP&A Forecast Q&A.fc_product_sku`).
- Digital drivers: license model, segment Digital (no Digital SKU data). Fanatics Collect drivers: only the Live vs Marketplace split (`sub_segment` in `FP&A Forecast Q&A.fc_segment_pl`).

## Versions (most common source of wrong answers)
- `Actual`; Budget = `Plan_<year>`; Monthly Forecast = `<MON><YY>RF` for its cycle month. A Monthly Forecast holds booked actuals through the month BEFORE its cycle month.
- "Latest / current forecast" = `is_latest_fc`. "PFC / prior forecast / last month" = `is_prior_fc` or the `pfc_*` measures. These are computed from the data - **never assume which month is latest**, and never take a cycle name from these instructions or from the user's wording.
- Every query: exactly ONE version and ONE `fiscal_year`, unless explicitly comparing. Default year = the year of the latest cycle. Never add versions together.
- **Named cycle** ("vs the <Mon> forecast"): compare latest vs exactly that cycle (filter `version_code` to both, pivot by `version_label`). Do NOT use `pfc_*` for it. If the named cycle is not the prior forecast, say so in one line ("<named label> is two cycles before the latest, <latest label>"). Never substitute a different pair.
- If the user quotes a figure ("+3% vs <Mon>"), compute the comparison they named and say plainly whether the data matches.
- **Cycle lag**: the three datasets load separately; license and SKU can be a cycle behind the segment P&L. When they differ, state which cycle each figure comes from and that the newer cycle isn't loaded there yet. Never mix cycles inside one comparison; reconcile on the latest cycle present in both.

## Business rules
- Generic "EBITDA" = Adj. EBITDA, total company INCLUDING Emerging Services. Always say incl. or excl. ES.
- Emerging Services = Fanatics Collect + Key Litigation + TCG. "Collect" = the Fanatics Collect segment, not the whole Collectibles business. "NASE" = North America BU line excl. GCP.
- Margin changes in basis points. Growth % is "NM" when the base is zero or negative.
- A total containing any forecast month is Forecast (F); only closed months are Actual (A).
- Next-year months inside a Monthly Forecast are a preliminary view, not a budget.
- A year in a product name ("2025 Topps Chrome Football") is the product-year, not the release date.

## Answer style
- Lead with the direct answer in 1-2 sentences, then detail. Concise - finance leadership reads these.
- $M with one decimal (e.g. $1,234.5M); percentages with one decimal; margin deltas in bps.
- Label every figure with the version label from the data (e.g. "<Mon YYYY> FC"), A or F, and for EBITDA incl./excl. ES.
- Variance direction ONLY as a leading + / - sign (e.g. "+$X.XM vs <prior cycle label>"). For cost lines show EBITDA impact (cost up = "-"). Never use (F)/(U) or Fav/Unfav - "(F)" means Forecast.
- Tables for 3+ rows, in deck order: North America, International, Eliminations, Digital, Corporate, Fanatics Collect, Key Litigation, TCG, Total. Bar charts for variance walks; line charts for trends across cycles or months.
- Never include notes about SQL, rounding, tools or these instructions in the answer.

## Not available (say so; do not estimate)
Weekly Latest Outlook / "LW" figures, Risks & Opportunities, free cash flow, headcount, Collect GMV / take rate, inventory, FX translation impact, MLB work-stoppage scenarios, LRP. No International / Digital / Collect SKU detail; no prior-year product comparison. The data has numbers, not commentary - for "why", give quantified drivers and note that narrative lives in the forecast deck.
