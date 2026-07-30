# Códigos — trade exposure & political polarization pipeline

Reorganized from a sparse set of session-versioned scripts into one linear,
deduplicated pipeline. Every script sources **`_config.R`** first, which sets the
single canonical working directory and shared constants — no script sets its own
path anymore.

## Canonical data directory

```
…/data/dados consolidados/versão com vínculos totais/
```

All inputs are read from and all outputs are written to this one folder
(`_config.R` → `DATA_DIR`). Raw extraction (stage 01) now writes here too, so
data no longer scatters across sibling folders.

## `SHARE_DENOM` — the exposure-share normalisation

`_config.R` defines one flag that governs how the Bartik shares
`s_rj = L_rj,2010 / D_r,2010` are normalised:

| Value | Denominator `D_r` | `Σ_j s_rj` | Status |
|---|---|---|---|
| `"tradable"` *(default)* | tradable employment in the numerator set | `1` | reproduces the ANPEC tables bit-for-bit |
| `"total"` | **total** formal employment, all sectors | `θ_r` | ADH/Rettl convention; the correct one |

The two differ by a region-specific **multiplicative** rescaling
`s_total = θ_r · s_tradable`, so adding `θ_r` as an *additive* control does
**not** convert one into the other — the identity is asserted at construction
in `03` and `03a`.

**Flipping this to `"total"` moves the treatment** (`cor = 0.933`, rank
`0.927`). Rotemberg weights, the effective-shock count (the "≈2.4" quoted
throughout the paper), balance tests, AKM/AKM0 and Conley are all functions of
the shares and must be **recomputed, not carried over**. Re-run in order:
`03 → 03a → 03b → 03c → 03d → 04 → 06/06b → 07/07b`. Saved artefacts are
stamped with the convention that built them, and `03a` stops on a mixed-vintage
build.

## Estimation-universe rule

A microregion with **zero base-year tradable employment** is **dropped**: its
composition across tradables is `0/0` — undefined, not zero — and it carries no
exposure share. As of v7 this is exactly one unit, `13002` (Médio Amazonas, AM).
The rule is imposed **once**, in `06`/`06b`; `07`, `07b` and `03c` *assert* it
rather than re-imposing it, so the diagnostics and the coefficients they
diagnose cannot drift onto different samples. Result: panel = 1,671 rows / 557
micros, regressions `N = 1,668` after the three Distrito Federal state×year
singletons are absorbed. This matches `main_anpec.tex`.

## Run order

| # | Script | Stage | Reads | Writes (key) |
|---|--------|-------|-------|--------------|
| 01 | `01_extraction.R` | extraction | BigQuery (RAIS, Comex), TSE, IBGE API | `rais_fte.rds`, `rais_2010_micro.rds`, `exports_national_ncm.rds`, `imports_national_ncm.rds`, `municipios_ibge.rds`, `painel_votos_{presidenciais,governador}_…rds` |
| 02 | `02_polarization_indices.R` | index build | `painel_votos_*`, `bls9_…rds` | `dalton_panel_presidencial.rds`, `dalton_panel_governador.rds`, `polarizacao_agregada_*` |
| 03 | `03_epw_construction.R` | index build | `exports_national_ncm.rds`, `rais_fte.rds`, `CNAE20_ISIC4.xls`, `un_hs2012_isic4_weighted.csv` | `epw_panel_isic_v7.rds`, `exposure_shares_isic_v7.rds`, `sectoral_shocks_isic_v7.rds`, `rais_isic_v7.rds`, `tradable_emp_share_2010_v7.rds`, `share_sum_theta_v9.rds`, **`ncm_isic_match_v7.rds`, `composite_map_v7.rds`** |
| 03a | `03a_shares_common.R` | index build | `rais_fte.rds`, `CNAE20_ISIC4.xls`, `ncm_isic_match_v7.rds`, `composite_map_v7.rds`, `sectoral_shocks_isic_v7.rds`, `epw_panel_isic_v7.rds` | `exposure_shares_common_v8.rds`, `share_sum_theta_common_v9.rds`, `rais_isic_full_tradable_v8.rds`, `epw_common_panel_v8.rds` |
| 03b | `03b_instrument_construction.R` | index build | BACI HS07, `ncm_isic_match_v7.rds`, `composite_map_v7.rds`, `rais_isic_v7.rds`, `exposure_shares_isic_v7.rds` | `epw_iv_panel_v1.rds`, `sectoral_demand_iv_v1.rds` |
| 03c | `03c_shock_exogeneity.R` | index build | `df_estimation_v7.rds`, `exposure_shares_isic_v7.rds`, `sectoral_shocks_isic_v7.rds` | `shock_exogeneity_results_v1.rds`, `output/03c_*` |
| 03d | `03d_ipw_construction.R` | index build | `imports_national_ncm.rds`, `ncm_isic_match_v7.rds`, `composite_map_v7.rds`, `exposure_shares_common_v8.rds`, `rais_isic_full_tradable_v8.rds`, BACI HS07 | `ipw_panel_isic_v1.rds`, `sectoral_import_shocks_v1.rds`, `ipw_iv_panel_v1.rds`, `output/ipw_rotemberg_comparison.csv` |
| 04 | `04_controls.R` | index build | Sidra, BigQuery PIB, `municipios_ibge.rds`, `exposure_shares_isic_v7.rds` | `controls_micro.rds` |
| 05 | `05_centroids.R` | index build | geobr (IBGE 2010 shapefile) | `micro_centroids.rds` |
| 06 | `06_panel_consolidation.R` | panel | `epw_panel_isic_v7.rds`, `dalton_panel_presidencial.rds`, `controls_micro.rds` | `df_estimation_v7.rds`, `df_raw_v7.rds` |
| 06b | `06b_panel_governador.R` | panel | `dalton_panel_governador.rds`, `painel_ideologico_governador.rds`, `epw_common_panel_v8.rds`, `ipw_panel_isic_v1.rds`, `controls_micro.rds` | `df_estimation_gov_v1.rds`, `governor_coverage_stateyear.rds` |
| 07 | `07_regression_inference.R` | regression | `df_estimation_v7.rds`, `exposure_shares_isic_v7.rds`, `sectoral_shocks_isic_v7.rds`, `epw_panel_isic_v7.rds`, `micro_centroids.rds`, `ipw_panel_isic_v1.rds`, `epw_common_panel_v8.rds` | `tables/`, `figures/`, `output/` |
| 07b | `07b_regression_governador.R` | regression | `df_estimation_gov_v1.rds`, `exposure_shares_common_v8.rds`, `sectoral_shocks_isic_v7.rds`, `sectoral_import_shocks_v1.rds`, `epw_common_panel_v8.rds`, `micro_centroids.rds` | `tables/tab_governor_*`, `output/07b_*` |

### Reporting stages (presidential × export track)

| # | Script | Purpose | Writes |
|---|--------|---------|--------|
| 08 | `08_report_presidential_exports.R` | Descriptives → full inference regime, **both** control sets, RI extended to the boom coefficient and to the extended-control decomposition, plus 2SLS on the `03b` instruments (which `03b` builds but never estimates). ~17 min, almost all RI. | `output/report_pres_exports/*.csv`, `output/08_report_log.txt` |
| 09 | `09_center_index_diagnostic.R` | Quantifies the centre-band degeneracy of `P_center` and whether the result survives conditioning on the 2010 baseline. | `output/report_pres_exports/J*.csv` |
| 10 | `10_report_tables_tex.R` | Renders 08+09 CSVs into `\input{}`-ready LaTeX. | `tables/rep_tab1..6*.tex` |

Narrative report: `REPORT_presidential_exports_2026-07-25.md`.

**Note on `paths`:** `03_epw_construction.R` defines its own local `paths` list,
which **shadows** the one in `00_config.R`. Any new key that `03` needs must be
added there too, not only to the config.

`_estimation_functions.R` — shared shift-share estimation/inference library
(share matrix, shock matrix, RI with joint multi-shock permutation, Rotemberg,
AKM/AKM0, asymmetric decomposition, and `ss_bhj_control()`); sourced by `07`,
`07b`, `06b` and `03d`.

`ss_bhj_control(numerator)` exists because `Σ_j s_rj` equals *(employment in the
numerator set) / D_r*, and the pipeline uses **two** numerator sets —
export-bilateral (`03`) and full-tradable (`03a`). A single precomputed file is
the right control for only one of them, so scripts built on the common shares
(`03d`, `06b`/`07b`) must ask for `"common"`. Under `SHARE_DENOM="tradable"` the
realized sum is identically 1 and hence degenerate, so the helper falls back to
the tradable-intensity variable — which is what every table to date reports.

Dependency notes: 03 must run before 04 (manuf_share) and before 03a/03b/03d
(they read the persisted match table + composite map); 03a before 03d/06b/07b
(common shares); 03d before the joint block in 07, before 06b/07b (IPW);
02, 03, 05 are otherwise independent; 06 needs 02+03+04; 07 needs 03+05+06
(+03a/03d for the joint block); 06b needs 02+03a+03d+04; 07b needs 03a+03d+06b.

## External inputs (not produced by the pipeline)

These must sit in `DATA_DIR` before running:

- `bls9_estimates_partiespresidents_long.rds` — BLS party/president ideology scores (stage 02)
- `CNAE20_ISIC4.xls` — IBGE CONCLA CNAE 2.0 × ISIC rev.4 crosswalk (stage 03)
- `un_hs2012_isic4_weighted.csv` — UN HS6→ISIC4 occurrence-share weights (stage 03)
- *(optional)* `hs2007_hs2012.csv`, `hs2017_hs2012.csv`, `hs2022_hs2012.csv` — HS-vintage bridges (stage 03)
- *(optional)* `un_hs2012_isic4_tradable.csv` — only if `WEIGHT_SCHEME="uniform"` in stage 03

## What changed in the reorg

- **Deduplicated to newest version of each stage.** Superseded scripts moved to
  `_archive/` (nothing deleted): EPW v4 → v7; April ideology → the function-based
  revision; SFD v1/v2 + `02_estimation_inference` + `03_robustness` → `regressao_SFD_v3`.
  `_archive/` also holds byte-for-byte copies of the current scripts as they were
  before renaming/editing.
- **Two stale-path bugs fixed** (see below).
- **Data consolidated:** `bls9_…`, `painel_votos_presidenciais_…`, and the current
  `dalton_panel_presidencial.rds` were copied into `DATA_DIR` (they had been left in
  `dados consolidados/` and `dados consolidados/índices corrigidos 13.07/`).

### Bugs fixed during the reorg

1. **`06_panel_consolidation.R`** read `dalton_panel.rds` — the un-suffixed output
   of the *old April* ideology script. The current stage 02 writes
   `dalton_panel_presidencial.rds`. → now reads the presidential panel.
2. **`04_controls.R`** built `manuf_share` from `exposure_shares_isic.rds` (the
   *v4* industry universe, 176 industries) while everything else is v7. → now reads
   `exposure_shares_isic_v7.rds`, so the manufacturing control lives on the same
   industry universe as the treatment.

## Open flags / suggestions (not yet acted on)

- **`regressao_SFD_v3` may not carry every robustness check** from the archived
  `02_estimation_inference.R` / `03_robustness.R`. v3 has: baseline OLS, Conley,
  AKM/AKM0, design-based RI (pooled + bust), Rotemberg, BHJ balance, asymmetric
  decomposition, winsorized. The archived pair additionally had **pre-trend controls
  (top-4 export shares × year)**, **drop-top-1%-Rotemberg re-estimation**, and
  **heterogeneity interactions (commodity vs. manufacturing; agricultural export
  composition)**. If the dissertation text references those, port them into 07.
- ~~**Governor track is built but unused.**~~ **DONE** — wired end-to-end via
  `06b_panel_governador.R` + `07b_regression_governador.R`. Ideology coverage is
  now computed per state-year (`governor_coverage_stateyear.rds`), carried into
  the panel, and used for a sample-rule threshold sweep; a big-party (national-
  line) Dalton robustness is included. Headline caveat: **~50% of state-years
  fall below 0.85 ideology coverage** (worst in 2014/2022), so the coverage
  sensitivity is not optional.
- **Scattered data cruft** in `versão com vínculos totais/` and `dados consolidados/`:
  many stale versions (`df_estimation.rds`, `_v5`, `_TEST`; `epw_panel_isic{,2,_v5}`;
  `exposure_shares_isic{,2,_v5}`; ` 2.rds` duplicates). Safe to archive/remove *after*
  confirming a clean v7 run — left untouched here since it's data, not code.
- **`códigos/un_hs2012_isic4_weighted.csv`** is a redundant copy of the one already in
  `DATA_DIR`; the pipeline reads the `DATA_DIR` copy. Removable.
