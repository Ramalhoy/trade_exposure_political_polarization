# Step 3, rerun under amendments A2 and A2.1a

*18/10/2026. A2 (commit `cadadb0`) and A2.1a (commit `e2b6879`) were pushed before any of these runs. No headline coefficient has been estimated. Outputs are in `step3b/out/`. The step 3 results under the original rules stay in `step3/` and remain part of the record.*

## Summary

| Gate | S0 | S3_N2ex | Evidence |
|---|---|---|---|
| (a) TSE totals vs raw TSE detalhe, primary outcome (deputy) | **PASS** | **PASS** | `gate_a_tse_primary.csv`, `deputy_party_check_log.txt` |
| (a) Governor 2022 (secondary outcome only) | FAIL (+0.180%) | same | `gate_a_tse_primary.csv` |
| (b) Replication | NOT DONE (A1.1) | NOT DONE | — |
| (c) Studentized RI: size in [0.03, 0.07] | **PASS** (0.037) | **FAIL, conservative** (0.019) | `gate_c_studentized_S{0,3}.csv` |
| (c) Bias at 0.038 below 0.0038 | pass (0.0009) | pass (0.0019) | same |
| (d) Studentized falsification, p ≥ 0.05 | **PASS** (0.813 / 0.879) | **PASS** (0.453 / 0.113) | `gate_d_studentized.csv` |
| (e) Clean-room treatment | PASS (unchanged) | PASS (unchanged) | `step3/out/gate_e_*` |
| A2.3 BLS reproduction (≤ 0.06) | **PASS** | same | `bls_scaling_repro_log.txt` |

## 1. Gate (a) against the raw TSE files

The step 3 failure for deputies in 2010 came from the secondary source, not from the data.

**Totals.** Measured against the agency's own `detalhe_votacao_munzona` files (nominal valid + party-list valid, round 1, Brazil only):
- **Deputy:** the stored panel matches exactly in 2010, 2014 and 2018, and is −0.023% in 2022.
- **President:** exact in 2014, 2018 and 2022. In 2010 it is −0.064%, and the gap equals the 64,698 in-transit votes (UF "VT"), which belong to no microregion.
- **Governor:** exact in 2010–2018.
- The published figure used in step 3 (96,580,011) does not match TSE's current raw release, which gives 98,389,861.

**Party level** (`deputy_party_check_log.txt`). In 2010 and 2014, nominal votes by party in the raw candidate files equal the stored panel exactly (largest difference 0, across 27 and 32 parties). The raw files hold only valid votes:
- 2010: deferred candidates 87.9M; deferred-with-appeal 1.45M.
- 2014: deferred 88.7M; deferred-with-appeal 0.49M; candidates rejected or withdrawn received 0.

Party-list totals equal detalhe in both years.

**What this means for A2.2.** The rebuild would reproduce the stored panel exactly, so the stored deputy panel stands. The 2018 and 2022 candidate files (8 GB uncompressed) were not extracted. Those years already reconcile at 0.000% and −0.023%, and they use TSE's own `QT_VOTOS_NOMINAIS_VALIDOS` (`01b_extraction_legislativo.R` lines 221–237).

**Governor 2022 (+0.180%).** In each of 11 states, the panel's excess equals detalhe's annulled-votes column exactly; Roraima alone accounts for 160,004. The panel therefore counts annulled governor votes. This affects only the secondary Δȳ-governor outcome. The fix, dropping annulled candidates using the 2022 candidate files, is required before step 4 if that outcome stays in the secondary family.

## 2. Gate (c), studentized

Studentized RI, B = 999 draws per replication, 1,000 replications.

| | S0 | S3 |
|---|---|---|
| Rejection at β = 0 (size) | **0.037** | **0.019** |
| Rejection at β = 0.038 | 0.115 | 0.097 |
| Rejection at β = 0.076 | 0.385 | 0.260 |
| sd(β̂) | 0.030–0.032 | 0.029–0.030 |
| Mean AKM standard error | 0.026 | 0.044 |
| P(EQ ∣ 0) at 0.038 / 0.059 / 0.162 | 0.003 / 0.085 / **0.930** | 0.001 / 0.040 / **0.712** |

**Size.** Studentizing fixes the over-rejection in both designs (step 3: 0.078 and 0.185). For S3 it overcorrects: the AKM standard error overstates the true spread by about 46% (0.044 vs 0.030), so the test is conservative. Size 0.019 lies outside the pre-set two-sided band.

**Equivalence benchmarks, declared before the headline (A2.4):**
- Only the Colantone–Stanig benchmark (0.162) is attainable, in both designs.
- Rettl (0.038) and Dippel–Gold–Heblich (0.059) are **not attainable**.
- The abstract can therefore at most say that the designs exclude effects of the size reported for Brexit (Colantone & Stanig 2018), and cannot rule out the smaller published effects.

## 3. Gate (d), studentized

| Design | Pre-period | β | AKM se | Studentized RI p | 95% set |
|---|---|---|---|---|---|
| S0 | 2002 → 2010 | −0.017 | 0.045 | 0.813 | [−0.211, 0.164] |
| S0 | 2006 → 2010 | −0.022 | 0.062 | 0.879 | [−0.389, 0.159] |
| S3 | 2002 → 2010 | +0.041 | 0.048 | 0.453 | [−0.181, 0.089] |
| S3 | 2006 → 2010 | +0.043 | 0.042 | 0.113 | [−0.014, 0.210] |

Both designs pass. S3's pre-period point estimates still exceed 0.038.

## 4. BLS (A2.3)

- **Reproduction:** passes the amended rule (largest gap 0.0535 ≤ 0.06; every correlation ≥ 0.9995). It still fails the original A1.5 rule, and both verdicts are reported.
- **Bootstrap:** 500 draws were generated (`bls_bootstrap_draws.rds`; respondents resampled within wave, seed 2026). The median bootstrap SD of the party scores is 0.0358, against a median stored Bayesian posterior SE of 0.0378. The two independent uncertainty measures agree. The draws enter in step 4.

## 5. What the plan now implies, and the decision left to the author

**S0** passes every gate that was run: (a) on the primary outcome, (c), (d) and (e). Gate (b) is recorded as not done under A1.1, not as a failure.

**S3** fails gate (c) because its test is **conservative**, not because it over-rejects. Under the decision table that is FAIL (row 9), so the abstract would report S0 alone and note S3's failed validation.

**A conservative test is still a valid test.** Its size stays below the nominal level. The two-sided band was written to catch both over-rejection and lost power, and the cost here is power: 0.26 at 2Δ, against 0.385 for S0.

**Options for S3:**
- (i) Keep the rule. S3 is reported but carries no inferential claim.
- (ii) Amend gate (c) to a one-sided criterion, size ≤ 0.07. This would be a second post-validation change, and the dissertation would have to report both gate versions.

That is the only open decision before step 4. The repair of governor 2022 is mechanical.
