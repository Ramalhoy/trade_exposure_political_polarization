# RATIONALE

Change log for the dissertation pipeline. One entry per audit tag; every number
that reaches the manuscript must trace to a script committed here and to an entry
below.

**Standing protocol.** No console-only runs. Every estimation writes a run log to
`output/`, and every reported figure appears in `output/RESULTS_MANIFEST.md`.
Commit before and after any re-run so the diff is inspectable.

---

## Section 1 — provenance of this file

Created 2026-07-29. `07_regression_inference.R` had referenced "RATIONALE.md,
section 2" since the v3 monolith, but the file itself was never in the repository —
which is the same class of failure as `[T-1b]` below: a claim of provenance with
nothing behind it. Entries before the T series are reconstructed from
`CODE_CHANGES_TODO.md`, `README.md` and the audit tree, and are marked as such.

---

## Packet T2 — incomplete-shares main specification

Executor packet: `EXECUTOR_PACKET_T2_theta.md`, which supersedes
`EXECUTOR_PACKET_T_theta.md` (written against the archived
`regressao_SFD_v3.R` / `00_epw_calculo_v7.R` monolith rather than the live
`00_config → 03 → 03a–03d → 04 → 06 → 07` pipeline).

Route decision, settled by the packet: flip `SHARE_DENOM` to `"total"` in
`00_config.R` and re-run `03 → 07`, rather than rescaling the treatment inside the
estimation script. The paper reports share-dependent diagnostics (Rotemberg
weights, effective shock count, BHJ balance, AKM/AKM0) alongside the main
specification, and those must be built on the same `W` as the treatment. The
in-script shortcut would reproduce the text–code mismatch the packet exists to
remove.

### [T-1] Diagnostic — did the existing θ-rescaled run condition on θ_r? (read-only)

**Finding: there was no such run.**

1. **Where the rescaled treatment is constructed:** nowhere. Grep for
   `delta_EPW *`, `* tradable_emp_share`, `epw_total`, `EPW_total`, `theta_r *`
   over the whole project returns only comments and identity assertions —
   `03_epw_construction.R:689` (the unit test), `00_config.R:45-57` (the algebra),
   `CODE_CHANGES_TODO.md:278` (prose). Not in `_archive/regressao_SFD_v3.R`
   either, which uses `delta_EPW` throughout with
   `ctrl_base = c("ln_gdp_pc", "ln_pop", "tradable_emp_share")`.
2. **Control vector of the run behind §6:** unrecoverable from code, but
   recoverable from the record. The §6 figures match the results table in
   `CODE_CHANGES_TODO.md §1b` line-for-line (boom-Center `−0.0205 → −0.0074`;
   bust-Dalton `+0.0133`; "RI p Dalton 0.647 / 0.721, Center 0.808 / 0.419" →
   "between 0.42 and 0.81"). That table lists `corrected` and
   `corrected + theta_r control` as **separate rows**.
3. **Is `tradable_emp_share` in it? No.** §6 quotes the `corrected` row, without
   the BHJ control. With the control, boom-Center is `−0.0177**` — significant —
   and bust-Dalton is `+0.0145 (t ≈ 1.9)`.
4. **Did the RI rebuild the rescaled treatment inside the loop?** Undeterminable.
   No placebo matrix for the rescaled treatment exists on disk; the only one,
   `output/ri_beta_distribution.rds`, is the complete-shares vintage (9,999 × 3,
   written after the document). Every §6 RI p-value is therefore unverifiable.

Three corrections to the packets' picture of the codebase, established in the
same pass:

- **`tradable_emp_share` was already in the live control vector** (`ctrl_base`,
  `07_regression_inference.R:149`), hence in `ctrl_ext` too. Packet T's [T-3]
  premise that it had to be *added* was stale; only the treatment changes.
- **Packet T2 [T-2b]'s guard edit was unnecessary.** The `Σ_j s_rj = 1`
  assertions in `03:639` and `03a:241` are already conditional on
  `SHARE_DENOM == "tradable"`, with the `(0,1]` branch already written for
  `"total"`. No edit made.
- **Packet T2 [T-4]'s premise was partly wrong**, and the correction matters:
  Table 3 (`mod_decomp`) and the pooled-Dalton RI p are **both** estimated on
  `ctrl_base`, the same controls the loop hardcoded, so those p-values were
  *correctly* calibrated. The real defects were narrower: the `ctrl_ext` columns
  of `tab_ols_baseline` carried a `ctrl_base` p-value, the `ΔP^N` columns carried
  the `ΔP^D` one, and `pooled_N` / `boom_D` / `boom_N` were never permuted at
  all. The [T-4] fix is still the right fix; the claim that "every RI p-value in
  Table 3 is mis-calibrated" is not.

### [T-1b] Quarantine of the §6 numbers

`CODE_CHANGES_TODO.md §1b` marked **UNREPRODUCIBLE — DO NOT CITE** in place, with
the [T-1] findings and the with/without-θ_r side-by-side recorded there. Table
retained, not deleted: it is the only record of that run and the comparison point
for the re-run.

**Carried forward for the rewrite.** §6's instability argument must be rewritten
regardless of what the re-run produces, because the instability it reports is an
artifact of the omitted control. And bust-Dalton carrying the framework-predicted
sign at t ≈ 1.9 under the correct specification is a materially different story
from the current draft's. Neither the old nor the new narrative is safe until the
re-run lands.

### [T-2b] `SHARE_DENOM = "total"` — incomplete shares

`00_config.R:57` flipped. Under this setting `s_rj = L_rj,2010 / L_r,2010^total`,
so `Σ_j s_rj = θ_r < 1` and varies across microregions — the case BHJ's
sum-of-shares control addresses, and the construction the paper's §3.3
identification argument assumes. Pipeline re-run `03 → 03a → 06 → 07`.

`04_controls.R` deliberately **not** re-run: its only share-dependent object,
`manuf_share_of_tradable`, is built from raw employment counts `L_rj_2010`
(`04_controls.R:259-267`), so it is invariant to the share denominator. (It also
requires BigQuery credentials.) Verified invariant rather than assumed.

New assertion in `07` ([T-2b]): `max|rowSums(W) − θ_r| < 1e-10` under `"total"`,
`max|rowSums(W) − 1|` under `"tradable"`, plus `Σ_j s_rj < 1` for every
microregion. A failure invalidates everything downstream, so it halts the run.

### [T-3b] Control set — verified, not changed

`tradable_emp_share` is in `ctrl_base` and therefore in every reported
specification. No change. Comment added at `07:149` recording that under
`"total"` it *is* `Σ_j s_rj` — the BHJ control, load-bearing rather than
incidental — and must not be dropped from any specification reporting
`delta_EPW`.

### [T-4] RI control-set mismatch fixed

`ri_fast()` is now parameterised on the control vector and returns all six
reported coefficients (`pooled_D`, `pooled_N`, `boom_D`, `bust_D`, `boom_N`,
`bust_N`) instead of three. Run once per control set, with the seed reset before
each so both see the same permutation stream and differ only in specification.
Four `feols` fits per draw cover six statistics — the decomposition model yields
boom and bust jointly.

Each reported cell is now located in a placebo distribution built under **its
own** controls, and the table notes pull the matched p-value from `ri_full`
rather than being hand-copied.

### [T-5] Permutation run — both conventions

`W` already embeds whichever denominator is in force, so under `"total"` the
placebo is `W_total %*% g_star` with **no** θ rescaling; multiplying by θ again
(correct only against a tradable-share `W`, as in Packet T) would square the
reweighting. `sd_epw` is recomputed from the new raw treatment, which keeps
boom/bust on the pooled coefficient's scale and preserves the nesting property
`β₊ = −β₋ ⇒ pooled β`.

`set.seed(2026)`, `B = 9999`, `lean = TRUE`. Placebo matrices written to
`output/ri_beta_distribution_<denom>_<ctrls>.rds` (four files: two conventions ×
two control sets). `output/ri_beta_distribution.rds` is **not** rewritten — it is
frozen as the old vintage's provenance. Per coefficient the run reports β̂,
clustered SE, placebo SD, placebo SD ÷ clustered SE, and two-sided p under both
conventions (`mean(|β*| ≥ |β̂|)` and the `(1+#)/(B+1)` variant the tables use).

### [T-6] Share-dependent diagnostics rebuilt

Rotemberg weights recomputed on the new `W` for **both** control sets
(`rotemberg_for()`), with per-year HHI, effective shock count `1/HHI`, top-3
share and top-5 |α| with ISIC codes. The `lm()` residualisation is kept
deliberately: `feols()` drops the Distrito Federal state×year singleton from
`resid()`, desynchronising the residual vector from `Wt`.

Symmetry test `H₀: β₊ = −β₋` restored for both outcomes (present in the 16 Jun
table at p = 0.106 Dalton / 0.032 center, lost in transcription). In magnitude
coding this is `β_boom + β_bust = 0`, tested on the clustered vcov; it is the
formal test of the paper's central asymmetry hypothesis.

**One packet claim corrected:** [T-6] item 5 states that the BHJ balance-test
weights are "national employment shares derived from `s_rj`, so they change with
the denominator." They are not. `03c_shock_exogeneity.R:196-197` builds
`s_bar = L_j_2010 / Σ_j L_j_2010` from the *shock* table's national employment
counts, and `g_jt` uses national denominators throughout. The balance test is
therefore **invariant** to the share denominator: the 2022 failure the paper
reports does not move.

### [T-7] Tables

Written under convention-tagged names (`tab_<stem>_<denom>.tex`). The untagged
files already on disk are the frozen complete-shares vintage and are left alone,
for the same provenance reason as `ri_beta_distribution.rds`.

`tab_desc_stats.tex` rebuilt in **raw units**. The version on disk reports
standardised variables (every mean 0, SD 1) and is produced by no current script —
an orphan of an old run. The rebuild adds the treatment row under its actual
convention and a `θ_r` row.

### [T-8]/[T-9] Provenance

Run logs to `output/07_run_log_<denom>.txt`; manifest fragment per convention to
`output/manifest_<denom>.rds` (estimates, diagnostics, sanity chain,
descriptives, input MD5s, `sessionInfo()`); merged by
`07z_results_manifest.R` into `output/RESULTS_MANIFEST.md`. Work done on branch
`theta-total-shares`, with a baseline commit taken before the flip.
