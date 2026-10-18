# Amendment A2.1a: the shock term in se_ER (clarification, before any studentized gate is run)

*18/10/2026. No studentized statistic has been computed on any outcome at this commit.*

**The problem.** A2.1 wrote the shock term of se_ER as the recentred shock g̃_nt. The published AKM (2019) estimator does something different: it uses X̃_nt, the coefficients from regressing the control-residualised treatment for year t on the shares. X̃ is recomputed in every permutation draw.

**The check.** On the 2014 cross-section of S3 with a placebo outcome:
- With X̃, the formula reproduces `ShiftShareSE::reg_ss(method = "akm")` exactly (0.295454 = 0.295454).
- With g̃ it does not (0.168928).

**The decision.** The statistic uses X̃, so it is the published AKM estimator, with shock paths clustered by unit across the three years. Nothing else in A2 changes.
