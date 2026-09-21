# RATIONALE_L.md — Packet L (Chamber of Deputies outcome)

Run: 2026-09-20, amended 2026-09-21. Scripts live in `códigos/packet_L/`; outputs in
`<DATA_DIR>/output/packet_L/`. Note the packet spec names the scripts at `códigos/` root —
they were moved into `packet_L/` when the branch was committed, matching `packet_D/` and
`packet_I/`. Nothing else about them changed; each sources `00_config.R` by absolute path.

Cross-packet items raised by this packet are registered in `CODE_CHANGES_TODO.md`
(addendum 2026-09-21): the `[PL-44]` provenance defect, and the two silent loader failures
`[PL-28]` / `[PL-29]`.

| stage | status |
|---|---|
| L1 extraction | **complete, both gates pass** |
| L2 seed crosswalk and stop | **complete, gate reached as specified** |
| L3 fill crosswalk from codebook | **not started — human step, and see the verdict below** |
| L4 coverage gate + `[PL-27]` decision rule | **not reached** |

---

## 0. VERDICT — read this first

**`[PL-27]` was never reached, because `[PL-19]` fails first.** Under a crosswalk that
resolves every plausible label drift, the share of Chamber votes with no ideology score is:

| year | matched | unmatched | `[PL-19]` gate (15%) |
|---|---|---|---|
| 2010 | 90.24% | 9.76% | pass |
| 2014 | 81.03% | **18.97%** | **fail** |
| 2018 | 76.82% | **23.18%** | **fail** |
| 2022 | 84.80% | **15.20%** | **fail** |

The shortfall is **not** mislabelling, so **filling the crosswalk cannot fix it**. It is
votes for parties the BLS survey never scored in the matching wave. The BLS file carries
13 / 14 / 20 / 20 party scores; the Chamber has 27 / 32 / 35 / 32 parties with votes. The
residual is the unscored tail plus two large single-party holes (`[PL-13]`, `[PL-15]`).

**Recommendation: do not spend the afternoon on the codebook yet.** L3 as specified cannot
clear the gate. The decision that matters is now upstream of the crosswalk — see §5.

This verdict is a measurement finding about ideology coverage. It is *not* a finding about
whether the Chamber level would behave better than the presidential one on `[PL-27]`; that
question remains open and untested.

---

## 1. Infrastructure — two silent failures that also affect the existing pipeline

Both produce an **empty result with no error**. Neither is specific to Packet L.

### `[PL-28]` TSE CDN rejects non-browser requests
`electionsBR:::download_unzip()` fetches with `httr::GET()` and a randomised user agent and
no other browser headers. The TSE Akamai edge answers **HTTP 403** with a 492-byte HTML
error page. electionsBR writes that page to the `.zip` path; `unzip()` then fails with only a
**warning** (`error 1 in extracting from zip file`) and `elections_tse()` returns a 0x0 tibble.

`Accept-Encoding` is the discriminating header: with the full browser set the CDN returns 200,
and dropping `Accept-Encoding` alone returns 403. Fix pre-seeds `tempdir()` with a correctly
fetched archive; `download_unzip()` skips its own download when the file exists, so
**electionsBR still does all the parsing** — only the transport is replaced.

> **`01_extraction.R` BLOCK C calls `elections_tse()` the same way and has the identical
> failure mode.** Re-running it today would silently rebuild the presidential and governor
> panels as empty frames. It has no `[PL-8]`-style guard to catch that.

### `[PL-29]` / `[PL-35]` readr cannot do file I/O under `DATA_DIR`
`DATA_DIR` contains non-ASCII characters (`dissertação`, `versão`, `vínculos`). macOS stores
them on disk in NFD while R's path string is partly NFC, and readr/vroom cannot resolve the
mixture. Verified on a file that demonstrably exists:

| call | result |
|---|---|
| `file.exists()` | TRUE |
| `base::read.csv()` | all 88 rows |
| `readr::read_csv()` — relative, `normalizePath()`, `file.path(getwd(),.)`, `enc2utf8()`, `enc2native()` | **all fail**, "cannot open the connection" |
| same `read_csv()` in an ASCII directory | works |
| `readr::write_csv()` | creates a new file, but **fails when one already exists** |

Inside `electionsBR:::juntaDados()` this is worse, because every read is wrapped in
`tryCatch(..., error = function(e) NULL)`: all reads return NULL, `rbindlist()` yields an
empty table, and the function returns 0x0 **without error**. Fixed by running the pull from
an ASCII scratch directory (`[PL-29]`) and routing all packet_L table I/O through base R
(`[PL-35]`).

> **13 pipeline scripts call readr readers with relative paths under this same `DATA_DIR`**
> (`03`, `03a`, `03b`, `03d`, `07`, `07z`, `10`, and five in `packet_D`). They are exposed to
> the identical failure. Not touched here — flagged for a separate decision.

### `[PL-30]`, `[PL-31]` guards added
`[PL-30]` asserts the pull is non-empty before anything touches it. `[PL-31]`: TSE re-published
the archives with **title-case** cargo labels (`Deputado Federal`), so the spec's
`CARGO_LEG <- "DEPUTADO FEDERAL"` matched zero rows. Now matched on a normalised string with
an assertion that the filter selected rows. (BLOCK C already used title case, `"Presidente"`.)

---

## 2. Data structure — what the Chamber archives actually contain

### `[PL-32]` the vote columns are not stable, and the 2018 change is semantic
| | nominal | legenda |
|---|---|---|
| 2010, 2014 | `QT_VOTOS_NOMINAIS` | `QT_VOTOS_LEGENDA` |
| 2018, 2022 | `QT_VOTOS_NOMINAIS_VALIDOS` | `QT_TOTAL_VOTOS_LEG_VALIDOS` |

From 2018 TSE splits counts into VALID / CONVERTED / ANNULLED parts. "Converted" are nominal
votes for a candidate whose registration failed, which the law reassigns to the party list.
The identity `QT_TOTAL_VOTOS_LEG_VALIDOS = QT_VOTOS_LEGENDA_VALIDOS + <converted>` holds
exactly in both years and is now asserted — **taking the total and its parts would double
count**. Decision: the index is a vote-share statistic, so it is built on **valid** votes,
which is exactly what the 2010/2014 columns already are. Annulled votes are excluded
(0 in 2018; ~0.9M of 109M, 0.85%, in 2022).

### `[PL-33]` the same party can appear twice in one municipality-zone
TSE emits a party under two *agremiação* records — in 2018 a `Coligação` row plus a
`Partido isolado` row, in 2022 two records with different `SQ_COLIGACAO`. The two years
behave **differently**, so the rule was read off the data rather than assumed:

- **nominal** are disjoint candidate tallies on each record → **sum, always**.
- **legenda** is a party-level total. 2018 **repeats** the identical number on both records
  (74 keys, all non-zero, 7,048 votes); 2022 **splits** disjoint tallies across them
  (2,094 keys, 21,128 votes). So: count a replicated value once, sum genuinely distinct ones.

Effect: 2018 legenda 6,857,812 → 6,850,764; 2022 unchanged. Affected votes are 0.007% and
0.019% of the year's valid total — a correctness fix, not something any result turns on.

### `[PL-4]` confirmed, by direct test
Within a 2018 coalition, legenda **differs across member parties** in **94.3%** of
coalition × municipality × zone groups (the 5.7% of ties are almost all zeros — 882 non-zero
of 43,380). So legenda is recorded against the party, not shared across the coalition, and
party-level attribution is valid. The packet asserted this; it is now tested.

### `[PL-2]` confirmed, and it matters more than the spec expected
Legenda share of the Chamber vote: **9.17% / 8.43% / 6.97% / 3.93%** (2010–2022). The spec
anticipated 3–8%; 2010 and 2014 are above that range. Reading `vote_mun_zone` as BLOCK C does
would have dropped this, unevenly along the ideology axis.

### `[PL-36]` the crosswalk seed was invalid as specified
The seed crossed the union of BLS labels with all four years, inventing rows that cannot hold
(NOVO in 2010, PSL in 2018, SD in 2014) — which `[PL-17]`, correctly, rejected. The seed now
draws the actual (year, label) pairs from the BLS file: **67 identity rows** = 13 + 14 + 20 + 20.

---

## 3. `[PL-13]` — the spec's premise was wrong, and the guard caught it

The packet states: *"the 2017 wave scores PSL as a party directly."* **It does not.** PSL is
scored in exactly one wave, **2021** (`ideo` = 0.803). The 2017 wave — the one mapping to the
2018 election — has no PSL entry.

PSL took **11.64%** of the 2018 Chamber vote, the second-largest delegation. That vote cannot
be scored from the contemporaneous wave, and it alone is most of the way to failing `[PL-19]`.

The guard's purpose is unchanged and still enforced: the presidential PSL patch substitutes
the BOLSONARO 2022 estimate, which scores a **candidate**, and must never be reused for a
party-level outcome. `ideologia_psl` is not referenced in `02b`, and an assertion now enforces
that. What changed is only that the check reports rather than halting before the crosswalk can
be seeded — the L2 deliverable — since the risk it guarded against is now a known finding.

**A symmetrical problem in 2022:** the 2021 wave scores DEM and PSL separately, but by the
2022 election both had merged into **UNIÃO**, which no wave scores. Per `[PL-15]`'s rule a
merger is not a renaming, so UNIÃO's **9.30%** is dropped — while two labels that scored
parties no longer on the ballot sit unused.

---

## 4. `[PL-34]` — a feasibility test that belongs before the human step

Added to `02b`: an **assumption-free upper bound** on coverage over *all possible* crosswalks.
Start from identity matches, then grant the wave's remaining unused BLS labels to the largest
still-unmatched TSE parties, one-to-one. No real crosswalk can beat that, because a crosswalk
is at best an injection into the wave's label set.

| year | BLS labels | TSE parties | identity | ceiling | floor unmatched |
|---|---|---|---|---|---|
| 2010 | 13 | 27 | 64.43% | 90.77% | 9.23% |
| 2014 | 14 | 32 | 60.18% | 84.36% | **15.64%** |
| 2018 | 20 | 35 | 61.47% | 88.28% | 11.72% |
| 2022 | 20 | 32 | 73.74% | 96.45% | 3.55% |

The bound **rules 2014 out on its own**, with no party knowledge required. It is deliberately
loose — it would happily "match" PSL to REDE — so it cannot rule any year *in*. That is what
`02b_aux_coverage_projection.R` is for: the realistic label-drift projection in §0, which is a
**hypothesis, writes nothing to `party_crosswalk_bls.csv`, and sets no `verified` flag**.
L3 remains the human step.

---

## 5. What the decision actually is now

The binding constraint is not the crosswalk. It is that **BLS wave coverage of the party
system is much thinner than the Chamber vote distribution**, and it varies by wave: PRB, SD,
PSC and PROS are scored from 2017 but not in the 2013 wave, so 2014 loses them even though the
same parties are scored later.

Three routes, in rough order of how much they change the specification:

1. **Abandon the Chamber outcome**, per the packet's own decision rule, and keep the
   presidential panel with the Jacobian figure (work plan item 15) as the honest patch.
2. **Change the wave-assignment rule** — carry a party's nearest available score across waves
   instead of requiring the contemporaneous one. This would recover most of the 2014 shortfall
   and some of 2018. It makes ideology partly time-invariant, which is a substantive change to
   what the index measures and contradicts the existing `ano_eleicao = year + 1` convention.
   **Not taken here; it is a specification decision, not a data-cleaning one.**
3. **Change the ideology source** for the legislative level to one with full party coverage
   (e.g. a roll-call-based measure). Largest change, outside this packet.

Note that route 2 does **not** rescue 2018 PSL or 2022 UNIÃO, which are the two largest single
holes, and it would score PSL-2018 from the 2021 wave — i.e. from a party already transformed
by the Bolsonaro realignment. That is the same anachronism the `[PL-13]` guard exists to prevent.

---

## 6. Foster–Wolfson, recorded as the packet requires

**Considered and rejected.** `ideo` is standardised around zero on roughly [−1, 1]. FW requires
a Gini and divides by the median, so it is undefined on negative support and unstable near a
zero median. It would need an affine rescaling to which the index is **not invariant**.
Esteban–Ray is the correct family here: it depends on |y_p − y_q| and is translation-invariant.
`P_er_10` / `P_er_14` take their formula verbatim from `packet_D/E0_frame.R` so the levels are
comparable, and α is pre-fixed by the specification rather than selected.

---

## 7. Deviations from the packet, and what was not done

**Branch.** The packet specifies `packet-L-legislativo` cut from the Phase 2 commit. The repo
(`data/códigos/`) is on `theta-total-shares` with a dirty tree — ~10 modified tracked files and
many untracked, from packets D/E/I. There is no commit identifiable as "Phase 2". **No branch
was created and nothing was committed**; that needs Yago's call on which commit is the base.

**Not done, deliberately:** no differences built, no estimation frame joined, no regression run
— per the packet. `[PL-12]` BigQuery cross-validation not run (it costs money, needs a billing
cap, and the G2 incident makes it a deliberate choice; the electionsBR route now works). `P_dip`
never computed, so `diptest` (installed) is unexercised. `[PL-27]` never reached.

**Scripts added beyond the packet's two:** `02b_aux_coverage_projection.R`, a decision aid, not
a pipeline stage.

**New audit tags introduced here:** `[PL-28]`–`[PL-36]`, continuing the packet's numbering
past `[PL-27]` so nothing collides with the spec's declared tags.

---
---

# AMENDMENT `[PL-37]`–`[PL-43]` — run 2026-09-21

Supersedes §0 of this log. The branch resumed at L2 and ran through L7.

| stage | status |
|---|---|
| L3′ crosswalk + `[PL-37]` carry | complete |
| L4 coverage with carry | **`[PL-19]` PASSES in every year** |
| L5 `[PL-27]` decision rule | **PASSES decisively — the branch lives** |
| L6 `[PL-39]` Chamber sensitivity | complete, arms (a) (b) + SE band; (c) not yet definable |
| L7 `[PL-40]`/`[PL-41]` retrofit | complete — **and it found two things that belong in the meeting** |

## A. L5 — `[PL-27]`, the decision rule

R² of `P_dalton` on first-place vote share, Chamber level:

| year | linear | quadratic |
|---|---|---|
| 2010 | 0.195 | 0.200 |
| 2014 | 0.042 | 0.048 |
| 2018 | **0.0008** | 0.014 |
| 2022 | **0.116** | 0.124 |

Presidential benchmark: **0.96** in 2022. Comparing like with like, 2022 falls from **0.96 to
0.116**. The Chamber index is not a transformation of a single scalar. **The level change
worked**, and by the packet's own pre-declared rule the Chamber outcome becomes the primary
measurement in Chapter 3.

Supporting: parties per microregion rise from 5–6 (presidential) to **13.0 / 18.9 / 21.8 /
19.3**. `y_bar`, the directional quantity Proposition 1 actually predicts, is
**−0.011 / +0.085 / +0.198 / +0.135** — a clear rightward move through 2018 and a partial
retreat in 2022.

## B. L4 — coverage under `[PL-37]`

| year | unscored | gate |
|---|---|---|
| 2010 | 9.76% | pass |
| 2014 | 6.30% | pass |
| 2018 | 8.75% | pass |
| 2022 | 13.61% | pass |

Matches the amendment's projection (90.2 / 93.7 / 91.3 / 86.4 matched) to the decimal. 2022
clears **without** UNIÃO, so `[PL-42]` stayed optional and was not run.

Crosswalk (L3′): 74 rows, 55 identity + 19 renaming, all `verified = TRUE`, built by
`02b_aux_fill_crosswalk.R`. **The basis is legal renaming plus internal evidence, not a
codebook page cite**: the BLS file back-labels parties with their modern sigla (MDB, DEM, PL,
CID all carry 1990 scores, when those parties were legally PMDB, PFL, PL, PCB/PPS), which is a
file whose series follow the legal party across renamings. If the codebook contradicts a row,
the codebook wins. Worth a spot-check: **PR→PL** (a 2006 PRONA merger sits inside that lineage)
and **CID** (PCB → PPS → Cidadania is a long chain).

`[PL-37]` carried 11 cells, all at distance 1: 2014 gains PODE, PROS, PSC, REDE, REP, SD from
the 2017 wave (backward); 2018 gains NOVO and PSL from 2021 (backward); 2022 gains PV and REDE
from 2017 (forward); 2010 gains PSD from 2013 (backward, **zero votes** — PSD was founded in
2011, so it changes nothing, consistent with the amendment's "nothing recovered in 2010").

Provenance load, `[PL-38]`:

| year | none | backward | forward | unscored |
|---|---|---|---|---|
| 2010 | 90.24 | 0.00 | 0.00 | 9.76 |
| 2014 | 81.03 | **12.67** | 0.00 | 6.30 |
| 2018 | 76.82 | **14.43** | 0.00 | 8.75 |
| 2022 | 84.80 | 0.00 | 1.59 | 13.61 |

## C. L6 — `[PL-39]` at the Chamber level

Cells ≥ 3%: **REP 2014** (4.55%, backward from 2017) and **PSL 2018** (11.64%, backward from 2021).

**The verdict survives every arm.** R² of `P_dalton` on first-place share:

| year | (a) point | (b) drop REP 2014 | (b) drop PSL 2018 |
|---|---|---|---|
| 2010 | 0.195 | 0.195 | 0.195 |
| 2014 | 0.042 | 0.046 | 0.042 |
| 2018 | 0.0008 | 0.0008 | 0.005 |
| 2022 | 0.116 | 0.116 | 0.116 |

Nowhere near 0.96 under any arm. **L5 does not rest on the imputation.**

**But the drop arm is not actually available for PSL-2018.** Dropping it pushes 2018 unscored
to **20.38%**, which fails `[PL-19]`. The (b) arm for that cell yields an index built on 79.6%
of the vote and is therefore not comparable to the others — it is reported as a bound, not as
an alternative specification.

Index sensitivity, 2018, to PSL: `y_bar` 0.1977 → 0.1401 on drop (−29%); `P_dalton` 0.4621 →
0.4474 (−3.2%). The ±2·`ideo.se` band is narrow: `y_bar` 0.1899–0.2055, `P_dalton` 0.4536–0.4715.
**So PSL-2018 matters mostly for the directional measure, which is the one Proposition 1
predicts** — exactly the alignment the amendment warned about. `P_dalton`, the outcome the
design actually uses, barely moves.

**Arm (c) is not yet definable at this level.** Break-even is the value at which the ΔP
verdict reverses; no ΔP regression has ever been run on the Chamber outcome, so there is no
verdict to reverse. It becomes computable when the Chamber ΔP enters the design.

## D. L7 — `[PL-41]` first reading: WITHDRAWN, see §G

> **This section is wrong and is kept only so the error is on the record.** The governor
> "failure" below is a raw-label artefact: the join used `02`'s bare `party` acronym, which is
> packet I's **V0** rung, not the rung the manuscript uses. Packet I had already established
> and fixed it (`[I-2]` crosswalk, `[I-3]` carry, `[I-4]` UNIÃO). **At the canonical rung both
> levels pass in every year.** Corrected in §G.

| level (V0, raw label — NOT canonical) | 2010 | 2014 | 2018 | 2022 |
|---|---|---|---|---|
| presidential | 0.28% | 1.38% | 3.87% | 0.63% |
| governor | 23.76% | 31.57% | 10.58% | 25.93% |

These numbers reproduce packet I's V0 column **exactly** (76.24 / 68.43 / 89.42 / 74.08
matched), which is the tell: they measure the un-crosswalked join, not the panel in use.

## E. L7 — `[PL-40]`: how much the presidential 2018 index rests on one imputed cell

| level | year | none | patch | unscored |
|---|---|---|---|---|
| presidential | 2018 | 50.12 | **46.01** | 3.87 |
| governor | 2018 | 86.50 | 2.92 | 10.58 |

**46% of the 2018 presidential vote is scored by the BOLSONARO 2022 candidate estimate** —
Bolsonaro's own first-round share. The dependence is severe:

| arm | `y_bar` 2018 | `P_dalton` 2018 |
|---|---|---|
| (a) point — BOLSONARO 2022 candidate, `ideo` = 0.862 | +0.0834 | 0.6411 |
| (b) drop | **−0.4496** | **0.3499** |
| (d) PSL 2021 **party** score, `ideo` = 0.803 | +0.0587 | 0.6170 |

Dropping the cell **reverses the sign of `y_bar`** and nearly halves `P_dalton`. The
candidate/party distinction (arm d) by contrast moves little: the question is whether PSL is
scored at all, not which of the two scores is used. That is reassuring for `[PL-40]`'s specific
worry and alarming for the broader one.

### `[PL-39]`(c) break-even, presidential

Specification, verbatim from `07_regression_inference.R`:
`feols(delta_P_dalton ~ delta_EPW + ln_gdp_pc + ln_pop + tradable_emp_share | state^year)`,
clustered `mesoregion_code^year`, common-2010-base differences. `delta_EPW` and every control
are held **exactly** fixed from `df_estimation_v7.rds`; only the outcome varies.

**Reconstruction validated exactly**: rebuilt `P_dalton` and `delta_P_dalton` reproduce the
stored frame with `cor = 1` and `max |diff| = 0` over all 1,671 rows, and the baseline on the
stored frame returns β = 0.000861, t = 0.179, p = 0.858 — identical to the rebuild.

Sweeping PSL-2018 over [−1, 1] in steps of 0.1:

- β stays **positive everywhere**, ranging 0.0001 to 0.0084.
- **p never falls below 0.21**; |t| never exceeds 1.25.
- Sign flips: **nowhere**. Significance lost: **everywhere** — it is never attained.

So the break-even is degenerate, and informative for that reason: **the baseline presidential
ΔP_dalton result is null regardless of how PSL-2018 is scored.** That conclusion does not rest
on the imputation, because in this specification there is no conclusion to rest on it.

> **Scope limit, stated plainly.** Only the **baseline OLS** was swept. The manuscript also
> reports IV/AKM, asymmetric boom/bust and winsorised specifications. Whether any of *those*
> rest on the PSL patch is **not** established here, and given that 46% of the 2018
> presidential vote is imputed, it is the obvious next thing to run. `02c_sensitivity_levels.R`
> takes the specification as an argument; extending the sweep is small.

## F. Not done

`[PL-42]` UNIÃO — not run; 2022 clears without it and the amendment keeps it optional.
`[PL-43]` V-Party — not started. Its two preconditions are unresolved and must be settled
first: (1) whether any release covers the **2022** election (the confirmable v2 runs 1970–2019,
which would make the comparison three cycles, not four); (2) standardisation within year on
the estimation sample, never pooled.

`P_dip` still unexercised. `[PL-12]` BigQuery cross-check still not run. Branch/commit state
unchanged — still `theta-total-shares`, dirty, **nothing committed**.

**New scripts:** `02b_aux_fill_crosswalk.R` (L3′), `02b_sens_legislativo.R` (L6),
`02c_sensitivity_levels.R` (L7). `02_polarization_indices.R` **not modified**.


---

## G. `[PL-44]` — correction to §D, and a provenance defect it exposed

### G.1 The gate passes at both levels

The §D governor result was measured on the raw `party` acronym join — packet I's **V0** rung.
Brazilian renaming makes that join drop PMDB, PR, PC do B, PPS, PRB, SOLIDARIEDADE and the rest,
which is the same label drift `[PL-15]` exists to fix at the Chamber level, and which packet I
had **already** resolved for these levels: `[I-2]` a time-windowed crosswalk over all 48 siglas,
`[I-3]` an adjacent-wave carry, `[I-4]` UNIÃO as a fusion.

Measured on the panels actually in use (`painel_ideologico_*_V3.rds`), unscored share:

| level | 2010 | 2014 | 2018 | 2022 |
|---|---|---|---|---|
| presidential | 0.28% | 0.63% | 1.38% | 0.12% |
| governor | 1.78% | 0.89% | 2.40% | 1.70% |

**`[PL-19]` passes at both levels in every year, with two orders of magnitude of margin.**
There is nothing here for the meeting. `[PL-41]` is answered and closed.

Worth recording: packet I's `[I-3]` carry rule — adjacent wave, distance 1, ties to the earlier
wave — is **the same rule** the amendment declares as `[PL-37]`, arrived at independently. The
two packets agree on the method, which is a point in favour of both.

### G.2 What reading those panels did surface

At the canonical rung, PSL-2018 carries `ideo = 0.8620139`. Verified against the BLS file:

| check | result |
|---|---|
| equals the BOLSONARO 2022 **candidate** estimate | **TRUE** |
| equals the PSL 2021 **party** score (0.8033588) | FALSE |
| the 2017 wave scores PSL at all | **FALSE** |
| labelled `ideo_source` | **`"onda"`** — own wave |

So the cell is an imputation — a *candidate* score applied to a *party*, from a wave four years
after the election — and packet I's provenance column records it as a contemporaneous own-wave
party score. The provenance system built specifically to track imputation carries the single
largest imputation in the data as non-imputed. The mechanism is plain: `[I-3]` computes carry
over an ideology table that already had `ideologia_psl` folded in by `02`, so by the time the
carry logic runs, the patch is indistinguishable from a real wave observation.

Scale: **46.01%** of the 2018 presidential vote and **2.92%** of the 2018 governor vote. Of the
96.13% of 2018 presidential vote packet I reports as `"onda"`, roughly 46 points are this.

**This does not change any coverage verdict** — the cell is scored either way, so the gate is
unaffected. What it changes is what the provenance columns mean, and therefore what `[I-3]`'s
reported carried shares (3.24 pp presidential 2018) actually describe: they exclude the largest
imputed cell in the panel.

The fix is one line in whichever script builds the ideology table for packet I — apply the carry
to the **unpatched** `ideologia`, and give the PSL-2018 cell its own source value
(`"patch_candidato"`), so it is visible to every downstream table. Not applied here: it is
packet I's object, `02` must not be modified, and the correction belongs in that packet's
numbering, not this one.

### G.3 What survives from §E unchanged

The `[PL-40]` sensitivity results stand — they were computed by varying the cell directly and
never depended on the gate. Dropping PSL-2018 still moves presidential 2018 `y_bar` from
**+0.083 to −0.450** and `P_dalton` from **0.641 to 0.350**; the party-score arm (d) still moves
little (+0.059 / 0.617). And the break-even sweep still shows the baseline presidential
`delta_EPW` coefficient is null across the whole of [−1, 1], with the reconstruction validated
to `max |diff| = 0` against the stored estimation frame.
