# Amendment A4: θ_dest is the sum of the design's own shares (S3)

*02/11/2026. Written after the step 4 report (commit `faa2e34`) and before any estimate under the new definition. The author approved this change on 02/11/2026. It is a **post-result change**: the step 4 headline for S3 had been seen, and the dissertation must say so.*

## A4.1 The definition

Plan §1 lists log(1+θ_dest) and 1{θ_dest = 0} among S3's base controls without defining θ_dest. From now on:

  θ_dest,r = Σ_{d ∈ design} s_rd

The sum runs over the 201 destinations of S3_N2ex, entrepôts excluded. It is the sum of shares of the shocks actually used (Borusyak, Hull & Jaravel 2022), and it is the definition the clean-room script (`cr_beta.R`) took from the plan text.

Until now the audited pipeline used `theta_r_dest` from `E0_frame.rds`. That variable sums over all 2010 destinations, entrepôts included: for 11001 (Porto Velho) it is 988.4, against 666.6 over the design's destinations. The two definitions also differ in 1{θ_dest = 0} for 3 microregions (9 stacked rows) whose 2010 exports go only to excluded destinations. Step 4 found the S3 clean-room β̂ differing by 11.4% (`step4_cleanroom_beta.csv`), all of it from this control.

## A4.2 What is rerun under A4

S0 does not use θ_dest and is unaffected. Its reruns serve only to reproduce earlier numbers, where both designs enter jointly (Holm, BH, BLS stability).

For S3:
- **Gate (c), studentized.** Same DGP, seeds and thresholds as A2.5/A3.1. The residual triplets come from the new controls.
- **Gate (d), studentized.** Same rules.
- **Step 4 in full**, as A3.3: primary, BLS stability, secondary family and AKM0, specification curve, clean-room β, and leverage.
- **Specification curve.** The uncentred variant's θ × year uses the same θ_dest. "S3-exporting microregions" means θ_dest > 0 under A4.1.

The step 3 and step 4 results under the old definition stay on record in `step3b/` and `step4/` (commit `faa2e34`). Everything under A4 is written to `step4a/`.

## A4.3 Rule if S3 fails a gate under A4

The decision table applies unchanged. If S3 fails gate (c) or (d) under the new controls, it is row 9 for S3.

## A4.4 Implementation

`ss_core.R` reads `SS_THETA`:
- `design` (the default from this commit) builds `Theta_log` = log(1+θ_dest) and `Theta_zero` = 1{θ_dest = 0} from the row sums of the S3 share matrix.
- `all` reproduces the pre-A4 controls from `E0_frame.rds`.
