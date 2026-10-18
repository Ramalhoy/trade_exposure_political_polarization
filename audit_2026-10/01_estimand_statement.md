# Step 1: Estimand statement for S0 and S3_N2ex

*17/10/2026. The script `audit_2026-10/step1_estimand.R` uses base R and imports no project code. Its log is `step1_log.txt`, and `[Lnn]` below means a line of that log. Inputs: `exposure_shares_isic_v7.rds` (s_rj), `sectoral_shocks_isic_v7.rds` (g_jt), `D1_s_rd.rds` (s_rd, column `s_rd_n2`), `D3_g_dt.rds` (g_dt), and `df_estimation_v7.rds` / `E0_frame.rds` (controls and fixed-effect cells only). No new outcome regression was run.*

**Reproduction gate (passed).** Σ_j s_rj·g_jt reproduces the stored S0 treatment to 3.6e-15 [L2–3] and Table 3's moments (0.112 / 0.494 / −4.726 / 9.107) [L5]. The S3 rebuild matches `epw_S3_N2ex` to 3.6e-12 [L7]. The stored pooled Dalton coefficients reproduce to the 6th decimal: S0 0.000862, S3 0.001596 [L6, L8]. The shares are the incomplete (total-employment) version, and Σ_j s_rj equals `tradable_emp_share` [L4]. This contradicts `00_config.R`, which says `SHARE_DENOM <- "tradable"`. The tradable shares miss the stored treatment by 33 [L2].

## What β is

Both designs regress Δpolarisation on Σ_n s_rn·g_nt, pooling 2014/18/22 differences from 2010, with state×year fixed effects and base controls. Under the shocks view (BHJ), β̂ is numerically a shock-level regression. It has a causal reading only if three things hold:

1. The shocks are as-good-as-random given controls, with their year means removed.
2. There are many shocks, so no exposure weight s_n dominates.
3. Effects are linear in s·g.

β then estimates Σ π_rn·β_rn, a convex average of region×shock effects with π ∝ s_rn²·Var(g_n) (AKM). The cumulative shocks are serially correlated (0.60–0.85 for S0, 0.57–0.81 for S3) [L19, L117], and RI permutes whole shock paths. So the independent unit is the **industry or destination**, not the unit-year.

| | **S0** (industry, ΔEXP/L_j) | **S3_N2ex** (destination, RoW arc growth) |
|---|---|---|
| Shock units | 152 [L12] | 201 [L110] |
| Effective units, Rotemberg (pooled estimator, unit level) | **3.13** base / 3.01 ext [L13, L62] | **6.16** [L111] |
| Effective units, AKM estimand weights | 2.86 [L16] | 6.16 [L114] |
| Effective units, BHJ exposure weights 1/Σs_n² | 24.8 [L15] | 12.9 [L113] |
| Largest AKM weights π_n | oil 0610 **0.508**, iron ore 0710 **0.293**, soy 0.051 [L45–51] | CHN 0.249, VEN 0.220, IRN 0.169, RUS 0.131 [L143–149] |
| Negative Rotemberg mass | 0.7% [L14] | 11.6% [L112] |
| Effective microregions (leverage on Σx⊥x) | **9.0**; top-10 carry 0.827 [L162] | **8.9**; top-10 carry 0.882 [L163] |
| Share of residualised treatment variance that is μ_t·Σs (not shock variation) | 0.011 [L18] | **0.386** [L116] |

**Why S0 has three shocks and not 25.** Exposure is spread out: cattle and soy each hold about 10% of s_n [L52–58]. But the per-worker shock is a capital-intensity gradient. Oil's g reaches 53.6 and iron ore's −31.4, against a median |g| of 0.10–0.19 [L188–193]. The variance comes from two industries that each employ 0.4% of the exposure mass [L188–189].

**Who identifies S0** [L164–171; names from `municipios_ibge.rds`]: Japaratuba SE 0.235, Coari AM 0.160, Macaé RJ 0.113, Parauapebas PA 0.099, Itabira MG 0.080, Tomé-Açu PA 0.055, Itaguara MG 0.053. The bust regressor is mostly iron ore: 71.6% of ΣEPW⁻ [L194].

**Who identifies S3** [L176–183]: Alto Araguaia MT 0.188, Cametá PA 0.149, Parauapebas PA 0.137, Baía da Ilha Grande RJ 0.134, Ouro Preto MG 0.112, Paranaguá PR 0.059. Paranaguá is a port, which raises a domicile-of-exporter question for step 4. S3 is uncorrelated with S0 overall (ρ = 0.019) [L9], but two of the top-10 leverage regions are the same in both designs (Parauapebas, Itabira) [L196].

## Narrowest claims the data support

**S0.** Within a state and election, the ~9 microregions whose 2010 formal employment was in crude-petroleum extraction or iron-ore mining showed no detectable difference in the change of ideological dispersion from the rest of their state. That holds as Brazil's per-worker export value rose in oil (toward 2022) and fell in iron ore (in every cycle). The causal reading rests on two industry export paths. Both are realised Brazilian export values, which are not foreign demand, so their exogeneity is an assumption about two series, not a design-based guarantee. β is not an "average effect of trade exposure" across Brazil. It is not informative about agriculture or manufacturing, whose combined estimand weight is small (soy 0.051, sugar 0.043 [L45–51]).

**S3.** As specified, it does not yet identify a BHJ estimand. 38.6% of its residual treatment variation comes from (year-mean shock) × (exports per worker), which the pooled log(1+Θ) control doesn't absorb [L116]. Once recentred (Borusyak–Hull) or with Θ×year controlled linearly, the narrowest claim would be this: microregions whose 2010 exports went to destinations whose rest-of-world import demand grew or collapsed (mostly China, Venezuela, Iran, Russia) are compared within state-year. That comparison rests on about 6 effective destinations and about 9 effective microregions.

## Claims in the current PDF that exceed this

(PDF page numbers)

1. **Abstract and resumo:** "export and import performance". No import treatment is estimated anywhere in the PDF.
2. **p.36 and §4.1.1, pp.38–39:** "the causal effect of trade exposure"; "variation in international demand… not directly determined by any single microregion". In fact g_jt is realised Brazilian exports, 80% of the weight sits on oil and iron ore, and three regions (Japaratuba, Coari, Macaé) carry 51% of S0's leverage.
3. **p.40:** "β estimates the average effect of a unit increase in ΔEPW". It is a weighted average with ~3 effective industries and ~9 effective microregions.
4. **p.12 and p.21:** "exposed workers concentrated in agriculture and extraction"; the soy-in-Mato-Grosso vs textiles-in-Santa-Catarina contrast. Soy carries about 5% of the weight. The estimator barely uses that contrast.
5. **p.12:** "the shock is a contraction in external demand". The dominant 2022 shock is an oil export *expansion* (g = +53.6) [L188].
6. **p.45, "≈2.4 effective shocks":** reproduces only as the mean of three within-year counts under extended controls (2.43) [L160]. For the pooled estimator with path-preserving RI, the count is 3.0–3.1 (2.86 by AKM weights). The definition needs restating, not just the number.
7. **p.45 and p.52:** "Dalton null robust/invariant to the industry composition of the shock". Dropping oil or iron ore changes the estimand, and those leave-outs are judged by cluster t, which the PDF itself discounts.
8. **p.46:** "tight null"; **p.52:** "genuinely flat response" (from a non-rejected symmetry test). No equivalence bound has been tested, and a failure to reject isn't evidence of flatness. Steps 2 and 4 address this.
9. **p.54, Table 6:** bust heterogeneity reported with stars and without RI. The bust regressor is 72% iron ore [L194], so "manufacturing vs commodity" partly relabels "iron-ore regions vs not".
10. **p.38:** "176 matched industries". The share matrix has 152 [L12], consistent with pp.42 and 47.

**Confirmed as stated:** Table 3 moments [L5]; oil α = 0.66 in 2022 under extended controls (0.657) [L160]; the p.50 reading "undetectable at this resolution, not a demonstrated zero".

## Flags (not done from raw material in this step, and why)

- "Raw" here means the stored s_rj, g_jt, s_rd and g_dt objects. Checking them against RAIS, Comex and BACI is step 3(a).
- The balance-test p-values (p.44) and the first-stage/placebo figures in the 12/10 roadmap were not re-verified. None is used above.
- **Office.** The president, governor (`I11` reads `exposure_shares_isic_v7.rds`) and deputy panels share the same W, so the S0 weights above hold for all three. `07b_regression_governador.R`, however, reads `exposure_shares_common_v8.rds` and `df_estimation_gov_v1.rds`, and **neither file exists in the folder**. Table 5's provenance has to be settled in step 5.
- The `SHARE_DENOM` flag mismatch would make a fresh pipeline run produce a different treatment. It must be fixed or pinned before the clean-room rebuild in step 3(e).
