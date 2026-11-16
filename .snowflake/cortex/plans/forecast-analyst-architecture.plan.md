# Plan: Forecast Cortex Analyst Architecture

## 1. Decision: one agent, three semantic views

**Recommendation: one Cortex Agent with three Cortex Analyst tools. Each tool is a single-logical-table semantic view sitting on a denormalized view.**

| Option | Verdict | Why |
|---|---|---|
| One semantic view for everything | Reject | The 20 questions span 3 grains: segment × month, license × month and SKU/COA × channel × month. Putting them in one table double-counts totals, goes over the ~100-column budget and needs multi-table relationships, which is the #1 cause of wrong answers. |
| Multiple separate agents | Reject | Users ask questions that cut across areas (Q16 "NA reconcile to SKU forecast", Q18 "Digital decline drivers"). An agent can call several analyst tools in one answer. Separate agents can't. |
| **One agent + 3 single-table SVs** | **Adopt** | Each SV has one clean grain and no joins. The agent's orchestration instructions route each question. |

```
                 FC Forecast Analyst (Cortex Agent)
                 ├─ orchestration: routing + labeling rules (A/F, vs-basis, incl/excl ES)
   ┌─────────────┼──────────────────────┬──────────────────────────┐
SV_FC_SEGMENT_PL   SV_FC_LICENSE_PL         SV_FC_PRODUCT_SKU      (Phase 3, optional)
version×month×     version×month×LOB×       version×month×SKU×     Cortex Search over
mgmt segment       league (hedge/unhedged)  channel + COA/release  FC deck commentary ("why")
~80% of Qs         Q20, GRL, Digital mix    Q16, Q18, Q19
```

## 2. What the data supports (verified live, Oct 19 2026)

- `CARDPLN_PL_BY_LOB` has every needed version: Actual FY23–26, Plan_2026, **JAN26RF…SEP26RF** (SEP26RF is now loaded), OCT/NOV/DEC25RF, and Rolling Forecast (Working). Grains are MONTH / QUARTER / YEAR.
- **Revenue ties exactly to the Sep FC deck.** Physical Cards 4,917.4 · ex-ES 4,989.4 · Collect 435.8 · Intl 828.7 · NA = NA Gross 4,239.2 + Topps Elims (150.5) = 4,088.7. Budget 3,372.0 and AUG26RF 4,856.7 also tie. Monthly SEP26RF revenue matches deck A.4 (324/319/228/…/408).
- **Forecast versions already contain actuals for closed months.** SEP26RF Jan–Aug = Actual, and AUG26RF runs through Jul. So the A/F flag and "true-up vs. still-forecast" splits (Q3, Q13) can be derived from version metadata.
- **BLOCKER: `ACX_EBITDA` ≠ deck Adj. EBITDA.**
  - FY26 SEP26RF: Physical Cards 1,838 vs. deck 2,287; Collect −121 vs. −10.
  - Q1 26 Actual total ≈ 144 vs. GAAP 301.
  - Gross margin runs ~$540M below the deck.
  - Likely causes are add-backs or allocations, and the intercompany COGS/royalty treatment.
  - Every EBITDA, margin and walk question (Q1, 5, 6, 7, 10, 11, 12, 15) depends on fixing this.
- Rollup table LOBs are NA Gross, Intl incl. Elims, Topps Elims, Physical Cards, ex-ES, Live & Collect and Key Litigation. **Digital, Corporate and TCG exist only in `CARDPLN_PL_BY_LOB_STG`** (LB_305 / LB_301 / LB_308).
- **Key Litigation = cost center `CC_40313`** (LB_301 46.2 + LB_302 2.8 ≈ 49 = deck 49). This answers Foundation doc §16 Q3.
- STG stores parent and child members side by side (`Total Channel` = DTC + Wholesale; `Total Cost Center` alongside `CC_*`; `Total Intercompany` alongside `ICP_*`). Naive sums double-count, so the leaf build has to pick exactly one member level per dimension.
- SKU forecast (`GMPLN_REVENUE_FORECAST_HISTORY`, 10 vintages incl. SEP26RF) is **NA only**: FY26 4,086.9 vs. segment NA 4,088.7 ($1.8M gap). Q16 can therefore be answered.
- License P&L (`CARDPLN_PL_BY_LEAGUE_V`) covers NA / Intl / Digital with `HEDGE` / `UNHEDGED`.
- Product-release view is NA-only and has the known broken PY (see memory), so it is used only for Budget vs. FC.

## 3. Semantic view designs

### SV_FC_SEGMENT_PL (core)
**Base view `V_FC_SEGMENT_PL`**: one row per **version × fiscal month × leaf management segment**, with P&L lines **pivoted wide**. Long-format P&L forces filters on every metric and is error-prone for text-to-SQL.

- **Leaf segments** (rows): NA (net of elims), International, Eliminations, Digital, Corporate (excl. CC_40313), Fanatics Collect (Live / Marketplace sub-LOB as an attribute), Key Litigation, TCG. Only leaves are stored, so totals are always `SUM` over hierarchy attributes and can't double-count.
- **Hierarchy dims**: `segment`, `segment_group` (Total Physical Cards / Digital / Corporate / Emerging Services), `is_ex_es`, `collect_sub_lob`, plus row-presence flags (`shows_in_revenue_exhibits`).
- **Version dims** (from new `DIM_FC_VERSION`): `version_code` (SEP26RF), `version_label` ("Sep FC"), `version_type` (Actual / Budget / Monthly FC / Rolling Working), `cycle_month`, `actuals_through_date`, `pfc_version_code`, `is_latest_fc`.
- **Time dims**: `period_date`, `fiscal_year`, `fiscal_quarter`, `month_name`, `af_flag` (`period_end <= actuals_through_date`), `af_transition_vs_pfc` (A→A / F→A trued-up / F→F still forecast).
- **Facts (current version)**: gross_sales, gross_to_net, net_revenue, manufacturing, royalties, autos_relics, other_product_costs, freight, mg_shortfall, obsolescence, cogs, gross_margin, marketing, contribution_margin, sga, ebitda, **adj_ebitda** (once reconciled), hedge_revenue, hedge_ebitda, fx.
- **Comparison facts pre-aligned on the same row**: `pfc_*`, `budget_*` and `py_*` for net_revenue, gross_margin, contribution_margin, marketing, sga, adj_ebitda. This gives about 25 columns and avoids self-joins for vs-PFC / vs-B / vs-PY.
- **Metrics**: one `SUM` per fact, e.g. `total_net_revenue`, `total_pfc_net_revenue`. Ratios, margins, bps and deltas are **not** metrics. They go in `custom_instructions` (`SUM(a)/NULLIF(SUM(b),0)`; bps = Δmargin × 10,000; print NM when the base ≤ 0) and in VQRs.
- **Column budget**: about 70.

### SV_FC_LICENSE_PL
On `CARDPLN_PL_BY_LEAGUE_V` (pivoted wide like the core view): version × month × LOB (NA / Intl / Digital) × league / category. Facts: net_revenue, gross_margin, contribution_margin, hedge, unhedged. Answers Q20 (Intl hedge), the GRL questions and the Digital product-group mix (Q18). Rule: GRL perimeter = Total ex-ES, so sum(license) must equal SV1 ex-ES.

### SV_FC_PRODUCT_SKU
On a view joining `GMPLN_REVENUE_FORECAST_HISTORY` (BY_CHANNEL_SKU grain only; drop GRAND_TOTAL / BY_SKU / BY_CHANNEL rows to avoid double-counting) with `GMPLN_BUDGET` as a scenario, plus COA / product attributes (product name, product-year, license, family, PFC and current street date from `FC_STREET_DATE_MASTER`). Version × month × SKU × channel. NA only, which is stated in the description. Answers Q16, Q19, and the NA part of Q18. **PY is excluded** until the PY_NETREV fix lands.

## 4. Agent instructions (key rules from the Foundation doc)
- **Routing**:
  - Segment / total / version-trend questions go to SV1.
  - License, hedge and GRL questions go to SV2.
  - SKU, channel, product release and street date questions go to SV3.
  - Reconciliation questions call SV1 + SV3.
- **Defaults**:
  - "Latest forecast" = `is_latest_fc`.
  - PFC = `pfc_version_code`.
  - "EBITDA" = Adj. EBITDA, Total incl. ES.
  - Fiscal year = calendar year.
  - Units are $M at full precision.
- **Labeling**:
  - Label every figure A or F; totals that span both are F.
  - State the comparison basis on every variance.
  - Label every EBITDA incl./excl. ES.
  - Put margin deltas in bps.
- **Traps**:
  - Product-name year ≠ street date.
  - Two meanings of "Collect".
  - NASE → NA synonym.
  - The $35M Intl→NA intercompany royalty (reported vs. adjusted).
  - Next-year quarters are preliminary.
- **Out of scope (say so, don't guess)**: Weekly Latest Outlook / LW, R&O items, FCF, headcount, GMV. None of these are in FCT_EPM. "Why" questions get quantified line-item drivers plus the caveat that narrative lives in the deck, until Phase 3.

## 5. Question coverage (20 questions)
| Status | Questions |
|---|---|
| Ready once SV1 is built (revenue ties) | 2, 3, 4, 8 (numbers), 9, 13, 14, 17 |
| Need the Adj. EBITDA / GM reconciliation | 1, 5, 6, 7, 10, 11 (EBITDA part), 12, 15 |
| Need SV3 | 16 (pre-checked, $1.8M), 19 |
| Partial | 18 (Digital via SV2 product groups; Collect only by Live vs. Marketplace, no Instant Rips split); 20 (hedge yes; FX translation not modeled, the FX line is only ~$0.6M); "why" in 7 / 8 (needs Phase 3) |

## 6. Validation
- **SQL assertion tests** (run on every version):
  - Leaf sum = CARDPLN rollups (Physical Cards, ex-ES, Collect).
  - Months sum to quarters, and quarters sum to the year.
  - Forecast-version A months = Actual.
  - GRL sum = ex-ES revenue.
  - SKU NA = segment NA within ±$2M.
  - Hedged + hedge = unhedged.
- **Deck tie-outs from Foundation Appendix A.1, A.2 and A.4** (±$1M) become VQRs. These become the `evaluate_semantic_view` suite, and several are flagged `use_as_onboarding_question`.
- Run the offline validator (`validate_semantic_model.py`) and `reflect_semantic_model` before deploying.

## 7. Open items for Finance Systems (blocking items first)
1. **Adj. EBITDA and GM bridge**: which add-backs or allocations turn `ACX_EBITDA` into deck Adj. EBITDA (FY26 gap ~$630M; Q1 26 A 144 vs. 301), and how intercompany COGS / royalty map into GM.
2. NA definition: is deck NA = NA Gross + Topps Elims for revenue (it ties), and how is the separate Eliminations EBITDA row built?
3. STG member-level rule: the canonical leaf filters for cost center, channel and intercompany.
4. Is the hedge stored at segment level, or only via league product groups?
