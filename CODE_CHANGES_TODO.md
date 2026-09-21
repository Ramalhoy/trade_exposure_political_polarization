# Code changes to make in Claude Code

Generated 2026-07-24, from the round-2 review. Paper-side text is already
corrected in `main_anpec.tex`; these are the pipeline changes that need to
follow so code and text agree.

Ordered by priority. Items 1 and 2 are needed before the December version;
item 3 is a discrepancy to resolve either way; item 4 is optional cleanup.

---

## STATUS as of 2026-07-25 — items 1b, 2, 3, 4 implemented

Item 1 (Bolsonaro scoring rule) is **not** done — it was out of scope for this
pass.

| Item | Decision taken | Where |
|---|---|---|
| **1b** share denominator | **Flagged, default = status quo.** `SHARE_DENOM <- "tradable"` in `_config.R` reproduces the ANPEC tables *bit-for-bit* (verified: 31,485/31,485 share rows identical to `exposure_shares_isic_v7.rds`, max diff 0). `SHARE_DENOM <- "total"` implements Option B in full. December is now a one-line change plus a re-run. | `_config.R`, `03` STEP 8, `03a` STEP 3/5 |
| **2** BHJ control in the panel | Done, plus a `stopifnot` guard. `07` now *asserts* the panel column agrees with `tradable_emp_share_2010_v7.rds` instead of silently re-joining. | `06` |
| **3** 1,671 vs 1,668 | **Drop** (paper behaviour). Rule imposed **once** in `06`; `07`/`03c`/`06b` assert it rather than re-imposing. | `06`, `06b`, `07`, `03c`, `main_anpec.tex` |
| **4** rename | Done: `manuf_share` → `manuf_share_of_tradable` everywhere, incl. the `etable` label. | `04`, `06`, `06b`, `07`, `03c` |
| stale `[A-10]` | Comment corrected; the filter is a **no-op** and is now documented as a forward guard, not as the mechanism that drops 13002. | `07` |

### Verified by running R against the real data (not asserted from the doc)

- `cor(EPW_tradable, EPW_total) = 0.9328`, rank `0.9268` — independently
  reproduces the 0.933 / 0.927 reported below.
- The θ identity `EPW_total = θ_r · EPW_tradable` holds to `1.8e-15`.
- **The TRAP assert passes**: under `"total"`, `Σ_j s_rj` over the
  export-bilateral numerator equals `tradable_emp_share` to `1.1e-16`.
- New sample rule → panel **1,671 rows / 557 micros**, regressions **N = 1,668**,
  identical across base and extended specs, 78 state×year cells. Exactly the
  paper's numbers.
- Joint export–import spec: 1,671 → **1,668**, coefficients unchanged.

### One correction to §1b below

The claim *"after the denominator change this correlation is 0.933 and the
[`03a`] guard will halt the build"* is only true if `03a` is changed **alone**.
`SHARE_DENOM` moves `03` and `03a` **together**, and under a common `L_r_all`
denominator the export-bilateral restriction on the numerator becomes
irrelevant (industries outside it carry `g_jt = 0`), so the two panels are
**algebraically identical**. Measured: `cor = 1`, `max|gap| = 0`. The guard is
therefore re-baselined to assert *equality to machine precision* under
`"total"` — strictly **stronger** than the 0.99 threshold, not looser. The
0.99 check is kept unchanged for `"tradable"` (measured min by-year cor
= 0.99906).

### 2026-07-25 — full re-run of the presidential x export track

Ran `02 -> 03 -> 03b -> 03c -> 04 -> 06 -> 07`, then new report scripts `08`/`09`/`10`.
All stages exit 0. Results in `REPORT_presidential_exports_2026-07-25.md`, CSVs in
`output/report_pres_exports/`, LaTeX in `tables/rep_tab1..6*.tex`.

Reproduces the paper: panel 1,671 / 557 micros, N = 1,668, 78 FE cells, 152
industries, eff. shocks 2.62/2.47/2.24, AKM placebo 0.357/0.334, and Table 2
descriptives to the last printed digit. The rebuilt treatment is bit-identical to
the pre-run vintage on the 557 shared micros (cor = 1, max diff = 0).

**Two pipeline repairs were needed before anything would run:**

1. `_config.R` was renamed to `00_config.R` mid-session, leaving all 14
   `source(".../\_config.R")` calls pointing at a missing file. Repointed.
2. `03` defines a **local** `paths` list that shadows the one in `00_config.R`, so
   `paths$share_sum` was NULL and STEP 8's `saveRDS` failed. Added the key locally
   with a comment about the shadowing.

**New findings that outrank items 1-4 below:**

- **THE CENTRE-EMPTYING OUTCOME IS BASELINE-DETERMINED.** `P_center` = 1 - (vote
  share to parties with ideo in [-0.25, 0.25]). All microregions face the same
  national menu, so it varies across space only if a party sits inside the band.
  In **2018 none does** (PODE nearest at 0.269): `P_center` takes **exactly one
  distinct value** across all 558 micros, so `dP_center = 1 - P_center_2010`
  identically, R^2 = **1.00000**. In 2022 only MDB (4.2%) qualifies, R^2 = **0.990**.
  Conditioning on the 2010 baseline (already in the panel, labelled a pre-trend
  control by `06`, never used by `07`) collapses the bust coefficient from
  **-0.0435 (p = 0.008) to -0.0001 (p = 0.989)**; within-R^2 goes 0.060 -> 0.670.
  Stack by stack the significance is entirely in the two degenerate years
  (2018 p = 0.016, 2022 p = 0.030) while 2014 -- the only stack with real outcome
  variation -- is null (p = 0.492). The IV reduced form collapses the same way
  (z_CHN: -0.0294, p = 0.004 -> +0.0021, p = 0.477). `dP_dalton` is unaffected
  throughout. See `09_center_index_diagnostic.R` and report section 6.
- **`07`'s decomposition uses `ctrl_base`; the paper's Table 3 uses `ctrl_ext`.**
  Headline cell differs (bust on centre: -0.043 vs -0.052), and neither is the
  -0.062 currently printed. Both are now reported; the paper must pick one.
- **Kleibergen-Paap must be computed under the inference cluster.** `fitstat()`'s
  default homoskedastic vcov returned 351 / 11.8 / 1029 for the three instruments;
  the correct cluster-robust values equal the first-stage F: 4.30 / 0.32 / 21.89.
  Only `z_CHN` is usable. Fixed in `08`.
- `07`'s import block was skipped by the new vintage guard, as designed: the
  `03a`/`03d` artefacts predate share-convention stamping.

### Still outstanding

- Item 1 (Bolsonaro `BOLSO_RULE`).
- Nothing has been **re-run**. `04` onwards must be re-run for
  `manuf_share_of_tradable` to exist in the saved `.rds` files.
- The saved `epw_panel_isic_v7.rds` is **stale**: it holds 558 micros while
  `exposure_shares_isic_v7.rds` holds 557. Re-running `03` will drop it to 557.
  This is harmless under the new rule (which keys on `tradable_emp_share > 0`)
  but means the current artefacts are mixed-vintage.

---

## 1. `02_polarization_indices.R` — Bolsonaro / PSL / PL scoring rule

**File:** `02_polarization_indices.R`, lines ~31–38

### Current code

```r
#usar estimativa para o Bolsonaro como equivalente à posição do PSL em 2018
psl <- ideologia %>%
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) %>%
  mutate(
    party.or.pres = "PSL",
    ano_eleicao   = 2018
  )

ideologia_psl <- bind_rows(ideologia, psl)
```

### Two problems

**(a) Wave mismatch, undocumented.** Line 25 sets `ano_eleicao = year + 1`, so
`ano_eleicao == 2022` selects the BLS wave fielded in **2021 (BLS 9)**. That
2021 measurement is then back-applied to the **2018** election. Table 1 of the
paper states 2018 → BLS 8 (2017). There is no BLS 8 entry for Bolsonaro
(verified: he appears once in the estimates file, at `year == 2021`,
`ideo = 0.862014`, `ideo.se = 0.043547`), so borrowing is unavoidable — but it
is an exception to the stated alignment rule and must be disclosed.

**(b) The rule is applied asymmetrically.** In 2018 Bolsonaro gets a
*candidate-level* score (0.862). In 2022 he runs on PL and gets the *party-level*
score (`PL`, 2021 = **0.493432**). The same candidate therefore moves **0.369
points left** between stacks purely from switching instrument type. The
personalistic-party justification invoked for 2018 applies at least as strongly
in 2022.

Reference values (from `bls9_estimates_partiespresidents_long.rds`):

| Entity | year | ideo | ideo.se |
|---|---|---|---|
| BOLSONARO | 2021 | 0.862014 | 0.043547 |
| PSL | 2021 | 0.803359 | 0.043212 |
| PL | 2021 | 0.493432 | 0.039260 |
| PL | 2017 | 0.434313 | 0.037256 |

### Change: parameterise the rule, default to candidate-anchored

```r
# ---------------------------------------------------------------------------
# BLS scoring rule for Bolsonaro's electoral vehicles.
#
# Neither PSL (2018) nor PL (2022) is a programmatic vehicle in the sense of
# Gunther & Diamond: the candidate signals the party's position rather than the
# reverse. We therefore use Bolsonaro's individual BLS estimate for BOTH the
# 2018 and 2022 stacks, so that the same object is measured by the same
# instrument across first differences.
#
# NOTE: BLS 8 (2017) contains no Bolsonaro entry, so the 2018 value is borrowed
# from BLS 9 (2021). This is the single exception to the wave-alignment rule of
# Table 1 and is disclosed as such in the paper.
#
# BOLSO_RULE:
#   "candidate"     - Bolsonaro's own score in both years          (PRIMARY)
#   "party"         - PSL 2021 for 2018, PL 2021 for 2022          (robustness)
#   "candidate_lo"  - candidate score minus 1 SE, both years       (robustness)
#   "candidate_hi"  - candidate score plus  1 SE, both years       (robustness)
#   "status_quo"    - old behaviour: candidate 2018, PL party 2022 (reproduces
#                     the current ANPEC tables)
# ---------------------------------------------------------------------------
BOLSO_RULE <- "candidate"

bols <- ideologia %>%
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022)
stopifnot("Bolsonaro BLS estimate not found" = nrow(bols) == 1)

bols_ideo <- bols$ideo
bols_se   <- bols$ideo.se

bols_val <- switch(
  BOLSO_RULE,
  candidate    = bols_ideo,
  candidate_lo = bols_ideo - bols_se,
  candidate_hi = bols_ideo + bols_se,
  NA_real_                       # "party" / "status_quo" handled below
)

if (BOLSO_RULE %in% c("candidate", "candidate_lo", "candidate_hi")) {

  psl_2018 <- bols %>%
    mutate(party.or.pres = "PSL", ano_eleicao = 2018, ideo = bols_val)
  pl_2022  <- bols %>%
    mutate(party.or.pres = "PL",  ano_eleicao = 2022, ideo = bols_val)

  ideologia_psl <- ideologia %>%
    filter(!(party.or.pres == "PL" & ano_eleicao == 2022)) %>%
    bind_rows(psl_2018, pl_2022)

} else if (BOLSO_RULE == "party") {

  # PSL 2021 stands in for PSL 2018; PL 2022 left at its own party score.
  psl_2018 <- ideologia %>%
    filter(party.or.pres == "PSL", ano_eleicao == 2022) %>%
    mutate(ano_eleicao = 2018)
  ideologia_psl <- bind_rows(ideologia, psl_2018)

} else if (BOLSO_RULE == "status_quo") {

  psl_2018 <- bols %>% mutate(party.or.pres = "PSL", ano_eleicao = 2018)
  ideologia_psl <- bind_rows(ideologia, psl_2018)

} else stop("unknown BOLSO_RULE: ", BOLSO_RULE)

cat(sprintf("BLS rule = %s | 2018 PSL = %.3f | 2022 PL = %.3f\n",
            BOLSO_RULE,
            ideologia_psl$ideo[ideologia_psl$party.or.pres == "PSL"  &
                               ideologia_psl$ano_eleicao == 2018][1],
            ideologia_psl$ideo[ideologia_psl$party.or.pres == "PL"   &
                               ideologia_psl$ano_eleicao == 2022][1]))
```

### What to report

Run `candidate` as primary and the other three as a measurement-robustness
panel. **Keep the two kinds of uncertainty separate** — they are not the same
object and should not be pooled into one "±1 SD" row:

- `candidate_lo` / `candidate_hi` bracket **BLS estimation error**:
  `[0.818, 0.906]`, width 0.087. This will show essentially nothing, which is
  the useful finding — the result is not sensitive to how precisely the BLS
  pins Bolsonaro down.
- `party` brackets **coding-convention uncertainty**: 0.493 vs 0.862, a gap of
  **8.5 standard errors**. This is where the real sensitivity lives, and it is
  the row a referee will look for.

---

## 1b. **THE SHARE DENOMINATOR — likely a genuine bug, decide before December**

**Verdict: the code deviates from the intended design, and the paper's original
"incomplete shares" text was right.**

### Evidence

`03_epw_construction.R` STEP 8 normalises within the tradable universe:

```r
L_r_2010 <- rais_isic |> group_by(micro) |> summarise(L_r_2010 = sum(workers))
shares   <- ... mutate(s_rj = L_rj_2010 / L_r_2010)
stopifnot(all(abs(... sum(s_rj) ... - 1) < 1e-6))     # shares sum to 1
```

Three independent signs that this was never a deliberate identification choice:

1. **`SPEC_import_and_governor.md` PART 0** frames the problem purely as
   *commensurability* between EPW and IPW — shares summing to 1 over the
   *export* set vs the *import* set. It takes "sums to 1" as given and only
   fixes **which set**. The question of whether the denominator should be total
   formal employment is never raised.
2. **The pipeline separately builds `tradable_emp_share` and calls it "the BHJ
   sum-of-shares control."** That object only *exists* as a control if the
   shares are meant to be incomplete. The code cannot coherently normalise to 1
   (making the sum degenerate) and also need a sum-of-shares control.
3. **ADH/Rettl-style designs use total local employment** as the denominator, so
   exposure scales with tradable intensity. The paper cites Rettl for the
   construction.

### The algebra

With `theta_r = tradable_emp_share`:

```
s_total[r,j]  = theta_r * s_tradable[r,j]
=> EPW_total[r,t] = theta_r * EPW_tradable[r,t]
```

The correct treatment is the current one **multiplied by tradable intensity**.
This is a region-specific *multiplicative rescaling*, so **adding
`tradable_emp_share` as an additive control does NOT recover it.**

`theta_r`: mean 0.250, sd 0.148, min 0.000, p25 0.125, median 0.247, p75 0.365,
max 0.681. So the current construction gives a microregion with 12% tradable
employment the same total shock weight as one with 37% — it differences out the
intensity dimension entirely.

### Why this trips your own guard

The spec's PART 0 says: *"assert `cor(EPW_common, EPW_v7) > 0.99` ... If the
correlation is materially below that, STOP and report — the denominator change
has moved the treatment and every `03c` result would need re-running."*

**`cor(EPW_current, EPW_corrected) = 0.933`** (rank corr 0.927). Below your own
threshold.

### What changes empirically (computed, B = 9,999, fuller controls, N = 1,668)

> ## ⚠️ UNREPRODUCIBLE — DO NOT CITE  *(marked 2026-07-29, Packet T2 [T-1b])*
>
> The table and RI p-values below are **quarantined**. The `[T-1]` diagnostic
> established that:
>
> 1. **No code in this project ever constructed `θ_r · ΔEPW`.** A full grep for
>    `delta_EPW *`, `* tradable_emp_share`, `epw_total`, `theta_r *` returns only
>    comments, identity assertions and prose. The generating script was never
>    saved — not in the repo, the git history, `.Rhistory`, `audit/`, or any
>    session transcript on this machine.
> 2. **No placebo matrix exists behind the four RI p-values.**
>    `output/ri_beta_distribution.rds` is the complete-shares run (9,999 × 3,
>    written 27 Jul 21:47, *after* this document), and it does not contain
>    `boom_N` — the coefficient the paper's §6 argument turns on — under either
>    convention. Whether the permutation loop rebuilt the *rescaled* treatment
>    inside the loop cannot be determined, so the p-values are unverifiable.
> 3. **`main.tex` §6 quotes the `corrected` row, i.e. the specification WITHOUT
>    the θ_r control** — the misspecification BHJ's incomplete-shares correction
>    exists to prevent. With the control the picture is materially different:
>    boom-Center is `−0.0205 → −0.0177**` (still significant) rather than
>    `−0.0205 → −0.0074` (ns), and bust-Dalton is `+0.0145 (t ≈ 1.9)` rather than
>    `+0.0133`. §6's claim that the cluster-robust picture is *unstable* across
>    normalisations — the claim the paper uses to justify RI as its primary
>    regime — is therefore an artifact of the omitted control, not a property of
>    the data.
>
> **Kept, not deleted:** it is the only record of that run and is the comparison
> point for the `SHARE_DENOM = "total"` re-run ([T-2b]). Replaced by
> `output/RESULTS_MANIFEST.md` once that lands. See `RATIONALE.md` `[T-1b]`.

| Treatment | Outcome | boom | bust |
|---|---|---|---|
| current | Center | **−0.0205 (0.0081)\*\*** | **−0.0617 (0.0164)\*\*\*** |
| corrected | Center | −0.0074 (0.0082) *ns* | **−0.0498 (0.0154)\*\*\*** |
| corrected + `theta_r` control | Center | **−0.0177 (0.0082)\*\*** | **−0.0469 (0.0151)\*\*\*** |
| current | Dalton | +0.0048 (0.0050) | +0.0053 (0.0091) |
| corrected | Dalton | +0.0057 (0.0065) | +0.0133 (0.0082) |
| corrected + `theta_r` control | Dalton | +0.0014 (0.0066) | +0.0145 (0.0076) *t=1.9* |

RI *p*-values under the corrected treatment: Dalton 0.647 / 0.721;
Center 0.808 / 0.419. **The null survives everywhere.**

Two things worth noting. The boom-on-center coefficient **loses significance**
under the correction, so the "two significant coefficients" framing is
construction-dependent. And the Dalton bust coefficient **moves toward the
predicted positive sign** and approaches significance — i.e. the corrected
construction is marginally *more* favourable to the framework.

### Exactly what to rebuild (Option B recipe)

**Anchor numbers:** total FTE all sectors = 45,444,209; tradable FTE in the
shares numerator = 9,274,520; national tradable fraction = 0.2041; `theta_r`
mean across microregions = 0.250.

#### Change 1 — `03_epw_construction.R`, STEP 8 (lines ~581–593)

The denominator you need is **already computed 15 lines below**, at lines
598–606, where `L_r_total` is read from `rais_fte.rds` (all 670 CNAE classes,
i.e. total formal employment). Move that block *above* STEP 8 and use it:

```r
# ---- total formal employment (ALL sectors) — moved up from old lines 598-606
if (RAIS_MEASURE == "fte") {
  L_r_total <- readRDS(paths$rais_fte) |>
    rename(micro = microregion_code, workers = total_fte)
} else {
  L_r_total <- readRDS(paths$rais_head) |> rename(micro = microregion_code)
}
L_r_all <- L_r_total |> group_by(micro) |>
  summarise(L_r_all = sum(workers, na.rm = TRUE), .groups = "drop")

# ---- STEP 8 — EXPOSURE SHARES  s_rj = L_rj,2010 / L_r_all,2010  (INCOMPLETE)
shares <- rais_isic |>
  rename(L_rj_2010 = workers) |>
  left_join(L_r_all, by = "micro") |>
  filter(L_r_all > 0) |>
  mutate(s_rj = L_rj_2010 / L_r_all)
```

#### Change 2 — replace the share-sum assertions (both files)

`03_epw_construction.R` line ~591 and `03a_shares_common.R` line ~190 both
assert the shares sum to 1. Under incomplete shares that is false by design.
The new invariant is that the share sum **equals** tradable intensity:

```r
share_sum <- shares |> group_by(micro) |>
  summarise(theta_r = sum(s_rj), .groups = "drop")
stopifnot("share sum outside (0,1]" = all(share_sum$theta_r > 0 &
                                          share_sum$theta_r <= 1 + 1e-9))
cat(sprintf("theta_r: mean %.4f | min %.4f | max %.4f\n",
            mean(share_sum$theta_r), min(share_sum$theta_r),
            max(share_sum$theta_r)))
saveRDS(share_sum, "share_sum_theta_v9.rds")   # <- THIS is the BHJ control
```

#### Change 3 — `03a_shares_common.R`, STEP 3 (lines ~180–190)

Same denominator substitution. Keep the full-tradable numerator and the explicit
`g_jt = 0` outside each bilateral set — that part was always right.

#### THE TRAP — numerator scope must match the control

The two scripts use **different numerator sets**:

- `03_epw_construction.R`: `rais_isic` *after* the STEP 6 restriction to
  `isic_bilateral = intersect(exports_isic$isic4, rais_isic$isic4)` — the
  **export-bilateral** set.
- `03a_shares_common.R`: the **full tradable** RAIS universe.

`sum_j s_rj` equals `(employment in the numerator set) / L_r_all`. The existing
`tradable_emp_share_2010_v7.rds` is `L_r_tradable / L_r_all` — so it only equals
`sum_j s_rj` if the numerator spans the **full tradable universe**.

**Therefore: build on `03a`'s full-tradable numerator, and derive the BHJ control
as the realized `sum_j s_rj` (Change 2) rather than reading the precomputed
file.** That makes them consistent by construction. If you instead keep `03`'s
narrower export-bilateral numerator, `tradable_emp_share` is the *wrong* control
and must be recomputed on the same restricted set.

#### Free unit test

Because the two constructions differ by exactly `theta_r`, the rebuild must
satisfy — to machine precision, provided the numerator sets match:

```r
chk <- epw_new |>
  inner_join(epw_old |> select(micro, year, EPW_old = EPW),
             by = c("micro", "year")) |>
  inner_join(share_sum, by = "micro") |>
  mutate(gap = abs(EPW - EPW_old * theta_r))
stopifnot("EPW_new != EPW_old * theta_r" = max(chk$gap) < 1e-10)
```

If that fails, the numerator sets differ — see the trap above.

#### Also re-baseline the 03a guard

`03a_shares_common.R` asserts `cor(EPW_common, EPW_v7) > 0.99`. After the
denominator change this correlation is **0.933** and the guard will halt the
build. That guard exists to detect *unintended* treatment movement; here the
movement is intended, so compare against the new baseline instead and keep the
0.99 check for future refactors.

#### Downstream, must be re-run in order

| Script | What changes |
|---|---|
| `03a_shares_common.R` | `exposure_shares_common_v8.rds`, `epw_common_panel_v8.rds` |
| `03b_instrument_construction.R` (L375–388) | `EPW_IV_A/B/CHN` — the external-demand instrument is built on `s_rj` |
| `03c_shock_exogeneity.R` (L60) | balance tests, **Rotemberg weights and effective-shock counts**, AKM/AKM0, Conley, drop-oil battery |
| `03d_ipw_construction.R` | IPW treatment and its Rotemberg comparison |
| `06_panel_consolidation.R` | `df_estimation` (`delta_EPW`, plus carry `theta_r`) |
| `07_regression_inference.R`, `07b` | all tables |

**Unaffected:** the NCM→ISIC and CNAE→ISIC crosswalks, the compositing to 152
industry groups, and the shock vector `g_jt = delta_EXP_j / L_j,2010` (national
denominators, untouched). Only the regional shares move.

Note that the **effective-shock count will change**, since Rotemberg weights
depend on the shares. The current "≈2.4" figure quoted throughout the paper is
tied to the present construction and must be recomputed, not carried over.

### Decision needed

- **Option A (deadline-safe, now implemented in the paper).** Keep the current
  treatment as headline — all diagnostics (Rotemberg, balance, AKM) are built on
  it — but disclose the normalisation, state Equation (`eq:theta`), and report
  that the null is robust. This is what `main_anpec.tex` now does.
- **Option B (correct, December).** Rebuild `s_rj` with `L_r_all` as denominator,
  restore `tradable_emp_share` as the BHJ control, and re-run `03c`, `03d`, `07`
  end to end — Rotemberg weights, balance tests, Conley, AKM all change.

Do **not** do a halfway version that adds `theta_r` as a control while leaving
the treatment normalised within tradables; per the algebra above that does not
correct the mismeasurement and the paper should not claim it does.

---

## 2. `06_panel_consolidation.R` — carry `tradable_emp_share` into the panel

**Why:** `03_epw_construction.R` (lines ~608–612) builds

```r
tradable_emp_share = L_r_2010 / L_r_all
```

and saves it as `tradable_emp_share_2010_v7.rds`. `03c` and `03d` both read and
use it. But `df_estimation_v7.rds` does **not** contain it — verified, the panel
has only `manuf_share` — so any analysis built off that panel silently omits the
tradable-intensity control.

**File:** `06_panel_consolidation.R`, the `df <- df_raw |> left_join(...)` block
at lines ~98–118.

```r
tes <- readRDS("tradable_emp_share_2010_v7.rds") |>
  mutate(microregion_code = as.character(micro)) |>
  select(microregion_code, tradable_emp_share)

df <- df_raw |>
  left_join(
    controls |> select(microregion_code,
                       ln_pop, urban_share, educ_share,
                       ln_gdp_pc, manuf_share),
    by = "microregion_code"
  ) |>
  left_join(tes, by = "microregion_code") |>
  mutate(tradable_emp_share = replace_na(tradable_emp_share, 0)) |>
  select(
    microregion_code,
    any_of(c("state", "mesoregion_code", "mesoregion_name")),
    year,
    P_dalton, P_center,
    delta_P_dalton, delta_P_center,
    delta_EPW,
    P_dalton_2010, P_center_2010,
    ln_pop, urban_share, educ_share, ln_gdp_pc,
    manuf_share, tradable_emp_share          # <- added
  ) |>
  arrange(microregion_code, year)
```

Add a guard so this cannot regress:

```r
stopifnot("tradable_emp_share missing from estimation panel" =
            "tradable_emp_share" %in% names(df))
```

---

## 3. Resolve the 1,671 vs 1,668 discrepancy (decide, then be consistent)

`07_regression_inference.R` line 93 does

```r
manuf_share = replace_na(manuf_share, 0)
```

so the pipeline **zero-fills** the missing manufacturing share for microregion
13002 (AM, Médio Amazonas, no base-year tradable employment) and reports
**N = 1,671**. The ANPEC Table 3 **drops** those rows and reports **N = 1,668**.

Note that `manuf_share` for this unit is genuinely `0/0` — undefined, not zero —
so zero-filling is a convention, not a correction. Both choices are defensible;
what matters is picking one.

- **Recommended:** drop (current paper behaviour). A microregion with no
  tradable employment has no exposure share and no defined tradable
  composition, so it contributes nothing to identification.
- If you prefer to keep the pipeline's zero-fill, change the paper's Table 3
  and the §3 attrition sentence to N = 1,671 and say the value is imputed.

Either way, make `07_regression_inference.R` and the paper agree, and state the
rule once in the paper.

---

## 4. Optional: rename `manuf_share` to reflect what it measures

`manuf_share` is manufacturing employment as a fraction of **tradable**
employment (mean 0.637, max exactly 1.000), not of total formal employment.
The paper now labels it "Manuf. share of tradable emp." Renaming the variable to
`manuf_share_of_tradable` in `04_controls.R` and downstream would stop this
being misread again — including by future reviewers, who flagged the 0.637 mean
as implausible precisely because the name implies a different denominator.

Low priority, touches several files, purely cosmetic.

---

## Verified during this pass (no action needed)

- `s_rj` sums to **exactly 1.0** per microregion, enforced by `stopifnot` at
  `03_epw_construction.R` line ~591 and again in `03a_shares_common.R`.
  Independently confirmed by reconstructing `delta_EPW` from
  `exposure_shares_isic_v7.rds` × `sectoral_shocks_isic_v7.rds`:
  **correlation with the panel = 1.000000**, 152 industry groups, 557
  microregions.
- Estimation sample has **78 state×year fixed-effect cells**.
- Boom/bust RI *p*-values recomputed at B = 9,999: Dalton 0.715 / 0.865;
  center-emptying 0.437 / 0.335. The bust values replicate the previously
  reported 0.866 and 0.332 to within Monte Carlo error, which independently
  validates Table 3.

---

## ADDENDUM 2026-09-21 — from Packet L. Two items that cross packet boundaries.

Full detail and the numbers behind both: `RATIONALE_L.md`. Scripts: `packet_L/`.

### A. Item 1 (Bolsonaro scoring rule) is not just open — it is mislabelled in the data

The STATUS table above records item 1 as *"not done — out of scope"*. Packet L `[PL-44]`
found that it is worse than open: at the **canonical** rung the imputation is recorded as
if it were a real observation.

In `painel_ideologico_{presidencial,governador}_V3.rds`, PSL-2018 carries
`ideo = 0.8620139`. Verified against `bls9_estimates_partiespresidents_long.rds`:

| check | result |
|---|---|
| equals the BOLSONARO 2022 **candidate** estimate | **TRUE** |
| equals the PSL 2021 **party** score (0.8033588) | FALSE |
| the 2017 wave scores PSL at all | **FALSE** |
| labelled `ideo_source` | **`"onda"`** — own wave |

So a candidate score, applied to a party, from a wave four years after the election, is
flagged as a contemporaneous own-wave party score. Mechanism: `02_polarization_indices.R`
folds `ideologia_psl` into the ideology table, and packet I's `[I-3]` carry then runs over
the **already patched** table, so the patch is indistinguishable from a wave observation by
the time provenance is assigned.

Scale: **46.01%** of the 2018 presidential vote, **2.92%** of the 2018 governor vote. Of the
96.13% that packet I reports as `"onda"` for presidential 2018, ~46 points are this.

**Consequence for reported numbers:** no coverage verdict changes (the cell is scored either
way). What changes is what the provenance columns mean — `[I-3]`'s carried shares (3.24 pp,
presidential 2018) exclude the largest imputed cell in the panel.

**Fix (belongs in packet I's numbering, not Packet L's):** run the carry against the
*unpatched* `ideologia` and give the cell its own source value, e.g. `"patch_candidato"`, so
it is visible downstream. Do not modify `02_polarization_indices.R`.

**Sensitivity already measured** (`packet_L/02c_sensitivity_levels.R`,
`output/packet_L/tab_pl40_*.csv`): dropping the cell moves presidential 2018 `y_bar` from
**+0.083 to −0.450** and `P_dalton` from **0.641 to 0.350**. Using the PSL *party* score
instead of the candidate score moves little (+0.059 / 0.617). A break-even sweep of the cell
over [−1, 1] leaves the **baseline OLS** `delta_EPW` coefficient insignificant throughout
(p never below 0.21) — reconstruction validated against `df_estimation_v7.rds` at
`max |diff| = 0`. **Only the baseline OLS was swept**; IV/AKM, boom/bust and winsorised
specifications have *not* been tested against this cell, and with 46% of the year imputed
they should be.

### B. Two silent data-loading failures that affect the whole pipeline

Both return an EMPTY result with NO error. Diagnosed in Packet L; not fixed outside it.

**`[PL-28]` — the TSE CDN now rejects `electionsBR`.** `electionsBR:::download_unzip()` sends
no browser headers; the TSE Akamai edge answers **HTTP 403** with a 492-byte HTML page.
electionsBR writes that page to the `.zip` path, `unzip()` fails with a mere **warning**, and
`elections_tse()` returns a 0×0 tibble. `Accept-Encoding` is the discriminating header — with
the full browser set the CDN returns 200; dropping it alone returns 403.

> **`01_extraction.R` BLOCK C calls `elections_tse()` the same way.** Re-running it today
> would silently rebuild the presidential and governor vote panels as **empty frames**. It
> has no emptiness guard. This is the highest-priority item in this addendum.

Working fix, ready to lift from `packet_L/01b_extraction_legislativo.R`: pre-seed `tempdir()`
with an archive fetched with browser headers. `download_unzip()` skips its own download when
the file exists, so electionsBR still does all the parsing — only the transport is replaced.

**`[PL-29]` / `[PL-35]` — readr cannot do file I/O under `DATA_DIR`.** The path contains
non-ASCII characters (`dissertação`, `versão`, `vínculos`); macOS stores them in NFD while R's
string is partly NFC, and readr/vroom cannot resolve the mixture. Verified on a file that
demonstrably exists: `file.exists()` TRUE, `base::read.csv()` reads every row, and **every**
`readr::read_csv()` form fails — relative, `normalizePath()`, `file.path(getwd(),.)`,
`enc2utf8()`, `enc2native()`. `readr::write_csv()` creates a new file but **fails when one
already exists**. The same calls work in an ASCII directory.

Inside `electionsBR:::juntaDados()` this is compounded: every read is wrapped in
`tryCatch(..., error = function(e) NULL)`, so all reads return NULL and the function returns
0×0 without error.

> **13 scripts call readr readers with relative paths under this `DATA_DIR`**: `03`, `03a`,
> `03b`, `03d`, `07`, `07z`, `10`, and five in `packet_D`. All are exposed.

Workarounds used in Packet L: run electionsBR pulls from an ASCII scratch directory
(`with_ascii_wd()`), and route table I/O through base R (`write_csv_safe()`).
