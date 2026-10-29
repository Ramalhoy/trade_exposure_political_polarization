# Amendment A3: one-sided size rule, governor 2022 repair, step 4 execution details

*29/10/2026. Written after the step 3 rerun (commit `525516b`) and before any headline estimate. The author approved A3.1 and A3.2. A3.3 fixes execution details for step 4 that the plan left open.*

## A3.1 Gate (c) size criterion becomes one-sided (post-validation)

**The change.** A design passes gate (c) if its size at nominal 5% is ≤ 0.07 (it was in [0.03, 0.07]). The bias rule is unchanged.

**Why.** A conservative test is still valid: its size stays below the nominal level. Its cost is power, and power is reported anyway.

**What must be reported.** This is the second change made after seeing results (step 3b: S3 size 0.019, `step3b/out/gate_c_studentized_S3.csv`). The dissertation reports both the two-sided and the one-sided verdict for gate (c).

**Effect.** Under A3.1 both designs pass gate (c): S0 0.037, S3 0.019.

## A3.2 Governor 2022 repair

The rule: drop the votes of every 2022 governor candidate whose votes the TSE candidate file marks as anything other than valid, read from `NM_TIPO_DESTINACAO_VOTOS`; then rebuild the governor 2022 indices from the repaired panel.

**Pass condition.** After the repair, the panel's round-1 total in each state must equal detalhe `QT_VOTOS_NOMINAIS_VALIDOS` to within 0.1%.

**Scope.** Only the governor outcomes change (secondary Δȳ and the specification curve). The repaired file is written in the audit folder; the pipeline file is not overwritten.

## A3.3 Step 4 execution details

**1. Primary.**
- Statistic: studentized RI (A2.1/A2.1a) with B = 9,999. The seed and draws are those of step 3.
- Point estimate: the recentred β̂.
- 90% and 95% sets: inverted by bisection on each side (tolerance 0.0005). This assumes the acceptance region is an interval, and a 0.002-grid scan of ±0.4 checks that assumption.
- Holm across the two designs.
- Equivalence: at the three benchmarks (A2.4). Before the headline, only 0.162 was declared attainable (`03b`).

**2. BLS stability (plan §2.4 with A2.3).**
- For each of the 500 bootstrap score draws, the deputy Dalton index is rebuilt and the primary classification recomputed.
- To keep this computationally feasible, these draws use B = 999.
- The rule is unchanged: if the classification changes in more than 5% of draws, the design's sentence becomes the row-4 sentence.

**3. Secondary family (BH, q = 0.05, ten tests).**
- Deputy Esteban–Ray (α = 1) and Δȳ for president, governor (repaired) and deputy: studentized RI as for the primary.
- The **bust coefficient (H1b)**:
  - The boom and bust regressors are nonlinear in the shocks. They are recentred by their expectation over the permutation draws: μ = the mean of max(±z\*, 0) across the B draws (Borusyak & Hull 2023, simulated recentring).
  - The statistic is the bust coefficient divided by its microregion-clustered standard error, because the AKM formula does not cover a nonlinear regressor.
  - Gate (c) did not validate this statistic, and the result is labelled "not validated".

**4. AKM0.** `ShiftShareSE::reg_ss(method = "akm0")` on the stacked data with the stacked share matrix, so shocks are clustered by unit across years. Reported for primary and secondary outcomes.

**5. Specification curve.**
- The grid is plan §6. "Uncentred" means the raw z with the sum of shares × year as controls (S0: θ_r × year; S3: θ_dest × year).
- "Strata: none" means permutation and recentring across all units.
- The deputy coverage rule keeps a stacked row only if scored coverage is ≥ 0.85 in both 2010 and t.
- Esteban–Ray for all three offices is computed from the stored ideological panels, the same way `E0_frame.R` computed it for the president.
- Each point reports β̂ and the studentized RI p with B = 999. These points are descriptive only.

**6. Clean-room agreement (A1.4).** The clean-room script computes the recentring and β̂ independently (with `fixest`) from its own treatment. It must match the audited β̂ to 1e-8 (relative).

**7. Leverage.**
- The ten microregions with the largest share of Σ x⊥·x are listed per design.
- Each is inspected in the raw RAIS (top CNAE classes), Comex 2010 municipal exports (top municipality and SH4 lines) and TSE detalhe (valid deputy votes).
- β̂ is re-estimated without the ten, as a descriptive check.
