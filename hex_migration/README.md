# FC Forecast semantic layer: Hex edition

This is the Hex migration of `../collectibles_forecast` (3 Cortex Analyst models plus a Cortex Agent). The Snowflake views are unchanged; Hex models sit on top of them.

## What maps to what
| Cortex (Snowflake) | Hex | File |
|---|---|---|
| Semantic model (dimensions, time_dimensions) | Semantic model dimensions | `semantic/*.yml` |
| Facts | `internal` number dimensions (measures are the public interface) | same |
| Metrics, plus ratio/variance logic that lived in VQRs and instructions | Measures: sums, filtered (`is_latest_fc`), `_vs_pfc` / `_vs_budget` / `_vs_py`, `_pct` (x100), `_bps_vs_*` | same |
| synonyms / sample_values | A "Synonyms:" / "Values:" line in descriptions (Hex has no such keys) | same |
| `module_custom_instructions` | One guide per model | `guides/fc-segment-pl.md`, `fc-license-revenue.md`, `fc-na-sku-product.md` |
| Agent orchestration + response instructions | Cross-model routing, version and labeling guide | `guides/fc-forecast-analyst.md` |
| verified_queries | Eval suites (`judge_final_answer` + `expectedSql`, which stays data-driven) | `evals/*.evals.yaml` |
| `03_assertions.sql` | Unchanged; keep running it in Snowflake | `../collectibles_forecast/sql/` |

Models: `fc_segment_pl` (94 dims / 135 measures), `fc_license_revenue` (22 / 8) and `fc_product_sku` (35 / 18).

## Load into Hex (phase 1: edit in the app)
1. Make sure the Hex Snowflake connection's role can `SELECT` from `ORACLE_DATA_PROD.SANDBOX.FC_SEGMENT_PL_V`, `FC_LICENSE_REVENUE_V` and `FC_PRODUCT_SKU_V`. Today only `CYERA_ROLE` and `SC_R_SANDBOX` have it. `CREATE OR REPLACE VIEW` drops direct grants until the nightly re-grant runs.
2. Open your semantic project in the Modeling Workbench. Add one file per `semantic/*.yml` and paste the contents in. Check that inline validation is clean, then publish (the preview has Explore and Threads tabs).
3. In Context Studio > Guides, add the 4 files in `guides/` (frontmatter included).
4. Endorse the 3 models so agents prefer them.
5. Let the Hex Modeling Agent refine the models. Good first asks:
   - trim `fc_segment_pl`'s 135 measures to the ones people use;
   - add curated `view`s;
   - tune descriptions using real Threads questions.
6. Run the eval suites from the Hex UI, or with `hex eval run` from WSL or Linux. Replace `<HEX_DATA_CONNECTION_ID>` first.

## Phase 2: git as the source of truth
When the models are stable, export the refined YAML back here and fill in `hex_context.config.yaml`. Then sync with `hex context preview` / `publish`, or the `hex-inc/action-context-toolkit@v2` GitHub Action. After that, edit only in git: synced resources are read-only in Hex. The Hex CLI doesn't run on Windows, so use WSL or CI.

## Validate locally before pasting or syncing
```
python scripts/validate_hex.py semantic/*.yml     # JSON Schema + refs + compiles every expr in Snowflake (snow CLI)
python scripts/check_context_files.py .           # guides frontmatter + eval structure
```

## Known gaps vs Cortex
- Hex can't force a filter on a model. "One version and one fiscal year" is only guidance, plus the version-pinned `latest_fc_*` measures.
- Two things live in guides only, because neither can be a single measure: named-cycle comparisons (filter to 2 `version_code`s and pivot by `version_label`) and the NA BU NASE/GCP/total ROLLUP layout.
- The license and SKU cubes can lag the segment P&L by a cycle (currently Sep vs Oct 2026 FC). The guides say to state this, not hide it.
- Eval SQL hard-codes `fiscal_year = 2026` where the question says "FY26". Update it at year end.
- The views live in `SANDBOX`. Before wide rollout, promote them to a governed schema and repoint `base_sql_table`.
