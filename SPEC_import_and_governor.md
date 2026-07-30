# Build spec — Import-competition treatment + Governor track

**For:** Claude Code, working in `data/códigos/` on the trade-exposure/polarization pipeline.
**Read first:** `README.md`, `_config.R`, `03_epw_construction.R`, `07_regression_inference.R`,
`Dissertation_Code_Assessment_V1.md`, and the logs `output/03b_iv_run_log.txt`,
`output/03c_exogeneity_log.txt`.

---

## 0. Why this work is being done (context that changes design choices)

The exogeneity battery (`03c`) established that the **export** treatment has an
**effective number of shocks of ≈ 2.4** (1/HHI of |Rotemberg α|). Iron ore (ISIC 0710)
carries α ≈ 0.61 (2014) and 0.59 (2018); oil & gas (0610) carries α ≈ 0.66 in 2022.
Cluster SEs over-reject at ~7× nominal (placebo rejection 0.357 vs 0.05). The baseline
OLS is null, and that null is **uninformative** — the design lacks power, it does not
demonstrate absence of an effect.

Therefore the import side is **not** being added for completeness. It is being added
because import competition plausibly spreads identifying variation across dozens of
mid-sized manufacturing industries in many regions, which should raise the effective
shock count substantially. **The headline diagnostic for Part A is the Rotemberg
concentration of the import treatment compared with the export treatment.** Report it
prominently even if the coefficient is null.

Two invariants for all new code:

- Every new script sources `_config.R` first and writes to `DATA_DIR`. No `setwd()`.
- Preserve the existing assert culture: economic identities encoded as `stopifnot()`,
  a `sink()` run log in `output/`, `sessionInfo()` at the end.

---

## PART 0 (do this first) — Shared share-denominator refactor

**Problem.** In `03_epw_construction.R` STEP 6, the universe is
`isic_bilateral = intersect(exports_isic$isic4, rais_isic$isic4)`, and STEP 8 computes
`s_rj` **after** that restriction — so shares sum to 1 over the *export*-bilateral
industry set. An import treatment built on its own `intersect(imports, rais)` set would
have shares summing to 1 over a *different* denominator, making EPW and IPW
non-commensurable and their sum meaningless.

**Fix.** Create `03a_shares_common.R` (or extend `03`) that computes exposure shares
**once, over the full tradable RAIS universe**:

```
s_rj = L_rj,2010 / L_r,2010      where L_r,2010 = sum over ALL tradable ISIC in RAIS
```

Save as `exposure_shares_common_v8.rds`. Each treatment then uses its own shock vector
with **explicit zeros** for industries outside its own bilateral set. Nothing else about
the crosswalk changes.

**Mandatory regression guard.** Rebuild EPW under the common shares and assert
`cor(EPW_common, EPW_v7) > 0.99` by year, and report mean/sd side by side. If the
correlation is materially below that, STOP and report — the denominator change has moved
the treatment and every `03c` result would need re-running.

**Also do the two-line fix in `03`** flagged in the assessment:
`saveRDS(ncm_isic_v6, "ncm_isic_match_v7.rds")` and
`saveRDS(composite_map, "composite_map_v7.rds")`, then replace the replayed STEP 1 of
`03b_instrument_construction.R` with `readRDS` calls. The composite map is derived from
the **product-code signature**, not from export values, so it is source-independent and
reusable for imports as-is.

---

## PART A — Import-competition treatment (`03d_ipw_construction.R`)

### A.1 Treatment definition

Mirror the export construction exactly:

```
IPW_rt = Σ_j s_rj · m_jt ,   m_jt = (IMP_jt − IMP_j,2010) / L_j,2010
```

Input `imports_national_ncm.rds` (already produced by `01_extraction.R`, currently unused;
columns `ano`, `id_ncm`, `valor_fob_dolar`, 2010–2022).

**Reuse, do not reimplement**, this exact sequence from `03`:
special-regime removal (HS ch. 97–99 only), CPI deflation to constant 2010 USD with
`USD_UNIT = 1e4`, NCM8→NCM6 aggregation, the saved `ncm_isic_match_v7.rds`
(producer-primacy, restrict-then-renormalize), the `[F-2]` manual-residual hook,
`composite_map_v7.rds` `[E-1]`, election-year filter **before** `complete()` `[F-1]`,
and explicit-zero grid completion before differencing `[B-1]`.
Add the `[F-3]` conservation asserts.

Universe: `isic_bilateral_imp = intersect(imports_isic, rais_isic)`; report its size and
its overlap with the export universe (152 industries). Shares come from Part 0.

### A.2 Required variants

1. **`IPW_total`** — all imports (headline).
2. **`IPW_final` / `IPW_interm` / `IPW_capital`** — split by UN **BEC** end-use
   (map HS6→BEC; the R `concordance` package ships BEC correspondences).
   This split matters theoretically: final-goods imports are the ADH *competition*
   channel (job displacement), while intermediate/capital imports are an *input-cost*
   channel that can raise local employment. Pooling them attenuates both. If the BEC
   mapping proves messy, at minimum flag consumer-goods chapters and report the split
   as heterogeneity rather than blocking on it.
3. **`IPW_china`** — imports sourced from China only, requiring a re-pull of Comex with
   `id_pais` (add a BLOCK B2 to `01_extraction.R`; keep it idempotent and cached).

### A.3 Instrument (ADH transposition)

`z^IMP_jt` = growth of **other middle-income countries'** imports from China in industry j,
per Brazilian worker, excluding Brazil throughout. Build from the **BACI HS07 files
already downloaded** for `03b` — same four election years, same orphans-only
HS2007→HS2012 bridge, same crosswalk.

Comparison set (make it a flag): Argentina, Chile, Colombia, Mexico, Peru, South Africa,
Turkey, Indonesia, Malaysia, Thailand. Report the first stage both pooled and **by year**
(the `03b` log showed a sign-flipping first stage for the China export instrument in 2014 —
check for the same pathology here before trusting any pooled F).

### A.4 Diagnostics — this is the point of the exercise

- Rotemberg weights for IPW by year; `eff_n = 1/HHI(|α|)`; top-10 industries.
  **Print an explicit comparison table against the export side's eff_n ≈ 2.4.**
- AKM placebo rejection rate at 5% for the import treatment (reuse the `03c` routine).
- Correlation between `EPW_rt` and `IPW_rt` by year — if strongly negative, the export-only
  specification was omitting a correlated regressor, which is the exclusion-restriction
  argument from the assessment.
- **Scaling sensitivity (do this for both treatments):** recompute Rotemberg weights using
  growth-rate shocks (Δln, or a Davis–Haltiwanger arc change robust to zeros) instead of
  per-worker levels. Mining is capital-intensive, so per-worker scaling mechanically
  inflates extraction-sector shocks and may be *manufacturing* the concentration. Report
  how much `eff_n` recovers under each scaling.

### A.5 Estimation additions to `07`

- Joint specification: `ΔP ~ EPW⁺ + EPW⁻ + IPW (+ controls) | state^year`.
- Net exposure `EPW − IPW` as an alternative single treatment.
- Asymmetric decomposition applied to IPW as well.
- Extend the RI regime to permute **both** shock vectors jointly (preserving each
  industry's shock path across years, as the existing `make_epw_star()` does).
- Report AKM/AKM0 alongside; AKM0 is the weak-identification-robust complement.

**Outputs:** `ipw_panel_isic_v1.rds`, `sectoral_import_shocks_v1.rds`,
`ipw_iv_panel_v1.rds`, `output/03d_ipw_run_log.txt`,
`output/ipw_rotemberg_comparison.csv`.

---

## PART B — Governor track (`06b_panel_governador.R`, `07b_regression_governador.R`)

`02_polarization_indices.R` already produces `dalton_panel_governador.rds` and
`painel_ideologico_governador.rds`; nothing downstream consumes them. Complete the branch
or delete it — the README has flagged this for months.

### B.1 Measurement issues that must be handled before estimation

These are more severe than on the presidential side. Do not skip them.

1. **Ideology coverage.** `02`'s `diagnostico_na()` already prints the share of votes cast
   for parties with no BLS score, by year. State races carry many more small parties.
   Extract that number **per state-year**, save it, and (a) report it in the appendix,
   (b) add a sample rule — e.g. drop state-years with coverage below 80–85% — and
   (c) show sensitivity to the threshold. Currently the coverage rate is computed and
   then thrown away.
2. **National party scores applied to state candidates.** BLS scores measure *national*
   party positions. Governor candidates from regional machines deviate from the national
   line far more than presidential candidates do. Treat this as the headline measurement
   caveat in the text, and consider a robustness that restricts to the ~6–8 largest
   national parties.
3. **Coalitions.** Governor races are coalition-dense; if the TSE data attributes votes to
   the candidate's own party (`SG_PARTIDO`), that is the right choice — verify it and
   state it explicitly.
4. **Common candidate menu within state-year.** Every microregion in a state faces the
   *same* candidate set, so `P_dalton` varies within state only through vote-share
   allocation, not through the ideological menu. This is fine — it is exactly the
   variation `state^year` FE leave behind — but it means the governor outcome measures
   *voter dispersion given a fixed menu*, whereas the presidential outcome mixes menu and
   allocation. Say so in the text; it is a genuine interpretive difference, and arguably
   a **cleaner** test of voter-side polarization.
5. **Round filter.** Keep `round == 1` (already done in `02`); second rounds exist in some
   states and would break comparability.
6. **Distrito Federal** elects a governor and has a single microregion, so it remains a
   `state^year` singleton and will be dropped by `feols` — same as the presidential track.
   Assert the estimation N explicitly rather than discovering it.

### B.2 Panel + estimation

`06b` mirrors `06_panel_consolidation.R` with `dalton_panel_governador.rds` as the outcome
source, joining the same EPW/IPW treatments, the same `controls_micro.rds`, the same 2010
baseline differencing. Keep the `_gov` suffix on every output.

`07b` mirrors `07_regression_inference.R`: same control sets, same `state^year` FE, same
four-regime inference (RI primary, AKM/AKM0 secondary, Conley + meso×year cluster
reference), same asymmetric boom/bust decomposition, same Rotemberg and balance
diagnostics. Factor the shared estimation code into `_estimation_functions.R` and have
both `07` and `07b` call it rather than duplicating ~400 lines — the two scripts will
otherwise drift, exactly as the v4/v7 files did.

### B.3 What the governor track buys scientifically

- A **falsification-flavored comparison**: if trade shocks polarize the electorate through
  national ideological conflict, the effect should be *weaker* in state races; if it works
  through local economic grievance, it could be *equally strong or stronger*. Either
  result is publishable and neither is a throwaway robustness.
- It doubles the outcome variation without adding any treatment variation — worth
  remembering that it does **not** solve the effective-shock problem. Same 2.4 shocks.

---

## Deliverables checklist

- [ ] `03a_shares_common.R` + the two `saveRDS` lines in `03` + `EPW_common ≈ EPW_v7` guard
- [ ] `03d_ipw_construction.R` with BEC split, China variant, ADH instrument
- [ ] `output/ipw_rotemberg_comparison.csv` — export vs import `eff_n`, both scalings
- [ ] `06b_panel_governador.R`, `07b_regression_governador.R`, `_estimation_functions.R`
- [ ] Coverage diagnostics saved per state-year + sample-rule sensitivity
- [ ] Every new table reports: N, effective # shocks, RI p-value, AKM0 interval — never a
      cluster-SE t-stat on its own, given the documented 7× over-rejection.

## Report back with

1. Import-side `eff_n` by year vs the export side's 2.4, under both scalings.
2. First stage for the ADH-style import instrument, pooled **and by year**.
3. `cor(EPW, IPW)` by year.
4. Governor ideology-coverage table by state-year, and how many state-years any proposed
   threshold would drop.
5. Whether `EPW_common` reproduced `EPW_v7` (correlation by year).
