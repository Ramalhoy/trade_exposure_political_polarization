# Executor Packet D — Exogenous-Demand Shift-Share (two branches)

**Project:** Trade Exposure and Political Polarization: Evidence from the Brazilian Case
**Revised:** 2026-08-10, after `G4` and the data acquisition. Supersedes the 11:19 draft.
**Origins:**
- **Branch A (committee):** *"testar robustez por destino (destino × ano eleitoral), cada j seria um destino"* — the destination becomes the shock unit.
- **Branch B (ADH-style):** industry remains the shock unit; realised exports are replaced by rest-of-world demand.

**Audit tags:** `[D-*]`, logged in `RATIONALE_D.md`
**Conventions:** `set.seed(2026)`, `B = 9999`, `stopifnot()` gates at every stage
**Non-negotiable:** `00_epw_calculo_v7.R` is locked. Packet D is strictly additive — new scripts, new outputs, new tags. No existing table or figure is overwritten.

---

## D.0 — What the packet is for

Not "does the arc respecification help". That question is settled and the answer
is no: `G3` shows the arc change raises the effective shock count from 2.59 to
5.57 **and destroys shock balance in all six cells** (`RATIONALE_D.md` `[D-0-5]`,
`[D-2]`). Arc growth rates are mechanically related to base size and commodity
industries sit at a distinct point on that gradient, so the respecification
trades one identification problem for another.

The live question is:

> **Can an exogenous foreign-demand shock deliver the arc's effective-shock gain
> without the arc's balance failure?**

That is rung S2 below, and `[D-PRE-2]` is its pre-registered prediction.

The motivating diagnosis is `[D-0-6]`: the published shock
`g_jt = ΔEXP_jt / L_j,2010` is a **capital-intensity gradient**. Exports per
formal FTE in 2010 are 1.6 in agriculture, 1.6 in manufacturing and 23.1 in
mining; ISIC 0610 and 0710 employ 65,000 people between them and carry Rotemberg
weights around 0.6. Workforce balance fails on precisely the axis that separates
those industries. All of it is one fact.

### The ladder

Between the published baseline and the committee's design, **three things change
at once** — scale, exogeneity and unit. Running the destination design alone
would leave any movement unattributable. So each rung changes exactly one thing:

| rung | unit | shock content | scale | crosswalk | isolates | status |
|---|---|---|---|---|---|---|
| **S0** | industry | realised exports | level | yes | — | published |
| **S1** | industry | realised exports | arc % | yes | scale | built (`G3`) |
| **S2L** | industry | RoW demand | level | yes | exogeneity at fixed scale | **= IV-A / IV-B, in `03b`** |
| **S2** | industry | RoW demand, destination-weighted | arc % | yes | exogeneity | to build |
| **S3** | destination | RoW demand | arc % | **no** | unit + crosswalk | to build |

Deliverable: one table, RI p-values leading, AKM placebo rejection rate as a row.

**S2L already exists and has never been run here.** `03b_instrument_construction.R`
implements it as IV-A (pure world demand) and IV-B (predicted exports,
Costa–Garred–Pessoa form), plus IV-C (China only — the single-destination special
case of Branch A). Re-running it is step 0 of the execution order, because it
settles `[D-3a]` and provides the S2L rung for free.

**What S2 changes relative to S2L**, and must not be lost in implementation: S2L
is level-per-worker and aggregates to world totals. S2 is proportional and
destination-weighted. If a construction divides by `L_j,2010`, it has rebuilt
IV-A.

---

## D.1 — Notation

| Symbol | Meaning |
|---|---|
| *r* | microregion |
| *j* | ISIC Rev. 4 industry (152, post-composite) |
| *d* | destination country |
| *p* | HS6 product |
| *t* | election year ∈ {2014, 2018, 2022}; interval *t*−4 to *t* |
| `L_r,2010`, `L_j,2010` | 2010 formal employment, FTE (contract-months ÷ 12) |
| `X_rd,2010` | microregion *r*'s 2010 exports to destination *d* |
| `M_djt^{RoW−BR}` | *d*'s imports of *j* from all origins except Brazil |
| `arcΔ(·)` | midpoint growth rate, D.2 |

---

## D.2 — The arc-percentage operator

```
arcΔ(v_t, v_{t−4})  =  (v_t − v_{t−4}) / [ (v_t + v_{t−4}) / 2 ]
```

Bounded in [−2, +2]. Symmetric: doubling +2/3, halving −2/3. Second-order
approximation to the log difference near zero. Defined when either endpoint is
zero (entry +2, exit −2); undefined only when both are, in which case the unit
carries no 2010 exposure and is dropped by construction.

Törnqvist, Vartia & Vartia (1985) for the derivation; Davis, Haltiwanger & Schuh
(1996) for the convention. See D.10.

**Both endpoints must be in the same constant currency.** BACI ships current USD;
deflate with `cpi_us.rds` before differencing. A deflated numerator over a nominal
denominator breaks an arc rate silently.

---

## D.3 — Branch B: industry unit, foreign-demand shock

### D.3.1 Shares — unchanged

`s_rj,2010` are exactly the v7 employment shares, read from
`exposure_shares_isic_v7.rds`. Do not recompute. This is what makes S1/S2 clean
contrasts against S0 — the share matrix is byte-identical, so any difference is
attributable to the shock alone. `θ_r = Σ_j s_rj` enters as the sum-of-shares
control.

### D.3.2 Shock

```
ω_jd,2010  =  X_jd,2010^{BR} / Σ_d X_jd,2010^{BR}        [Σ_d ω_jd = 1]

Z_jt       =  Σ_d  ω_jd,2010 × arcΔ( M_djt^{RoW−BR} , M_dj,t−4^{RoW−BR} )
```

*The growth rate of foreign demand facing Brazilian industry j, weighted by where
Brazil actually sold that industry's output in 2010.* Dimensionless, bounded in
[−2, +2]. Brazil is excluded from every numerator, so Brazilian supply conditions
— pre-salt ramp-up, exchange-rate pass-through, domestic capacity, policy — do
not enter.

`ω_jd` comes from BACI's own Brazil rows (`i == 76`) at HS6, mapped through the
v7 crosswalk. Not from Comex, which is SH4 only.

**S2L** is IV-A / IV-B in `03b` and is taken from there rather than rebuilt.

### D.3.3 The crosswalk does not disappear here — say so

`M_djt` requires mapping BACI HS6 to ISIC Rev. 4: **the same crosswalk, applied to
a different dataset.** Branch B inherits crosswalk error and may inherit it
differently, since the composition of world trade within a category differs from
Brazil's.

Apply the **identical** crosswalk object `03b` replays — same vintage, composite
aggregation, producer-primacy rule, restrict-then-renormalise fix. **Never load
`cnae_isic_crosswalk 2.rds`; it is defective (`[D-0-2]`).** Any divergence between
the two applications is a bug, not a modelling choice.

This limitation is what Branch A is for.

### D.3.4 Optional: shock-level IV (S2-IV)

Because the endogenous object is the *shock*, not a region-level treatment, `Z_jt`
can legitimately instrument the realised arc shock at the industry level. This is
not the framing that was dropped — that one needed a region-level mediating
treatment that is not measured. Here the first stage is at the shock level, which
is what BHJ contemplate.

Criterion is pre-registered at `[D-PRE-3]` and is **randomization-inference based,
not F-based**. With 2.6–5.6 effective shocks, an F calibrated to nominal J = 152
overstates precision by the same mechanism that drives the AKM placebo to 21%.
Report the Montiel Olea–Pflueger effective F; do not gate on it.

---

## D.4 — Branch A: destination unit

### D.4.1 Shares

**Primary, crosswalk-free.** Comex `EXP_YYYY_MUN.csv` gives município × SH4 ×
destination × year. Aggregate to microregion on the **2010** IBGE territorial
division, drop the product dimension, fix 2010:

```
X_rd,2010  =  Σ_{m ∈ r} Σ_p  export value (m, p, d, 2010)
```

Two normalisations, both reported:

```
N2 (primary):   s_rd = X_rd,2010 / L_r,2010     θ_r = Σ_d s_rd   [incomplete; θ_r controlled]
N1 (robust):    s_rd = X_rd,2010 / Σ_d X_rd,2010                  [complete, sum to 1]
```

N2 is primary because it matches the paper's existing treatment of incomplete
shares and preserves the intensity margin. N1 is pure destination composition and
is closest to the committee's literal phrasing.

Note the internal consistency N2 buys: **shares carry economic magnitude, shocks
are scale-free.** That is exactly the division of labour argued for the arc
respecification — the economic weighting moved into `s_rd` where it belongs.

**Secondary, diagnostic bridge.** `s_rd = Σ_j s_rj,2010 × ω_jd,2010`. This
reintroduces the crosswalk and is **not** the crosswalk-free variant. Its only
purpose is to test the Comex municipality-attribution problem (D.7.1).

### D.4.2 Shock

```
ω_pd,2010^{BR}  =  share of Brazil's 2010 exports to d accounted for by product p

g_dt  =  Σ_p  ω_pd,2010^{BR} × arcΔ( M_dpt^{RoW−BR} , M_dp,t−4^{RoW−BR} )
```

*d*'s import growth from the rest of the world, restricted to the basket Brazil
sold to *d* in 2010. Baseline weights fixed at 2010, so no post-treatment
information enters. No HS→ISIC mapping anywhere in this branch.

**Take `ω_pd` from BACI's Brazil rows at HS6**, not from Comex at SH4 — cleaner,
and avoids a product-granularity mismatch. If SH4 is used instead, aggregate BACI
to HS4 for consistency and record the choice.

**Robustness variant:** unweighted total imports of *d*. Agreement means the shock
is a broad demand cycle; divergence means within-destination composition matters.

### D.4.3 Exposure and decomposition (both branches)

```
EPW_rt   =  Σ_u  s_ru · g_ut                 u ∈ {j} Branch B, {d} Branch A
EPW⁺_rt  =  Σ_u  s_ru · g_ut · 1{g_ut > 0}
EPW⁻_rt  =  Σ_u  s_ru · g_ut · 1{g_ut < 0}
```

**Apply the v7 sign convention.** `EPW⁻` retains its negative sign. Consult the
`RATIONALE.md` entry for the original sign correction before estimating, and
assert `EPW⁺ + EPW⁻ = EPW`.

---

## D.5 — Estimation and inference *(Phase 2 — not authorised in Phase 1)*

```
Δ Y_rt  =  β⁺ EPW⁺_rt  +  β⁻ EPW⁻_rt  +  γ θ_r  +  X_r,2010' δ  +  λ_t  +  ε_rt
```

Outcomes: Dalton, Esteban–Ray, centre-emptying, first-differenced. Controls
identical to the baseline. `θ_r` omitted under N1.

**None of these are IV specifications** except S2-IV, explicitly flagged. Every
rung is a reduced-form shift-share whose shifters differ in their claim to
exogeneity. State this in §3 and §6.

| Regime | Role | Detail |
|---|---|---|
| Randomization inference | **primary** | permute `g_ut` across units within year, `B = 9999` |
| AKM / AKM0 | secondary | shock unit = *j* or *d* |
| Mesoregion × year clustering | reference | as currently |
| Conley spatial HAC | reference | same cutoff ladder |

**RI blocking.** Branch A permutes across ~226 destinations. An unrestricted
permutation treats China and Paraguay as exchangeable, understating the null
variance in the direction that flatters the estimate. Report both unrestricted
and income-group-blocked p-values.

---

## D.6 — Diagnostics, every rung *(Phase 1 deliverable)*

1. **Rotemberg weights.** `α_u` per year; top-5 with sign; top-3 share; effective
   number `1 / Σ_u α_u²`.
2. **Effective-shock ladder.** One row across S0…S3. Benchmarks from
   `G3_rotemberg_concentration.csv`: **level 2.59, arc 5.57** (mean of yearly,
   both control sets). The manuscript's "between five and nine" is corrected to
   five to six by `[D-0-7]` — the output exists and the earlier "unsupported"
   flag was wrong.
3. **BHJ balance**, exposure-weighted, per cycle, on **both** characteristic sets:
   - trade: `commodity + log_exp2010` (the `G3` form)
   - workforce: `sh_loweduc + sh_white + sh_male + mean_lnwage` from
     `sector_chars.rds`, built 2026-08-10 (`[D-0-4]`)
   - destinations (Branch A): log GDP per capita, log distance, income group,
     commodity-importer indicator, China dummy, top-5-partner dummy, 2010 share
     of Brazil's exports
4. **The pre-registered predictions.** `[D-PRE-1]` 2022 trade balance;
   `[D-PRE-2]` workforce balance, at least 4 of 6 cells passing at S2/S3. Both
   are already logged and must not be edited after seeing results.
5. **Independence.** Correlate `EPW_rt` across all rungs. Benchmark
   `ρ(S0, S1) = 0.373` Pearson, 0.572 Spearman. If `ρ(S0, S3) > 0.9`, `[D-PRE-4]`
   reframes Branch A as a measurement check.
6. **China concentration.** Brazil's destination mix is concentrated on China, so
   `α_China` may dominate Branch A as iron ore dominates S0. Report either way.

---

## D.7 — Threats, disclosed in §3

**Branch A**

1. **Comex municipality attribution.** Exports are recorded against the exporting
   firm's declared município, not the production location. Trading companies and
   port municipalities absorb exports produced elsewhere. *Mitigation:* leave-out
   of the top-20 exporting municípios; exclusion of port microregions; the
   employment-imputed bridge.
2. **Entrepôt destinations.** Netherlands, Singapore, Hong Kong, UAE re-export;
   first destination ≠ final demand. *Mitigation:* robustness dropping them, with
   their 2010 value share reported.
3. **Shares are not independent of industry mix.** Quantify with D.6.5 rather than
   asserting independence.
4. **SH4 product detail in Comex.** Coarser than BACI's HS6. Affects `ω_pd` only
   if taken from Comex; D.4.2 recommends taking it from BACI instead.

**Branch B**

5. **Crosswalk error persists**, applied to foreign rather than Brazilian data.
6. **Price versus volume.** `M_djt` is a value series. For iron ore and crude
   petroleum, world import *values* move with world *prices*, which are not
   independent of Brazilian supply — Brazil and Australia together are a large
   share of the seaborne iron ore market. Excluding Brazil from the numerator
   removes Brazil's quantities but not Brazil's influence on the price at which
   everyone else's are valued. **Sharpest objection to Branch B; raise it in the
   text before a referee does.** *Partial mitigation:* a volume-based variant
   using BACI `q` for the top-10 industries by Rotemberg weight — same files, no
   extra download.

**Both**

7. **Exclusion restriction.** Rest-of-world demand reaches Brazilian voters
   through the exchange rate, federal fiscal revenue and the terms of trade,
   bypassing local labour markets entirely. Not testable within the design. State
   it plainly.
8. **HS vintage.** Fixed: HS07, release V202601. HS12 begins in 2012 and cannot
   cover the 2010 base year. Do not chain vintages.

---

## D.8 — Robustness battery *(Phase 2)*

- Ladder S0 → S1 → S2L → S2 → S3, all outcomes
- Branch A: N1 vs N2; Brazil-basket-weighted vs total-imports shock;
  leave-one-destination-out (China, USA, Argentina, Netherlands, top-5 jointly);
  entrepôt exclusion; port-microregion exclusion
- Branch B: S2 vs S2-IV; volume variant for top-10 Rotemberg industries;
  leave-one-industry-out (0710, 0610)
- Both: unrestricted vs blocked RI; trimming, winsorising, IHS on `EPW`

---

## D.9 — Execution order

**Phase 1 — instruments and diagnostics only. No outcome regression.**

0. **Rename `BACI_HS07_V202601/` → `baci/`; move the 14 unused year files out.**
   Do not edit `03b` — it must stay byte-comparable.
1. **Re-run `03b_instrument_construction.R`.** Produces S2L, the IV-A/IV-B
   first-stage F that settles `[D-3a]`, and Rotemberg weights for an exogenous
   *level* shock. — *gate: report before proceeding*
2. **Balance-test `z_A` and `z_B`** against `sector_chars.rds` and the `G3` trade
   form. Newly possible. — *gate: if they fail as badly as `g_jt`, stop; the
   packet premise is in question and `[D-PRE-2]` needs rewriting*
3. Build `m_dp_row` with Brazil excluded — *gate: assert Brazil absent; reconcile
   world totals within 1%*
4. Branch A shares; run the employment-imputed bridge — *gate: stop if
   `ρ < 0.5`*
5. Build `Z_jt` and `g_dt`; inspect distributions and top/bottom 20 units
6. Rotemberg and effective-shock counts across the full ladder
7. Balance tests, all three characteristic sets
8. Independence-correlation matrix — *gate: `[D-PRE-4]` at 0.9*

**Phase 2 — not authorised until Phase 1 is reviewed.** Estimation, full
inference ladder, robustness battery, write-up.

`sector_chars.rds` is **built** (2026-08-10) and is no longer a prerequisite.

---

## D.10 — References

**Arc-percentage / midpoint growth rate**

- Törnqvist, L., Vartia, P., & Vartia, Y. O. (1985). "How Should Relative Changes Be Measured?" *The American Statistician*, 39(1), 43–46.
- Davis, S. J., Haltiwanger, J. C., & Schuh, S. (1996). *Job Creation and Destruction*. MIT Press.
- Davis, S. J., & Haltiwanger, J. (1992). *Quarterly Journal of Economics*, 107(3), 819–863.
- Haltiwanger, J., Jarmin, R. S., & Miranda, J. (2013). "Who Creates Jobs?" *Review of Economics and Statistics*, 95(2), 347–361. — **the citation that does the argumentative work**: the small-firm job-creation finding is a regression-to-the-mean artefact of the base-year denominator, so the choice is substantive, not cosmetic.
- US Census Bureau, *Business Dynamics Statistics* methodology — the measure is the official BDS denominator.

**Shift-share identification**

- Borusyak, K., Hull, P., & Jaravel, X. (2022). *Review of Economic Studies*, 89(1), 181–213.
- Adão, R., Kolesár, M., & Morales, E. (2019). *Quarterly Journal of Economics*, 134(4), 1949–2010.
- Goldsmith-Pinkham, P., Sorkin, I., & Swift, H. (2020). *American Economic Review*, 110(8), 2586–2624. — Rotemberg weights.

**Weak-instrument criteria (S2-IV only)**

- Montiel Olea, J. L., & Pflueger, C. (2013). "A Robust Test for Weak Instruments." *Journal of Business & Economic Statistics*, 31(3), 358–369. — effective F, benchmark 23.1.
- Lee, D. S., McCrary, J., Moreira, M. J., & Porter, J. (2022). *American Economic Review*, 112(10), 3260–3290. — tF; F > 104.7 for a valid 5% t-test.

**Destination-based and foreign-demand shocks**

- Hummels, D., Jørgensen, R., Munch, J., & Xiang, C. (2014). *American Economic Review*, 104(6), 1597–1629. — **primary cite for Branch B**; the template for instrumenting realised trade with destination-specific world demand excluding the home country.
- Aghion, P., Bergeaud, A., Lequien, M., & Melitz, M. J. (2024). *Review of Economics and Statistics*, 106(3), 608–626. (NBER WP 24600.) — destination × product demand shocks with fixed baseline export weights; closest analogue to the `ω_pd,2010` construction.
- Brambilla, I., Lederman, D., & Porto, G. (2012). *American Economic Review*, 102(7), 3406–3438.
- Costa, F., Garred, J., & Pessoa, J. P. (2016). *Journal of International Economics*, 102, 50–69. — the Brazilian antecedent, and the form IV-B already implements. **The single-destination special case of Branch A** — say so explicitly in §2.
- Autor, D., Dorn, D., & Hanson, G. (2013). *American Economic Review*, 103(6), 2121–2168.
- Louzada, L. "Globalization and Political Preferences: Evidence from Brazil's China Shock." Working paper. — adjacent on outcome and setting; **verify the current version and its shock construction before citing.**

*Verify page numbers and years against published versions before entry into the `.bib`.*
