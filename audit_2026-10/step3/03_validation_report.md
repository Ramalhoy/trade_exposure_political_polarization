# Step 3: Validation suite, results against thresholds fixed in advance

*18/10/2026. The thresholds come from `02_analysis_plan.md` §5 (commit `14fa296`) and amendment A1 (commit `3951dcc`, pushed before any gate ran). No headline coefficient has been estimated.*

*Scripts are in `audit_2026-10/step3/` and outputs in `step3/out/`. Every number below names its output file. Package versions and source commits are in `environment_manifest.txt`.*

## Summary

| Gate | S0 | S3_N2ex | Evidence |
|---|---|---|---|
| (a) Reconciliation to published totals | **FAIL** (shared) | **FAIL** (shared) | `gate_a_reconciliation.csv` |
| (b) Replication of Jones–Menéndez González–Owen and Costa–Garred–Pessoa | **NOT DONE** | **NOT DONE** | Amendment A1.1 |
| (c) Monte Carlo: size within [0.03, 0.07] | **FAIL** (0.078) | **FAIL** (0.185) | `gate_c_montecarlo.csv` |
| (c) Monte Carlo: bias at Δ below 0.1Δ | pass | pass | same |
| (c) P(EQ ∣ β = 0) ≥ 0.5 | **underpowered** (0.023) | **underpowered** (0.273) | same |
| (d) Falsification, 2002/2006 → 2010 | PASS | PASS (p = 0.090 / 0.085) | `gate_d_falsification.csv` |
| (e) Clean-room rebuild of the treatment | PASS (3.6e-15) | PASS (2.5e-14 relative) | `gate_e_s0_log.txt`, `gate_e_s3_log.txt` |
| A1.5 Reproduction of the BLS scaling | **FAIL** (one item: 0.0535 > 0.05) | same | `bls_scaling_repro.csv` |

**What the plan says this implies.** Both designs fail gate (c). Under the decision table (row 10), the abstract sentence is therefore: *"Neither design passes its pre-specified validation; no causal estimate is reported."* That holds unless you approve an amendment (Section 3). No headline has been run, so an amendment made now is still a pre-registered one.

## 1. Results by gate

### (a) Reconciliation

| Item | Pipeline | Published | Difference | Pass? |
|---|---|---|---|---|
| Comex exports 2010 / 2014 / 2018 | — | — | ≤ 4e-9 | ✓ |
| Comex exports 2022 | — | — | −0.098% | ✓ |
| RAIS 2010 active contracts on 31/12 | 44,068,355 | 44.068 million (MTE) | — | ✓ |
| President 2010, round 1, valid votes in Brazil | — | — | −0.064% | ✓ |
| President 2018, round 1, valid votes in Brazil | — | — | 0.000% | ✓ |
| Deputy 2014 | — | — | +0.095% | ✓ |
| Deputy 2018 | — | — | −0.083% | ✓ |
| **Deputy 2010** | **98,389,861** | **96,580,011** | **+1.874%** | **FAIL** |
| Deputy 2006 (raw TSE party file vs detalhe valid) | — | — | −0.164% | FAIL |

- **Not done:** president 2014 and 2022 (no figure for votes abroad); deputy 2022; governor in all years.
- **The likely cause of the 2010 failure** is in `01b_extraction_legislativo.R` (lines 221–237). For 2010 and 2014 it reads `QT_VOTOS_NOMINAIS`, and those files have no split into valid and sub-judice-annulled votes. The 2010 base year of the **primary outcome** therefore probably includes about 1.8 million votes that TSE annulled. Confirming this needs the raw TSE 2010 file.
- **Sources:** exports from IBGE *Anuário* table s7t4101 (Secex/Comex Stat). The TSE and RAIS totals come from secondary pages that reproduce the agency figures; the agency sites were unreachable from this workspace (proxy 403). Sources are recorded row by row in the CSV.

### (b) Replication: not done

Both papers build exposure shares from 2000 Census microdata (Jones et al. §4.1 and footnote 17), and Jones et al. build trade changes from 2000/2002 BACI. Neither input is in the folder: the BACI files start in 2007. A version using this pipeline would be a different estimand (A1.1), so nothing was approximated.

### (c) Monte Carlo

Setup: B = 9,999 permutations, 1,000 replications, residuals resampled by microregion within state.

| Design | Size at nominal 5% | Rejection at β = Δ | Rejection at β = 2Δ | sd(β̂) | P(EQ ∣ β = 0) |
|---|---|---|---|---|---|
| S0 | **0.078** | 0.275 | 0.634 | 0.030 | **0.023** |
| S3 | **0.185** | 0.510 | 0.883 | 0.030 | **0.273** |

Additional, not a gate (residuals held in place, shocks drawn at random): size is 0.050 for S0 and 0.058 for S3. The test is exact when the shocks really are a random draw. It over-rejects *conditional on the realised shocks*.

**Diagnostic** (`gate_c_diagnostic_log.txt`). The realised recentred treatment has a residual norm well below the permutation median:

| Design | Realised ‖x⊥‖² | Permutation median | Percentile of the realised value |
|---|---|---|---|
| S0 | 985.6 | 1,764.7 | 29th |
| S3 | 1,414.7 | 3,314.8 | 12th |

The permutation null for the *coefficient* is therefore too narrow for the shocks that actually occurred. This is a property of the test statistic, not a coding error:
- The in-place variant reaches nominal size.
- `fixest` reproduces the coefficient exactly (`check_fixest_log.txt`).
- `bartik.weight` reproduces the step 1 Rotemberg weights to 4e-16 (`check_rotemberg_bartikweight_log.txt`).

Power: with sd(β̂) ≈ 0.030 in both designs, **neither can show equivalence at Δ = 0.038**. This was declared before any headline was run.

### (d) Falsification

| Design | Pre-period | β | RI p | 95% set |
|---|---|---|---|---|
| S0 | 2002 → 2010 | −0.017 | 0.615 | [−0.124, 0.069] |
| S0 | 2006 → 2010 | −0.022 | 0.643 | [−0.298, 0.091] |
| S3 | 2002 → 2010 | +0.041 | 0.090 | [−0.013, 0.079] |
| S3 | 2006 → 2010 | +0.043 | 0.085 | [−0.010, 0.122] |

Both designs pass the pre-set rule (p ≥ 0.05). Note, though, that **S3's pre-period point estimates (0.041, 0.043) are larger than the equivalence bound Δ = 0.038**.

How the pre-period outcomes were built (`gate_d_build_log.txt`):
- They come from raw TSE files with verified SHA-256.
- A canary check reproduces the stored 2010 deputy Dalton index to 1e-16.
- Scored-vote coverage is 0.919 in 2002 and 0.879 in 2006, with the 11 BLS parties of 2001/2005.

### (e) Clean-room rebuild

The rebuild uses independent code and the raw extraction files: RAIS FTE, Comex NCM exports, Comex municipal exports for 2010, and the four BACI years.
- S0: shares, L_j and shocks all match the stored versions; the treatment matches to 3.6e-15.
- S3: all 18,609 share cells match exactly; the shocks match to 3e-15; the treatment matches to 2.5e-14 (relative).
- **Caveat:** the clean room reuses three pipeline decision tables as data: `ncm_isic_match_v7.rds` (including the manual overrides), `composite_map_v7.rds`, and the country-code maps in `D1_s_rd.rds`. The rebuild verifies the arithmetic, not those choices.
- Coefficient-level agreement is checked in step 4 (A1.4).

### A1.5 BLS scaling reproduction

The model is re-estimated from `BLS9_full` by alternating least squares (rjags is not available here):
- Correlation with the stored scores is ≥ 0.9995 in every wave.
- The largest gap is 0.0535 (PROS, 2021), just over the 0.05 threshold.
- The rule is applied as written: **the BLS bootstrap is not run**.

## 2. Infrastructure

- **R toolchain:** `fixest` 0.14.2, `ShiftShareSE`, `targets` 1.4.1, `bartik.weight` and `renv` 1.0.3. CRAN is blocked in this workspace, so the packages were built from GitHub sources (commits recorded).
- **No `renv.lock`:** a lockfile can't be produced without CRAN metadata. `environment_manifest.txt` is the substitute.
- **Git:** `git push` from your Mac fails (SSH host key). The branch was pushed instead through a git bundle from this workspace.

## 3. Decisions needed before step 4 (none taken)

1. **Gate (c).** Either:
   - (i) accept FAIL for both designs (decision row 10); or
   - (ii) approve amendment A2: replace the RI statistic with a studentized one (the coefficient divided by its AKM standard error in each permutation) and re-run gate (c) with the **same** thresholds before any headline.

   Option (ii) is a post-validation change, so the report would say so.
2. **Deputy 2010 base year.** Please provide the raw TSE 2010–2022 files (`detalhe_votacao_munzona` and `votacao_candidato_munzona`, with the annulment fields). They would let me rebuild the primary outcome on valid votes and finish gate (a).
3. **BLS bootstrap.** Either keep the rule (not run), or approve an rjags re-estimation if you can run rjags on your Mac.
4. **Equivalence.** At sd ≈ 0.030, the "informative null" rows of the decision table cannot be reached at Δ = 0.038. They become reachable only at the sensitivity bounds (0.059 or 0.162), which the plan already reports.
