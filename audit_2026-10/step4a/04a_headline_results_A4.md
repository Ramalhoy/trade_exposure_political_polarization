# Step 4a: Headline results under amendment A4 (θ_dest over the 201 design destinations)

*02/11/2026. Every estimate here was run after A4 was committed (`34f06b1`). Scripts and outputs are in `step4a/` (container paths `audit/…`, outputs in `audit/out/`). The pre-A4 results stay on record in `step4/` (`faa2e34`); container copies are in `audit/out_preA4/`. Every number names its file.*

**A4 is a post-result change.** The pre-A4 S3 headline (β̂ −0.0260, class EQ) had been seen before θ_dest was redefined. The dissertation must say so, and it should report the pre-A4 number alongside (§6).

## 0. Gates under A4

| Gate | S0 | S3 | Source |
|---|---|---|---|
| (c) size, studentized | 0.03–0.07 band (unchanged, A3.1) | **0.018**: passes A3.1 (one-sided, ≤ 0.07); would fail the original two-sided band | `gate_c_stud_S3_log.txt` L2, L16 |
| (c) bias at 0.038 | unchanged | 0.0019 < 0.0038 → pass | same, L7, L16 |
| (c) power at 0.038 / 0.076 | unchanged | 0.091 / 0.257 | same, L7, L12 |
| (c) mean se vs sd(β̂) at 0 | unchanged | 0.0442 vs 0.0302 (se conservative) | same, L2 |
| (c) P(EQ \| β = 0) at 0.038 / 0.059 / 0.162 | unchanged | 0.001 / 0.042 / **0.706** → only 0.162 is attainable | same, L17–19 |
| (d) falsification | PASS | PASS | `gate_d_stud_log.txt` |
| (e) clean-room β̂, \|rel. diff\| ≤ 1e-8 | −2.2e-15 → **PASS** | −3.0e-15 → **PASS** | `step4_cleanroom_beta.csv` rows 1–2 |

- **The clean-room failure of step 4 is resolved.** Row 3 of `step4_cleanroom_beta.csv` (`S3_diag_theta_all`, θ over all destinations) now differs by −0.103. It is a diagnostic of the old definition, not a gate.
- **S3 passes every gate it is subject to.** Decision-table row 9 does not apply.

## 1. Primary family: deputy ΔDalton, studentized RI, B = 9,999

Source: `step4_primary.csv`, `step4_primary_log.txt`.

| | S0 (149 units) | S3_N2ex (201 units) |
|---|---|---|
| β̂ (SD per SD) | 0.0336 | **−0.0289** |
| AKM se | 0.0433 | 0.0358 |
| Studentized RI p | 0.6307 | 0.2962 |
| Holm-adjusted p | 0.6307 | 0.5924 |
| Coefficient RI p (failed gate c; not used) | 0.3299 | 0.0493 |
| 90% set (bisection) | [−0.100, 0.239] | **[−0.075, 0.045]** |
| 95% set (bisection) | [−0.157, 0.280] | [−0.088, 0.094] |
| Grid check (0.002): is the acceptance region an interval? | yes, both levels | yes, both levels |
| RI p at β = −0.162 / +0.162 | 0.0474 / 0.2448 | 0.0014 / 0.0191 |
| Δ\* = smallest symmetric bound excluded | 0.239 | 0.0746 |
| Excludes 0.038 / 0.059 / 0.162 | no / no / no | no / no / **yes** |
| Class | **INC** | **EQ** (excludes CS 0.162) |

- **S0 is unchanged to the last digit.** It does not use θ_dest.
- **S3's coefficient p of 0.0493 must not be quoted.** It is the statistic that failed gate (c) in step 3. The plan uses the studentized p (0.2962).
- **Canary.** The studentized se equals `ShiftShareSE::reg_ss` "AKM" (S3 0.03577379 in both `step4_primary.csv` and `step4_akm0.csv`).

**Decision-table row 2** (S0 INC, S3 EQ, as amended by A2.4). The sentence this licenses:

> "The destination-demand design rules out effects on the ideological dispersion of federal-deputy votes larger than 0.075 SD per SD (90% randomization set [−0.075, 0.045]). That excludes the effect size reported for Brexit (Colantone & Stanig, 0.162), but not those reported for PT vote share (0.038) or the extreme right in Germany (0.059). The industry-export design is too imprecise to bound the effect ([−0.100, 0.239])."

## 2. BLS score uncertainty

Source: `step4_bls_stability.csv`. 500 bootstrap score draws; classification recomputed with B = 999 on each draw.

| | Class | Share of draws with a different class | β̂ across draws, 5th–95th percentile | Row-4 rule (> 5%)? |
|---|---|---|---|---|
| S0 | INC | 0.006 | [0.025, 0.035] | no |
| S3 | EQ | 0.000 | [−0.029, −0.021] | no |

The centred sensitivity gives the same classes (`step4_bls_stability.csv` rows 3–4). As before, the draws are shifted relative to the stored scores: S3's median across draws is −0.024, against −0.029 on the stored scores.

## 3. Secondary family (BH, q = 0.05, 10 tests) and AKM0

Source: `step4_secondary.csv`, `step4_akm0.csv`.

| Test | S0 β̂ (p) | S3 β̂ (p), A4 | S3 p, pre-A4 |
|---|---|---|---|
| Deputy ΔER(α=1) | −0.025 (0.733) | 0.007 (0.832) | 0.805 |
| President Δȳ | 0.012 (0.796) | −0.001 (0.970) | 0.987 |
| Governor Δȳ (repaired) | −0.007 (0.756) | 0.010 (0.512) | 0.524 |
| Deputy Δȳ | −0.015 (0.616) | −0.006 (0.808) | 0.776 |
| Bust coefficient, H1b (**not validated**) | −0.012 (0.856) | 0.022 (0.502) | 0.473 |

- **BH:** the smallest q is 0.952. Nothing survives, so the abstract carries no secondary sentence.
- **AKM0:** S0's sets are bounded and all contain 0 (deputy Dalton [−0.198, 0.103]). Every S3 set is still (−∞, ∞). This is unchanged from step 4.

## 4. Leverage

Source: `step4_leverage_top10.csv`, `step4_leverage_beta.csv`.

- **The ten highest-leverage microregions are the same as in step 4, with the same shares to three decimals.** A4 changes a control, not the treatment, and leverage is computed on the treatment residualised on that control. Order: Baía da Ilha Grande 0.289, Parauapebas 0.198, Cametá 0.114, Ouro Preto 0.094, Paranaguá 0.077, Guarapari 0.065, Itabira 0.044, Alto Araguaia 0.035, Lins 0.013, São Jerônimo 0.013.
- **The top 10 carry 94.1% of S3's leverage** and 57.4% of S0's.
- **Without its top 10, S3's β̂ is −0.092** (pre-A4: −0.079); S0's is −0.079. The S3 figure lies outside its own 90% set. This is descriptive, not a test. It says the S3 point estimate is set by a handful of terminal and port locations.
- **Every raw-data check in step 4 §4 carries over unchanged.** Those checks are RAIS composition, Comex municipality and SH4, and TSE votes equal to the panel; they do not depend on θ_dest.

## 5. Specification curve (descriptive; B = 999)

Source: `step4_speccurve.csv`. There are 256 points per design. The headline points reproduce §1 (S3 β̂ −0.02892, p 0.296 at B = 999).

| | β̂ range, all points | Points with p < 0.05 | Deputy Dalton (32 points) |
|---|---|---|---|
| S0 | [−0.112, 0.088] | 0 / 256 | all positive, 0.008 to 0.088, p ≥ 0.213 |
| S3 | [−0.039, 0.073] | 8 / 256 | all negative, −0.039 to −0.007, p ≥ 0.111 |

- **The same eight S3 points have p < 0.05 as before.** They are governor ER(1.4), uncentred, β̂ 0.019–0.022. Recentring removes them.
- **What changed versus step 4.**
  - The "exporting" sample is redefined (θ_dest > 0 under A4): 1,383 rows instead of 1,392 in the full-coverage version. Only points in that sample moved for S0 (max |Δβ̂| 0.0028); S0 full-sample points are identical.
  - S3 points move by at most 0.0046.

## 6. Pre-A4 vs A4, S3 headline

| | Pre-A4 (`out_preA4/step4_primary.csv`) | A4 (`out/step4_primary.csv`) |
|---|---|---|
| θ_dest | all destinations, entrepôts included | the 201 design destinations |
| β̂ | −0.0260 | −0.0289 |
| se | 0.0346 | 0.0358 |
| Studentized p / Holm | 0.3154 / 0.6308 | 0.2962 / 0.5924 |
| 90% set | [−0.070, 0.047] | [−0.075, 0.045] |
| Δ\* | 0.070 | 0.075 |
| Class | EQ (CS) | EQ (CS) |
| Clean room (gate e) | FAIL (0.114) | PASS (3e-15) |

**The substantive conclusion does not depend on the choice.** Both definitions give class EQ, and both exclude 0.162 but not 0.059. The bound moves from 0.070 to 0.075. I suggest the dissertation report A4 as the headline and give the pre-A4 bound in a footnote, saying the definition was fixed after the first run.

## 7. Caveats that carry into step 5

1. **Gate (c).** S3 passes under A3.1's one-sided size rule (0.018 ≤ 0.07), not under the original two-sided band. The test is conservative: the se overstates sd(β̂) by about 46%. That favours failing to reject, and makes EQ harder to reach, not easier.
2. **Only 0.162 is attainable.** Even at a true β of 0, S3's design could not have excluded 0.038 (P = 0.001) or 0.059 (P = 0.042). The non-exclusion of those two benchmarks is uninformative and must not be written as "consistent with" them.
3. **AKM0 cannot bound S3,** and 94% of S3's leverage sits in ten terminal or port microregions (the exporter-domicile issue). The EQ claim is a statement about the randomization distribution of destination shocks, conditional on those exposure shares.
4. **Not done:** gate (b), whose inputs are missing (A1.1), and the renv lockfile (CRAN is unreachable; `environment_manifest.txt` records the package commits instead).
