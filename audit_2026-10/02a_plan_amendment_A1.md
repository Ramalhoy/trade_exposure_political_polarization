# Amendment A1 to the analysis plan (02_analysis_plan.md)

*Written 18/10/2026, before any validation gate or new estimate was run. It clarifies or replaces parts of the plan that turned out to be ambiguous or infeasible once the newly supplied inputs were inspected. It does not change the primary design, outcome, inference regime, multiplicity rule, equivalence bound or decision table.*

## A1.1 Gate (b) cannot be run as specified

Both target papers build exposure shares from **2000 Census microdata**:
- Jones, Menéndez González & Owen (draft dated 20/09/2026): §4.1 and footnote 17 (82 Census traded industries). Trade changes are measured from 2000/2002 with BACI.
- Costa, Garred & Pessoa (2016): Census 2000 and 2010 microdata.

Neither input is in the folder:
- There is no Census microdata.
- The BACI files in the folder start in 2007 (HS07 vintage).
- BigQuery and CEPII are unreachable from this workspace.

A version run "with this pipeline" would replace the base year (2010 for 2000/2002), the shares (RAIS formal employment for Census employment) and the shock (all destinations for China only). That is a different estimand, so the pre-set threshold (point estimate inside the published 95% CI) would not be meaningful. **Gate (b) is recorded as NOT DONE, missing inputs.** No approximate version is run.

## A1.2 Gate (d): how the pre-period outcomes are aligned

The plan did not say how two pre-period differences meet a three-year treatment. The alignment is fixed as follows:

- **Outcomes:** two cross-sections, ΔD_r(2002→2010) and ΔD_r(2006→2010), where D is the federal-deputy Dalton index.
- **Building D for 2002 and 2006:** raw TSE `votacao_partido_munzona_{2002,2006}`, round 1, votes = nominal + party-list votes, aggregated to IBGE-2010 microregions. Party scores come from the stored BLS estimates of the nearest preceding wave (2001 for 2002, 2005 for 2006). Labels are mapped by the same renaming rules as `party_crosswalk_bls.csv` (PFL→DEM, PPB/PP→PP, PPS→CID, PMDB→MDB, PL→PL, PC DO B→PCDOB). Unscored parties are dropped, as in 2010–2022.
- **Regressor:** z̄_r, the mean over t ∈ {2014, 2018, 2022} of the recentred treatment z̃_rt, standardised.
- **Model:** state fixed effects and base controls; the 3 DF rows absorbed as before.
- **Inference:** randomization inference with the same within-stratum permutations (B = 9,999).
- **Pass rule:** a design passes if p ≥ 0.05 in **both** pre-period tests. Any rejection fails that design. No multiplicity correction is applied, which makes the gate stricter.

## A1.3 Gate (c): data-generating process, stated exactly

- e_r = the microregion's triplet of residuals from regressing standardised deputy ΔDalton on base controls and state×year fixed effects. The treatment does not enter.
- Each replication resamples whole microregion triplets with replacement within state. This keeps the fixed-effect structure.
- y = β · z̃/sd(z̃) + e.
- 1,000 replications at each β ∈ {0, Δ = 0.038, 2Δ}.
- RI uses the same B = 9,999 permutation draws in every replication.
- **Additional, not a gate:** the same exercise with e held in place (not resampled) and the "true" shocks drawn from the permutation distribution.

## A1.4 Gate (e): scope in step 3

In step 3 the clean-room script rebuilds the treatment vectors (z, μ, z̃) for both designs from the extraction-level files, without importing project code:
- RAIS FTE by CNAE
- Comex NCM exports
- BACI
- The IBGE and UN crosswalks

They must agree with the audited pipeline's vectors to 1e-8. Agreement on the headline coefficient is checked in step 4, where both scripts compute it side by side.

## A1.5 New prerequisite: reproducing the BLS scaling

Before any bootstrap, the party scores must be rebuilt from `BLS9_full` (legislator-level placements). The reproduction passes if, in every wave from 2001 to 2021, the correlation with the stored scores is ≥ 0.99 and the largest absolute difference is ≤ 0.05 on the stored scale. If it fails, the bootstrap is not run and the 95% stability rule of plan §2.4 is reported as NOT DONE.

## A1.6 Gate (a): sources and concepts

- Official aggregates come from the publishing agency's own pages: MDIC/Comex Stat, TSE and MTE/RAIS.
- Exports are compared to the current revised official series.
- RAIS headcount (`rais_2010_micro.rds`) is compared to the official number of active employment contracts on 31/12/2010. FTE has no official counterpart, so it is reported but not gated.
- Any total that cannot be reached at an official source is marked NOT DONE.
