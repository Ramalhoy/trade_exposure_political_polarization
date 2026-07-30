# Export exposure and political polarization in Brazil
## Complete results report — presidential races, export treatment

**Run date:** 2026-07-25 · **Pipeline:** `02 → 03 → 03b → 03c → 04 → 06 → 07 → 08 → 09 → 10`
**Flags:** `SHARE_DENOM = "tradable"` · `RAIS_MEASURE = "fte"` · `WEIGHT_SCHEME = "share"` · RI `B = 9,999`, seed 2026
**Scope:** presidential outcomes, export treatment only. No import (IPW) channel, no gubernatorial track.

Every number below comes from this run. Machine-readable copies are in
`output/report_pres_exports/*.csv`; LaTeX tables ready to `\input{}` are in
`tables/rep_tab1…6*.tex`. Run logs are `output/{00_v7,03b_iv,03c_exogeneity,08_report,09_center}*.txt`.

---

## 0. Executive summary

1. **The pooled effect of export exposure on polarization is zero** under every
   inference regime, for both outcomes and both control sets. RI *p*-values range
   from 0.647 to 0.948; AKM0 confidence sets all contain zero.

2. **The design is underpowered, not informative about absence.** The effective
   number of shocks is **2.24–2.62** (mean 2.44) out of 152 industry groups: the
   single largest industry carries **58–65%** of the Rotemberg mass (Σ|α|) and the
   top three carry **75–86%** — iron ore (ISIC 0710) in 2014 and 2018, oil & gas
   (0610) in 2022. Cluster standard errors over-reject by **roughly sevenfold**
   (placebo rejection 0.357 and 0.334 against a nominal 0.05). Any cluster-SE
   *t*-statistic in this design has to be read against that.

3. **The one apparently significant result — the centre-emptying decomposition — is
   mechanical, and should not be reported as an effect.** The centre-emptying index
   is degenerate in two of the three stacked differences: in 2018 it takes *exactly
   one value* across all 558 microregions, so `ΔP^N = 1 − P^N₂₀₁₀` identically
   (R² = 1.00000); in 2022 R² on the 2010 baseline is 0.990. Conditioning on that
   baseline drives the bust coefficient from **−0.043 (p = 0.008) to −0.0001
   (p = 0.989)**. The same collapse occurs in the IV reduced form. Section 6 is the
   core of this report.

4. **The Dalton index is the trustworthy outcome** and it is cleanly null. Its
   baseline R² is small (0.006–0.201), its coefficients are invariant to
   conditioning on the baseline, and every inference regime agrees on zero.

5. **Only one of the three external-demand instruments is usable.** Cluster-robust
   first-stage F: `z^CHN` = 21.9, `z^A` = 4.3, `z^B` = 0.3. The China-demand
   instrument reproduces the same pattern as OLS, including the spurious
   centre-emptying result.

**Recommended framing for the conference paper.** Lead with the null on Dalton and
the effective-shock diagnostic as the substantive contribution: a well-executed
Bartik design on Brazilian export exposure cannot detect polarization effects
because commodity concentration leaves ~2.4 independent shocks. Report the
centre-emptying index as a measurement casualty with the diagnostic in Section 6,
rather than as a second result.

---

## 1. Sample

| Quantity | Value |
|---|---|
| Estimation panel | **1,671** rows = 557 microregions × 3 first differences |
| Estimation *N* | **1,668** after state×year singleton absorption (Distrito Federal, 3 obs) |
| State×year FE cells | 78 |
| Industry groups | 152 (export-bilateral ∩ RAIS tradable, composite-aggregated) |
| SD of raw ΔEPW | 1.866387 (scale anchor for boom/bust) |
| Missing values | none |

**Sample rule.** A microregion with zero base-year tradable employment has an
undefined tradable composition (0/0, not 0). Exactly one such unit exists — 13002,
Médio Amazonas (AM) — and it is dropped once, in `06`, with `07`/`03c` asserting
the rule rather than re-imposing it. This reconciles the code with the paper: the
panel is 1,671 and the regressions report 1,668.

**Ideology coverage** (share of presidential votes cast for parties without a BLS
score): 2010 = 0.28%, 2014 = 1.38%, 2018 = 3.87%, 2022 = 0.63%. Coverage is not a
concern on the presidential side.

---

## 2. Descriptive statistics

Estimation panel, raw units (`tables/rep_tab1_descriptives.tex`).

| Variable | N | Mean | SD | Min | p25 | Median | p75 | Max |
|---|---|---|---|---|---|---|---|---|
| Δ Dalton index | 1,671 | 0.2259 | 0.1409 | −0.0947 | 0.0720 | 0.2645 | 0.3323 | 0.5436 |
| Δ Centre-emptying index | 1,671 | 0.2181 | 0.1856 | −0.2393 | 0.0541 | 0.2180 | 0.3835 | 0.6133 |
| Δ EPW (Bartik) | 1,671 | 0.4662 | 1.8664 | −18.4227 | 0.0360 | 0.2134 | 0.6247 | 40.5680 |
| Dalton index, 2010 | 1,671 | 0.2732 | 0.0291 | 0.1667 | 0.2558 | 0.2833 | 0.2949 | 0.3091 |
| Centre-emptying index, 2010 | 1,671 | 0.6614 | 0.1297 | 0.3867 | 0.5582 | 0.6524 | 0.7709 | 0.9361 |
| Log GDP per capita | 1,671 | 16.2514 | 0.6529 | 14.8714 | 15.7057 | 16.3113 | 16.7114 | 18.1702 |
| Log population | 1,671 | 12.1256 | 0.9425 | 7.8747 | 11.5159 | 12.0656 | 12.6055 | 16.4405 |
| Urban share | 1,671 | 0.7205 | 0.1654 | 0.2234 | 0.5856 | 0.7279 | 0.8638 | 1.0000 |
| Education share | 1,671 | 0.2619 | 0.0891 | 0.0977 | 0.1920 | 0.2511 | 0.3178 | 0.5540 |
| Manuf. share of tradable emp. | 1,671 | 0.6425 | 0.2541 | 0.0000 | 0.4632 | 0.6992 | 0.8537 | 1.0000 |
| Tradable emp. share of total | 1,671 | 0.2502 | 0.1473 | 0.0024 | 0.1251 | 0.2473 | 0.3653 | 0.6812 |

Two naming points worth stating in the paper, because both have been misread
before: **`manuf_share_of_tradable`** is manufacturing over *tradable* employment
(hence the 0.64 mean, which would be implausible over total employment), and
**`tradable_emp_share`** is tradable over *total* formal employment (mean 0.25).
The first measures composition, the second intensity.

### Treatment by election year

| Year | N | Mean | SD | Min | p10 | Median | p90 | Max | % negative |
|---|---|---|---|---|---|---|---|---|---|
| 2014 | 557 | 0.1858 | 0.7285 | −8.268 | −0.0708 | 0.1383 | 0.7339 | 3.415 | 18.9 |
| 2018 | 557 | 0.2483 | 1.6002 | −18.423 | −0.1258 | 0.1216 | 1.1322 | 13.486 | 29.6 |
| 2022 | 557 | 0.9644 | 2.6451 | −11.881 | 0.0019 | 0.5161 | 2.2850 | 40.568 | 9.9 |

The treatment is strongly right-skewed and its dispersion grows over the period,
tracking the commodity cycle.

### Outcome levels — *read this before interpreting ΔP^N*

| Year | N | P_dalton mean | P_dalton SD | P_center mean | P_center SD | P_center distinct values |
|---|---|---|---|---|---|---|
| 2010 | 558 | 0.2730 | 0.0293 | 0.6618 | 0.1301 | 558 |
| 2014 | 558 | 0.3205 | 0.0553 | 0.6716 | 0.1628 | 558 |
| 2018 | 558 | 0.6411 | 0.0687 | **1.0000** | **0.0000** | **1** |
| 2022 | 558 | 0.5353 | 0.0462 | 0.9673 | 0.0155 | 558 |

Polarization rises sharply on both measures between 2014 and 2018 and falls back
somewhat in 2022 — the aggregate pattern the paper describes. But `P_center` has
**zero cross-sectional variance in 2018**. Section 6 explains why and what follows.

---

## 3. Pooled treatment: baseline OLS under every inference regime

`tables/rep_tab2_baseline.tex`. Outcomes, treatment and controls standardized on
the estimation sample; state×year fixed effects throughout; *N* = 1,668.

### ΔP^D (Dalton)

| | Baseline controls | Extended controls |
|---|---|---|
| β(ΔEPW) | 0.00401 | 0.00074 |
| SE meso×year (primary reference) | 0.00423 (p = 0.344) | 0.00502 (p = 0.883) |
| SE mesoregion pooled | 0.00534 (p = 0.454) | 0.00622 (p = 0.906) |
| SE Conley 250 km | 0.00586 (p = 0.494) | 0.00660 (p = 0.911) |
| SE Conley 500 km | 0.00620 (p = 0.518) | 0.00616 (p = 0.905) |
| SE AKM | 0.00298 (p = 0.178) | 0.00323 (p = 0.819) |
| **RI *p* (primary regime)** | **0.647** | **0.939** |
| AKM0 *p* | 0.226 | 0.818 |
| AKM0 95% set | [−0.0039, 0.0113] | [−0.0068, 0.0099] |
| Within R² | 0.1046 | 0.1449 |

### ΔP^N (centre-emptying)

| | Baseline controls | Extended controls |
|---|---|---|
| β(ΔEPW) | −0.00092 | −0.00227 |
| SE meso×year | 0.00803 (p = 0.908) | 0.00832 (p = 0.785) |
| SE mesoregion pooled | 0.01163 (p = 0.937) | 0.01224 (p = 0.853) |
| SE Conley 250 km | 0.01284 (p = 0.943) | 0.01275 (p = 0.859) |
| SE Conley 500 km | 0.01058 (p = 0.930) | 0.01011 (p = 0.823) |
| SE AKM | 0.01468 (p = 0.950) | 0.01638 (p = 0.890) |
| **RI *p*** | **0.948** | **0.867** |
| AKM0 *p* | 0.950 | 0.889 |
| AKM0 95% set | [−0.0375, 0.0376] | [−0.0512, 0.0341] |
| Within R² | 0.0557 | 0.0787 |

**The pooled null is unanimous.** Every regime, both outcomes, both control sets.

The variance estimators disagree in an informative direction. For ΔP^D the AKM
standard error (0.0030) is *smaller* than the meso×year cluster one (0.0042), yet
the AKM0 *p*-value (0.226) is much closer to significance than any cluster *p*
(0.34–0.52) and the AKM0 set is asymmetric about the point estimate
([−0.0039, 0.0113]). For ΔP^N the ordering reverses: AKM (0.0147) is nearly double
the cluster SE (0.0080). Both patterns are signatures of few effective shocks —
the point-identified AKM variance is not reliable here, and the AKM0 set, which
does not assume a strong first stage, is the one to quote.

---

## 4. Asymmetric boom/bust decomposition

`tables/rep_tab3_decomposition.tex`. ΔEPW⁺ = max(ΔEPW, 0) and ΔEPW⁻ = max(−ΔEPW, 0)
are both non-negative magnitudes, each divided by SD(ΔEPW). Proposition 1 predicts
β⁻ > 0 and β⁻ ≥ |β⁺|.

| Outcome | Controls | β boom (SE) | β bust (SE) | RI *p* boom | RI *p* bust | Within R² |
|---|---|---|---|---|---|---|
| ΔP^D | base | 0.00567 (0.00515) | 0.00090 (0.00946) | 0.595 | 0.973 | 0.105 |
| ΔP^D | extended | 0.00477 (0.00540) | 0.00995 (0.00863) | 0.638 | 0.704 | 0.145 |
| ΔP^N | base | −0.01597 (0.00865)* | **−0.04346 (0.01626)\*\*\*** | 0.441 | 0.426 | 0.060 |
| ΔP^N | extended | −0.02285 (0.00932)** | **−0.05225 (0.01594)\*\*\*** | 0.318 | 0.367 | 0.086 |

Stars are cluster *p*-values; **the RI *p*-values are the primary regime and none is
below 0.31.**

**Sign audit against Proposition 1.** Dalton: β⁻ > 0 in both control sets — the
predicted sign, but nowhere near significance, and β⁻ < |β⁺| under base controls so
the magnitude ordering fails. Centre-emptying: β⁻ < 0 in both — **the opposite of
the predicted sign**. The apparently strongest coefficients in the whole exercise
therefore contradict the theory they are meant to test, which is itself a signal
that they are not measuring what the label says. Section 6 shows they are not.

**Control-set discrepancy to fix in the paper.** `07`'s decomposition block uses
the *baseline* control set, while the paper's Table 3 prints the *extended* set.
The two differ materially for the headline cell (bust on ΔP^N: −0.043 vs −0.052),
and neither equals the −0.062 currently printed. Whichever is chosen, the code and
the table must be made to agree.

---

## 5. Shock-level diagnostics: why this design has little power

`tables/rep_tab4_diagnostics.tex`.

| Year | HHI(\|α\|) | Eff. # shocks | Top-1 share | Top-3 share | Balance F (p) | Negative α |
|---|---|---|---|---|---|---|
| 2014 | 0.3811 | **2.62** | 0.599 | 0.746 | 1.22 (0.298) | 67 |
| 2018 | 0.4054 | **2.47** | 0.584 | 0.862 | 1.23 (0.295) | 54 |
| 2022 | 0.4473 | **2.24** | 0.654 | 0.819 | **4.43 (0.013)** | 44 |

Mean effective shocks **2.44** across years, from 152 nominal industry groups.

**Dominant industries (Rotemberg α).** 2014: iron ore 0710 (0.608), then soya/
maize/other crops around 0.05–0.08. 2018: 0710 (0.594), oil & gas 0610 (0.250).
2022: 0610 (0.663), 0710 (0.105), refined petroleum 1920 (0.063). The design is
effectively two commodity shocks with a fringe.

**Shock balance.** Shocks are balanced on non-mechanical industry observables
(commodity dummy, log 2010 export level) in 2014 and 2018, but **not in 2022**
(F = 4.43, p = 0.013) — the commodity-boom year. The secondary specification that
includes Lⱼ terms rejects in all three years, but those terms are mechanically tied
to gⱼₜ = ΔEXPⱼ/Lⱼ and that test should not be read as evidence against exogeneity.

**Cluster SEs over-reject roughly sevenfold.** AKM placebo rejection at a 5%
nominal level, 4,999 draws: **0.357** (ΔP^D) and **0.334** (ΔP^N). This is the
single most important caveat for anyone reading a *t*-statistic in this literature,
and it is why RI and AKM0 are the primary and secondary regimes here rather than
robustness checks.

**Drop-robustness.** With ΔP^D, coefficients stay near zero throughout
(range −0.0091 to 0.0040). With ΔP^N the coefficient is *unstable*: baseline
−0.0009, dropping oil/gas and refining +0.0230 (t = 2.49), additionally dropping
construction materials +0.0264 (t = 2.83), drop-top-1%-Rotemberg +0.0095. The
treatment correlation with the baseline falls to 0.45–0.67 in these variants, so
they are genuinely different treatments — but a coefficient that moves from 0 to
+0.026 and flips sign relative to the decomposition is not a stable estimate.

**Pre-trends.** Adding top-4 export-share × year controls moves ΔP^D from 0.0040
(0.0042) to 0.0078 (0.0144) and ΔP^N from −0.0009 (0.0080) to 0.0293 (0.0239).
Neither is significant, and the standard errors roughly triple — those controls
absorb most of the identifying variation, which is what two effective shocks
implies.

---

## 6. The centre-emptying index is baseline-determined — the key finding

`tables/rep_tab6_centre_index.tex`, script `09_center_index_diagnostic.R`.

### 6.1 The mechanism

The index is

```
P^N[r,t] = 1 − (vote share to parties with BLS ideology in [−0.25, +0.25])
```

The BLS scale is symmetric on ≈[−1, 1], so this band is a correctly specified
centre. But **every microregion in a presidential election faces the same national
candidate menu.** P^N can therefore vary across space only through vote
*allocation*, and only if at least one party actually sits inside the band. Whether
the band is occupied at all is a national, year-level fact.

| Year | # parties in band | Parties in band | Centre vote share | Closest party outside |
|---|---|---|---|---|
| 2010 | 1 | PSDB | 0.3270 | PV (−0.267) |
| 2014 | 2 | PSDB, PV | 0.3461 | PSB (−0.428) |
| **2018** | **0** | **— none —** | **0.0000** | **PODE (+0.269)** |
| 2022 | 1 | MDB | 0.0418 | PDT (−0.356) |

In 2018 the entire scored field was polarized: PSL +0.862, PSDB +0.478, MDB +0.385,
PODE +0.269, PT −0.668, PDT −0.405, REDE −0.555, PSOL −0.898. **Not one party fell
inside the centre band**, and PODE missed it by 0.019. So the centre vote share is
exactly zero and `P^N = 1` in every microregion — the index took a single distinct
value across all 558 units.

### 6.2 The consequence

| Year | SD(ΔP^N) | **R² of ΔP^N on P^N₂₀₁₀** | R² of ΔP^D on P^D₂₀₁₀ |
|---|---|---|---|
| 2014 | 0.0798 | 0.0244 | 0.2012 |
| 2018 | 0.1298 | **1.00000** | 0.0060 |
| 2022 | 0.1206 | **0.9902** | 0.0000 |

For 2018, `ΔP^N = 1 − P^N₂₀₁₀` *identically*. For 2022 it is 0.990 of the way
there. With state×year fixed effects absorbing the year mean, regressing ΔP^N on
the treatment within those two stacks is — up to sign — regressing **−P^N₂₀₁₀** on
the treatment. That is a pure cross-sectional correlation between export exposure
and the 2010 political baseline, not an effect on a change.

### 6.3 Conditioning on the baseline destroys the result

The panel already carries `P_center_2010` and `06` labels it a pre-trend control,
but `07` never conditions on it.

| Outcome | Controls | 2010 baseline | β bust (SE) | p | β boom (SE) | Within R² |
|---|---|---|---|---|---|---|
| ΔP^N | base | no | −0.04346 (0.01626) | **0.008** | −0.01597 (0.00865) | 0.060 |
| ΔP^N | base | **yes** | **−0.00010 (0.00763)** | **0.989** | 0.00158 (0.00249) | 0.670 |
| ΔP^N | extended | no | −0.05225 (0.01594) | **0.001** | −0.02285 (0.00932) | 0.086 |
| ΔP^N | extended | **yes** | **−0.00859 (0.00734)** | **0.243** | −0.00617 (0.00330) | 0.676 |
| ΔP^D | base | no | 0.00090 (0.00946) | 0.924 | 0.00567 (0.00515) | 0.105 |
| ΔP^D | base | **yes** | 0.00118 (0.00950) | 0.902 | 0.00585 (0.00515) | 0.105 |
| ΔP^D | extended | no | 0.00995 (0.00863) | 0.250 | 0.00477 (0.00540) | 0.145 |
| ΔP^D | extended | **yes** | 0.01090 (0.00863) | 0.208 | 0.00538 (0.00537) | 0.146 |

The centre-emptying bust coefficient goes to **zero** (−0.0001, p = 0.989) and
within-R² leaps from 0.060 to 0.670: the 2010 baseline explains the outcome almost
completely, and once it is held fixed the treatment explains nothing. The Dalton
coefficients are untouched — the correct control behaviour, since its baseline R²
is small.

### 6.4 Which stack carries the result

Single-difference regressions, state fixed effects, mesoregion clusters:

| Stack | β bust (SE) | p | β boom (SE) |
|---|---|---|---|
| 2014 — *the only stack with genuine variation* | −0.0350 (0.0509) | **0.492** | 0.1600 (0.0643) |
| 2018 — degenerate (R² = 1.000) | −0.0425 (0.0174) | 0.016 | −0.0429 (0.0255) |
| 2022 — near-degenerate (R² = 0.990) | −0.0664 (0.0303) | 0.030 | −0.0217 (0.0106) |

The significance lives entirely in the two degenerate stacks. The one stack where
the index actually measures a change is null.

### 6.5 What to do

Three defensible options, in order of preference:

1. **Condition on the 2010 baseline** in every ΔP^N specification and report the
   null. Cheap, and the control is already in the panel.
2. **Restrict ΔP^N to stacks where the centre band is occupied** — effectively
   2010→2014 only — and be explicit that the measure is undefined when no
   centrist party runs.
3. **Re-specify the index** so it does not depend on a band being occupied: a
   continuous measure such as the vote-weighted share of mass within a distance of
   the national median, or a bimodality statistic.

What should *not* happen is reporting −0.062*** as an effect of trade exposure on
centre-emptying. In 2018 the centre did not empty *in any microregion because of
trade*; it was empty everywhere because no centrist candidate ran.

---

## 7. External-demand instruments

`tables/rep_tab5_iv.tex`. Instruments standardized; baseline controls and
state×year FE throughout; clusters meso×year. `03b` builds these and reports a
first stage but never estimates 2SLS — done here.

### First stage: ΔEPW ~ z

| Instrument | β (SE) | Cluster-robust F | Within R² |
|---|---|---|---|
| z^A (RoW demand) | 0.4287 (0.2068) | **4.30** | 0.188 |
| z^B (Brazil mix) | −0.0867 (0.1523) | **0.32** | 0.015 |
| z^CHN (China demand) | 0.6307 (0.1348) | **21.89** | 0.398 |

Only `z^CHN` clears conventional strength thresholds. `z^B` has essentially no
first stage, which is notable because it is the instrument that embeds Brazil's own
product mix and was expected to be the strongest — `03b`'s own log flags this. The
`03b` run also shows the industry-level first stage sign-flipping across years
(cor(EPW, EPW_IV) by year: z^A −0.20, −0.38, +0.77; z^CHN −0.24, +0.52, +0.77), so
pooled first-stage strength is masking year-level instability.

**Note on Kleibergen-Paap.** With one instrument, KP equals the cluster-robust
first-stage F (4.30 / 0.32 / 21.89). An earlier version of this report computed KP
from `fitstat()`'s default homoskedastic vcov, which returned 351 / 11.8 / 1029 —
inflated by one to two orders of magnitude. Any KP statistic in this design must be
computed under the same cluster structure used for inference.

### 2SLS and reduced form

| Instrument | Outcome | 2SLS β (SE) | p | Reduced form β (SE) | p | Reduced form + 2010 baseline | p |
|---|---|---|---|---|---|---|---|
| z^A | ΔP^D | 0.0069 (0.0089) | 0.437 | 0.0030 (0.0042) | 0.477 | 0.0034 (0.0042) | 0.414 |
| z^A | ΔP^N | −0.0572 (0.0384) | 0.138 | −0.0245 (0.0096) | **0.011** | **0.0032 (0.0035)** | **0.358** |
| z^B | ΔP^D | 0.0059 (0.0462) | 0.899 | −0.0005 (0.0040) | 0.898 | −0.0004 (0.0040) | 0.924 |
| z^B | ΔP^N | 0.1658 (0.2715) | 0.542 | −0.0144 (0.0106) | 0.176 | 0.0020 (0.0043) | 0.641 |
| z^CHN | ΔP^D | 0.0089 (0.0064) | 0.163 | 0.0056 (0.0041) | 0.170 | 0.0061 (0.0041) | 0.139 |
| z^CHN | ΔP^N | −0.0467 (0.0225) | **0.039** | −0.0294 (0.0101) | **0.004** | **0.0021 (0.0030)** | **0.477** |

Read the reduced form, not the 2SLS, for `z^A` and `z^B`: it is immune to
first-stage weakness. The pattern is exactly the OLS pattern — nothing on Dalton,
an apparently significant negative effect on centre-emptying that **vanishes the
moment the 2010 baseline enters** (z^CHN: −0.0294, p = 0.004 → +0.0021, p = 0.477).
The instrument does not rescue the centre-emptying result; it inherits the same
mechanical channel, which is strong confirmation that the channel is mechanical
rather than causal.

---

## 8. Reproducibility and caveats

**To reproduce**, from `códigos/`:

```bash
Rscript 02_polarization_indices.R && Rscript 03_epw_construction.R && Rscript 03b_instrument_construction.R && Rscript 03c_shock_exogeneity.R && Rscript 04_controls.R && Rscript 06_panel_consolidation.R && Rscript 07_regression_inference.R && Rscript 08_report_presidential_exports.R && Rscript 09_center_index_diagnostic.R && Rscript 10_report_tables_tex.R
```

`04` requires live IBGE SIDRA and BigQuery access; `03b` reads the four BACI HS07
files (~1 GB each). `08` takes ~17 minutes, almost all of it the RI loop. Total
wall time for the chain above was roughly 45 minutes on this machine.

**Verified during this run.** The rebuilt treatment is bit-identical to the previous
vintage on the 557 shared microregions (correlation 1, max absolute difference 0),
and the polarization indices are unchanged, so nothing in this report is driven by
the pipeline edits — only the sample rule and two added columns changed. The θ
identity `EPW_total = θ_r · EPW_tradable` holds exactly, and `Σⱼ s_rj = 1` to
machine precision under `SHARE_DENOM = "tradable"`.

**Known limitations, in the order a discussant will raise them.**

1. **Centre-emptying measure** — Section 6. The most serious issue.
2. **Effective shocks ≈ 2.4** — the null is uninformative about absence of effects.
   Say so explicitly rather than claiming evidence of no effect.
3. **2022 shock balance fails** (p = 0.013) in the commodity-boom year.
4. **Share normalization.** Shares are normalized within tradables, so the
   treatment measures shock per *tradable* worker and differences out
   cross-regional tradable intensity. The ADH/Rettl convention would use total
   formal employment. `SHARE_DENOM = "total"` implements it; switching moves the
   treatment (correlation 0.933) and requires re-running everything downstream,
   because Rotemberg weights and the 2.4 figure are functions of the shares.
5. **Bolsonaro scoring rule is still asymmetric.** In 2018 he receives a
   *candidate-level* BLS score (0.862, borrowed from the 2021 wave since BLS 8 has
   no entry for him); in 2022 he receives the *party-level* PL score (0.493). The
   same candidate moves 0.369 points left between stacks purely from a change of
   instrument type — a gap of 8.5 standard errors. This directly affects both
   outcome indices in the 2018 and 2022 stacks and is **not yet fixed** (item 1 of
   `CODE_CHANGES_TODO.md`). It should be resolved before the conference version.
6. **Import channel absent.** `07`'s joint block was correctly skipped this run
   because the `03a`/`03d` artifacts predate the share-convention stamping. If
   cor(EPW, IPW) is strongly negative, the export-only specification omits a
   correlated regressor.
7. **Common-base stacking** induces within-microregion correlation across the three
   differences; meso-pooled clustering is reported for this reason and changes
   nothing.
