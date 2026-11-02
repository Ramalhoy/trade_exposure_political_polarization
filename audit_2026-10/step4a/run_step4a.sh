#!/bin/bash
# A4 rerun of step 4 (SS_THETA=design is the default in ss_core.R)
cd /home/claude/w
Rscript audit/step4_primary.R > audit/out/step4_primary_log.txt 2>&1
Rscript audit/step4_bls_stability.R > audit/out/step4_bls_stability_log.txt 2>&1 &
Rscript audit/step4_secondary.R > audit/out/step4_secondary_log.txt 2>&1
wait
Rscript audit/step4_speccurve.R > audit/out/step4_speccurve_log.txt 2>&1 &
Rscript audit/cleanroom/cr_beta.R > audit/out/step4_cleanroom_beta_log.txt 2>&1
Rscript audit/step4_leverage.R > audit/out/step4_leverage_log.txt 2>&1
wait
echo STEP4A_DONE
