# Packet L — Amendment `[PL-37]`–`[PL-43]`

**Date:** 21/09/2026. **Status:** unblocks the branch stopped at L2.
**Companion to** `packet_L_spec.md` and `RATIONALE_L.md`. Same `[PL-n]` namespace,
continuing past `[PL-36]`.

> **For Claude Code:** this amendment is part of **Packet L**, not Packet E. It resumes the
> `packet-L-legislativo` branch. It also adds one retrofit that touches the presidential and
> governor panels (`[PL-40]`, `[PL-41]`) — that retrofit is **additive**: it writes new
> columns and new outputs and must not modify `02_polarization_indices.R`.

---

## Why the branch resumes

`[PL-19]` failed because a party's score was required to come from the **contemporaneous**
wave. Relaxing that to the **nearest** wave, at a distance of **one wave**, clears the gate in
every year:

| year | matched now | matched under `[PL-37]` | recovered by |
|---|---|---|---|
| 2010 | 90.24% | 90.24% | — (nothing within one wave) |
| 2014 | 81.03% | **93.70%** | PRB→REP, SD, PSC, PROS, PTN→PODE — 12.67 pts, all from the 2017 wave |
| 2018 | 76.82% | **91.25%** | PSL, NOVO — 14.44 pts, from the 2021 wave |
| 2022 | 84.80% | **86.39%** | PV, REDE — 1.59 pts, from the 2017 wave |

Widening to three waves improves only 2010 (95.84%) and 2014 (94.53%) and changes 2018 and
2022 not at all. **Take the one-wave rule**: it clears every year and is the version that
survives a question about why the cap is where it is.

Note 2022 clears **without** UNIÃO. The merger rule (`[PL-42]`) is therefore optional and must
not be a dependency.

---

## `[PL-37]` Nearest-wave carry — the rule

Declared before any index is computed, and never revised in light of a result.

1. A party's score for election year *t* comes from the wave mapping to *t* (`ano_eleicao =
   year + 1`) **when that wave scores it**. This is unchanged and always takes precedence.
2. Otherwise, from the **nearest** wave that scores it, measured in waves, at **distance ≤ 1**.
3. Ties (one wave earlier and one later both score it) resolve to the **earlier** wave —
   positions are then pre-determined relative to the election.
4. Distance > 1 is **not** carried. The party's votes stay unmatched and are reported.
5. The rule is symmetric in direction by construction, but the two directions are **not**
   equally safe and are reported separately (`[PL-38]`). Forward carry (an earlier wave
   scoring a later election) keeps positions pre-determined. Backward carry (a later wave
   scoring an earlier election) does not, and is the reason `[PL-39]` exists.

Under this rule the backward-carried cells are exactly: **PRB, SD, PSC, PROS, PTN→PODE in
2014** (from 2017) and **PSL, NOVO in 2018** (from 2021). The forward-carried cells are **PV
and REDE in 2022** (from 2017). Everything else is contemporaneous.

## `[PL-38]` Provenance is carried in the data, not in a comment

Every ideology cell gains three columns, written into `painel_ideologico_*.rds` at every level:

| column | meaning |
|---|---|
| `ideo_wave` | the wave the score actually came from |
| `ideo_carry` | `"none"`, `"forward"`, `"backward"` |
| `ideo_carry_dist` | 0, or 1 |

```r
stopifnot(
  "[PL-38] carry distance exceeds the declared cap" = all(ideo_carry_dist <= 1),
  "[PL-38] a cell is flagged carried but sits in its home wave" =
    all((ideo_carry == "none") == (ideo_carry_dist == 0)),
  "[PL-38] provenance missing on a scored cell" = !anyNA(ideo_wave[!is.na(ideo)])
)
```

Every table that reports an index also reports the **share of votes resting on a carried
score**, by year and by direction. A reader must be able to see, without opening the code,
how much of any given number is imputed.

---

## `[PL-39]` The three-way sensitivity — the protocol

The carry rule is not the problem. **One cell is.** PSL-2018 is **11.64%** of the Chamber vote
and is 81% of that year's entire rescue — and PSL-2018 is the party whose rise *is* the
polarization event the dissertation exists to detect. The 2021 wave scores it at
`ideo = 0.803`, near the right extreme of a [−1, 1] scale. Assigning it pushes 2018
polarization up in precisely the regions where PSL polled well, which is the hypothesised
direction. That is measurement error **aligned with the hypothesis**, not noise.

So every cell above a declared mass threshold is reported three ways. Applies at **all three
levels** — Chamber, presidential, governor — and to **any** imputed cell, not only carried
ones (`[PL-40]`).

**Threshold:** any imputed party holding **≥ 3%** of a year's valid votes at that level.
Declared here, before the indices exist.

### (a) Point
The carried (or patched) score, used as the headline. Reported with its provenance flag.

### (b) Drop
The party is excluded and vote shares are **renormalised over scored parties only** — the same
rule the index already applies to unmatched votes, so this is not a new device. Report the
index and the resulting coverage.

### (c) Break-even
Not a range — a **threshold**. Solve for the value the imputed party's score would have to
take for the study's conclusion at that level to reverse, holding everything else fixed:

```
find  y*  such that  the sign / significance verdict on the relevant ΔP coefficient flips
```

Then state where `y*` sits relative to the observed distribution of scores in that wave. If
PSL-2018 would have to be scored centre-left for the 2018 result to change, the finding does
not rest on the imputation and you can say so in one sentence. If `y*` sits comfortably inside
the plausible range for a Bolsonarist party, the finding **does** rest on it, and that is the
result to report.

Break-even is preferred to a min–max envelope because the envelope over a [−1, 1] support is
so wide that it renders every year inconclusive — true but useless. Report the ±2 × `ideo.se`
interval around the carried score as an auxiliary, since `ideo.se` is in the BLS file and
costs nothing.

**A conclusion that survives (a), (b) and (c) is reported normally. One that does not is
reported as conditional on the imputation, in the body, not in a footnote.**

---

## `[PL-40]` Retrofit: the presidential and governor panels do this already, undeclared

`02_polarization_indices.R` substitutes the **BOLSONARO 2022** estimate for **PSL in 2018**:

```r
psl <- ideologia %>%
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) %>%
  mutate(party.or.pres = "PSL", ano_eleicao = 2018)
```

That is the same class of imputation as `[PL-37]`, on the same party, in the same year, in the
direction that most favours the hypothesis — and it is currently invisible in every table the
dissertation reports. It is also **worse** than the Chamber carry in one respect: it scores a
**candidate** and applies it to a **party**, and `ideologia_psl` is shared by both the
presidential and governor builds.

**Required, additive, in a new `02c_sensitivity_levels.R`:**

1. Flag the patched cells with the `[PL-38]` provenance columns at both levels.
2. Measure what share of each year's presidential and gubernatorial vote rests on the patch.
3. Run the full `[PL-39]` three-way at both levels for every cell over the 3% threshold.
4. Add a fourth arm at these two levels only: **party-score arm** — PSL-2018 scored from the
   2021 **PSL party** entry (`ideo = 0.803`) rather than from the BOLSONARO candidate
   estimate. This is the apples-to-apples comparison the Chamber level will be using, and it
   tells you whether the candidate/party distinction moves anything.

Do **not** modify `02_polarization_indices.R`. Write new panels with a `_sens` suffix and a
comparison table.

## `[PL-41]` The presidential and governor panels have never faced a blocking coverage gate

`diagnostico_na()` prints coverage; nothing stops on it. `[PL-19]` was written for Packet L and
was never applied to the levels already in the dissertation — and the function's own comment
anticipates the problem: *"importante rodar para governador: corridas estaduais trazem mais
partidos pequenos sem score BLS."*

**Run the 15% gate retrospectively at both levels, by year.** If a year fails, that is a
finding about results already in the manuscript, and it belongs in the meeting before it
belongs in a table. Report it whatever the answer; do not stop the packet on it.

## `[PL-42]` UNIÃO 2022 — optional, and kept optional

UNIÃO (DEM + PSL merger, Feb 2022) holds **9.30%** of the 2022 Chamber vote and no wave scores
it. 2022 clears `[PL-19]` at 86.39% without it, so this is an extension, not a fix.

If run: score UNIÃO as the **vote-weighted mean of the 2021 DEM and PSL scores**, weighted by
the two parties' 2018 Chamber vote shares. Declare it a merger rule, distinct from a carry,
give it its own provenance value (`ideo_carry = "merger"`), and put it through `[PL-39]` —
9.30% is well over the threshold. Report 2022 with and without it.

## `[PL-43]` V-Party as a declared second source, not a replacement

A second ideology source belongs in the appendix as a robustness column, built once and
compared, never silently substituted. See the note accompanying this amendment for how to
build it. Two things must be settled **before** any code is written, and recorded here:

1. **Coverage of 2022.** The version I can confirm (v2, published February 2022) runs
   **1970–2019**. If no later release covers the 2022 Brazilian election, V-Party can serve
   2010 / 2014 / 2018 only, and the comparison is three cycles, not four. Check first; do not
   discover this after building the panel.
2. **Scale.** V-Party's left-right item is not on the BLS's standardised [−1, 1] metric. The
   two sources are compared **after** each is standardised within year on the estimation
   sample — never pooled, never averaged into a single score.

---

## Sequence to resume

| stage | action | gate |
|---|---|---|
| L3′ | Apply `[PL-37]`; fill `party_crosswalk_bls.csv` for the **renamings only** (PRB→REP, PTN→PODE, PV, REDE, NOVO, SD, PSC, PROS). The unscored tail stays unmatched — no judgement needed on it. | `[PL-16]`, `[PL-17]` |
| L4 | Coverage with carry. | `[PL-19]` — expect 90.2 / 93.7 / 91.3 / 86.4 |
| L5 | `[PL-27]` decision rule: R² of `P_dalton` on first-place vote share, by year, against the presidential 0.96 in 2022. **STOP AND REPORT.** | the branch lives or dies here |
| L6 | `[PL-39]` three-way on every cell ≥ 3%, Chamber level. | — |
| L7 | `[PL-40]` / `[PL-41]` retrofit at presidential and governor levels, additive. | — |

L5 remains the decision. The carry rule only buys the right to ask the question; it does not
answer it, and a Chamber index that reproduces the presidential pathology should still be
abandoned.
