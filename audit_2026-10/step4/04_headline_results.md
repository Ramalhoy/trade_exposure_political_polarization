# Step 4: Headline results under the plan (02) and amendments A1, A2, A2.1a, A3

*29/10/2026. Every estimate here was run after A3 was committed (`89f004e`) and after the governor repair was committed (`6eec898`). Scripts and outputs are in `step4/` (container paths `audit/…`). Every number names its file.*

## 0. Two problems found in step 4 that need your decision

**(i) The clean-room β fails for S3 under the literal plan text.**
- S0: clean room 0.03363505, audit 0.03363505, rel. diff −2.2e-15 → PASS.
- S3: clean room −0.02891754, audit −0.02595022, rel. diff +0.114 → FAIL (`step4_cleanroom_beta.csv`).
- The whole gap comes from one control. Plan §1 says "log(1+θ_dest)". The clean room read θ_dest as the sum of shares over the **201 destinations in the design**. The audited pipeline (and step 1, gates c and d) uses `theta_r_dest` from `E0_frame.rds`, which sums over **all destinations, entrepôts included**: for microregion 11001 (Porto Velho), 988.4 vs 666.6 (`E0_frame.rds` `theta_r_dest` vs row sums of its `W_n2ex`).
- With E0's definition the clean room matches to −8.9e-16 (row `S3_diag_theta_all`). Treatment, recentring, strata and sample all agree.
- So this is a spec ambiguity, not a coding error. Either reading needs an amendment, and it is made after seeing results:
  - (a) θ over all destinations (what the pipeline did). Amend the clean room; the headline stands as reported below.
  - (b) θ over the 201 design units (the BHJ "sum of shares of the shocks used"). Then the audited S3 headline is off-spec and must be rerun with that control. Its point estimate is −0.0289; its RI set and class have **not** been computed.
- Until you choose, S3 has **failed gate (e) as written**. Under the decision table that is row 9: the abstract would rest on S0 alone.

**(ii) Under AKM0, S3 cannot bound anything.** Its AKM0 set is (−∞, ∞) for every outcome (`step4_akm0.csv`). S0's AKM0 set is bounded: [−0.198, 0.103]. The plan makes AKM0 secondary, so it does not decide a claim. But S3's bounded RI set and its unbounded AKM0 set disagree, and §4 below shows why: 94% of S3's identifying variation sits in ten microregions.

## 1. Primary family: deputy ΔDalton, studentized RI, B = 9,999

Source: `step4_primary.csv`, `step4_primary_log.txt`.

| | S0 (149 units) | S3_N2ex (201 units) |
|---|---|---|
| β̂ (SD per SD) | 0.0336 | −0.0260 |
| AKM se | 0.0433 | 0.0346 |
| Studentized RI p | 0.6307 | 0.3154 |
| Holm-adjusted p | 0.6308 | 0.6308 |
| Coefficient RI p (failed gate c in step 3) | 0.3299 | 0.0607 |
| 90% set (bisection) | [−0.100, 0.239] | [−0.070, 0.047] |
| 95% set (bisection) | [−0.157, 0.280] | [−0.081, 0.096] |
| Grid check (0.002): is the acceptance region an interval? | yes, both levels | yes, both levels |
| Δ\* = smallest symmetric bound excluded | 0.239 | 0.070 |
| Excludes 0.038 / 0.059 / 0.162 | no / no / no | no / no / **yes** |
| Class | **INC** | **EQ** (excludes 0.162) |

- **Canary.** The studentized se equals `ShiftShareSE::reg_ss` "AKM" with a block-diagonal share matrix and `sector_cvar` = unit (S0 0.04331732 both; S3 0.03460515 both; `step4_akm0.csv`).
- **S0's set is asymmetric.** The upper end (0.239) is set by a few large oil and iron-ore shocks.

**Decision-table row 2** (S0 INC, S3 EQ), as amended by A2.4, *conditional on (i) resolving as (a)*:

> "The destination-demand design rules out effects on the ideological dispersion of federal-deputy votes larger than 0.070 SD per SD (90% randomization set [−0.070, 0.047]), which excludes the effect size reported for Brexit (Colantone & Stanig, 0.162) but not those reported for PT vote share (0.038) or the extreme right in Germany (0.059); the industry-export design is too imprecise to bound the effect ([−0.100, 0.239])."

If (i) resolves as (b), the S3 clause is undetermined until rerun. If the gate-(e) failure stands, the sentence becomes row 9 with S0 alone (INC).

## 2. BLS score uncertainty (plan §2.4, A2.3, A3.3.2)

500 bootstrap score draws, deputy Dalton rebuilt each time, classification recomputed with B = 999. The canary (stored scores reproduce `y_dep`) holds to 1e-10. Sources: `step4_bls_stability.csv`, `…_draws.csv`.

| | Class on stored scores (B = 999) | Share of draws with a different class | β̂ across draws, 5th–95th percentile | Row-4 rule (> 5%)? |
|---|---|---|---|---|
| S0 | INC | 0.006 | [0.025, 0.035] | no |
| S3 | EQ | 0.000 | [−0.026, −0.018] | no |

- **Two results are stable.** The classification holds across score uncertainty.
- **A labelled sensitivity gives the same result.** This version centres each draw on the stored score; it is not part of the rule.
- **The draws are shifted relative to the stored scores.** Draw-mean minus stored score ranges from −0.10 to +0.11 per party. For S0 the median β̂ across draws is 0.030, against 0.0336 on the stored scores.

## 3. Secondary family (BH, q = 0.05, 10 tests)

Source: `step4_secondary.csv`.

| Test | S0 β̂ (p) | S3 β̂ (p) |
|---|---|---|
| Deputy ΔER(α=1) | −0.025 (0.733) | 0.008 (0.805) |
| President Δȳ | 0.012 (0.796) | −0.000 (0.987) |
| Governor Δȳ (repaired) | −0.007 (0.756) | 0.010 (0.524) |
| Deputy Δȳ | −0.015 (0.616) | −0.007 (0.776) |
| Bust coefficient, H1b (**not validated**) | −0.012 (0.856) | 0.022 (0.473) |

- **BH:** the smallest q is 0.952. Nothing survives, so the abstract carries no secondary sentence.
- **H1b:** the predicted sign (b_bust > 0) appears only in S3, at p = 0.47. In S0, b_bust = −0.012 and b_boom = +0.027.
- **AKM0** (`step4_akm0.csv`): every secondary set for S0 contains 0 (p 0.46–0.61). Every S3 set is unbounded.

## 4. Leverage: the ten microregions carrying each design

Sources: `step4_leverage_top10.csv`, `step4_leverage_beta.csv`. "Share" is the share of Σ x⊥·x.

**Concentration.**
- S0's top 10 carry **57%**. S3's carry **94%**; its first two carry 49%.
- Without its top 10, each design's β̂ is −0.079 (S0 and S3 alike; n = 1,638). This is descriptive. For S3, −0.079 falls outside its own 90% set.

**S0** (oil and iron ore):

| Rank | Microregion | Share | What carries it |
|---|---|---|---|
| 1 | Japaratuba (SE) | 0.117 | Oil and gas extraction (CNAE 06000, 16.2% of FTE) |
| 2 | Coari (AM) | 0.117 | Oil and gas extraction (12.5%) |
| 3 | Parauapebas (PA) | 0.082 | Iron ore |
| 4 | Macaé (RJ) | 0.073 | Oil |
| 5 | Itabira (MG) | 0.063 | Iron ore |

Japaratuba and Coari record **no** Comex exports in 2010. Their exposure comes from oil employment, since the export shock is national.

**S3:**

| Rank | Microregion | Share | What carries it |
|---|---|---|---|
| 1 | Baía da Ilha Grande (RJ) | 0.289 | Angra dos Reis: 100% of exports, 99.5% of them crude oil (SH4 2709), shipped through the terminal there |
| 2 | Parauapebas (PA) | 0.198 | Iron ore, 2601 |
| 3 | Cametá (PA) | 0.114 | Abaetetuba: 98.7% live cattle (0102) |
| 4 | Ouro Preto (MG) | 0.094 | Iron ore |
| 5 | Paranaguá (PR) | 0.077 | The port: chicken, soy and meal |
| 6 | Guarapari (ES) | 0.065 | Anchieta: 99.5% iron ore pellets |

**What this means.** These are logistics locations, where exports are recorded at the terminal. That is the exporter-domicile problem the plan flagged for Paranaguá. Their treatment values reach −19.6 SD (Baía da Ilha Grande, 2018).

**Vote counts.** For all 18 distinct microregions, raw TSE detalhe 2010 deputy valid votes equal the stored panel exactly (`tse_vs_panel` = 0). Scored coverage ranges from 0.621 (Japaratuba) to 0.996.

## 5. Specification curve (descriptive; B = 999)

Source: `step4_speccurve.csv`. There are 256 points per design. The headline points reproduce §1.

| | β̂ range, deputy (128 points) | Share of points with p < 0.05 |
|---|---|---|
| S0 | [−0.113, 0.088] | 0 of 256 |
| S3 | [−0.036, 0.074] | 8 of 256 |

- **S0, deputy Dalton:** all 32 points are positive (0.009 to 0.088) and all have p ≥ 0.20. The headline (0.034) sits in the lower part: extended controls, no strata, or no recentring each move β̂ to about 0.05–0.07; the exporting-only sample moves it down (0.009 with base controls).
- **S3, deputy Dalton:** all 32 points are negative (−0.036 to −0.006), with p ≥ 0.16.
- **S3's eight p < 0.05 points** are all governor ER(1.4), uncentred, with β̂ ≈ 0.02. Recentring removes them.

## 6. What changed relative to step 3

Nothing in the gates changed, except that gate (e) is now evaluated on β̂ (A1.4/A3.3.6): S0 passes, and S3 fails pending decision (i).

The governor repair (A3.2) affects only the governor rows of §3 and §5. After the repair, all 27 states equal TSE detalhe at 0.00000% (`step4/out/repair_governor_2022_log.txt`).

## 7. Not done, and why

- **Gate (b)** (replication): NOT DONE, inputs missing (A1.1).
- **renv lockfile:** not possible. CRAN is unreachable from this workspace, so packages were built from GitHub with their commits recorded (`environment_manifest.txt`).
- **The S3 headline under θ over the 201 units:** not run, pending decision (i).
