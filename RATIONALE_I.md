# RATIONALE — Packet I

Change log for the I series: repair of the **ideology join** in
`02_polarization_indices.R:55`. Companion to `RATIONALE.md` and `RATIONALE_D.md`;
same protocol. One entry per audit tag; every number that reaches the manuscript
must trace to a script committed here and to an entry below.

**Standing protocol.** No console-only runs. Every estimation writes a run log to
`output/packet_I/`. CSVs carry full precision; rounding happens only at render.
Commit before and after any re-run so the diff is inspectable.

**`revision/` is LOCKED.** Packet I sources `revision/R00_setup.R` and reads
`revision/H2_baseline_repro.R` as the pattern for its canary. Nothing in
`revision/` is modified.

**Nothing is written to the manuscript by this packet.**

---

## Section 0 — the defect

`02_polarization_indices.R:55` joins the BLS ideology scores onto the vote panels
with a bare `left_join` on the party acronym:

```r
left_join(ideologia_psl, by = c("party" = "party.or.pres", "year" = "ano_eleicao"))
```

The BLS uses its own labels applied **retroactively** — the legend that is today
`MDB` is `MDB` in the 1990 wave too, when the TSE called it `PMDB` — so a raw
acronym join drops exactly the legends that were renamed, which in Brazil are
disproportionately the large ones. Measured ideology coverage of the first-round
vote before the repair:

| level | 2010 | 2014 | 2018 | 2022 |
|---|---|---|---|---|
| presidential | 99.72 | 98.62 | 96.13 | 99.37 |
| governor | 76.24 | 68.43 | **89.42** | 74.08 |

The governor 2018 figure on record elsewhere is 86.5%. Both are right: the gap is
exactly the `PSL-2018 ← BOLSONARO-2021` imputation that `02` performs
(`PSL` = 2.921 pp of the 2018 governor vote; 89.421 − 2.921 = 86.500). This packet
reports the coverage **with** the patch, because the patch is part of the live
baseline. Verified in `I5_denominator.R` (`I5_denominator_log.txt`).

### The ladder ([D-1] discipline: one change per rung)

| rung | change | |
|---|---|---|
| **V0** | baseline — the join exactly as `02` performs it today | |
| **V1** | + crosswalk | TSE sigla → BLS label, time-windowed |
| **V2** | + carry | adjacent-wave carry for parties unscored in their own wave |
| **V3** | + UNIÃO 2022 | by succession from DEM and PSL |

One rule is held fixed on **all four** rungs: the `PSL-2018 ← BOLSONARO-2021`
imputation already in `02`. It belongs to the baseline, so re-deriving it would
make V1/V2/V3 multi-change rungs. Under a pure carry rule PSL-2018 would instead
take the PSL *party* score of the 2021 wave, +0.803 rather than +0.862 — the same
class of question as PL-2022, and out of scope here for the same reason
(`P3` anomaly 5).

---

## Section 1 — execution

### [I-1] Canary: the published Table 3 reproduces under V0 — **PASS**

`packet_I/I1_canary.R`, in the pattern of `revision/H2_baseline_repro.R`, with one
addition H2 does not need. H2 moves nothing; Packet I moves the **outcome**, so
the canary also has to establish that the outcome can be rebuilt from the raw
vote panel without drift.

**Part A — the published table.** All 12 treatment coefficients and all 12
standard errors reproduce at three decimals, `N = 1,668` on every model.

One cell requires the correction already on the record at `RATIONALE_D.md`
`[D-69]`: `ΔP^N`, base controls, bust estimates **−0.04047594**, which the
manuscript prints as −0.041 through a double rounding (−0.0405 at 4 dp, then
−0.041 at 3 dp) where a direct round gives **−0.040**. `I1` evaluates against the
`[D-69]`-corrected table and reports both counts — 11 of 12 against the printed
table, 12 of 12 against the corrected one — so that this packet neither
re-flags a known manuscript defect as a reproduction failure nor quietly relaxes
its own criterion.

**Part B — the `02 → 06` rebuild.** Rebuilding the presidential index from the
raw vote panel under V0 and differencing against 2010 reproduces the canonical
artefacts exactly:

| check | value |
|---|---|
| `max abs(P^D_rebuilt − dalton_panel_presidencial)` | **0** |
| `max abs(P^N_rebuilt − dalton_panel_presidencial)` | **0** |
| `max abs(z(ΔP^D_rebuilt) − df_estimation_v7$delta_P_dalton)` | **0** |
| `max abs(z(ΔP^N_rebuilt) − df_estimation_v7$delta_P_center)` | **0** |
| `max abs(Σ_p v_rpt − 1)` over 2,232 cells | 2.22e-16 |

Exact zeros, not tolerances. This is what licenses `[I-7]` to re-execute the
`02 → 06 → 07` chain **in-script** for each rung instead of overwriting
`dalton_panel_presidencial.rds` and `df_estimation_v7.rds`. The canonical
artefacts remain the provenance of the published table — the same reason `[T-5]`
froze `ri_beta_distribution.rds`.

### [I-2] Crosswalk: `data/party_crosswalk.csv`

The versioned artefact lives at `códigos/data/party_crosswalk.csv` — inside the
git repository, because it is a hand-curated input, not a pipeline output, and
"versioned" has to mean something. Columns as specified:
`sigla_tse, vigencia_ini, vigencia_fim, rotulo_bls, data_renomeacao, fonte`.

**It covers all 48 siglas that appear in either panel, not only the renamed
ones.** Identity mappings and *decided non-matches* are written out as rows, so
the contract asserted in `I0_setup.R` can be the strong one: **every observed
(sigla, election year) resolves to exactly one crosswalk row**, and overlapping
or missing windows halt the run. A sigla with no BLS label is not an absence in
the artefact; it is a row whose `rotulo_bls` is empty and whose `fonte` records
the decision.

**Load-bearing vs documentary.** Only `vigencia_ini`/`vigencia_fim` enter the
join, and they are verified against the panels themselves. `data_renomeacao` and
`fonte` are documentary: a date imprecision cannot move a number. Where a
registration date and the data disagree, **the window follows the data** — `REDE`
appears in the 2014 governor panel (TO and AM, 0.097% of the national vote)
although the party was registered in Sep/2015, so its window opens in 2014 and
the discrepancy is recorded in `fonte`.

**Joins run on a normalised key** (`sigla_key()`: upper-case, accent-stripped,
whitespace-squished), so `PC do B` ≡ `PC DO B` and an NFC/NFD mismatch on `UNIÃO`
cannot silently break a join on this project's decomposed-UTF8 paths. Key
injectivity is asserted.

**The supplied list was not assumed complete.** `I2_crosswalk_scan.R` sweeps both
panels and lists every sigla unmatched under V0 ordered by national vote: **89
panel-year rows, 36 distinct siglas**, of which **22 sigla-years are above the
0.5% decision threshold**. Beyond the nine supplied cases (PMDB→MDB, PC do B→PCDOB,
REPUBLICANOS→REP, PRB→REP, SOLIDARIEDADE→SD, PR→PL, PPS→CID, PODEMOS/PTN→PODE,
PFL→DEM), the sweep found **eight further consequential siglas**, none of which is
a rename this packet could have guessed from the list:

| sigla | worst panel-year | disposition | why |
|---|---|---|---|
| NOVO | gov 2018, 5.41% | V2 carry | scored only in the 2021 wave |
| PATRIOTA / PATRI / PEN | gov 2022, 0.81% | **no score** | never scored in any BLS wave |
| PRTB | gov 2018, 0.80% | **no score** | never scored |
| DC / PSDC | gov 2018, 0.79% | **no score** | never scored |
| PROS | gov 2014, 0.75% | V2 carry | scored 2017 and 2021 only |
| PV | gov 2022, 0.65% | V2 carry | scored through 2017, absent from 2021 |
| PSC | pres 2014, 0.75% | V2 carry (2014); **no score** (2010) | scored 2017/2021 only, no adjacent wave for 2010 |
| PMN | gov 2010, 0.98% | **no score** | never scored |

**Assertion that kills the run** (`I2`, executed): no sigla above 0.5% of the
national vote in any panel-year may lack both a match and a recorded decision.
Result: **22 consequential sigla-years — 9 resolved at V1, 6 at V2, 2 at V3, 5
recorded as permanently unscorable — 0 without a decision.**

The five permanently unscorable ones (PATRIOTA, PRTB, DC, PMN, and PSC-2010) are
a **ceiling on what any crosswalk can achieve**: 2.4% of the 2018 governor vote is
cast for parties the BLS never measured. That is a data limit, not a bug, and it
is why governor coverage stops at ~98% rather than at 100%.

Coverage by rung (`I2_coverage_by_rung.csv`):

| level | year | V0 | V1 | V2 | V3 |
|---|---|---|---|---|---|
| governor | 2010 | 76.24 | **98.22** | 98.22 | 98.22 |
| governor | 2014 | 68.43 | 95.87 | **99.11** | 99.11 |
| governor | 2018 | 89.42 | 92.19 | **97.60** | 97.60 |
| governor | 2022 | 74.08 | 86.60 | 87.37 | **98.30** |
| presidential | 2010 | 99.72 | 99.72 | 99.72 | 99.72 |
| presidential | 2014 | 98.62 | 98.62 | **99.37** | 99.37 |
| presidential | 2018 | 96.13 | 96.13 | **98.62** | 98.62 |
| presidential | 2022 | 99.37 | 99.37 | 99.37 | **99.88** |

**The crosswalk does not touch the presidential panel at all.** Every presidential
sigla is already either a BLS label or a legend the BLS never scored; V1 ≡ V0
there, exactly, and the identity is asserted rather than asserted-by-eye
(`[I-7]`, outcome fingerprints). The entire presidential gain comes from carry
(2014, 2018) and from UNIÃO (2022).

### [I-3] Carry: the rule, the ledger, and the validation

**Rule.** A party scored in a wave *adjacent* to the election's own wave, but not
in that wave, carries the nearest wave. Adjacent means distance 1 in the BLS wave
sequence; a party scored only in a distant wave is **not** carried — PSTU, scored
in the 1993 wave alone, stays unscored through 2010–2022. Ties resolve to the
**earlier** (pre-electoral) wave, consistent with `02`'s own note that the index
is taken from the year before the election. No tie actually occurs
(`I3_carry_ledger.csv`, 0 of 10 cells have neighbours on both sides).

**`ideo_source ∈ {onda, carry, fusao}`** is carried on the ideology table and
therefore on the panel; `I3_ideo_source_shares.csv` reports the share of the vote
by source, by rung, level and year. At V2 the carried share is 3.24 pp of the
presidential vote in 2018, 2.50 pp in 2014, and 5.41 / 3.24 / 0.77 pp of the
governor vote in 2018 / 2014 / 2022.

**The ledger — 10 (sigla, election) cells:**

| sigla | election | BLS label | own wave | carried from | ideo | gov % | pres % |
|---|---|---|---|---|---|---|---|
| NOVO | 2018 | NOVO | 2017 | 2021 | +0.711 | 5.414 | 2.495 |
| PRB | 2014 | REP | 2013 | 2017 | +0.425 | 1.626 | — |
| PROS | 2014 | PROS | 2013 | 2017 | +0.020 | 0.750 | — |
| PV | 2022 | PV | 2021 | **2017** | −0.069 | 0.646 | — |
| PSC | 2014 | PSC | 2013 | 2017 | +0.541 | 0.443 | 0.750 |
| SD | 2014 | SD | 2013 | 2017 | +0.153 | 0.316 | — |
| REDE | 2014 | REDE | 2013 | 2017 | −0.555 | 0.097 | — |
| REDE | 2022 | REDE | 2021 | **2017** | −0.555 | 0.125 | — |
| PTN | 2014 | PODE | 2013 | 2017 | +0.269 | 0.005 | — |
| SOLIDARIEDADE | 2014 | SD | 2013 | 2017 | +0.153 | — | — |

**Eight of the ten carries are forward** (they import a score measured *after* the
election). This is the same rule `P3` applied to NOVO-2018 and it is stated here
as a limitation rather than defended: where a party is new, the only wave that
measures it is a later one. The two backward carries (PV-2022, REDE-2022) are
pre-electoral and unproblematic.

**The validation the packet requires — confirmed.** `|Δideo|` for the same party
between consecutive waves, against the SD of `ideo` *between* parties within a
wave (`I3_wave_stability.csv`, `I3_sd_between_parties.csv`):

| transition | n | mean abs Δ | median | max | argmax |
|---|---|---|---|---|---|
| 2009 → 2013 | 13 | **0.0625** | 0.047 | 0.158 | DEM |
| 2013 → 2017 | 14 | **0.1083** | 0.079 | 0.258 | PSDB |
| 2017 → 2021 | 18 | **0.1256** | 0.094 | **0.3198** | PSDB |

Between-party SD: 0.4914 / 0.5291 / 0.4856 / 0.5089 across the four waves, mean
**0.5037**.

The figures supplied with the packet (0.063 / 0.103 / 0.126, max 0.32, SD ≈ 0.50)
are **confirmed to the digit**. Pooled: mean 0.1020, max 0.3198 (PSDB, 2017→2021).

**Ratios**: mean `|Δ|` is **0.202** of the between-party SD; the worst single
movement is **0.635** of it. A carried score is therefore a fifth of a
between-party standard deviation off on average — small against the dispersion
the index measures — but the tail is not negligible, and the two parties that
drive it (PSDB, DEM, both moving ≈0.31 between 2017 and 2021) are large. The
honest statement: the carry is justified in the mean and is a real assumption in
the tail. No carried cell in the ledger involves PSDB or DEM.

### [I-4] UNIÃO 2022 by succession — **STOPPED, decision pending**

UNIÃO has no BLS label: the party did not exist when the 2021 wave was fielded.
Both constituents are scored in that wave — **DEM +0.4313, PSL +0.8034** — so the
score is a weighted mean of the two and the entire content of the decision is the
weight. The spread is **0.3720**, so `d(score)/d(w_PSL) = 0.372`: a weight shift
of 0.134 moves the score by 0.05.

| scheme | role | w_PSL | score |
|---|---|---|---|
| Chamber bench at the fusion (PSL 54, DEM 28) | **primary** | 0.6585 | **0.6763** |
| deputies elected in 2018 (PSL 52, DEM 29) | primary, variant | 0.6420 | 0.6702 |
| 2018 governor vote (PSL 2,785,414; DEM 6,962,454) | **fallback** | 0.2857 | **0.5376** |

**Gap between primary and fallback = 0.1387 > 0.05, so the packet's stopping rule
fires.** Both are reported; V3 is not estimated until the weight is chosen. The
two *bench* counts differ by only 0.006, so the choice that matters is
bench-versus-vote, not which bench count.

Sources for the bench: CNN Brasil, 06/10/2021 (PSL 54, DEM 28, total 82) and the
81 federal deputies elected in 2018 by the two legends; TSE homologated the
fusion on **08/02/2022**.

**One consequence is already settled and does not depend on the decision:** every
candidate score in [0.4313, 0.8034] lies outside the neutral band [−0.25, 0.25],
so **`P^N` is invariant to the weight** and only `P^D` moves. Across the *entire*
weight range `w_PSL ∈ [0,1]`, presidential mean `P^D` 2022 moves from 0.5358 to
0.5382 (0.05 of a within-year SD); governor mean `P^D` moves from 0.3828 to
0.4278. The decision is immaterial for the presidential track and material for
the governor track.

**Not in this packet:** PL-2022 (party score vs Bolsonaro's individual score).
Separate substantive change, registered as `P3` anomaly 5.

### [I-5] Guard on the denominator

`02` filters `!is.na(ideo)` **before** summing votes, so every index denominator
is the *scored* vote. `P3` item 2 established the direction; `I5_denominator.R`
decomposes it exactly. For a cell with scored set `S` and newly scored set `A`:

```
ΔP^N = [ N_S/T_S − N_S/(T_S+T_A) ]  +  [ −N_A/(T_S+T_A) ]
         REWEIGHTING (denominator)      COMPOSITION (numerator)
```

The identity is asserted cell by cell; max residual over all cells and steps
**1.39e-16**.

**Cumulative V0 → V2, mean over microregions** (`I5_PN_decomposition_cumulative.csv`):

| level | year | ΔP^N | reweighting | composition |
|---|---|---|---|---|
| presidential | 2010 | 0 | 0 | 0 |
| presidential | 2014 | +0.0021 | +0.0021 | 0 |
| presidential | 2018 | 0 | 0 | 0 |
| presidential | 2022 | 0 | 0 | 0 |
| governor | 2010 | **−0.1258** | +0.0816 | **−0.2075** |
| governor | 2014 | **−0.1810** | +0.0722 | **−0.2532** |
| governor | 2018 | −0.0057 | +0.0007 | −0.0064 |
| governor | 2022 | −0.0206 | +0.0325 | −0.0531 |

**The mechanism runs the opposite way from the one `P3` flagged, and it is
larger.** `P3` warned that dropping a *non-neutral* party inflates `P^N`. On the
governor panel the dropped mass was overwhelmingly *neutral* — MDB scores +0.054
in the 2009 wave, inside the band — so the composition channel dominates and V0
**over**states `P^N` by 0.13–0.18 in 2010 and 2014. Reweighting works in the
predicted direction (+0.07 to +0.08) but is a third the size.

The presidential panel is untouched except for +0.0021 in 2014, which is pure
reweighting: every party carry adds there (PSC, +0.541) is non-neutral.

**What this repairs is not only a mean.** Share of microregions where `P^N`
is degenerate at exactly 1 — no scored vote anywhere in the neutral band:

| level | year | V0 | V1 | V2 |
|---|---|---|---|---|
| governor | 2010 | 35.5% | **9.5%** | 9.5% |
| governor | 2014 | 48.2% | **13.8%** | 13.8% |
| governor | 2018 | 66.8% | 60.8% | 60.8% |
| governor | 2022 | 44.1% | 35.5% | **31.5%** |
| presidential | 2018 | 100% | 100% | 100% |

Half the governor-2014 sample carried a mechanically degenerate outcome under V0.
The presidential 2018 degeneracy is a different problem (`R3-M1`/`G1`) and this
packet does not touch it: NOVO at +0.711 is outside the band, so scoring it
cannot restore variation there — the `P3` finding, reproduced.

### [I-6] Treatment invariance — **PASS, exact zeros**

`delta_EPW`, the effective shocks, the Rotemberg weights and the BHJ balance test
are functions of `W`, `g` and the sample, never of the ideology join. That is an
argument, so it is asserted (`I6_invariance.R`):

| check | V0 vs V1 vs V2 |
|---|---|
| `max abs Δ(delta_EPW)`, standardised and raw | **0** |
| `max abs Δ(epw_boom)`, `max abs Δ(epw_bust)` | **0** |
| estimation sample (micro × year) identical | TRUE |
| `max abs Δ(tradable_emp_share)` | **0** |
| `max abs Δ(Rotemberg α)` over 456 industry-years | **0** |
| effective shocks 1/HHI, by year | 2.8833 / 2.5050 / 2.3805 on every rung |

The effective-shock counts match `[T-6]`'s 2.88 / 2.51 / 2.38 (mean 2.59). The
BHJ balance test is not re-run: it regresses `g_jt` on industry characteristics
and no outcome enters it; its four inputs are hashed in `I6_input_md5.csv` and
Packet I writes none of them.

### [I-8] Governor track: the minimum, and the stop

`06b`/`07b` depend on four artefacts that do not exist here — `epw_common_panel_v8.rds`,
`exposure_shares_common_v8.rds` (both `03a`), `ipw_panel_isic_v1.rds`,
`sectoral_import_shocks_v1.rds` (both `03d`) — plus `share_sum_theta_common_v9.rds`
and `rais_isic_full_tradable_v8.rds`, also from `03a`. Verified rather than
trusted (`I8_artefact_inventory.csv`). **No reconstruction attempted.**

**Minimum to run `07b` with the export treatment alone:**

1. **Run `03a_shares_common.R`.** All six of its inputs are present. It writes the
   four common-share artefacts, all of which belong to the export channel.
2. **One correction to the record:** `revision/README` quirk 2 states that libxls
   cannot open `CNAE20_ISIC4.xls` from this path at all, and concludes that stage
   `03` cannot be re-run on this machine. Tested directly in `I8`: under a pinned
   UTF-8 locale the **direct read succeeds**. The quirk is locale-dependent, not a
   blocker. `03a` is executable here.
3. **Three code edits**, because `06b` and `07b` read the import artefacts
   unconditionally: `06b:51` + `06b:128` (the IPW join and column select);
   `07b:49` plus the joint EPW+IPW and net-exposure blocks (`07b:99-100`,
   `07b:148-190`); and the `ss_ri(list(EPW, IPW), …)` call, which an export-only
   run must reduce to `EPW` alone.
4. **Rebuild the governor index under the chosen rung** before `06b`:
   `dalton_panel_governador.rds` and `painel_ideologico_governador.rds` on disk
   are V0.

`03d` is a separate matter: `imports_national_ncm.rds` *is* present, but `03d`
also needs BACI HS07 and the common shares from `03a`. The import channel is
outside this packet either way.

**STOPPED HERE for decision.** Points 1–4 are a real piece of work (a pipeline
stage, three edits to LOCKED-adjacent pipeline scripts, and a governor index
rebuild) and modifying `06b`/`07b` is beyond "add a packet". Nothing was
attempted.

---

## Section 2 — Pre-registration

**Written before `I7_regressions.R` was run.** Not to be edited afterwards; dated
additions are appended, never substituted. What was already known at the time of
writing is stated as known, so that nothing here can be read as a prediction of
something already observed: `I2` (coverage by rung), `I3` (carry ledger and wave
stability), `I4` (UNIÃO weights), `I5` (index levels and the `P^N`
decomposition) and `I6` (invariance) had all run. **No regression had been
estimated on any rung other than V0.**

```
[I-PRE-1]  The presidential track moves little.
  Known at writing: the crosswalk touches ZERO presidential siglas, so
  V1 == V0 there by construction; carry adds 0.75 pp of the 2014 vote (PSC)
  and 2.50 pp of the 2018 vote (NOVO); UNIAO adds 0.51 pp in 2022.
  Precedent: P3 imputed NOVO-2018 alone and found cor(P^D old, new) = 0.9975,
  no microregion moving more than one decile, and every dP^N estimate
  numerically unchanged.
  PREDICTION, at V2 and at V3, against V0:
    (a) cor(P^D_V0, P^D_v) >= 0.99 in every year;
    (b) no microregion moves more than one decile of P^D in any year;
    (c) every one of the 12 treatment coefficients moves by less than
        0.5 x its own clustered SE;
    (d) no sign flip on any coefficient whose |beta| > 0.5 SE at V0;
    (e) no RI p crosses 0.10 in either direction;
    (f) the null of RATIONALE.md [T-2b] survives: every RI p stays above 0.30.

[I-PRE-2]  The gain is in the governor track.
  Known at writing: coverage 76/68/89/74 -> 98/99/98/98 across V0->V3, and
  the share of microregions with a degenerate P^N falls from 35/48/67/44%
  to 9/14/61/32%.
  PREDICTION: no estimate is offered, because 06b/07b cannot run ([I-8]).
  This is registered so that the absence of governor coefficients in
  RESULTS_I.md is legible as a blocked deliverable and not as a silent drop.

[I-PRE-3]  dP^N in 2018 does not move on the presidential track.
  NOVO (+0.711) is outside the neutral band, so scoring it cannot add neutral
  mass; P^N_2018 == 1 in every microregion under every rung, hence dP^N is
  mechanically unchanged in that year. The only presidential P^N movement
  available is 2014 (+0.0021 mean, pure reweighting) and 2022 (UNIAO, whose
  score is outside the band under any weight, hence reweighting only).
  PREDICTION: the dP^N coefficients move less than the dP^D ones.

[I-PRE-4]  If the presidential track DOES move materially, that is a finding.
  A material move is any of (c), (d), (e) above failing. Should that happen it
  is to be reported as a finding about the fragility of the index to the
  scored menu -- NOT as a repair, NOT as a new baseline, and NOT with the
  ladder re-cut to make it disappear. The rung responsible is to be named,
  since each rung changes exactly one thing.

[I-PRE-5]  What would make V2 unreportable.
  The carry is defensible only while a carried score is small against the
  between-party dispersion. Registered threshold, fixed before estimation:
  if the mean |delta ideo| between consecutive waves had exceeded 0.25 --
  half the between-party SD -- the carry would have been reported as an
  assumption too strong to headline. Measured: 0.0625 / 0.1083 / 0.1256,
  i.e. 0.12 / 0.22 / 0.25 of the between-party SD. The rule passes on the
  mean in every transition and the tail (max 0.32, PSDB 2017->2021) is
  recorded as the limitation.
```

---

## Section 3 — Results

*(filled by `[I-7]`; see `output/packet_I/RESULTS_I.md`)*

---

## Outstanding

1. **`[I-4]` UNIÃO weight** — primary (bench, 0.6763) vs fallback (2018 governor
   vote, 0.5376); gap 0.1387. V3 is not estimated until this is decided.
2. **`[I-8]` governor track** — decision required on whether to run `03a` and edit
   `06b`/`07b` for an export-only governor estimation.
3. **`[I-2]` residual ceiling** — 2.4% of the 2018 governor vote and 1.3% of the
   2018 presidential vote belong to legends the BLS never measured (PATRIOTA,
   PRTB, DC, PMN). No crosswalk can reach them; the manuscript should say so.
4. **The PSL-2018 rule** — preserved from the baseline here. Whether it should be
   the Bolsonaro individual score (+0.862) or the PSL party score (+0.803) is the
   same question as PL-2022 and belongs with `P3` anomaly 5.
