> **STATUS 21/09/2026 — RUN, AND BLOCKED AT L2. Do not re-run as written.**
> `[PL-19]` fails before `[PL-27]` is reached: matched vote share is 90.2 / 81.0 / 76.8 /
> 84.8% for 2010 / 2014 / 2018 / 2022. The `[PL-34]` ceiling test proves this is **not** a
> crosswalk problem — no possible crosswalk clears 2014. L3 (the human codebook step) is
> therefore **not worth doing** under this specification. Full detail and tags
> `[PL-28]`–`[PL-36]` in `RATIONALE_L.md`. Three premises in this spec were wrong and are
> corrected inline below.

# ⚠️ PACKET L — SEPARATE TRACK. NOT PART OF PACKET E. ⚠️

> **For Claude Code:** this packet is **not** authorised by the Packet E prompt.
> Do not run any stage of it while working on PE1–PE5, and do not read it as
> context for them. It is invoked only by its own opening message, which names
> Packet L explicitly. If you arrived here from `prompt_claude_code_e_series.md`,
> stop and go back.
>
> **For Yago:** Packet E answers *does the shock bite, and does S3 behave better*.
> Packet L answers a different question — *is the outcome measured at the right
> level* — on a different branch, with its own baseline and its own failure mode.
> Running them in one session is how the two get confused in the write-up.

**Branch:** `packet-L-legislativo`, cut from the Phase 2 commit.
**Scripts:** `data/códigos/01b_extraction_legislativo.R`, `02b_polarization_legislativo.R`
**Outputs:** `output/packet_L/`
**Audit tags:** `[PL-n]` — distinct from `[PE-n]` (Packet E), `[E-n]` (`00_epw_calculo_v7.R`), `[D-n]`, `[M-n]`.
**Log:** `RATIONALE_L.md`

---

## 1. Why this exists

**CORRECTED 21/09.** The BLS file carries **13 / 14 / 20 / 20 party scores** for the
2010 / 2014 / 2018 / 2022 elections — not the ~12/19/26/20 originally written here. That
figure subtracted a uniform number of presidents from each wave without checking; the 2009
wave contains **no** presidents, 2013 contains six, 2017 seven, 2021 one. The 2014 count was
overstated by a third, and 2014 is the year that fails hardest.

The presidential panel uses five or six of those scores, so the underuse is real — but it is
not "three quarters", and the Chamber has 27 / 32 / 35 / 32 parties taking votes against
13 / 14 / 20 / 20 available scores. **That gap, not label drift, is what blocks the packet.**

The concrete symptom: on the presidential panel, first-place vote share explains
**96%** of `P_dalton` variance in 2022 (P2), the index is **concave** in that
share with a turning point at 0.43–0.49, and **74% / 84%** of microregions sit on
the descending branch in 2018 / 2022. That is not a robustness problem. It means
`P_dalton` is a transformation of a single scalar, and the mapping from the
model's grievance tilt to the index has the wrong sign over most of the sample.

A Chamber of Deputies panel has the same election years (2010, 2014, 2018, 2022),
so it drops into the existing stacked first-difference design with **no timing
change and no new baseline** — unlike the municipal alternative, which has no
2010 election at all.

## 2. The decision rule, declared before running

`[PL-27]` is the test. Regress `P_dalton` on first-place vote share by year, at
the Chamber level.

- **R² materially below the presidential 0.96** → the level change worked, the
  index is measuring a distribution, and the Chamber outcome becomes the primary
  measurement in Chapter 3.
- **R² comparable to 0.96** → the level change bought nothing. Abandon the branch,
  record why in `RATIONALE_L.md`, and keep the presidential panel with the
  Jacobian figure (work plan item 15) as the honest patch.

Declare this before looking. It is the whole point of running the branch.

## 3. What is genuinely different from the presidential build

### `[PL-2]` Proportional races have two vote types — this is the easy thing to get wrong

`01_extraction.R` BLOCK C reads `elections_tse(type = "vote_mun_zone")`, which
carries **nominal (candidate) votes only**. Correct for a majoritarian race.
Wrong here: a party's Chamber total is *nominal + legenda*, and dropping legenda
understates brand-voting parties (PT, PSOL) relative to candidate-centric ones —
a bias that runs straight along the ideology axis the index is built on.

`01b` reads `type = "party_mun_zone"` instead, which carries both, and reports
the legenda share per year (`tab_pl_vote_types.csv`). Typically 3–8%.

### `[PL-4]` Coalitions attribute votes to parties, not coalitions

Proportional coalitions (pre-2018) pooled *seats*, not votes. TSE records both
nominal and legenda votes against the party the voter selected, so party-level
attribution is valid. The coalition label is retained for diagnostics only.

### `[PL-13]` The PSL patch does not carry over — but the stated reason was WRONG

`02_polarization_indices.R` substitutes the BOLSONARO 2022 estimate for PSL in
2018. That is a *presidential* device — it scores a candidate — and must not be
reused for a party-level outcome. **That part stands and is enforced by assertion.**

**The justification given here was false.** This spec claimed "the 2017 wave scores PSL as a
party directly" and wrote it as a `stopifnot`. It does not: **PSL is scored in exactly one
wave, 2021** (`ideo` = 0.803). The 2017 wave — the one mapping to the 2018 election — has no
PSL entry. The claim was inferred from seeing PSL in the file's entity list without checking
which wave it sat in: exactly the "asserted from plausible inference rather than inspection"
failure that `D_data_contracts.md` §0a exists to prevent, written into a contract.

Consequence: PSL took **11.64%** of the 2018 Chamber vote and cannot be scored from the
contemporaneous wave. That single hole is most of the way to failing `[PL-19]` in 2018.
Symmetrically in 2022, the 2021 wave scores DEM and PSL separately but both had merged into
**UNIÃO** by the election, which no wave scores — **9.30%** dropped, while two now-unusable
labels sit idle.

### `[PL-15]` The party crosswalk is the actual work

With five or six labels, name drift never mattered. With 25–30 across four cycles
it is the binding constraint: PMDB→MDB, PR→PL, PRB→REPUBLICANOS, PPS→CIDADANIA,
PTN→PODE, PEN→PATRIOTA, PTdoB→AVANTE, PSDC→DC, and DEM+PSL→UNIÃO.

**`02b` ships the crosswalk deliberately incomplete and refuses to run until it
is verified.** On first run it seeds `party_crosswalk_bls.csv` with identity rows
only (TSE label == BLS label, no judgement involved) and stops. Every other row
must be filled from the **Zucco & Power BLS codebook**, which states which legal
party each score refers to in each wave.

Two rules for filling it:

1. A **renaming** earns a row only if the codebook says the score follows the
   renamed party. Do not infer it from the name.
2. A **merger is not a renaming.** UNIÃO (DEM + PSL, 2022) gets a row only if the
   2021 wave scores it. Otherwise its votes are dropped and the loss shows up in
   the coverage table — which is the correct, visible outcome.

Unresolved cases to adjudicate rather than assume, flagged by the script:
`PP` vs `PPold` (which wave is which?), and what `CID` denotes — it appears as
early as the 1990 wave, so it is not simply Cidadania.

### `[PL-19]` Coverage threshold, declared in advance

More than **15%** of votes without an ideology score in any year is a stop, not a
footnote: an index built on 80% of the vote is not comparable to one built on
98%, and the missing fraction is not random across the ideology axis. The script
errors rather than continuing.

## 4. New indices, and what each is for

| index | role |
|---|---|
| `P_dalton`, `P_center` | unchanged formulas, for comparability with the presidential level |
| `P_er_10`, `P_er_14` | Esteban–Ray, α = 1.0 / 1.4, formula taken **verbatim** from `packet_D/E0_frame.R` so the levels are comparable. α is pre-fixed by the specification, not selected. |
| `P_rq` | Reynal-Querol — **distance-free**. Ignores the ideology scores entirely. If results are unchanged with and without it, the BLS scores are doing no work, and you want to know that before defending them. `[PL-20]` |
| `P_dip` | Hartigan dip statistic. Tests unimodality directly, so it is monotone in bimodality and sidesteps the Dalton concavity problem. **Exploratory.** `[PL-21]` |
| `y_bar` | vote-weighted mean ideology — **directional**, not dispersion. What Proposition 1 actually predicts. `packet_I` has it for governor and nothing has it elsewhere. |

`[PL-21]` note: the dip test needs a continuous sample and a 25-point support is
degenerate. `02b` draws 5,000 voters with probability `v_rpt` and jitters each by
that party's **own** `ideo.se`, which is in the BLS file. This propagates the
ideology measurement error the rest of the pipeline ignores, rather than adding
arbitrary noise. Fixed seed, `set.seed(2026)`. Never a headline number.

**Foster–Wolfson was considered and rejected.** `ideo` is standardised around
zero on roughly [−1, 1]; FW requires a Gini and divides by the median, so it is
undefined on negative support and unstable near a zero median. It would need an
affine rescaling to which the index is **not invariant**. Esteban–Ray is the
correct family here — it depends on |y_p − y_q| and is translation-invariant.
Record this in `RATIONALE_L.md` so the choice is defensible rather than absent.

## 5. Stages

| stage | script | gate |
|---|---|---|
| L1 | `01b_extraction_legislativo.R` | `[PL-10]`/`[PL-11]`: microregion count matches the presidential panel; unmapped votes < 0.5%. |
| L2 | `02b_polarization_legislativo.R`, first run | Seeds `party_crosswalk_bls.csv` and **stops**. |
| L3 | fill the crosswalk from the codebook | **Human step. Not delegable.** Set `verified = TRUE` only on rows actually checked. |
| L4 | `02b`, second run | `[PL-19]` coverage gate, then `[PL-27]` the decision rule. **STOP AND REPORT.** |

Do not build differences, join the estimation frame, or run a single regression
in this packet. L4 produces a measurement verdict; whether the Chamber outcome
enters the design is a separate decision taken on that verdict.

## 6. BigQuery

The `electionsBR` path reads TSE directly and costs nothing — it is the default,
and given the G2 incident (a cached OAuth token billed to a real GCP account
without authorisation) it should stay the default.

`01b` carries commented basedosdados queries for **validation only**, with a
mandatory schema check first, because basedosdados column names have moved
between releases. One property makes the cross-check worth its cost: basedosdados
carries `id_municipio` (IBGE) natively, so the BigQuery route does **not** need
the Passuelo crosswalk. Comparing microregion assignment between the two routes
is therefore an independent test of the TSE→IBGE mapping used by BLOCK C — any
disagreement is a finding about the existing presidential and governor panels,
not only about this one.

Set a billing cap before running it. `[PL-12]` reconciles the two pulls at 0.1%.
