# Step 2: Analysis plan (pre-registration)

*Drafted 17/10/2026, before any new treatment-effect estimate. It is committed to `Ramalhoy/trade_exposure_political_polarization` together with `input_manifest.sha256`, the SHA-256 of the 22 stored inputs. Any departure from this plan after the commit is labelled "deviation" in the text, with the commit that made it.*

## 0. Decisions already taken (author, 17/10/2026)

- **D1. Total-employment convention only.** The shares are s_rj = L_rj,2010 / L_r,2010^all for S0 and s_rd = X_rd,2010 / L_r,2010^all for S3. Any other construction counts as an error, not as a robustness variant. The `SHARE_DENOM` flag in `00_config.R` is set to `"total"` and the clean-room pipeline hard-codes it.
- **D2. Both designs are recentred (Borusyak & Hull 2023, *Econometrica* 91(6)).** Step 1 found that 38.6% of S3's residual treatment variance came from μ_t × Σs, not from shocks (`step1_log.txt` L116). The BHJ practical guide (*JEP* 2025) says the sum-of-shares control "needs to be interacted with period FEs" when shift means vary by period. Recentring on the RI assignment distribution nests that correction.

## 1. Primary question, design, outcome and office

**Question.** Does local exposure to export shocks change the ideological dispersion of the vote? This is H1.

**Primary outcome and office: Δ Dalton index of the federal-deputy vote**, from 2010 to t ∈ {2014, 2018, 2022}, built from `dalton_panel_deputado_federal.rds`. Outcome-only diagnostics (`step2_construct.R`, log `step2_construct_log.txt`) justify this choice. Within state-year, which is the variation the design uses, the R² of the Dalton index on the leading party's share and its square is:

| Office | 2010 | 2014 | 2018 | 2022 |
|---|---|---|---|---|
| Deputy | 0.18 | 0.06 | 0.02 | 0.12 |
| Governor | 0.45 | 0.35 | 0.39 | 0.25 |
| President | 0.53 | 0.59 | 0.72 | **0.96** |

In 2022 the presidential index is close to a transform of the winner's share. The deputy index is a dispersion measure.

The deputy outcome has a known weakness: scored-vote coverage is only 0.90 / 0.94 / 0.91 / 0.86 (same log). Coverage sensitivity therefore enters the specification curve.

**Designs.** Both are co-primary. Each counts only if it passes every gate in step 3.
- **S0:** Σ_j s_rj · g_jt, with g_jt = ΔEXP_jt / L_j,2010. There are 152 industry units, the canonical Rettl construction.
- **S3_N2ex:** Σ_d s_rd · g_dt, with g_dt the arc growth of rest-of-world-except-Brazil imports, by destination. There are 201 destination units, with entrepôts dropped.

**Estimating equation, the same for both designs:**

Δy_rt = α_s(r)t + β · z̃_rt / sd(z̃) + γ′X_r,2010 + ε_rt

- Sample: 1,671 rows, of which 1,668 remain after the three DF state-year singletons drop.
- Fixed effects: state×year.
- X (base controls): ln GDP pc and ln population. S0 also includes θ_r. S3 also includes log(1+θ_dest) and 1{θ_dest = 0}.
- Δy is standardised over the estimation sample.
- β is reported in SD of outcome per SD of the recentred treatment.

**Recentring.** z̃_rt = z_rt − μ_rt.
- μ_rt = E[z_rt] under the assignment process used for inference: shock paths permuted uniformly within strata.
- In closed form, μ_rt = Σ_k (Σ_{n∈k} s_rn) · ḡ_kt, where ḡ_kt is the unweighted mean of g_nt within stratum k. μ is invariant to the within-stratum permutations, so the RI recomputes only z.
- **Strata, S0:** ISIC Rev.4 section A (11 units), B (11), C (130).
- **Strata, S3:** World Bank region.
  - East Asia & Pacific + South Asia (36 units)
  - Europe & Central Asia + North America (53)
  - Latin America & Caribbean (35)
  - Middle East & North Africa (21)
  - Sub-Saharan Africa (46)
  - The 10 territories with no WB code (IOT, COK, NFK, PCN, WLF, S19 → EAP; FLK, MSR, ANT, AIA → LAC) are assigned by geography.
- **Exchangeability units.** Industries whose share columns are identical across all r are merged into one unit before permutation. 0510 and 0520 have identical L_j,2010, so the 1/n CNAE split must be checked in step 3. The merge list is fixed in step 3(a) and logged.

## 2. Inference regime

1. **Primary: design-based randomization inference.**
   - B = 9,999 within-stratum permutations of whole shock paths, applied jointly across 2014/18/22. Seed 2026.
   - Statistic: the recentred OLS coefficient. This is the Borusyak–Hull statistic whose Hodges–Lehmann estimator is β̂.
   - p-values are two-sided: (1 + #{|β*| ≥ |β̂|}) / (B + 1).
   - Confidence sets come from test inversion on Δy − b·z̃ over a grid of step 0.001 on [−0.30, 0.30], extended if the set hits a boundary. 95% sets are used for testing, and 90% sets for equivalence.
2. **Secondary: AKM0.** Use `ShiftShareSE::reg_ss(method = "akm0")` on z̃ with the same W and controls. Unbounded sets are reported as unbounded.
3. **Reference only:** mesoregion×year clustered SEs and Conley SEs (250/500 km). These never decide a claim.
4. **Uncertainty from ideology scores.** Party scores are re-estimated from bootstrap resamples of BLS legislator-level placements (500 draws), rebuilding the outcome each time. A claim stands only if its classification (Section 4) is the same in ≥ 95% of draws. **Blocked:** legislator-level BLS files are not in the folder, and Harvard Dataverse is unreachable from this workspace (proxy 403). See Section 7.

## 3. Multiplicity and the equivalence bound

**Primary family:** {S0, S3} × deputy Dalton, pooled β. That is two tests at most.
- **Rejection:** Holm at α = 0.05 on the RI p-values.
- **Equivalence (TOST):** a design is "EQ" if its 90% RI-inverted set lies inside [−Δ, +Δ]. Claiming the null for both designs is an intersection–union test, so no adjustment is needed.

**Secondary family, Benjamini–Hochberg at q = 0.05 across all of them.** Five per design, ten in total:
- Δ Esteban–Ray (α = 1) of the deputy vote
- The bust coefficient on deputy Dalton, from the β⁺/β⁻ decomposition: H1b, the asymmetry hypothesis
- Δȳ for president, governor and deputy: H2, direction

**Everything else is descriptive and makes no inferential claim:**
- President and governor Dalton
- Centre-emptying
- Esteban–Ray α = 1.4
- Year-specific slopes
- The Table 6 heterogeneity cuts

**Equivalence bound: Δ = 0.038 SD per SD.** This is the smallest published SD-per-SD effect among the trade-shock voting papers in the folder that report both SDs:

| Paper | Outcome | Effect | Where |
|---|---|---|---|
| Rettl (2025, HBS WP 25-038) | ΔPT vote share | **0.0378** | Table 1, col. 1. Same EPW design, scaling, country and unit |
| Dippel, Gold & Heblich (NBER) | Extreme-right vote share | 0.044 × 1.35 = 0.059 | Preferred spec, col. 6, standardised outcome; SD of exposure €1,350 |
| Colantone & Stanig (2018, *APSR*) | Leave share | 12.233 × 0.14 / 10.6 = 0.162 | Table 1, col. 1; shock SD 0.14, Leave SD 10.6 pp |

- Equivalence is also reported, as sensitivity, at Δ = 0.059 and 0.162.
- Excluded: Autor et al. (2020, *AER*) reports only interquartile scalings in the main text, so its SD conversion would be an approximation.
- Context only, not a bound: the Scheiring et al. (2024, *BJPS*) meta-analysis gives partial correlations of 0.058 (mean) and 0.016 (bias-adjusted, Table 4).
- Caveat stated in the text: all three anchors are directional vote-share outcomes, not dispersion.

## 4. Decision table: result → abstract sentence

Each design ends in one of five classes:
- **EQ:** 90% RI set ⊂ [−Δ, Δ]
- **POS / NEG:** Holm-adjusted RI p < 0.05, with that sign
- **INC:** neither EQ nor POS/NEG
- **FAIL:** a step 3 gate failed

Where a set is both inside ±Δ and excludes 0, the class is "EQ+sig" (row 3). Bracketed values are filled from the run; nothing else in the sentence changes.

| # | S0 | S3 | Abstract sentence |
|---|---|---|---|
| 1 | EQ | EQ | "In two export shift-share designs identified from different shocks (realised exports by industry, and foreign import demand by destination), the effect of export exposure on the ideological dispersion of federal-deputy votes is bounded within ±0.038 SD per SD (90% randomization sets [a, b] and [c, d]), which excludes the effect reported for PT vote share in the same design." |
| 2 | EQ | INC (or the reverse) | "The [EQ design] bounds the effect within ±0.038 SD per SD ([a, b]); the [INC design] is too imprecise to bound it ([c, d])." |
| 3 | EQ+sig | any non-FAIL | "The [design] detects a nonzero effect of [β] SD per SD ([a, b]), smaller than the smallest published comparable effect." The other design is then described by its own row-2/5 clause. |
| 4 | INC | INC | "Neither design can distinguish a zero effect from effects of the size published for comparable shocks ([a, b]; [c, d]); the null is uninformative." |
| 5 | POS/NEG | INC (or the reverse) | "Only the [design] detects an effect, [β] ([a, b]), identified from about [n] microregions dominated by [units]; the other design can neither confirm nor exclude it." |
| 6 | POS/NEG | EQ (or the reverse) | "The [design] estimates [β] ([a, b]), but the [other], identified from different shocks and places, excludes effects beyond ±0.038; the first estimate is not read as an effect of export exposure in general." |
| 7 | POS | POS (or NEG, NEG) | "Both designs find that export exposure [raises/lowers] dispersion: [β0] ([a, b]) and [β3] ([c, d])." |
| 8 | POS | NEG (or the reverse) | "The two designs give significant estimates of opposite sign; the answer depends on the design, and no claim is made." |
| 9 | FAIL | x (or the reverse) | The sentence uses only the passing design and adds: "The [failed design] does not pass its pre-specified validation ([gate]); see Chapter [k]." |
| 10 | FAIL | FAIL | "Neither design passes its pre-specified validation; no causal estimate is reported." |

- **Secondary results:** at most one abstract sentence, and only for results that survive BH. Each is labelled with its family.
- **BLS-bootstrap rule:** if a primary classification changes in more than 5% of draws, the sentence becomes the row-4 sentence for that design.

## 5. Validation gates (step 3), with thresholds fixed now

| Gate | Pass if |
|---|---|
| (a) Reconciliation | Comex national exports by year within 1% of the official MDIC total. RAIS 2010 formal employment within 0.5% of the official total. TSE valid votes by office-year within 0.1% of the TSE totals. Every number traced to a file. |
| (b) Replication | Jones–Menéndez González–Owen (export → PT share) and Costa–Garred–Pessoa (labour effects), rebuilt with this pipeline. The point estimate must fall inside the published 95% CI with the same sign. |
| (c) Monte Carlo | Real W, g, strata and controls; outcome = planted β·z̃ + residuals resampled by microregion; 1,000 replications. Size at nominal 5% must be in [0.03, 0.07] under β = 0. Mean bias at β = Δ must be < 0.1Δ. Power at β = Δ and P(EQ ∣ β = 0) are reported. If P(EQ ∣ β = 0) < 0.5, the design is declared underpowered for equivalence before the headline is run. |
| (d) Falsification | Δy from 2002 and 2006 to 2010 regressed on the same z̃ (the 2014/18/22 shock paths). The primary RI p must be ≥ 0.05 in both designs. Failure counts as FAIL for that design. |
| (e) Clean-room rebuild | An independent script, importing no project code, rebuilds the headline β for both designs from the raw files. Must agree to 1e-8 (relative). |

## 6. Specification curve (descriptive only, declared now)

The curve is the full grid of these choices, with share convention fixed at total and strata fixed:

| Choice | Options |
|---|---|
| Controls | base, extended |
| Centring | recentred, or uncentred with θ×year |
| Strata | primary, none |
| Sample | full; S3 exporting microregions only |
| Deputy coverage rule | none; cells ≥ 0.85 |
| Index | Dalton, Esteban–Ray 1.0, Esteban–Ray 1.4, centre-emptying |
| Office | deputy, governor, president |

The headline is not chosen from the curve.

**Top-10 leverage inspection.** The ten microregions with the largest share of Σ z̃⊥ z̃ in each design are checked in the raw RAIS, Comex/BACI and TSE records. This covers employment composition, exporter domicile (e.g. the Paranaguá port) and vote counts. The headline is reported with and without the ten as a descriptive check.

## 7. Software and inputs that are not yet available

**Software:** R with `targets` + `renv` (lockfile committed); `fixest`; `ShiftShareSE`; `bartik.weight` (from GitHub). There is no CRAN R port of `ssaggregate`. The shock-level aggregation is coded directly from BHJ (2022), and each figure is cross-checked against Stata `ssaggregate` only if you can run Stata.

**Missing from the folder, needed before step 3 can be completed (or each item is marked "not done"):**
- BLS legislator-level placements (Power & Zucco, Harvard Dataverse)
- TSE results for 2002/2006 and BLS waves 2001/2005, for gate (d)
- The Jones–Menéndez González–Owen and Costa–Garred–Pessoa papers with their estimation details, for gate (b)
- Official MDIC, RAIS and TSE totals, for gate (a). I can try to obtain these through web lookup.
