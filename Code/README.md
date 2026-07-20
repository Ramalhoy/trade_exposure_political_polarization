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

## Run order

| # | Script | Stage | Reads | Writes (key) |
|---|--------|-------|-------|--------------|
| 01 | `01_extraction.R` | extraction | BigQuery (RAIS, Comex), TSE, IBGE API | `rais_fte.rds`, `rais_2010_micro.rds`, `exports_national_ncm.rds`, `imports_national_ncm.rds`, `municipios_ibge.rds`, `painel_votos_{presidenciais,governador}_…rds` |
| 02 | `02_polarization_indices.R` | index build | `painel_votos_*`, `bls9_…rds` | `dalton_panel_presidencial.rds`, `dalton_panel_governador.rds`, `polarizacao_agregada_*` |
| 03 | `03_epw_construction.R` | index build | `exports_national_ncm.rds`, `rais_fte.rds`, `CNAE20_ISIC4.xls`, `un_hs2012_isic4_weighted.csv` | `epw_panel_isic_v7.rds`, `exposure_shares_isic_v7.rds`, `sectoral_shocks_isic_v7.rds`, `rais_isic_v7.rds`, `tradable_emp_share_2010_v7.rds` |
| 04 | `04_controls.R` | index build | Sidra, BigQuery PIB, `municipios_ibge.rds`, `exposure_shares_isic_v7.rds` | `controls_micro.rds` |
| 05 | `05_centroids.R` | index build | geobr (IBGE 2010 shapefile) | `micro_centroids.rds` |
| 06 | `06_panel_consolidation.R` | panel | `epw_panel_isic_v7.rds`, `dalton_panel_presidencial.rds`, `controls_micro.rds` | `df_estimation_v7.rds`, `df_raw_v7.rds` |
| 07 | `07_regression_inference.R` | regression | `df_estimation_v7.rds`, `exposure_shares_isic_v7.rds`, `sectoral_shocks_isic_v7.rds`, `epw_panel_isic_v7.rds`, `micro_centroids.rds` | `tables/`, `figures/`, `output/` |

Dependency notes: 03 must run before 04 (manuf_share); 02, 03, 05 are otherwise
independent; 06 needs 02+03+04; 07 needs 03+05+06.

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
- **Governor track is built but unused.** Stage 02 produces `dalton_panel_governador.rds`;
  nothing downstream consumes it. Either wire a governor robustness panel or drop the branch.
- **Scattered data cruft** in `versão com vínculos totais/` and `dados consolidados/`:
  many stale versions (`df_estimation.rds`, `_v5`, `_TEST`; `epw_panel_isic{,2,_v5}`;
  `exposure_shares_isic{,2,_v5}`; ` 2.rds` duplicates). Safe to archive/remove *after*
  confirming a clean v7 run — left untouched here since it's data, not code.
- **`códigos/un_hs2012_isic4_weighted.csv`** is a redundant copy of the one already in
  `DATA_DIR`; the pipeline reads the `DATA_DIR` copy. Removable.
