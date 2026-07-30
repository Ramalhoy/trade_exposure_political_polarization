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

### Results of the re-run (2026-07-29)

Full numbers in `output/RESULTS_MANIFEST.md`. Chain run under a pinned UTF-8
locale: `07`(tradable, env override) → `07y` → `03` → `06` → `03c` → `07`(total)
→ `07z`. `04` skipped as invariant (above).

**Verification anchors, all met.** `max|rowSums(W) − θ_r| = 6.11e-16`; θ identity
in `03` `max gap = 7.99e-15`; `Σ_j s_rj == tradable_emp_share` for all 557
microregions; `Σ_j s_rj ∈ [0.0024, 0.6812]`, so strictly < 1 everywhere; N chain
1,674 → 1,671 (micro 13002 dropped) → 1,668 estimated on every model; bust counts
**identical across conventions, 325 pooled / 105 / 165 / 55**, as θ_r ≥ 0
requires; by-year cor(EPW_total, EPW_tradable) = 0.923 / 0.948 / 0.925; nesting
`max|b(boom−bust) − b_pooled| = 4.3e-18`.

**The null is intact, and now it is intact everywhere.** Under the main
specification every one of the six coefficients has an RI p between **0.43 and
0.93** (extended controls), 0.47–0.91 (base). Under the complete-shares
robustness convention the range is 0.32–0.95. No treatment coefficient is
distinguishable from its placebo distribution under either normalisation or
either control set. This is the finding, and it does not depend on the
share convention — which is exactly the ground on which the specification can now
be chosen to match the identification argument rather than to obtain a result.

**§6's instability argument does not survive, but not for the reason [T-1b]
anticipated.** The quarantined table attributed boom-Center's loss of
significance to the *convention*. It is actually a *control-set* effect:

| boom, ΔP^N | base controls | extended controls |
|---|---|---|
| complete shares | −0.0160 (0.0087) * | −0.0229 (0.0093) ** |
| incomplete shares | −0.0127 (0.0082), t = 1.55, ns | −0.0184 (0.0085) ** |

Under extended controls the coefficient stays significant under both
conventions; under base controls it weakens under both. The draft's claim that
the cluster-robust picture is *unstable across normalisations* is therefore not
supported in either direction, and the [T-1b] quarantine stands: the `corrected`
row §6 quoted was the misspecified one, and my extended-controls figures
approximately reproduce the table's `corrected + theta_r control` row
(−0.0205 → −0.0177) rather than the row the draft used.

**The framework-predicted sign appears where the quarantined table said it
would.** Under the main specification with extended controls, bust-Dalton is
**+0.0146 (0.0078), t = 1.87** — positive, as Prop. 1 requires, and marginally
significant on clustered SEs — against the quarantined table's +0.0145 (0.0076),
t ≈ 1.9. Its RI p is 0.62, so the design-based regime does not support it. The
honest statement is that the sign is right and the design cannot resolve it.

**The placebo/cluster SE ratios widened rather than collapsing.** [T-5] asked
whether they fall toward 1 under the rescaling. They do not: 2.6×–6.2× under the
main convention against 2.3×–5.3× under the robustness one. The design-based null
is between three and six times wider than the cluster-robust one, which is a
direct quantitative argument for the paper's choice of RI as primary — and a
better one than the instability claim it currently uses.

**Diagnostics that moved.** Effective shocks 2.88 / 2.51 / 2.38 (mean **2.59**
base, 2.43 ext) against 2.62 / 2.47 / 2.24 (mean 2.44) under complete shares —
the paper's "≈ 2.4" survives as a description of both, but the main-specification
figure is 2.6. AKM/AKM0 for pooled ΔP^D move to p = 0.752 / 0.749 (from
0.178 / 0.226), tracking the much smaller pooled point estimate. Symmetry is
rejected for ΔP^N under both conventions (p = 0.0036 total, 0.0020 tradable) and
not rejected for ΔP^D (0.488 / 0.570).

**Diagnostics that did not move, as predicted:** the BHJ balance test is
**0.2978 / 0.2946 / 0.0135** under `"total"` — identical to the draft's
0.30 / 0.29 / 0.01. The 2022 failure is unchanged, confirming the [T-6]
correction empirically rather than by code-reading.

**Not run:** `03a`/`03b`/`03d`. Their artefacts do not exist in this data
directory, so the joint export–import block in `07` was already skipped under the
old vintage and remains skipped; enabling the import channel is a separate piece
of work and is out of this packet's scope.

### [T-8]/[T-9] Provenance

Run logs to `output/07_run_log_<denom>.txt`; manifest fragment per convention to
`output/manifest_<denom>.rds` (estimates, diagnostics, sanity chain,
descriptives, input MD5s, `sessionInfo()`); merged by
`07z_results_manifest.R` into `output/RESULTS_MANIFEST.md`. Work done on branch
`theta-total-shares`, with a baseline commit taken before the flip.
