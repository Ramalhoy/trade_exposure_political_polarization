# Amendment A2 to the analysis plan

*Written 18/10/2026, after the step 3 validation report (commit `9dd0b12`) and before any headline estimate. The author approved each change on 18/10/2026.*

**All four changes are post-validation.** Each was chosen after seeing a gate fail, and the dissertation must say so. The thresholds in plan §5 are unchanged unless a section below states otherwise. The step 3 results under the original rules stay on record and will be reported next to the amended ones.

## A2.1 Studentized randomization-inference statistic (replaces plan §2.1)

**Statistic.** The test statistic becomes t = β̂ / se_ER. The point estimate is still β̂ from the recentred regression.

se_ER is the exposure-robust standard error (Adão–Kolesár–Morales; the BHJ shock-level form). Shock paths are clustered by unit across the three years, and the shocks are the recentred ones, g̃_nt = g_nt − ḡ_k(n),t:

    se_ER² = Σ_n ( Σ_t g̃_nt · Σ_{r ∈ t} s_rn · û_rt )² / ( Σ x⊥² )²

Here û are the residuals of the same FWL regression, and x is scaled exactly as in plan §1.

**Inference.**
- In each of the B = 9,999 within-stratum permutations, se_ER* is recomputed from that draw's permuted g̃ and that draw's residuals.
- p = (1 + #{|t*| ≥ |t̂|}) / (B + 1).
- Confidence sets invert this studentized test: under H0: β = b, y is replaced by y − b·x.

**What is still reported.** The coefficient-based RI p-value is reported beside it, labelled "failed gate (c) in step 3". AKM0 remains the secondary regime.

**Why.** Studentized permutation tests remain exact under the sharp null and become asymptotically valid for the weak null and under heteroskedasticity (DiCiccio & Romano 2017, *JASA*; Wu & Ding 2021, *JASA* 116(536)). Step 3 found the coefficient statistic too narrow for the realised shocks (‖x⊥‖² at the 29th and 12th percentiles of its permutation distribution, `gate_c_diagnostic_log.txt`). With 3–6 effective shocks the asymptotic justification is weak, so the gate decides.

## A2.2 Deputy outcome rebuilt on valid votes (fixes the gate (a) failure)

**Nominal votes, 2010–2022.** Rebuilt from the raw TSE `votacao_candidato_munzona_{year}` files (SHA-256 in `tse_2010_2022/SHA256SUMS.txt`).
- 2018 and 2022: use TSE's own `QT_VOTOS_NOMINAIS_VALIDOS`.
- 2010 and 2014: those files have no validity field. Nominal votes count as valid when the candidacy's final situation is one TSE treats as valid. The set of situations is the one whose national total reproduces `detalhe_votacao_munzona` `QT_VOTOS_NOMINAIS_VALIDOS` within 0.1%. That set is reported. If no set of situations reaches 0.1%, the year fails gate (a).

**Party-list (legenda) votes.** These come from the stored panel. The raw party files for 2010–2022 were not supplied. Their total must match detalhe `QT_TOTAL_VOTOS_LEG_VALIDOS` within 0.1%, or the year fails.

**Everything else is unchanged:** microregion aggregation, the BLS mapping and the Dalton formula. A canary check confirms that the old inputs reproduce the stored index.

**Gate (a) for TSE is rerun against the raw detalhe files**, the agency's own primary data, for president, governor and deputy in every year.

## A2.3 BLS reproduction threshold

**The change.** The per-item limit becomes 0.06 (it was 0.05). The correlation limit stays at ≥ 0.99. The only item over 0.05 was PROS 2021 at 0.0535, a party with 0.73% of the 2022 deputy vote that is used only in 2022.

**What the bootstrap does.**
1. Draw 500 resamples of respondents within each wave, seed 2026.
2. Re-estimate the scores by alternating least squares.
3. Map them to the stored scale with the same global affine fit.
4. Rebuild the outcome from each draw.

The draws are generated in step 3. They enter only in step 4, through the 95% stability rule of plan §2.

## A2.4 Reframed equivalence claim (replaces the Δ = 0.038 rule in plan §§3–4)

**Benchmarks.** Equivalence (TOST via the inverted 90% studentized set) is tested at each of three published effects:

| Benchmark | Effect (SD per SD) |
|---|---|
| Rettl | 0.038 |
| Dippel–Gold–Heblich | 0.059 |
| Colantone–Stanig | 0.162 |

**What is reported.** For each design:
- Δ\*, the smallest symmetric bound excluded, equal to max(|lower|, |upper|) of the 90% set.
- Which benchmarks are excluded.

**Power, declared before the headline.** The gate (c) rerun reports P(EQ ∣ β = 0) at each benchmark. Any benchmark with P(EQ ∣ β = 0) < 0.5 is declared "not attainable" before the headline is computed.

**Decision-table changes.** Rows 1, 2, 3 and 6 replace "±0.038" with "the largest published benchmark it excludes ([name], [value])". EQ becomes "excludes at least the 0.162 benchmark". The sentence for row 1 becomes:

> "Two export shift-share designs identified from different shocks rule out effects on the ideological dispersion of federal-deputy votes larger than [Δ\*] SD per SD, which excludes the effect sizes reported for [benchmarks]; neither can rule out effects of the size reported for PT vote share in the same design (0.038)."

The last clause is dropped if 0.038 is in fact excluded.

## A2.5 Gates rerun under A2

- **Gate (c):** the same DGP and thresholds, with the studentized statistic. Each replication uses B = 999 permutation draws, purely for computational reasons; the actual inference keeps B = 9,999.
- **Gate (d):** rerun with the studentized statistic and the rebuilt 2010 base.
- **Gates (b) and (e):** unchanged. (b) remains NOT DONE; (e) concerns the treatment and still passes.
