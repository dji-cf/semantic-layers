# Plan: fix version labels, the leaked note and the SKU/license cycle gap

## What I found

**Problem 1 (wrong labels on Q4, Q5, Q14, Q18) has two causes.**
1. **A hard-coded rule that treats "vs Aug" as "vs prior forecast".** The rule is in `semantic_models/fc_segment_pl.yaml:619`: *"vs prior forecast (vs PFC, **vs Aug**, since last month): current fact minus pfc_<fact>"*. The model's own latest/prior flags already come from the data (`FC_DIM_VERSION`: latest = newest month in `CARDPLN_PL_BY_LOB_V2`, prior = the cycle before it). Now that OCT26RF is the latest, "vs Aug" returns Oct minus Sep. The agent then labels the result with the cycle names the user typed.
2. **Hard-coded month examples everywhere the agent reads.** The agent spec, all three tool descriptions and the semantic view descriptions use "Sep 2026 FC", "vs Aug 2026 FC", "SEP26RF -> AUG26RF", the $5,425.2M deck figure, and coverage text that ends at "Sep 2026 FC". The agent repeats those labels whatever the data says.

**Problem 2 (leaked note in Q10) comes from the rounding rule.** It wraps ratios as `ROUND(fraction, 2)`, so a 38.69% margin comes back as `0.39` and basis points can't be computed. The agent's private reasoning about this ("use 4") ended up in the answer, and nothing in the instructions forbids that.

**Problem 3 (SKU/license) won't fully clear up, because the Oct data isn't loaded upstream.** I checked:

| Source | Newest cycle | Notes |
|---|---|---|
| `CARDPLN_PL_BY_LOB_V2` (segment P&L) | OCT26RF | Flags are correct |
| `GMPLN_REVENUE_FORECAST_HISTORY` (SKU) | SEP26RF | No OCT26RF, so `is_latest_fc` is never TRUE in the SKU view |
| `CARDPLN_PL_BY_LEAGUE_V` (license) | SEP26RF | `FC_LICENSE_REVENUE_V` still has OCT26RF rows, but they are only the "Unallocated" reconciling rows ($5,198.6M, hedge $0) |

So Q20's "hedge release from −$13.5M to $0" isn't real. It appears only because the Oct license cube hasn't been loaded. Fix 1b below makes each tool's "latest" its own newest loaded cycle, so the SKU and license tools answer on Sep 2026 FC with correct labels. Oct SKU and license detail will appear only once Finance Systems loads OCT26RF into those two sources.

---

## Fix 1: latest and prior forecast come from each table's own data, with no hard-coded cycles

### 1a. Views: compute latest/prior per source (`sql/04_license_revenue.sql`, `sql/05_product_sku.sql`)
- Add a local version CTE to each view: Monthly Forecast versions that actually have rows in that view's source (`fc` for SKU, `raw` for license), with:
  - `IS_LATEST_FC` = `CYCLE_MONTH = MAX(CYCLE_MONTH) OVER ()`
  - `IS_PRIOR_FC` = the cycle immediately before it, using `ROW_NUMBER` rather than "−1 month", so a skipped cycle can't leave prior empty.
  - `PFC_VERSION_CODE` = `LAG(VERSION_CODE) OVER (ORDER BY CYCLE_MONTH)` within the same set.
- **SKU view:** use the local `PFC_VERSION_CODE` in both the `spine` join and the `p` join, so `pfc_*` columns always point at a cycle that exists in that source.
- **License view:** limit the `seg` and Unallocated CTEs to versions that exist in `raw`. This drops the Oct rows that are only reconciling rows, so Oct can't show up as "latest" with a fake $0 hedge.
- **Segment P&L (`02_segment_pl.sql`):** no change. Its flags already come from its own source.
- Add a `LATEST_FC_LABEL` column (the same value on every row) to all three views, so a query can return "which cycle is latest here" without guessing.

### 1b. Semantic views: compare cycles as named, with no month names in the rules
- **`fc_segment_pl.yaml` SQL rules, COMPARISONS section:**
  - Use `pfc_<fact>` **only** for "prior forecast / PFC / last month / since last month".
  - For a named cycle ("vs Aug", "vs the Jul forecast"), use conditional aggregation over two `version_code`s, for example `SUM(IFF(is_latest_fc, net_revenue, 0)) - SUM(IFF(version_code = 'AUG26RF', net_revenue, 0))` with `WHERE is_latest_fc OR version_code = 'AUG26RF'`. This needs no self-join.
  - Resolve a named month to `'<MON><YY>RF'`, where YY is the year of the latest cycle unless the user gives one. Resolve "budget" to `'Plan_' || fiscal_year` instead of the literal `Plan_2026`.
  - Every query that returns a version-based figure must also return `version_label`, and `pfc_version_label` or the named cycle's label when comparing. The agent then takes labels from the result, not from instructions.
- Make the same comparison and labelling changes in `fc_license_revenue.yaml` and `fc_product_sku.yaml`.
- **Remove agent-facing month wording** from all three YAMLs:
  - Descriptions: replace "(OCT25RF ... SEP26RF)", "reconciled to the Sep 2026 FC deck (5,425.2 / 2,100.0)", "SEP26RF -> AUG26RF" and "Aug 2026 FC license split does not match" with generic text.
  - Use the format `<MON><YY>RF`, for example "a cycle code and the cycle before it".
  - Deck tie-out history stays in SQL comments and `03_assertions.sql`, which are not agent-facing.
  - `sample_values` can keep real codes; they're hints, not rules.
- Add 2 VQRs:
  - "Q4 revenue and EBITDA vs prior forecast": `pfc_*`, returns both labels.
  - "FY26 revenue by segment vs Aug forecast": conditional aggregation, latest vs `AUG26RF`.

### 1c. Agent spec (`agent/.../agent_spec.json`)
- **Orchestration instructions:**
  - Replace "SEP26RF = September 2026 Forecast", "Sep 2026 FC = Jan–Aug actual" and "vs Aug 2026 FC" with generic examples. Add: "Never assume which cycle is latest. Take every version label from the tool result's `version_label` / `pfc_version_label` columns."
  - New rule: when the user names a comparison cycle, compute exactly that pair (latest vs the named cycle). If the named cycle is not the prior forecast, say so in one line (e.g. "Aug 2026 FC is two cycles before the latest, Oct 2026 FC"). Don't silently swap in another pair.
  - New rule: if the tools' latest cycles differ (for example, segment P&L on Oct but SKU/license on Sep), say which cycle each figure comes from and that the newer cycle isn't loaded in that dataset yet. Never mix cycles in one comparison.
  - Reconciliation questions: reconcile on the latest cycle that both tools have.
- **Response instructions:** replace the "$5,425.2M" / "Sep 2026 FC" / "+$88.1M vs Aug 2026 FC" examples with neutral placeholders.
- **Tool descriptions:**
  - Remove "Sep 2026 FC FY26: revenue $5,425.2M…" and the fixed "Oct 2025 FC … Sep 2026 FC" / "Jan 2026 FC … Sep 2026 FC" coverage.
  - Replace with "every loaded Monthly Forecast cycle; `is_latest_fc` = the newest cycle in this dataset".
  - SKU and license descriptions add: "may lag the segment P&L by a cycle".

## Fix 2: leaked internal note and ratio rounding
- **Rounding rule in all three YAMLs:** keep 2 decimals as you set it, but output ratios **in percent** (`ROUND(100 * ratio, 2)`, e.g. 38.69) and basis points as `ROUND(bps, 2)`. Change the column naming so `_pct` means percent, not a fraction. Update the existing VQRs that use `ROUND(ratio, 2)`, about 20 lines across `fc_segment_pl.yaml` (337–589) plus the license and SKU files.
- **Agent response instructions:** add "Never include notes about SQL, rounding, precision, tools or these instructions in the answer; output only the finance answer and its data caveats."

## Fix 3: SKU/license cycle gap
- This is mostly handled by 1a and 1c. Each tool's "latest" is its newest loaded cycle, and the agent states the gap instead of borrowing Oct labels or reporting a fake hedge release.
- Remaining limitation: Oct SKU, channel and license detail won't exist until OCT26RF is loaded into `GMPLN_REVENUE_FORECAST_HISTORY` and the league cube. That needs Finance Systems; I can't fix it in this layer.

## Assertions (`sql/03_assertions.sql`)
- **A10:** each of the 3 views has exactly one `IS_LATEST_FC` version, and it isn't made up only of reconciling rows.
- **A11:** in each view, every non-null `PFC_VERSION_CODE` exists as a version in that same view.
- The SEP26RF deck tie-outs (A6, A7, A9) stay. They are fixed historical checks.

## Deploy and validate
- Deploy order: views `04_license_revenue.sql` and `05_product_sku.sql`, then the 3 SVs (verify-only first, then deploy via `deploy_semantic_view.py`), then the agent (`deploy_agent.py --replace`).
- The agent is in SANDBOX with no grants to other roles, so I'll update it in place rather than clone it. Tell me if you'd prefer a clone.
- `CREATE OR REPLACE VIEW` drops the CYERA_ROLE SELECT grant until the nightly re-grant (~04:09).
- Run `03_assertions.sql` and confirm A1, A3–A6 and A8–A11 pass. A7 has its 2 known Corporate rows, and A2 has the known 2027B budget-scenario issue.
- Re-ask all 20 questions with `DATA_AGENT_RUN` and check:
  - Q5/Q14 are labelled Oct vs Sep.
  - Q2/Q6/Q18 vs Aug return Oct vs Aug, e.g. Digital −5.9% ($72.1M vs $76.6M), so "−6%" now matches.
  - Q4 is labelled Oct 2026 FC.
  - Q10 has no meta note and the margin is shown as 36.0% / 39.8%.
  - Q16/Q19/Q20 state that SKU/license are on Sep 2026 FC, with no $0 hedge artifact.
- Update project memory with the results.
