# `códigos/revision/` — ANPEC revision battery (2026-07-30)

Additive. **Nothing in the existing pipeline was deleted, moved or overwritten.** Every script
here sources `R00_setup.R`, which sources `00_config.R` and `_estimation_functions.R` and then
rebuilds the estimation frame of `07_regression_inference.R` verbatim — same inputs, same
universe rule, same standardisation, same `W` and `g_mat`. `H2_baseline_repro.R` asserts that
reproduction against the published Table 3 before anything else runs.

Two files outside this directory were edited, both additively, with every replaced line kept
commented immediately above its replacement and tagged `## [REV-H1]`:

- `figuras/brazil_polarization_map_2x2.R` — placeholder subtitle and source line (task H1), plus
  the portability fixes needed to make it run at all.

## Run order

```
H2_baseline_repro.R          # must pass before anything else is believed
H3_environment.R
G1_center_2018.R             # gate 1 — degenerate 2018 stack        (R3-M1)
G2_first_stage.R             # gate 2 — labour-market first stage    (R1-M5)
G3_arc_shock.R               # gate 3 — arc-% respecification        (R3-M4)
P1_ri_confidence_set.R       # bound the null by test inversion      (R1-M3)
P2_nonmonotonicity.R         # outcome curvature + directional       (R2-M1)
P3_novo_imputation.R         # symmetric NOVO imputation             (R2-M2)
P4_year_interacted.R         # year-interacted controls              (R1-M1)
P4b_wald_only.R              # corrected common-gamma Wald test
P5_stratified_ri.R           # stratified RI + distribution shape    (R1-M2)
P6_tail_sensitivity.R        # winsorise/rank + binscatter           (R1-M7)
P7_crosswalk_allocation.R    # allocation-rule sensitivity           (R3-M2)
P8_compositing.R             # by-year compositing diagnostics       (R3-M3)
P9_inference_housekeeping.R  # SE ladder, partial R2, within-SDs      (R1-m2/m3, R3-m2/m3)
```

Outputs go to `<DATA_DIR>/output/revision/<task-id>/`. The deliverable is
`<DATA_DIR>/output/revision/RESULTS_MEMO.md`.

## Run them ONE AT A TIME

`fixest` dies with a bus error or segfault inside `combine_fixef()` on long randomization loops
when several R processes compete for the machine. `R00_setup.R` pins
`setFixest_nthreads(1)` (override with `REV_NTHREADS`), which reduces but does not eliminate it.
Two P4 runs and one P5 run were lost to this.

## Two environment quirks this code works around

1. **readr cannot OVERWRITE a file** whose absolute path contains the decomposed-UTF8
   `dissertação`/`versão` segments — it normalises the path on the overwrite branch and libc
   rejects it. Creating a new file is fine, so a first run succeeds and every re-run fails.
   `R00_setup.R` masks `write_csv` with a version that unlinks first. `readr::read_csv` fails on
   the same paths in both directions; use base `read.csv` to read these outputs back.
2. **libxls cannot open `CNAE20_ISIC4.xls` from that path at all.** `G2_first_stage.R` copies the
   workbook to an ASCII temp path before reading. This means stage `03` cannot currently be
   re-run on this machine either, although its committed outputs are intact.
3. **cairo and X11 are absent**, so `cairo_pdf` and the `ragg` PNG device warn and write nothing.
   Figures use `grDevices::pdf` / `grDevices::png`, which cannot encode em-dashes in the default
   encoding — keep figure text ASCII.

## New raw artefact

`G2_first_stage.R` pulled RAIS for 2010/2014/2018/2022 from BigQuery
(`basedosdados.br_me_rais.microdados_vinculos`, billed to `GCP_BILLING`) and wrote
`<DATA_DIR>/rais_fte_panel_2010_2022.rds` (603,555 rows). The script is idempotent — it skips the
pull if that file exists — so re-running costs nothing.
