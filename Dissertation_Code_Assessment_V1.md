# Dissertation Code Assessment — V1

**Project:** Trade Exposure and Political Polarization: Evidence from Brazilian Microregions
**Scope reviewed:** `_config.R`, `01_extraction.R` → `07_regression_inference.R`, `_archive/`, `README.md`, dissertation `.tex`
**Benchmark corpus:** the 32 PDFs in `papers relevantes/` (Autor, Dorn, Hanson & Majlesi 2020; Borusyak, Hull & Jaravel — quasi-experimental shift-share + practical guide; Goldsmith-Pinkham, Sorkin & Swift — Bartik; Adão, Kolesár & Morales — AKM inference; Campello & Urdinez 2020; Dix-Carneiro & Kovak — regional dynamics; Dix-Carneiro et al. — crime; Rodrik — globalization & populism; Guriev & Papaioannou 2020; and the Brazil-specific populism/gender/incumbency papers), plus current literature.
**Date:** 2026-07-20

> Note on method: the review PDFs could not be rendered in this session, so the SOTA
> comparison rests on close knowledge of these specific papers (all identifiable from
> the corpus) rather than page-level re-reading. Claims about your code are verified
> line-by-line against the scripts.

---

## 1. Executive Summary

This is a **well-above-average empirical pipeline for a Master's dissertation**. The architecture (single `_config.R`, numbered linear stages, documented dependency graph, archived superseded versions) and the internal-validity engineering in `03_epw_construction.R` (complete-grid zero-filling before differencing, producer-primacy renormalization of the HS→ISIC crosswalk, identified-composite aggregation with conservation asserts) reflect a level of care that most published shift-share papers do not document. The inference stack in `07_regression_inference.R` — design-based randomization inference as primary, AKM/AKM0 as secondary, Conley and clustered SEs as reference, plus Rotemberg weights — is squarely aligned with the Borusyak-Hull-Jaravel / Goldsmith-Pinkham-Sorkin-Swift consensus.

The binding constraints are now **scientific, not software**. Three gaps dominate everything else:

1. **The treatment is an own-country, uninstrumented shock.** `g_jt` is built from *Brazil's own* national export changes. Every SOTA paper in your corpus that estimates causal effects of trade shocks (ADH-style US papers, Campello & Urdinez for Brazil) instruments local exposure with *other countries'* trade flows precisely because a country's own exports load on domestic supply and policy shocks — some of which (exchange-rate politics, sectoral policy, Lava Jato's effect on Petrobras/construction) are themselves political. This is the single largest threat to the dissertation's core claim.
2. **The import-competition channel is extracted but never used.** `imports_national_ncm.rds` is produced in stage 01 and consumed nowhere. The literature (ADH; Dix-Carneiro & Kovak; your own `.tex`, which promises an imports extension) treats import competition and export demand as distinct, oppositely-signed labor-market channels. Omitting imports both misses half the phenomenon and potentially biases the export coefficient (import and export exposure are spatially correlated).
3. **No pre-trend/placebo falsification is active.** The archived `03_robustness.R` had a pre-trend control block; it was not ported to 07, and there is no ADH-style regression of *pre-period* (2002→2010) polarization changes on *post-2010* shocks — the standard exogeneity falsification in Autor et al. (2020).

The roadmap below is ordered so that the identification gaps close first; presentation-layer and engineering items come last.

---

## 2. Codebase Strengths & Weaknesses

### 2.1 Strengths

- **Architecture.** One config as single source of truth for paths/constants; strictly linear numbered stages with a README dependency table; superseded scripts archived rather than deleted; run logs via `sink()` with `sessionInfo()` provenance. This is reproducible-research practice most economics repos lack.
- **Defensive correctness.** The pipeline is dense with `stopifnot()` invariants that encode *economic* identities, not just types: crosswalk weights sum to 1 per NCM (`03`, step 3a.3), export value and employment conserved through composite aggregation (`[F-3]`), exposure shares sum to 1 per microregion, EPW ≡ 0 in 2010, identical estimation N across all models (`[A-5]`), exact-reparameterization proof for the boom/bust sign convention (`[A-1]`/`[A-9]`).
- **Sophisticated crosswalk engineering (`03`).** The orphan autopsy → HS-vintage bridge → producer-primacy → restrict-then-renormalize sequence is a genuinely careful solution to the NCM→ISIC many-to-many problem, and the **identified-composite aggregation** (`[E-1]`) — collapsing ISIC classes with identical product signatures before shares/shocks are formed — shows an unusually correct understanding of *why* duplicated shocks break AKM independence and RI exchangeability. This deserves an appendix section in the dissertation; it is a contribution-grade detail.
- **Complete-grid shock panel (`[B-1]`).** Treating industry-years absent from Comex as true zeros before differencing (so total collapses register as the most negative admissible shock rather than 0) is exactly right for a design whose headline result lives on the bust margin.
- **Inference regime.** Primary RI permutes industry identities *jointly across years, preserving each industry's shock path* — the correct exchangeability unit for a common-base stacked design. The `[M-10]` note (cross-year correlation from the shared 2010 base; meso-level pooled clustering as robustness) shows the failure mode was understood, not stumbled past. Rotemberg weights + HHI concentration diagnostics are computed and exported.

### 2.2 Weaknesses and technical debt

**Critical (can produce wrong numbers or a broken run):**

- **`05_centroids.R` is not a script; it is a saved interactive session.** Run top-to-bottom it (a) appends microregion 24019 *twice* (once from the dissolved RN municipalities, once from the 2017 vintage), so the final `stopifnot(nrow(centroids) == 558)` either fails or passes with a duplicated row depending on whether the first append succeeded; (b) re-saves `micro_centroids.rds` twice with different contents; (c) contains an exploratory `for`-loop over vintages with no bearing on output. Since Conley SEs consume this file, a duplicated/wrong centroid silently perturbs the reference inference regime. **Rewrite as one deterministic path with a uniqueness assert (`stopifnot(!any(duplicated(centroids$micro)))`).**
- **The BHJ shock-balance test is a dead branch.** `07` §6 requires `data/sector_chars.rds`, which no stage builds (the `else` prints a TODO). The dissertation `.tex` explicitly promises the Borusyak-Hull-Jaravel balance test. As it stands, the shock-exogeneity check that your primary inference regime *presupposes* is not run.
- **PSL-2018 ideology imputation is backward-in-time.** `02` assigns Bolsonaro's *2022* BLS estimate to PSL in *2018*. Given that the 2018 PSL vote is the pivotal observation for the entire polarization surge, importing a post-radicalization score into the pre-period mechanically inflates measured 2018 dispersion. This needs, at minimum, a sensitivity table (PSL's own 2018-wave score if available in BLS wave 9; a conservative bound; drop-2018 robustness).

**Moderate (methodological hygiene):**

- **Baseline polarization controls are built but never used.** `06` constructs `P_dalton_2010`/`P_center_2010` and comments them as "pre-trend controls"; no control set in `07` includes them. Mean reversion in polarization is a live confounder in first-difference designs — either include them (Barro-style convergence control) or justify their exclusion (Nickell-type concerns) explicitly.
- **Neutral band ±0.25 is a hard-coded magic number** (twice, in `02`). `P_center` and `S_neutral` are threshold-dependent; no sensitivity analysis exists anywhere in the pipeline.
- **Ideology-coverage selection is diagnosed but not propagated.** `02` renormalizes vote shares over BLS-scored parties only and prints the excluded-vote share, but that coverage rate never enters the panel as a weight, control, or sample restriction — so measurement quality varies systematically across region-years (worse for governor races, worse where small parties are strong) and is then ignored.
- **`04_controls.R` retains interactive debris:** un-commented `info_sidra()` metadata calls that hit the API every run; a result-discarding `pib_mun %>% mutate(...)` at line 197; a Block-2 header documenting Sidra table 3548 while the code queries 3547/variable 1643; education categories matched by regex on Portuguese labels (brittle across `sidrar` versions — assert the matched category count instead).
- **Version-suffix drift in `03`:** the header, comments, asserts and messages say "v6" throughout while every output is written `_v7`, and the internal filename says `00_epw_calculo_v7.R` while the file is `03_epw_construction.R`. Cosmetic, but it *will* confuse a replicator (and future-you). Same stale internal filenames in `05` and `07`.
- **Governor branch is built and orphaned** (flagged in your README; still true). Either wire it as an outcome robustness or cut it.

**Minor (efficiency / portability):**

- **RI is needlessly slow.** 9,999 permutations × 3 full `feols` refits re-estimate the FE projection of the *unchanged* outcome and controls every draw. Frisch-Waugh-Lovell: residualize `y` and the controls on FE once, then each draw only requires residualizing the permuted treatment and one cross-product — roughly an order of magnitude faster, which matters once you add IV, imports, and governor outcomes to the RI battery. (`fixest::demean()` does the projection step directly.)
- Absolute Windows path hard-coded in every `source()` header; GCP billing ID committed in `_config.R`; no `renv` lockfile; no master runner (`00_run_all.R`) despite a clean linear DAG; `write_xlsx` side-outputs duplicate every RDS.

---

## 3. SOTA Gap Analysis

| Dimension | Your implementation | SOTA benchmark (corpus) | Verdict |
|---|---|---|---|
| Exposure design | Shift-share EPW: 2010 within-tradable employment shares × cumulative national export-per-worker changes | Same family: ADH; Autor et al. 2020; Campello & Urdinez 2020 | **At par** in construction; crosswalk hygiene arguably ahead |
| Identification | Own-country shocks, reduced form, no IV | Other-country instruments: ADH use other high-income countries' imports from China; Campello & Urdinez instrument Brazilian exposure with China's demand; Costa-Garred-Pessoa split China-boom vs China-competition | **Materially behind** — the central gap |
| Shock channels | Exports only | ADH tradition: import competition primary; Brazil papers: both channels, opposite signs | **Behind**; imports already extracted, unused |
| Shock exogeneity tests | Balance test scaffolded, dead (missing `sector_chars.rds`); no pre-trends | BHJ: balance on industry observables + pre-trend falsification; Autor et al.: pre-period outcome placebo | **Behind** (scaffold exists) |
| Inference | RI (shock-level permutation, path-preserving) primary; AKM/AKM0; Conley; meso×year + pooled-meso clusters | Exactly the BHJ/AKM prescription; RI as primary is what BHJ recommend with few effective shocks | **At or ahead of par** |
| Shift-share diagnostics | Rotemberg weights + HHI + top-5, exported | GPSS full battery: also drop-top-Rotemberg re-estimation (archived, not ported), per-shock β_k | **Near par**; port the archived pieces |
| Estimator form | Region-level OLS only | BHJ recommend the shock-level equivalent regression (`ssaggregate`) when shocks are the identifying variation | **Behind** |
| Shares denominator | Within-tradable shares (sum to 1) + tradable-emp-share control | ADH-style: total-employment denominator; BHJ: sum-of-shares control for incomplete shares — your formulation is a valid variant but non-standard | **Defensible, needs a stated rationale + total-denominator robustness** |
| Outcome measurement | Vote-share-weighted Dalton dispersion + center-emptying index over BLS scores | Autor et al. use candidate/party extremity shifts; European papers use party-family shares. A *continuous ideological dispersion* outcome is your stated contribution | **Novel — but under-stress-tested** (threshold, coverage, PSL imputation) |
| Weighting | Unweighted | ADH tradition weights by voting-eligible population / electorate | **Behind (easy fix as robustness)** |
| Mechanisms | None in code (heterogeneity archived) | Dix-Carneiro-Kovak: local labor-market first stage; gender/status-threat paper; informal-insurance paper | **Behind**, consistent with dissertation stage |

**Bottom line vs SOTA:** your *measurement and inference machinery* is at the frontier for this design class; your *identification strategy* is one generation behind the very papers you cite. Closing that gap is worth more than everything else combined.

---

## 4. Development Roadmap

Ordered by impact on the core research problem. Items 1–3 are the scientific core; 4–5 consolidate.

### Step 1 — Instrument the export shock with external demand (highest priority)

**Why:** removes the own-country supply/policy endogeneity that currently undermines causal interpretation; converts the design from "reduced-form Bartik with own shocks" to the quasi-experimental shift-share your corpus defines.

**How, concretely:**
1. New script `03b_instrument_construction.R`. From BACI (CEPII) or UN Comtrade, build for each HS6×year the imports of the **rest of the world excluding Brazil** (equivalently: world demand net of Brazil), 2010–2022; optionally the China-specific variant (China's imports from world excl. Brazil) to mirror Campello-Urdinez.
2. Push these values through the **identical** deflation → HS-bridge → producer-primacy → composite-aggregation path as the actual exports (factor the crosswalk block of `03` into a function both scripts call — this is the one place where refactoring is scientifically necessary, since instrument and treatment must live on the same industry universe).
3. Build `z_jt = ΔWorldDemand_jt / L_j,2010`, then `EPW_IV_rt = Σ_j s_rj · z_jt`.
4. In `07`: `feols(delta_P_dalton ~ ctrl | state^year | delta_EPW ~ delta_EPW_IV)`, report first-stage F (expect it to be strong — Brazil is a price-taker in most of these markets), and re-run the RI regime permuting the *instrument* shocks.

### Step 2 — Activate the import-competition channel

**Why:** the data already exist (`imports_national_ncm.rds`); the dissertation text promises it; omitting it likely biases the export coefficient and forfeits the comparison that structures the entire Brazil literature (China-boom vs China-competition).

**How:** parallel construction `IPW_rt = Σ_j s_rj · ΔIMP_jt / L_j,2010` through the same crosswalk function; instrument with other emerging economies' imports from China (ADH transposition, as in Costa-Garred-Pessoa); estimate jointly: `ΔP ~ EPW⁺/EPW⁻ + IPW | state^year`, with the asymmetric decomposition extended to both channels. Expect sign structure: bust-exports and import-penetration both polarizing.

### Step 3 — Pre-trend, placebo, and balance battery

**Why:** this is the falsification layer every referee will ask for first, and it is currently the difference between "assumed" and "supported" shock exogeneity.

**How:**
1. Extend the TSE pull in `01` to 2002 and 2006 (`electionsBR` covers both; BLS ideology waves cover the period), build `ΔP_{2002→2010}`, and regress it on post-2010 `ΔEPW` (and the IV) — the Autor et al. (2020) placebo. Null result = headline exhibit.
2. Build `sector_chars.rds` (RAIS 2010: share low-education, share female, mean log wage, informality proxy from Census) and **turn on the dead BHJ balance test** in `07` §6.
3. Port from `_archive/03_robustness.R` and `02_estimation_inference.R`: top-4-export-shares × year pre-trend controls; drop-top-1%-Rotemberg re-estimation; commodity-vs-manufacturing heterogeneity.
4. Add `P_dalton_2010`/`P_center_2010` to a control-set variant to address mean reversion.

### Step 4 — Estimator and measurement robustness

**How:** (a) shock-level BHJ regression (transform to industry level à la `ssaggregate`; a ~40-line R implementation given you already have `W` and `g_mat`); (b) total-employment-denominator EPW variant; (c) electorate-weighted WLS; (d) `P_center` threshold sweep (±0.15/0.20/0.25/0.30) and a threshold-free alternative (Esteban-Ray or vote-share-weighted ideological variance you already compute); (e) PSL-2018 imputation sensitivity; (f) wire the orphaned governor panel as an outcome robustness — it exists end-to-end through stage 02 already.

### Step 5 — Engineering consolidation (do last, cheap)

Rewrite `05_centroids.R` deterministically with a duplicate-micro assert; strip interactive debris from `04`; fix v6/v7 comment drift in `03`; add `00_run_all.R` + `renv::init()`; replace absolute paths with `here::here()`; FWL-accelerate the RI loop before the model count triples in Steps 1–3; move the GCP billing ID to an environment variable.

---

## 5. Closing Assessment

The repository has already passed through the failure modes that sink most shift-share applications (silent zero-coding of collapses, crosswalk value leakage, duplicated-shock pseudo-industries, misaligned inference frames) and documents its own fixes — that history in `_archive/` plus the assert density is exactly what a replication package should look like. What remains is a research-design deficit, not a coding deficit: an uninstrumented own-country shock, a missing import channel, and an inactive falsification layer. Steps 1–3 close precisely those gaps and would move the dissertation from "careful measurement with contestable identification" to the identification standard of the papers it benchmarks against.
