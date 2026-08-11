# RATIONALE — Packet D

Change log for the D series: worker-characteristic balance (`G4`) and the
exogenous-demand shift-share extension. Companion to `RATIONALE.md`; same
protocol. One entry per audit tag; every number that reaches the manuscript must
trace to a script committed here and to an entry below.

Append to `RATIONALE.md` when the packet closes.

**Standing protocol.** No console-only runs. Every estimation writes a run log to
`output/`. Commit before and after any re-run so the diff is inspectable.

**This file is authoritative.** It supersedes `RATIONALE_D_amendments.md`
(2026-08-10, second pass), whose contents are folded in below. Delete that file.

---

## Section 0 — provenance

Created 2026-08-10; consolidated the same day. The packet originates in two
places:

1. A qualification-committee annotation: *"testar robustez por destino
   (destino × ano eleitoral), cada j seria um destino"* — make the destination,
   not the industry, the shock unit.
2. An independently-arrived-at ADH-style construction: keep the industry as the
   shock unit but replace realised Brazilian exports with rest-of-world demand.

These are different proposals and the packet runs both. See `[D-1]`.

`G4_sector_chars.R` is a prerequisite rather than part of the packet proper: it
builds the artefact whose absence made the BHJ balance test in
`07_regression_inference.R` §6 a dead branch. It is logged here because its
result changes how the packet must be motivated (`[D-0-6]`).

---

## Section 1 — `G4`: sector_chars.rds and the dead balance test

### [D-0-1] Education cut fixed at `grau_instrucao_apos_2005 ≤ 6`

RAIS codes education 1–11; 7 is completed secondary. `sh_loweduc` is therefore
the FTE-weighted share of links **strictly below completed secondary**.

Recorded as a coding choice rather than a default, and exposed as `LOWEDUC_MAX`
at the top of the script rather than inline, because the balance test's power
depends on it and a reader must be able to see it moved. Not tuned: the value was
set before the test was run.

### [D-0-2] Crosswalk integrity — the check is absolute, and the committed copy is defective

**Finding: `cnae_isic_crosswalk 2.rds` is wrong and must not be used.**

The first version of this check compared the fresh CNAE→ISIC build against the
committed `.rds` and warned on any difference. It warned on every run. The
artefact, not the build, is at fault.

| | pairs | distinct cnae4 | distinct isic4 |
|---|---|---|---|
| fresh build from `CNAE20_ISIC4.xls` | **743** | 672 | 416 |
| `cnae_isic_crosswalk 2.rds` | 1,146 | 1,003 | 711 |

All 743 fresh pairs are contained in the 1,146, so the artefact is a strict
superset with **403 spurious pairs**. Every one of the 403 is explained by a
single mechanism: the old script used `str_pad(code, 4, pad = "0")` where the v7
pipeline uses `str_sub(code, 1, 4)`. Left-padding promotes CNAE and ISIC
*aggregates* to counterfeit 4-digit *class* codes — `"01" → "0001"`,
`"011" → "0011"`. Decomposition of the 403: 283 from 3-digit groups, 104 from
2-digit divisions, 8 from 1-digit, 8 from blank rows. This is the origin of the
impossible codes `0001`, `0011`, `0025` and of the many rows where
`cnae4 == isic4`.

**Not cosmetic.** The counterfeit targets inflate the denominator in
`w_cnae = 1 / n()` for ten live classes:

| cnae4 | correct n | artefact n |
|---|---|---|
| 0111 | 2 | 3 |
| 0121 | 3 | 4 |
| 0132 | 1 | 2 |
| 0133 | 5 | 6 |
| 0141 | 7 | 9 |
| 0142 | 1 | 2 |
| 0151 | 1 | 2 |
| 0152 | 2 | 3 |
| 0721 | 1 | 2 |
| 0722 | 1 | 2 |

Joining employment to the artefact would split cereals across three ISIC targets
instead of two, and ISIC 0721 across two instead of one.

**Published results are unaffected.** `00_epw_calculo_v7.R` rebuilds the
crosswalk from the workbook on every run. A grep over every `.R`/`.r` in the tree
finds no reader of `cnae_isic_crosswalk 2.rds`. It is an orphan from the
`epw_calculo.r` era; the `" 2"` suffix is macOS duplicate-file naming.

**Resolution.** `[D-0-2]` now pins the fresh build against absolute constants —
743 pairs, 672 CNAE4, 416 ISIC4, largest split `1/7` — and adds a direct guard
that aborts if any `cnae4` or `isic4` begins `"00"`, since no real CNAE 2.0 or
ISIC rev. 4 *class* code does. That guard is what would have caught the defect at
source. The artefact is flagged with a NOTE on every run.

**Action outstanding:** rename or delete `cnae_isic_crosswalk 2.rds`. Nothing
reads it today, but it sits in `DATA_DIR` under a plausible name with 55% row
inflation, and Packet D introduces new scripts that could pick it up.

### [D-0-3] ISIC 0143 is absent from the CNAE parse and this is correct

`rais_isic_v7.rds` contains ISIC `0143`; the STEP 2 crosswalk does not. This looks
like a bug and is not one.

`0143` is camelid rearing. Row 60 of `CNAE20_ISIC4.xls` carries `"-"` in both CNAE
columns because Brazil has no corresponding class, so `clean_code()` returns `""`
and the `^[0-9]{4}$` filter drops it — correctly. It re-enters as a **composite
label**: `composite_map_v7.rds` heads the group `{0143, 0145, 0146, 0149}` with
`0143`, and the other three members are reachable from CNAE. The industry-set
assertion in STEP 5 runs *after* composite mapping and therefore passes; all 152
v7 industries are recovered.

Recorded because the tempting repair — loosening the STEP 2 filter to admit it —
would reintroduce exactly the padding defect of `[D-0-2]`.

### [D-0-4] `sector_chars.rds` built; construction decisions

**Why a new BigQuery pull was unavoidable.** No local artefact carries worker
characteristics. Audited: `rais_2010.rds` and `rais_2010_micro.rds`
(`total_vinculos` only), `rais_fte.rds` (`total_fte` only), `rais_isic_v7.rds`
(`workers` only), `rais_fte_panel_2010_2022.rds` (FTE, links, links-3112,
`wagebill_nominal`). The last supports a mean wage but carries no education, race
or sex. `01_extraction.R` BLOCK A never requested those columns.

Decisions, each of which could reasonably have gone the other way:

1. **FTE weighting, not link counts.** Characteristics are weighted by annualised
   FTE using the `mes_admissao`/`mes_desligamento` expression of
   `01_extraction.R` BLOCK A2 verbatim, so they carry the same employment measure
   as the exposure shares. Counting links would silently reweight seasonal
   industries — a three-month harvest contract would count the same as a
   year-round one.
2. **Per-variable denominators.** Item non-response differs across education, race
   and sex, so each share carries its own denominator rather than a common `N`.
   Coverage is reported per industry (`cov_educ`, `cov_raca`, `cov_sexo`,
   `cov_wage`) and retained in the saved object.
3. **`mean_lnwage` is the mean of logs, not the log of the mean**, computed over
   strictly positive `valor_remuneracao_media`. Nominal 2010; no deflation, as
   this is a single cross-section.
4. **Counts, not shares, carried through the `w_cnae = 1/n` split**, so the
   fractional CNAE→ISIC allocation aggregates correctly. Shares are formed only
   after composite aggregation.
5. **`composite_map_v7.rds` is loaded, never recomputed.** The export-side
   signature that generated it is not reconstructible from this script's inputs.

**Guards.** A schema probe runs before the billed query and aborts with the real
field list if `grau_instrucao_apos_2005` / `raca_cor` / `sexo` have been renamed.
An encoding assertion catches the failure mode where those columns are stored as
labels rather than codes — `SAFE_CAST` would return NULL and every share would
silently be zero. `CONFIRM_SCAN` defaults to `FALSE`: the script prints the
dry-run scan estimate and stops, because the query is billed.

**Result.** 152 industries, matching the v7 universe exactly.

| | mean | sd | min | max |
|---|---|---|---|---|
| `sh_loweduc` | 0.444 | 0.186 | 0.029 (3030) | 0.889 (0121) |
| `sh_white` | 0.680 | 0.121 | 0.148 | 0.913 |
| `sh_male` | 0.769 | 0.146 | 0.253 | 0.957 |
| `mean_lnwage` | 7.163 | 0.413 | 6.540 (0121) | 9.000 (0610) |

Item-response coverage, minimum across industries: education 1.000, sex 1.000,
wage 0.948, **race 0.750**. `sh_white` is computed on known-race links only and
that must appear in the table note.

*TO FILL from the run log: the national FTE-weighted male / white / low-education
shares printed by the encoding assertion.*

### [D-0-5] BHJ balance on workforce characteristics — the test that was dead

`07_regression_inference.R` §6 now executes its live branch. Exposure-weighted by
national employment shares `[A-6]`, regressing the shock on
`sh_loweduc + sh_white + sh_male + mean_lnwage`, `df1 = 4`, `df2 = 147`.

| shock | year | F | p |
|---|---|---|---|
| `g_jt` | 2014 | 3.815 | **0.0056** |
| `g_jt` | 2018 | 1.906 | 0.113 |
| `g_jt` | 2022 | 5.186 | **0.00062** |
| `g_arc` | 2014 | 4.822 | **0.0011** |
| `g_arc` | 2018 | 5.838 | **0.00022** |
| `g_arc` | 2022 | 2.734 | **0.031** |

Read jointly with `G3_bhj_balance.csv`, which balances the same shocks on *trade*
characteristics (`commodity + log_exp2010`), **one of twelve cells passes at 5%**:

| shock | year | trade chars (G3) | workforce chars (G4) |
|---|---|---|---|
| `g_jt` | 2014 | 0.298 | **0.0056** |
| `g_jt` | 2018 | 0.295 | 0.113 |
| `g_jt` | 2022 | **0.013** | **0.00062** |
| `g_arc` | 2014 | **3.6e-6** | **0.0011** |
| `g_arc` | 2018 | **5.4e-7** | **0.00022** |
| `g_arc` | 2022 | **0.0031** | **0.031** |

This supersedes the earlier reading that only 2022 was problematic. The level
shock passes trade balance in 2014 and 2018 but fails workforce balance in 2014
and 2022.

**G3 and G4 are not independent tests.** `sh_loweduc` and `mean_lnwage` are near
proxies for the commodity indicator — mining is high-wage and high-education,
agriculture the reverse. They should be reported as two views of one failure, not
as two failures. See `[D-0-6]`.

### [D-0-6] Interpretation: the EPW shock is a capital-intensity gradient

Four diagnostics, one underlying fact. Recorded here so that §3.4 states it once
rather than reporting the symptoms separately.

1. **Exports per formal FTE, 2010** (10k USD): agriculture 1.6 (11 industries,
   1.49M FTE), manufacturing 1.6 (130 industries, 7.58M FTE), **mining 23.1** (11
   industries, 207k FTE). Agriculture and manufacturing are identical; mining is
   14× either. At industry level, ISIC 0610 crude petroleum 56.7 (28,749 FTE) and
   ISIC 0710 iron ore 80.1 (36,052 FTE).
2. **Rotemberg weights** concentrate on those same two industries: α(0710) = 0.576
   in 2014 and 0.600 in 2018; α(0610) = 0.229 in 2018 and 0.657 in 2022.
3. **Effective number of shocks** under the level specification: 2.88 / 2.51 /
   2.38, mean 2.59.
4. **Workforce balance** fails on precisely the axis that separates those
   industries: 0610 has `sh_loweduc` 0.045 and `mean_lnwage` 9.000 — the highest
   wage in the sample — against 0.889 and 6.540 for perennial crops.

The common cause: `g_jt = ΔEXP_jt / L_j,2010` divides a value by a headcount, and
exports per worker is not proportional to the labour-market dislocation a worker
experiences. A one-billion-dollar export collapse in iron ore and the same
collapse in footwear are identical in dollars and wildly different in jobs. The
treatment is dominated by industries employing almost nobody, while the mechanism
in Figure 1 runs through local labour demand.

**Consequence for the paper.** The shocks perspective presupposes quasi-random
shock assignment. It is now demonstrably violated, which explains the AKM placebo
over-rejection (~21% at 5% nominal) rather than merely restating it. This
strengthens the methodological contribution and simultaneously weakens the null:
"no detectable effect" now sits inside a design that fails its own exogeneity
check, and the text must concede that rather than lean on the null as a finding.
This is the motivation for Packet D.

### [D-0-7] Correction to the manuscript: "between five and nine effective shocks"

The claim was flagged as unsupported because a grep over scripts, logs and CSVs
returned nothing. **That was wrong** —
`output/revision/G3/G3_rotemberg_concentration.csv`, written 2026-07-30, contains
it. The grep predated `G3`.

The figure in the text is nonetheless loose:

| controls | 2014 | 2018 | 2022 | mean |
|---|---|---|---|---|
| level, base | 2.88 | 2.51 | 2.38 | 2.59 |
| arc, base | 5.20 | 6.09 | 5.42 | **5.57** |
| level, ext | 2.76 | 2.28 | 2.27 | 2.43 |
| arc, ext | 5.53 | 6.14 | 5.03 | **5.57** |

It is **five to six**, not five to nine, on both control sets. Tighten the
sentence rather than softening it; the true range is a cleaner claim than the one
in the draft.

---

## Section 2 — Packet D design decisions

### [D-1] Route: two branches on one ladder, not a single robustness check

Between the published baseline and the committee's destination design, **three
things change simultaneously** — the shock's scale (level → proportional), its
exogeneity (realised → foreign demand) and its unit (industry → destination).
Running the destination design alone would leave the source of any movement
unattributable.

The packet is therefore organised so that each rung changes exactly one thing:

| rung | unit | shock content | scale | crosswalk | isolates |
|---|---|---|---|---|---|
| S0 | industry | realised exports | level | yes | — (baseline) |
| S1 | industry | realised exports | arc % | yes | scale |
| S2L | industry | RoW demand | level | yes | exogeneity at fixed scale |
| S2 | industry | RoW demand | arc % | yes | exogeneity (ADH branch) |
| S3 | destination | RoW demand | arc % | **no** | unit + crosswalk (committee) |

Deliverable: one table, five columns, RI p-values leading, with the AKM placebo
rejection rate as a row. If the null breaks, the responsible assumption is named.

**The ADH branch does not remove the crosswalk.** It applies the same NCM→ISIC
mapping to BACI rather than to Comex, so it inherits crosswalk error — possibly
differently, since the composition of world trade within a category differs from
Brazil's. Only the destination branch is crosswalk-free. Stated explicitly so the
two are not sold as sharing a benefit.

### [D-2] Status of the arc-percentage respecification: not a clean improvement

`G3` establishes that the arc change **raises the effective shock count from 2.59
to 5.57 and destroys shock balance** (`[D-0-5]`, `[D-0-7]`). Arc growth rates are
mechanically related to base size, and commodity industries occupy a distinct
point on that gradient, so the respecification trades one identification problem
for another.

It therefore cannot be presented as a fix. The live question becomes: **can an
exogenous foreign-demand shock deliver the arc's effective-shock gain without the
arc's balance failure?** That is rung S2, and it is the packet's central test.

Level-vs-arc treatment correlation, for the record: Pearson 0.373, Spearman 0.572
pooled (`G3_treatment_correlation.csv`). Not a relabelling — the ladder is
informative.

Reference provenance for the arc measure: derived in Törnqvist, Vartia & Vartia
(1985); named for and standardised by Davis, Haltiwanger & Schuh (1996); the
official denominator of the Census Bureau's Business Dynamics Statistics.
Haltiwanger, Jarmin & Miranda (2013) is the citation that carries the argument —
it shows the small-firm job-creation finding is a regression-to-the-mean artefact
of the base-year denominator, establishing that the choice is substantive rather
than cosmetic.

### [D-3] The dropped IV, and where an IV framing is still defensible

The project record states only that the IV approach was dropped as infeasible and
that the design is reduced-form following Rettl. Two distinct reasons, of which
one is fatal:

1. **No endogenous regressor.** An IV needs a mediating treatment — local
   employment or wages — with polarization as the second stage. The design
   regresses polarization on exposure directly. Absent a measured first stage, an
   "instrument" is not an instrument; it is a different reduced-form shock. This
   is why `G2_first_stage.R` matters: it would supply the missing first stage.
2. **Data and power**: bilateral demand series over three election cycles, with a
   shock space dominated by two industries.

A China-demand instrument is the **single-destination special case** of the
general destination-share construction. The destination shock is therefore not a
revival of the dropped IV but its generalisation, and it is deployed as an
**alternative reduced-form exposure measure**, not a first stage — which keeps
the Rettl framing intact and sidesteps reason (1).

The one place an IV framing survives is the **shock-level** first stage (S2-IV):
instrumenting the realised arc shock with the exogenous arc shock across
industries, which is what BHJ contemplate. It is to be run, reported with its
first-stage diagnostics, and not led with.

**The dropped IV is now identified concretely.** It was not a hypothetical: it is
`03b_instrument_construction.R`, variants IV-A (pure world demand,
`z_jt = (D_jt − D_j,2010) / L_j,2010`) and IV-B (predicted exports,
Costa–Garred–Pessoa form). The script is complete and was run on a machine other
than the current one.

**Reported failure mode: weak first stage.** See `[D-3a]` for its provenance
caveat and `[D-3b]` for why it is close to uninformative.

**No balance test was ever run on IV-A or IV-B.** It could not have been:
`sector_chars.rds` did not exist until 2026-08-10 (`[D-0-4]`), and the
trade-characteristic balance test in `G3` was written 2026-07-30, after the IV
attempt. This matters for `[D-PRE-2]`, which is therefore **not** contradicted by
the earlier failure — the exogeneity premise has never been tested, only
instrument strength.

Expect weakness at S2-IV for a further reason: iron ore and crude petroleum export
values are substantially price-driven, and world import *values* of those goods
move with world *prices* that Brazil is large enough to influence. See the
price-versus-volume threat in `packet_D_spec.md` §D.7.

### [D-3a] Provenance of the IV-A / IV-B failure — recollection, not record

**Status: unverified.** The run log is on a different machine and has not been
recovered. The author's recollection is that both variants failed on **first-stage
strength**, and that no balance test was run. No output of `03b` exists in this
repository — `epw_iv_panel_v1.rds`, `sectoral_demand_iv_v1.rds` and
`output/03b_iv_run_log.txt` are all absent — so the script has never executed
*here*.

Recorded as recollection rather than finding. It must not be cited in the
manuscript in this state.

**Verification is now cheap and is the recommended next action.** As of
2026-08-10 the BACI HS07 V202601 files are present (`[D-4]`), so `03b` can be
re-run end to end. It writes `output/03b_iv_run_log.txt` including first-stage
diagnostics, which converts this entry from recollection into record. Re-run
before building anything new.

### [D-3b] Why a weak first stage under IV-A / IV-B is close to uninformative

The failure is consistent with the design and does not indict the
exogenous-demand premise. Three reasons, all of which the packet is built to
address:

1. **Both variants are level per-worker.** `z_jt` divides by `L_j,2010`, so both
   inherit the capital-intensity gradient of `[D-0-6]` untouched. Fixing
   exogeneity while retaining the level normalisation was never going to dislodge
   ISIC 0710 and 0610 from the design, and the first stage is estimated largely
   off those two industries.
2. **Both aggregate to world totals.** Neither carries destination weights, so
   neither can separate demand growth in the markets Brazil actually sells to from
   world demand at large. For a commodity exporter with a concentrated destination
   mix this is a material loss of signal.
3. **The nominal degrees of freedom are fictitious.** A first stage on 152
   industries is effectively estimated off 2.59 independent shock units under the
   level specification (`[D-0-7]`). A weak F under those conditions is close to
   uninformative in either direction — which is precisely the argument for the
   RI-based criterion in `[D-PRE-3]` rather than a conventional F threshold. The
   observed failure is therefore **supporting evidence for that choice**, not a
   reason to abandon the branch.

What the packet changes relative to IV-A / IV-B: **level → proportional** (rung S1
→ S2) and **world totals → destination weights** (rung S2 → S3). Neither was
tried. The download required for both is the same one already made.

### [D-4] Data acquisition closed, 2026-08-10

Present in `DATA_DIR`:

| artefact | detail |
|---|---|
| `BACI_HS07_V202601/` | 18 annual files 2007–2024, 6.0 GB; `country_codes_V202601.csv`; `product_codes_HS07_V202601.csv` |
| `CEPII Gravity database/` | `Gravity_V202211.rds`, `Countries_V202211.csv` |
| `World Bank historical income classifications.xlsx` | |

**BACI vintage decision closed: HS07, release V202601.** HS07 rather than HS12
because HS12 begins in 2012 and cannot cover the 2010 base year; HS07 spans
2010–2022 in one classification with no splicing. The justification is
`03b_instrument_construction.R` lines 24–29 and predates this packet.

Confirmed on inspection: columns `t, i, j, k, v, q`; Brazil is country code `76`;
values in **thousand USD, current**; quantities in metric tons.

Four operational decisions, each of which will silently corrupt a join if missed:

1. **Directory name.** `03b` expects `baci/BACI_HS07_Y*_V*.csv`. The download
   extracted to `BACI_HS07_V202601/`. Rename the directory rather than editing the
   script, so that `03b` remains byte-comparable to its committed form.
2. **Zero-padding on `k`.** BACI strips leading zeros from HS6 codes in some
   releases. Pad to width 6 before any crosswalk join, or every product in HS
   chapters 01–09 fails to match silently. Assert `all(nchar(k) == 6)` after
   padding.
3. **Deflation.** BACI values are current USD. Deflate with `cpi_us.rds`, as `03b`
   already does. Both endpoints of any arc growth rate must be in the same constant
   currency (`packet_D_spec.md` §D.2).
4. ~~**Country-code harmonisation is a clean numeric join.** BACI's
   `country_code` is the numeric ISO 3166-1 code (4 Afghanistan, 76 Brazil),
   which matches `CO_PAIS_ISON3` in sheet 10 of
   `data/misc/TABELAS_AUXILIARES.xlsx` directly. No name matching is required.
   The unmatched-code log is still written, but the risk flagged in
   `packet_D_spec.md` §D.7 is much smaller than anticipated.~~

   > **SUPERSEDED 2026-08-10 by `[D-20]`. This item is false.** BACI keys on UN
   > Comtrade **area** codes, not ISO 3166-1: the United States is 842, not 840.
   > A numeric join drops 15.17% of 2010 export value across 19 areas, Brazil's
   > second-largest destination among them. Struck through rather than deleted so
   > that the error, and the fact that it was asserted without inspection, stay
   > in the record. Join on alphabetic `iso3` plus the explicit 14-entry
   > aggregation map; see `D_data_contracts.md` §1b as corrected.

   The one part of this item that survives: CEPII Gravity keys on alphabetic
   `iso3`, routed through `Countries_V202211.csv` `iso3num` or BACI's
   `country_iso3`.

**Open:** whether `Gravity_V202211.rds` carries `gdpcap_d` for 2010. If it does,
the World Bank WDI pull is unnecessary and the destination-characteristic set for
the balance test comes from one object together with `dist`, `contig` and
`comlang_off`. Check on first read; the file was too large to inspect outside R.

**Housekeeping:** only 2010, 2014, 2018 and 2022 are required, since shocks are
cumulative against 2010. The other fourteen year files (4.7 GB) should be moved
out of the working directory so that no `list.files()` glob pulls the full panel.

**Branch A share data needs no download.** `EXP_YYYY_MUN.csv`, 2010–2022, in
`tema mestrado/data/exportações/`, carries `CO_ANO; CO_MES; SH4; CO_PAIS;
SG_UF_MUN; CO_MUN; KG_LIQUIDO; VL_FOB` — 226 destinations in 2010, 730k rows.
Two caveats: product detail is **SH4, not HS6**, so the `ω_pd` basket weighting is
coarser than `packet_D_spec.md` §D.4.2 specifies; and the files sit outside
canonical `DATA_DIR`, so copy them in rather than pointing a script across trees.

### [D-5] Tag-numbering conflict with `D_data_contracts.md` — this file wins

`D_data_contracts.md` instructs that the microregion-count resolution be logged
as `[D-1]` and the country-code harmonisation as `[D-3]`. Both tags are already
occupied here — `[D-1]` is the two-branch ladder, `[D-3]` the dropped IV — and
this file is authoritative (§0). Packet D therefore continues the numbering from
`[D-5]`. The contracts file's tag suggestions are void; its *schemas* are not.
Recorded so that a reader who greps `[D-1]` and finds a ladder rather than a
microregion count knows why.

### [D-6] A UTF-8 locale is a hard prerequisite, and this is not cosmetic

`03b` failed on its first execution here, at STEP 3, with
`cannot open the connection` on `hs2007_hs2012.csv` — a file that exists and
that `file.exists()` had just confirmed two lines earlier.

Cause: a non-interactive shell on this machine gives R
`l10n_info()$codeset == "US-ASCII"`. `readr` resolves a relative path to an
absolute one before opening it, and under an ASCII codeset the absolute path
`…/dissertação/…/versão com vínculos totais/…` comes back as a **mixed**
NFD/NFC byte string (`dissertac<cc><a7>a<cc><83>o` decomposed, `vers<c3><a3>o`
precomposed). libc rejects it. `base::read.csv` on a relative path is
unaffected, which is why the failure looks intermittent across the pipeline.

This is the same defect `revision/R00_setup.R` lines 32–35 works around for
*writes*; the read side was never diagnosed. **Fix is environmental, not
textual:** run every script with `LANG=en_US.UTF-8`. Nothing was edited to
accommodate it, and `03b` is byte-identical to its committed form
(sha256 `54bbac0a…b98cedd2`, unchanged before and after).

### [D-7] Microregion count resolved: **557**, and the 1,668 / 1,671 / 1,674 spread explained

`D_data_contracts.md` requires `N_MICRO_EXPECTED` be pinned to one value.
Pinned to **557**, verified against every v7 artefact rather than asserted:

| object | microregions |
|---|---|
| `exposure_shares_isic_v7.rds` | 557 |
| `epw_panel_isic_v7.rds` | 557 |
| `rais_isic_v7.rds` | 557 |
| `df_estimation_v7.rds` | 557 (1,671 rows = 557 × 3) |
| `controls_micro.rds` | **558** |

The 558 is the IBGE 2010 territorial division. The one microregion that carries
controls but no exposure is **13002 (Japurá, AM)**: `manuf_share_of_tradable`
is `NA` because it has no tradable formal employment in RAIS 2010, so it cannot
receive a share and is dropped at construction, not by a filter anyone wrote.

The table-N spread follows mechanically and is **not** three different samples:

- **1,674** = 558 × 3 — the count if 13002 were retained. Appears nowhere in a
  live artefact; it is the arithmetic a reader performs from "558 microregions".
- **1,671** = 557 × 3 — the estimation sample. This is the correct N.
- **1,668** = 1,671 − 3 — `fixest` drops three `state^year` singletons in
  specifications carrying that fixed effect. Confirmed in `03b`'s own log
  (`3 fixed-effect singletons were removed`) and reproduced in `D0`.

**Separate finding, as instructed: the manuscript's 556 was not reproduced by
any object loaded here.** It is not the estimation sample, not the share
universe and not the territorial division. Either it is stale or it comes from a
vintage not in this tree. It should be treated as an error and corrected to 557
unless a source is produced. Packet D asserts 557 everywhere and does not
inherit the ambiguity.

### [D-8] Base `grDevices::pdf`, not `cairo_pdf`

This R has no working cairo (`libXrender`/`libSM` absent; no XQuartz), so
`cairo_pdf` fails at device open and `ggsave` writes nothing while exiting 0 —
a silent failure. Both are vector devices. Figures use the base device. Do not
"upgrade" this.

---

## Section 2b — Stage 0 results: `03b` re-run, and what the instruments do

Executed 2026-08-10 by an unmodified `03b_instrument_construction.R` plus the
new, purely diagnostic `códigos/packet_D/D0_iv_diagnostics.R`. Outputs in
`output/packet_D/`. **No outcome regression was run**; `[D-PRE-2]` was addressed
from the shocks alone, before the polarization panel was touched, which makes
specification search structurally impossible at this stage.

Two canaries gate everything below. `D0` reproduces the twelve published balance
cells of `G3_bhj_balance.csv` / `G4_bhj_balance_workforce.csv` to
`max|ΔF| = 2.0e-14`, and the effective-shock benchmarks 2.5896 / 5.5689 to
`< 1e-6`. The new numbers are therefore on the same ruler as the old ones, not
merely similar to them.

### [D-9] `[D-3a]` converted from recollection to record: the F values

The author's recollection was **correct**. Both IV-A and IV-B are weak; IV-B is
not weak but empty.

| level | endogenous | instrument | β | t | **F** | within-R² |
|---|---|---|---|---|---|---|
| industry | `g_jt` | `z_A` | +0.00714 | 1.72 | **2.97** | 0.044 |
| industry | `g_jt` | `z_B` | +0.02114 | 0.08 | **0.01** | 0.0001 |
| industry | `g_jt` | `z_CHN` | +0.05481 | 4.73 | **22.33** | 0.218 |
| industry | `g_arc` | `z_A` | +0.00028 | 1.43 | 2.04 | 0.004 |
| industry | `g_arc` | `z_B` | +0.03473 | 1.70 | 2.89 | 0.013 |
| industry | `g_arc` | `z_CHN` | +0.00136 | 3.01 | 9.04 | 0.008 |
| region | `ΔEPW` | `EPW_IV_A` | +0.01879 | 2.21 | **4.88** | 0.177 |
| region | `ΔEPW` | `EPW_IV_B` | −0.15563 | −0.37 | **0.14** | 0.023 |
| region | `ΔEPW` | `EPW_IV_CHN` | +0.06748 | 5.17 | **26.71** | 0.378 |

With one excluded instrument, `F = t²` is simultaneously the robust first-stage
Wald F, the Kleibergen–Paap rk Wald F and the Montiel Olea–Pflueger effective F,
so these are directly comparable to the 23.1 benchmark of `[D-PRE-3]`.

**The surprise is IV-C.** The China variant — which `packet_D_spec.md` §D.4 and
`[D-3]` identify as the *single-destination special case of Branch A* — is the
only variant that clears the benchmark, at 22.3 (industry) and 26.7 (region).
The header comment's expectation that "z_B [will be] strongly predictive — it
embeds Brazil's product mix" is exactly inverted: `z_B` is the weakest series in
the packet. Preserving Brazil's 2010 product mix while letting only RoW growth
move turns out to remove essentially all covariation with the realised shock.

That the destination-restricted variant is the strong one is the first
independent evidence for the committee's proposal, and it arrives from the
branch that was supposed to be a diagnostic afterthought.

### [D-10] Balance: exogeneity at fixed level scale does **not** restore workforce balance

`[A-6]` national employment weights, `df1 = 4`, `df2 = 147` (workforce);
`df1 = 2`, `df2 = 149` (trade). Bold = fails at 5%.

**Workforce characteristics** (`sh_loweduc + sh_white + sh_male + mean_lnwage`):

| shock | 2014 | 2018 | 2022 | cells passing |
|---|---|---|---|---|
| `g_jt` | **0.0056** | 0.113 | **0.00062** | 1 / 3 |
| `g_arc` | **0.0011** | **0.00022** | **0.031** | 0 / 3 |
| `z_A` | **1.6e-10** | 0.095 | **4.2e-06** | 1 / 3 |
| `z_B` | **3.4e-06** | **0.031** | **0.0051** | 0 / 3 |
| `z_CHN` | **7.9e-07** | **1.2e-06** | **3.7e-06** | 0 / 3 |

`z_A` and `z_B` pass **1 of 6**. `z_A` in 2014 fails at F = 15.36, four times
worse than `g_jt`'s 3.81 in the same cell. This is a failure at least as bad as
the one the packet exists to repair.

**Trade characteristics** (`commodity + log_exp2010`):

| shock | 2014 | 2018 | 2022 | cells passing |
|---|---|---|---|---|
| `g_jt` | 0.298 | 0.295 | **0.013** | 2 / 3 |
| `g_arc` | **3.6e-06** | **5.4e-07** | **0.0031** | 0 / 3 |
| `z_A` | 0.082 | 0.094 | 0.329 | **3 / 3** |
| `z_B` | **0.00021** | 0.078 | **0.0015** | 1 / 3 |
| `z_CHN` | 0.133 | 0.233 | 0.131 | **3 / 3** |

**`[D-PRE-1]` is confirmed at the exogenous level rung.** `g_jt` fails trade
balance in 2022 at p = 0.013; `z_A` passes at p = 0.329 and `z_CHN` at p = 0.131.
The prediction — that the 2022 failure reflects Brazilian supply expansion
(pre-salt) rather than destination demand, and that removing Brazil from the
numerator removes it — holds. Recorded as the packet's first pre-registered
prediction to survive contact with data.

**The two characteristic sets now separate cleanly**, which `[D-0-5]` said they
would not. On the realised shocks they are two views of one failure. On the
exogenous shocks they diverge: `z_A` and `z_CHN` are 3/3 on trade and 1/3 and
0/3 on workforce. Exogeneity buys trade balance and buys nothing on workforce.

**Which axis fails.** Coefficients (weighted, `s_bar`) locate it exactly where
`[D-0-6]` said it would be. For `z_A` in 2014, `mean_lnwage` carries t = 6.26
and `sh_male` t = −3.43; in 2022, `mean_lnwage` t = 3.95. The wage gradient —
the capital-intensity gradient — is the failing axis, untouched by replacing
realised exports with foreign demand.

### [D-11] Effective shocks: the level normalisation is doing all the work

Mean of yearly, base controls, identical `W` and `rotemberg_for()` throughout.

| shock | 2014 | 2018 | 2022 | **mean** | top-1 α | dominant industry |
|---|---|---|---|---|---|---|
| `g_jt` (S0) | 2.88 | 2.51 | 2.38 | **2.59** | 0.59 | 0710 → 0610 |
| `g_arc` (S1) | 5.20 | 6.09 | 5.42 | **5.57** | 0.35 | 0111 |
| `z_A` (S2L) | 1.55 | 1.93 | 1.86 | **1.78** | 0.74 | **0610** |
| `z_B` (S2L) | 3.83 | 3.02 | 1.80 | **2.88** | 0.53 | 0710 |
| `z_CHN` | 1.23 | 1.27 | 1.23 | **1.25** | 0.89 | **0610** |

**Exogeneity alone makes concentration worse, not better.** `z_A` falls to 1.78
against the baseline's 2.59 — the exogenous instrument is *more* concentrated
than the shock it was built to replace, with ISIC 0610 crude petroleum carrying
α = 0.82 / 0.75 / 0.73. `z_CHN` is the extreme: 1.25 effective shocks, α(0610)
≈ 0.90 in all three cycles. China's import demand *is* petroleum, and IV-C's
strong first stage in `[D-9]` is very largely one industry.

`z_B` at 2.88 is the only exogenous series above baseline, and it is the one
with no first stage at all.

This is `[D-3b]` item 1 promoted from conjecture to measurement. Dividing by
`L_j,2010` is what concentrates the design; whether the numerator is realised
Brazilian exports or Brazil-excluded world demand is close to irrelevant to
concentration. The arc respecification, whatever else is wrong with it, is the
only change so far that has moved the effective shock count at all.

### [D-12] BACI housekeeping executed

`BACI_HS07_V202601/` → `baci/` was already done before this session. The
fourteen unused year files (4.4 GB) were moved to
`dados consolidados/baci_unused_years/`, outside `DATA_DIR`, leaving 2010, 2014,
2018, 2022 and the two metadata files. Same-volume rename; reversible.

Sanity anchors from the `03b` log, all within expected range: world trade
excluding Brazil 14.7 → 23.6 T USD current (2010 → 2022); Brazil's exports
0.22 → 0.36 T; China's imports excluding Brazil 1.17 → 2.21 T. Dictionary hit
rate 98.3% of value by direct match, 1.66% residual orphan, 0% recovered by the
HS2007→HS2012 bridge. BACI/Comex 2010 Brazilian export ratio **1.072**
(214.9 B vs 200.4 B), inside the 0.9–1.1 band the script anticipates.

---

## Section 2c — Stage 1 step 1: Branch A shares

`D1_shares_destino.R`, run 2026-08-10. Comex `EXP_2010_MUN.csv` only — no BACI,
no crosswalk, no ISIC. No outcome regression.

### [D-13] Auxiliary sheets are addressed by name, not index

`TABELAS_AUXILIARES.xlsx` has a leading `ÍNDICE` sheet, so the sheet **named**
`"10"` (countries) is the 11th and `excel_sheets()[10]` returns the NCM→PPE
table. A positional read joins zero countries and raises no error. Sheet `"13"`
is the Comex municipality directory.

### [D-19] Comex uses pre-1988 IBGE UF codes — 31.2% of exports at stake

`CO_MUN` is IBGE's 7-digit geocode with the UF prefix frozen at the pre-1988
numbering for four federal units. The trailing five digits are identical.

| UF | Comex prefix | IBGE prefix |
|---|---|---|
| São Paulo | 34 | 35 |
| Mato Grosso do Sul | 52 | 50 |
| Goiás | 53 | 52 |
| Distrito Federal | 54 | 53 |

The renumbering followed the creation of Mato Grosso do Sul (1977) and Tocantins
(1988); Comex never migrated. Left unhandled it drops **970 municipalities —
every one in SP, GO, MS and DF — carrying 31.2% of Brazil's 2010 export value**,
including the município of São Paulo, silently and with no error. The first run
of `D1` did exactly that and was caught only because the value-reconciliation
assertion fired.

Remap verified rather than assumed: after applying it, **5,568 of 5,568** real
municipalities match IBGE by code and **5,568 of 5,568** agree on federal unit.
Residual unresolved: two pseudo-codes, `9300000` (`EX`) and `9999999` (`ND`),
0.0027% of value.

### [D-20] BACI keys on UN Comtrade area codes, not ISO 3166-1 — the contract is wrong

**`D_data_contracts.md` §1b and `[D-4]` item 4 are incorrect.** Both state that
BACI's `country_code` "**is** the numeric ISO 3166-1 code" and joins directly
onto `CO_PAIS_ISON3` with "no name matching required", and both predict a
near-empty unmatched log. The numeric join is not clean and fails on the largest
possible destinations:

| destination | ISO 3166-1 | BACI | 2010 share of Brazil's exports |
|---|---|---|---|
| United States | 840 | **842** | **9.63%** |
| France | 250 | **251** | 1.78% |
| India | 356 | **699** | 1.74% |
| Taiwan | 158 | **490** (Other Asia, nes) | 0.87% |
| Switzerland | 756 | **757** | 0.69% |
| Norway | 578 | **579** | 0.36% |

A numeric join silently drops **15.17% of 2010 export value across 19 areas**,
Brazil's second-largest destination among them.

**Resolution.** Join on the alphabetic `iso3` BACI also ships, which is reliable,
then apply an explicit 14-entry map for the areas where Comtrade *aggregates*
territories into a metropole (`PRI`/`VIR`/`UMI` → USA; `GLP`/`MTQ`/`GUF`/`REU`/
`MCO` → France; `LIE` → Switzerland; `IMN`/`GGY` → UK; `FRO` → Denmark; `TWN` →
Other Asia, nes). Every target is asserted present in BACI's own country list.

Folding Comex into BACI's scheme is the correct direction, not the reverse:
`m_dp_row` is built from BACI, so destination 842 already contains Puerto Rico's
imports and Comex's `PRI` must join onto it.

**After the fix the unmatched log is empty** — 0 codes, 0.000000% of value.

### [D-21] `ZZZ` is a residual bucket, not a country

Twelve Comex `CO_PAIS` codes carry `iso3 = ZZZ`: "Not defined", "To define",
"Not declared", "Sem informação", "Central Banks", "International
Organizations", the USSR, and the only one with material 2010 value — **"Planes
and ships provisions"** (ship and aircraft stores, **1.78%** of exports). These
are excluded as non-destinations with their share reported, rather than silently
dropped or assigned to a country. Attributed value is therefore 98.22% of the
national total by construction, and that figure is not a coverage failure.

### [D-22] BACI iso3 duplicates: dedupe only where ambiguous

BACI marks superseded partners `(...YYYY)`. Some share an `iso3` with their
successor (Belgium-Luxembourg/`BEL`, Fed. Rep. of Germany/`DEU`,
Sudan/`SDN`); one does not — Netherlands Antilles/`ANT`. A blanket
"drop every `(...)`" filter therefore deletes a live destination carrying 0.48%
of 2010 exports, because the Antilles were dissolved in October 2010 and existed
for most of the base year. That is what the first version of this rule did.
Deduplicate only where an `iso3` is genuinely ambiguous.

### [D-23] Territorial reconstitutions manufacture fake ±2 arc shocks

Live identification problem, not housekeeping. `g_dt` is an arc rate and
`arcΔ(0, v) = +2`, `arcΔ(v, 0) = −2`. A destination dissolved mid-panel shows a
**total demand collapse** and its successors show **entry from nothing** — pure
reclassification artefacts that would land in the extreme tail of the shock
distribution and can carry large Rotemberg weight.

Two reconstitutions fall inside 2010–2022: the Netherlands Antilles (530 →
Curaçao 531, Sint Maarten 534, Bonaire 535, October 2010) and Sudan (736 →
Sudan 729, South Sudan 728, July 2011). Each group is folded into **one
persistent unit spanning the whole panel**, keyed by the pre-split code. Aruba
was already separate and is not folded. Belgium-Luxembourg and the FRG dissolved
before the window and are folded for symmetry at no cost.

The fold and the area map are **saved inside `D1_s_rd.rds`** so that `D2`/`D3`
read them rather than redeclaring them; BACI and Comex cannot drift onto
different destination universes.

Found only because `[D-22]` forced a look at what the `(...)` filter was
removing. Worth stating in §3 as a disclosed threat that was measured and
neutralised rather than assumed away.

### [D-14] N2 denominator is `L_r_all`, total formal employment

`exposure_shares_isic_v7.rds` carries both `L_r_2010` (**tradable** employment)
and `L_r_all` (total). Verified: `s_rj = L_rj_2010 / L_r_all` and
`θ_r = L_r_2010 / L_r_all` exactly. Under `SHARE_DENOM = "total"` (`[T-2b]`) the
industry design normalises by total formal employment, so Branch A must too —
otherwise `s_rd` and `s_rj` are not comparable and `θ_r` denotes two different
quantities in the same table. The name `L_r_2010` in that object is a trap.

### [D-15] No deflation in `D1`, and that is correct

Shares are fixed at 2010, which *is* the base year of the constant-USD series,
so current and constant 2010 USD coincide. Deflation becomes mandatory the
moment a second year enters (`D3`); it does not apply to a single-year
cross-section. Recorded because an auditor checking "was `cpi_us.rds` applied"
would otherwise flag its absence.

### [D-16] The employment-imputed bridge moves from `D1` to `D2`

The script table assigns the bridge to `D1`, but
`s_rd_bridge = Σ_j s_rj × ω_jd` requires `ω_jd`, which is built from BACI's
Brazil rows and does not exist until `D2`. `D1` is kept BACI-free — that is what
makes it the cheap step-1 gate. The deliverable `tab_d_bridge.md` is unchanged;
only the script that writes it moves. The `ρ < 0.5` gate moves with it.

### [D-18] Zero-export microregions retained at zero under N2

Branch A is defined on the v7 microregion universe (**557**), not on the set that
happens to export. **464 export, 93 do not**, and the accounting closes on 557
exactly. The 93 are retained at `s_rd_n2 = 0`, `θ_r = 0`; N1 is a composition
and is undefined for them, so they are excluded from N1 **only**. Dropping them
would silently change the sample between rungs of the same ladder.

### [D-24] Result: microregion destination exposure is diffuse enough to work

The pre-test in the Stage 1 brief computed the *national* destination mix and
flagged that the microregion-level distribution is the real test. It is:

| statistic | effective destinations (1/HHI) |
|---|---|
| national mix (208 destinations) | **18.28** |
| microregion mean | 6.45 |
| microregion median | 4.95 |
| microregion p25 / p75 | 2.32 / 9.53 |
| microregion min / max | 1.00 / 30.57 |
| **value-weighted mean** | **9.83** |

144 of 464 exporting microregions (31.0%) have fewer than 3 effective
destinations — but they carry only **6.53%** of 2010 export value. The 70
microregions with fewer than 1.5 effective destinations carry **0.75%**.

Since Rotemberg weights are exposure- and value-weighted, the operative
statistic is the value-weighted mean, **9.83** — 3.8× the industry design's
effective *shock* count of 2.59, and above every exogenous industry series built
in Stage 0.

**Necessary, not sufficient.** The industry axis also looked diffuse in exposure
(19.67 effective industries) and still collapsed to 2.59 effective *shocks*. The
collapse there came from shock-side dispersion produced by the `L_j,2010`
denominator (2022 tail: ISIC 0129 at `g = 88.9` on 3,672 workers). `g_dt` is an
arc rate on a large national import aggregate, bounded in [−2, +2], so that
specific mechanism has no analogue — but the effective-shock count cannot be
declared until `D3`/`D4`.

Supporting descriptives: China is the top destination at **15.6%**, USA 9.9%,
Argentina 9.4%; the top 20 destinations carry 73.4%. Entrepôts (`NLD`, `ARE`,
`HKG`, `SGP`) carry a joint **7.04%**, with the Netherlands alone at 4.56% —
large enough that the leave-out in `D.8` is not optional. The top 20 declaring
municípios carry **41.3%** of attributed export value, which is the magnitude of
the attribution threat in spec §D.7.1.

---

## Section 2d — Stage 1 step 2: BACI destination ingest and the bridge gate

`D2_baci_destino.R`, run 2026-08-10, after the Stage 1 amendment.

### [D-25] Saint Lucia added to the entrepôt set

`LCA` ranks 19th at **USD 2.744 bn, 1.39%** of Brazil's 2010 exports — larger
than the island's entire annual import bill. It is transhipment through the
island's oil storage terminal, not final demand. Entrepôt set becomes
`NLD, SGP, HKG, ARE, LCA`, joint 2010 share **8.43%** (was 7.04%).

It matters more than the other four because the commodity is **petroleum** — the
same ISIC 0610 that carries α ≈ 0.90 in `z_CHN` (`[D-11]`). If `LCA` surfaces in
Branch A's top Rotemberg weights, that is the petroleum concentration
reappearing under a destination label rather than an industry one, and `D4` must
say so rather than reporting it as a destination result.

### [D-26] Two defects in the `D1` markdown writer — the CSVs were always right

1. **Identifiers were rounded.** `signif(, 4)` was applied to every numeric
   column including the microregion code: `12003` printed `12000`, and `23011`,
   `23012`, `23013`, `23014` all printed `23010` — four distinct microregions
   rendered as one repeated four times. Rounding is now applied to **doubles
   only**, and rows are pasted per column rather than through `apply()`, which
   coerces the frame to a character matrix and reformats numbers on the way.
2. **"15 most concentrated" listed 33 rows.** `slice_min(n = 15)` keeps ties, and
   there are 33 single-destination microregions. That is a **tie group, not a
   ranking**, and is now reported as the statistic it is — 33 of 464 (7.1%),
   carrying **0.014%** of export value — with the illustrative table capped
   explicitly at the largest 15 by export value.

The dangerous case: the markdown is what gets copied into prose, so a table
writer that silently corrupts identifiers is worse than a wrong number.

### [D-27] N1 and N2 are different samples; `theta_r_dest` is not `θ_r`

Binding on every downstream table.

**Samples.** 93 of 557 microregions have zero 2010 exports. N2 retains them at
`s_rd_n2 = 0`, `theta_r_dest = 0` (**N = 557**); N1 is a composition, undefined
for them, and drops them (**N = 464**). N1 is not comparable to N2, nor to the
industry design in the same way. `ρ(EPW_S0, EPW_S3)` for `[D-PRE-4]` is
computable **only on the 464**. Never print an N1 and an N2 column without
stating the sample.

**Units.** Branch A's `theta_r_dest` is *exports per formal worker* (2010 USD,
mean 4,545, max 205,088). The industry design's `θ_r` is the *tradable
employment share*, a unit-free fraction in [0,1]. Different units, different
object. The column keeps the name `theta_r_dest` through to the tables and is
never rendered as a bare `θ_r` in prose.

### [A1 confirmed] The exposure-diversity argument for Branch A is withdrawn

Computed inside `D1` rather than quoted, so both sides are measured the same way:

| per microregion | mean effective units | median | p25 | p75 | below 3 |
|---|---|---|---|---|---|
| ISIC industries (v7, employment-weighted) | **7.89** | 6.10 | 3.71 | 10.06 | 18.5% |
| destinations (`D1`, export-weighted) | **6.45** | 4.95 | 2.32 | 9.53 | 31.0% |

Destinations are **slightly more concentrated than industries**, not less. The
denominators differ — export value against employment — so this compares
dispersion, not magnitude, and the earlier value-weighted 9.83 is not
comparable to the industry side.

What survives: the industry design carries 7.89 effective *industries* of
exposure per region but only **2.59 effective shocks**. That collapse is
shock-side dispersion from the `L_j,2010` denominator. `g_dt` is an arc rate
bounded in [−2, +2], so that dispersion is arithmetically impossible.
**The case for Branch A now rests entirely on shock dispersion**, and `D3` must
report `sd(g_dt)` and its range against `sd(g_jt)` and `sd(g_arc)` before any
Rotemberg weight is computed.

### [D-28] `ω_pd` and `ω_jd` taken from BACI's Brazil rows at HS6

Per spec §D.4.2 and threat §D.7.4, not from Comex at SH4. Two reasons: it avoids
a product-granularity mismatch between the weights and the `m_dp_row` they
weight, and it keeps numerator and denominator inside one dataset with one set
of reconciliation conventions. The cost is that `ω` is BACI's view of Brazil's
exports, which differs from Comex's by ~7% in total (`[D-12]`).

Ingest results: `m_dp_row` 3,362,908 raw cells over four years; Brazil asserted
absent (the packet's single most important assertion, checked before and after
the destination fold). Brazil's 2010 BACI exports rebuilt here 216.34 B against
`03b`'s 214.9 B — **0.67% apart, inside the 1% tolerance**. HS6 outside the v7
dictionary: **0.66%** of Brazil's 2010 exports. `ω_jd` covers **152 of 152**
industries; `ω_pd` covers 207 destinations.

### [D-29] Raw-ingest cache

`D2_ingest_cache.rds` holds only the two raw aggregates, **before** deflation,
folding or any modelling choice, so nothing downstream can be frozen into it.
Re-reading 1.3 GB to re-run a diagnostic is the difference between a 30-second
iteration and a four-minute one, and the brief requires each script to be
independently runnable and idempotent. Delete the file to force a re-read.

### [D-30] BRIDGE GATE FAILED — and the gate does not measure what it was meant to

**Result.** `ρ(s_rd_N1, s_rd_bridge)`, pooled over 95,029 microregion ×
destination cells on the N1 sample of 464:

| statistic | value |
|---|---|
| pooled Pearson | **0.320** |
| pooled Spearman | 0.462 |
| mean within-microregion Pearson | 0.434 |
| median within-microregion Pearson | 0.439 |
| microregions with ρ < 0.5 | 59.5% |

Against the pre-specified threshold of 0.50 this is a **FAIL**, and `D2` stops
with a non-zero exit rather than proceeding to `D3`.

**Diagnosis — the failure is not primarily municipality attribution.** Three
pieces of evidence, all computed after the gate fired:

1. **At the national level the bridge works.** Aggregating both series to
   national destination shares gives Pearson **0.772** and Spearman **0.947**.
   There is no municipality-attribution problem in a national aggregate, so a
   near-perfect rank correlation there says the industry→destination imputation
   is sound and the disagreement is entering at the regional level or in levels.
2. **Value-weighted, the gate passes.** Weighting cells by microregion export
   value gives Pearson **0.586**, above the threshold. Within-microregion ρ rises
   monotonically with export size: 0.23 in the bottom quintile, 0.40, 0.42, 0.54,
   **0.58** in the top. The unweighted pooled figure is carried by tiny
   microregions where both series are noise.
3. **The residual level gap is the capital-intensity gradient again.** The single
   largest discrepancy is **China: 15.6% actual against 6.3% imputed**, a 2.5×
   understatement. The reason is mechanical — China's purchases from Brazil are
   concentrated in ISIC 0710 (42% of that industry's exports) and 0610 (22%),
   whose *national employment shares* are 0.39% and 0.31%. An
   employment-weighted bridge cannot see China.

**Therefore the bridge is a joint test of two things**, only one of which it was
designed to test: Comex municipality attribution **and** the assumption that a
region's employment mix proxies its export mix. The second is *known* to be
badly violated in this setting — it is `[D-0-6]`, the finding that motivates the
entire packet. A ρ of 0.32 does not license the conclusion that Comex
attribution is severe enough to change the design; it mostly re-measures the
capital-intensity gradient.

**No clean alternative exists in this tree.** Every regional export series here
(`exportacoes_micro_2010_2022.rds` included) is built from the same Comex
municipality attribution, so none is independent of the threat. There is no
production-location source to test against.

**Resolution: the gate is withdrawn as invalid, not failed.**

The distinction is the whole of it. `s_rd_bridge = Σ_j s_rj × ω_jd` assumes a
region's **employment** mix proxies its **export** mix. **Even under perfect
municipality attribution that bridge would fail here**, because export value per
formal worker varies 14× across sectors — which is `[D-0-6]`, the finding the
packet exists to address. China at 15.6% actual against 6.3% imputed is not
evidence of attribution error; it is ISIC 0710 and 0610 carrying national
employment shares of 0.39% and 0.31%.

The statistic therefore has **essentially no power** for the quantity it was
written to detect. ρ = 0.320 is consistent with perfect attribution; so is
0.586. Neither number licenses a conclusion about Comex attribution in either
direction.

This disposes of the three readings that were on the table:

- **Re-specifying on the value-weighted statistic is rejected**, and not only
  because it changes a threshold after seeing the result. Value-weighting does
  not separate the two failure sources — it reweights toward regions where both
  series are less noisy. Passing at 0.586 would license nothing about
  attribution, so adopting it would buy a threshold breach with no inferential
  gain.
- **Stopping Branch A is rejected**: halting a design on an uninformative signal
  is the same error as proceeding on a false positive.
- **Proceeding is correct**, but it is logged here as *gate withdrawn*, not as
  *gate failed and overridden*. Only the first is accurate, and the difference
  matters to anyone auditing this file later.

`D3` proceeds. The attribution threat is real and unmeasured, and is replaced —
not waived — by a test with power against it (`[D-31]`).

### Gate-design note — three mis-specified gates, one trigger

Revised 2026-08-10: the count is **three**, not two. `[D-PRE-4]` belongs on the
list.

| gate | what it asked | why it was wrong |
|---|---|---|
| Stage 0 workforce balance | do `z_A`/`z_B` pass the test `g_jt` fails? | applied an **industry-side** test to a design with no industry dimension |
| bridge `ρ < 0.5` | does the employment-imputed share track the Comex share? | conflated the **threat under test** with the **phenomenon under study** |
| `[D-PRE-4]` `ρ > 0.9` | is S3 just S0 relabelled? | guarded **one tail of a two-tailed problem** |

`[D-PRE-4]` fired a pass at ρ = 0.025, and the pass means something quite
different from what the gate assumed. It was written to catch "S3 is S0
relabelled, so Branch A is only a measurement check". What ρ ≈ 0 actually
licenses is not "S3 is independent and therefore a valid identification check"
but "**S3 is a different treatment, so two nulls are not corroboration of one
another**". The gate had no branch for that reading, because it only looked
upward.

**The shared trigger, and why it is actionable.** All three were written before
`[D-0-6]` was sharp — before the capital-intensity gradient was identified as the
thing organising every diagnostic in the packet. That is why they are
*conceptually* wrong rather than merely unlucky: each was specified against a
diagnosis that had not yet matured.

**Mechanism: stamp every gate with the diagnosis it was written against.**
"Re-read each gate against the current diagnosis before it fires" is correct but
easy to skip, because nothing prompts it. A stamp supplies the prompt: when the
diagnosis moves — as it did at `[D-0-6]`, and again at `[D-30]` — **every gate
stamped against the superseded state is flagged for re-read**. That converts a
discipline which depends on remembering into one with a trigger. Stamps are
recorded in the pre-registration block below and are not to be back-dated.

**Note that this is a different discipline from `D_data_contracts.md` §0a**, and
neither substitutes for the other. §0a ("inspect first, then assert") prevents
`[D-20]`: a *factual* claim about a file, checkable in one line, asserted without
the check. It would not have prevented any of the three gates above, because a
gate can be conceptually wrong about a property that is perfectly well measured.
Two failure modes, two rules; keep both.

### [D-31] Production-capacity orphan test — a valid measure of the attribution threat

**Why a new test.** Every regional *export* series in this tree inherits the same
Comex declaring-município attribution, so no export series can test it. But
**RAIS is independent of Comex**, and it observes where productive capacity is.
The attribution threat has a signature RAIS can see: a microregion credited with
exports of goods it has no capacity to produce.

**Definition.** For microregion *r*, the share of 2010 export value in products
whose producing industry employs nobody in *r*.

```
capability set   C_r  =  { isic4 : workers_{r,isic4} > 0 }   from rais_isic_v7.rds
product p is ORPHAN in r  ⟺  ISIC(p) ∩ C_r = ∅
orphan_share  =  Σ_{r,p : orphan} X_{r,p}  /  Σ_{r,p} X_{r,p}
```

**Construction decisions, all pinned before running.**

1. **Conservative by design.** A product counts as *capable* if *r* employs
   anyone in **any** ISIC reachable from it. This minimises measured orphan
   value, so the statistic is a **lower bound** on attribution error and a
   threshold breach is decisive rather than suggestive.
2. **Strictly zero employment**, not a positive cutoff. Zero is unambiguous; any
   cutoff is a tuning knob.
3. **SH4 → ISIC via the v7 dictionary**, aggregated up from HS6: the ISIC set for
   an SH4 is the union over its HS6 children. The crosswalk enters the
   **diagnostic only** and never the shares — Branch A stays crosswalk-free where
   it counts.
4. **Composite map applied**, so capability is assessed on the same 152-industry
   universe as everything else.
5. **Denominator** is attributed 2010 export value on the 464 exporting
   microregions (98.22% of the file, `[D-18]`). `CO_PAIS` 990 already excluded.
   SH4 with no ISIC match in the v7 dictionary are excluded from **both**
   numerator and denominator and reported separately — 0.66% of Brazil's 2010
   exports fall outside the dictionary (`[D-28]`).

**Reported alongside the headline.**

- orphan share by microregion; the 20 largest orphan cells with product,
  destination and value
- orphan share among the **top-20 declaring municípios** (41.3% of attributed
  value, `[D-19]`)
- orphan share among the **entrepôt destinations** `NLD, SGP, HKG, ARE, LCA`
  (8.43%, `[D-25]`)
- orphan share in **ISIC 0610 and 0710** specifically — the two industries that
  dominate every other diagnostic in this packet

**Secondary prediction, pre-registered at `[D-PRE-6]`.** If the mechanism is
attribution, orphan value should **concentrate in port and state-capital
microregions**, which is where trading companies and shipping agents are
domiciled. If orphan value is spread roughly uniformly across microregions, the
more likely explanation is crosswalk noise, and the attribution reading weakens
regardless of the headline number.

**What the test cannot see.** Attribution error between two microregions that
both have capacity in the relevant industry is invisible to it. That is the
lower-bound caveat, and it must be stated wherever the number is reported.

**Timing.** Runs alongside `D3` rather than blocking it. `D3` is not
conditioned on the result; `[D-PRE-6]` governs what the result implies.

---

## Section 2e — Stage 1 step 3: shocks, and the orphan test

### [D-32] Shock baseline: the contract and the ladder disagree — both are built

`D_data_contracts.md` §3.2 and §4.4 write `arcΔ( m[t] , m[t−4] )`, a **rolling**
four-year window, so 2018 would be measured against 2014. The published rungs do
not do that: `sectoral_shocks_isic_v7.rds` defines
`g_jt = (EXP_jt − EXP_j,2010)/L_j,2010` and `G3`'s arc divides by
`0.5·(exp_national + exp_2010)` — both **cumulative against 2010**, and
`[D-4]` says so outright.

Comparability against S0/S1 is the point of the ladder, so the **2010 baseline is
primary**. The rolling variant is computed and reported so the contract's reading
is on the record. They are not close: `ρ(cumulative, rolling)` is 1.000 in 2014
by construction, **0.509** in 2018 and **0.343** in 2022. This is a substantive
choice, not a formatting one, and the contract should be corrected.

### [D-35] `[A1]` settled: shock dispersion is where Branch A wins

Reported before any Rotemberg weight, as the amendment requires. `sd` is in each
shock's own units and is **not** comparable across rows; the last two columns are
dimensionless and are.

| shock | unit | mean sd | min | max | max&#124;g&#124;/sd | eff. units by magnitude |
|---|---|---|---|---|---|---|
| `g_jt` (S0, level per worker) | industry (152) | 6.35 | −32.0 | **88.9** | **9.16** | **10.87** |
| `g_arc` (S1, arc) | industry (152) | 0.45 | −1.75 | 1.99 | 4.19 | 84.02 |
| `Z_jt` (S2, arc, dest-weighted) | industry (152) | 0.28 | −1.91 | 1.24 | 5.21 | 70.62 |
| `g_dt` (S3, arc, destination) | destination (207) | 0.61 | −2.00 | 2.00 | **3.27** | **110.87** |
| `g_dt_tot` (S3 robustness) | destination (207) | 0.42 | −1.43 | 1.54 | 3.62 | 115.77 |

`eff_units_by_magnitude = (Σ|g|)² / Σg²` is the effective number of units by
shock magnitude alone, before any exposure weight — a preview of Rotemberg
concentration that does not depend on `W`.

**The A1 prediction holds.** `g_jt` concentrates 152 industries into an effective
10.9 by magnitude and carries a 9.2-sigma tail; `g_dt` retains an effective 110.9
of 207 destinations with the thinnest tail in the packet. The arc bound does
exactly what was claimed: `g = 88.9` cannot occur.

75 of 621 destination-cycles carry `|g_dt| > 1`, but those destinations hold only
**6.07%** of Brazil's 2010 exports, and the extreme values are microstates —
Palau, Eritrea, Northern Marianas, Montserrat, Djibouti. The exception is
**Saint Lucia at −1.9985 in 2022**, essentially at the bound, which is `[D-25]`
firing exactly as anticipated.

### [D-31 result] Orphan test: **2.66%**, `[D-PRE-6]` PASSES

Against a pre-registered 20% threshold: orphan value is **2.66%** of attributed
2010 export value (USD 5.21 bn of 195.47 bn). Median microregion orphan share is
0.002%; the value-weighted figure is 2.66%. SH4 outside the v7 dictionary —
0.71% of value — left both numerator and denominator.

**The `[D-PRE-6]` secondary prediction is confirmed.** Orphan value concentrates
in ports exactly as attribution would predict:

| group | microregions | export value | orphan share | share of all orphan value |
|---|---|---|---|---|
| port only | 9 | 12.5 B | **14.6%** | **35.2%** |
| port and capital | 15 | 26.1 B | 0.43% | 2.2% |
| capital only | 12 | 24.6 B | 0.006% | 0.03% |
| neither | 428 | 132.3 B | 2.47% | 62.7% |

Port or capital microregions are 7.8% of the sample and 32.3% of export value but
**37.3% of all orphan value**. The largest orphan cells are textbook
transhipment: microregion 35063 (Santos) exporting SH4 1701 sugar to ARE, SAU,
NGA, CAN, IND; microregion 33003 exporting SH4 2709 crude petroleum to CHL, NLD,
ESP; 31002 exporting SH4 7108 gold to GBR, CHE.

**So the mechanism is attribution and its magnitude is small.** Both halves
matter. Two further readings:

- The **top-20 declaring municípios have a *lower* orphan share** (2.04%) than
  everyone else (3.11%). The biggest declarers are largely genuine producers;
  the attribution problem sits in a handful of port microregions, not in the
  large-declarer tail the threat was framed around.
- **ISIC 0710 iron ore has an orphan share of exactly 0.00%**, and 0610 crude
  petroleum 4.48%. The two industries that dominate every other diagnostic in
  this packet are not where the attribution problem is.
- Entrepôt destinations carry 5.78% orphan against 2.38% elsewhere.

Lower-bound caveat travels with the number: attribution error between two
microregions that both have capacity in the relevant industry is invisible here.

### [D-34] Destination characteristics come from CEPII Gravity alone

`Gravity_V202211.rds` carries `gdpcap_d`, `gdp_d`, `pop_d`, `dist`, `contig` and
`comlang_off` in one object (4,699,296 rows, 87 columns, 1948–2021). **The World
Bank WDI pull contemplated in `[D-4]` is unnecessary and is dropped.** Keyed on
alphabetic `iso3` and routed to BACI's numeric code via `Countries_V202211.csv`
`iso3num`, as `[D-4]` item 4 prescribes.

### [D-36] Owed from the Stage 0 review: the `g_arc` balance axis

`g_arc` on the workforce set, weighted balance coefficients:

| year | `sh_loweduc` t | `mean_lnwage` t | `sh_male` t | `sh_white` t |
|---|---|---|---|---|
| 2014 | 1.33 | 0.47 | 1.83 | −0.31 |
| 2018 | **3.24** | **2.57** | 0.50 | 1.46 |
| 2022 | **2.75** | **2.44** | −0.94 | 0.09 |

The failing axis is education-and-wage, the same axis that carries `g_jt` in 2022
(`sh_loweduc` t = 3.69, `mean_lnwage` t = 4.42) and `z_A` in 2014
(`mean_lnwage` t = 6.26). **The level and arc balance failures do collapse into
one mechanism** — the capital-intensity gradient of `[D-0-6]` — as the Stage 0
review conjectured. They should be reported as one finding, not three.

### [D-37] Owed from the Stage 0 review: `D0_shock_correlations.csv` in prose

Pooled over 456 industry-cycles. The three exogenous instruments are **strongly
correlated with each other and weakly with the realised shocks**: ρ(`z_A`,`z_B`)
= 0.768, ρ(`z_A`,`z_CHN`) = 0.717, ρ(`z_B`,`z_CHN`) = 0.560, against
ρ(`g_jt`,`z_A`) = 0.278, ρ(`g_jt`,`z_B`) = 0.311, ρ(`g_jt`,`z_CHN`) = 0.421.
Against the **arc** shock they are weaker still — 0.104, 0.092, 0.143.

Two things follow. First, `z_A`, `z_B` and `z_CHN` are close to one construction,
which is why their first stages and balance results move together and why
treating them as three independent instruments would overstate the evidence.
Second, ρ(`g_jt`, `g_arc`) = 0.310 Pearson but **0.789 Spearman** — the level and
arc shocks agree closely on the *ordering* of industries and disagree on
magnitudes, which is the signature of a denominator effect rather than a
different economic signal, and is further support for `[D-0-6]`.

---

## Section 2f — Stage 1 step 4: Rotemberg, balance, independence

`D4_diagnostics.R`. Benchmarks reproduced before any new number: S0 2.5896,
S1 5.5689, both to `< 1e-6`.

### [D-38] `α_China`: the destination design does **not** collapse into IV-C

The `[D-PRE-4]` prior pointed the unfavourable way — `z_CHN` carries
α(0610) ≈ 0.90 (`[D-11]`), so China might have dominated Branch A as iron ore
dominates S0. It does not.

| rung | 2014 | 2018 | 2022 |
|---|---|---|---|
| S3_N1 | 0.030 | 0.002 | 0.035 |
| S3_N2 | 0.371 | 0.087 | −0.022 |

Under N1 China is a small weight in all three cycles despite holding a 15.6%
exposure share. The general destination design is a genuinely different object
from the China-only special case.

### [D-39] Effective shocks across the full ladder

Mean of yearly, base controls, identical machinery throughout.

| rung | unit | 2014 | 2018 | 2022 | **mean** | top-1 α | dominant unit |
|---|---|---|---|---|---|---|---|
| S0 `g_jt` | industry | 2.88 | 2.51 | 2.38 | **2.59** | 0.59 | 0710 → 0610 |
| S1 `g_arc` | industry | 5.20 | 6.09 | 5.42 | **5.57** | 0.35 | 0111 |
| S2 `Z_jt` | industry | 1.81 | 1.77 | 1.96 | **1.85** | 0.73 | **0141** |
| S3_N2 `g_dt` | destination | 7.94 | 5.72 | 3.16 | **5.61** | 0.39 | **LCA** |
| S3_N1 `g_dt` | destination | 17.56 | 3.01 | 4.65 | **8.41** | 0.38 | VEN |

**S3_N1 at 8.41 is the highest in the packet**, against the industry design's
2.59. Branch A delivers the de-concentration Branch B never did.

**S2 collapses to 1.85 — worse than the published baseline.** `Z_jt` is
dominated by ISIC **0141** (cattle) at α = 0.92 / 0.77 / 0.73. Destination
weighting at the industry unit does not de-concentrate; it re-concentrates on a
different industry. Every industry-unit construction in this packet — level,
arc, exogenous level, exogenous destination-weighted — ends up dominated by one
or two industries. The unit, not the shock content, is what carries the problem.

### [D-40] `[D-25]` confirmed: Saint Lucia dominates S3 under N2

Mean |α| across cycles, entrepôt destinations:

| rung | LCA | HKG | SGP | NLD | ARE |
|---|---|---|---|---|---|
| S3_N2 | **0.441** | 0.004 | 0.002 | 0.017 | 0.006 |
| S3_N1 | 0.026 | 0.046 | 0.016 | 0.009 | 0.007 |

Under **N2** Saint Lucia carries α = 0.255 / 0.465 / **0.602** and is the single
dominant unit in 2018 and 2022. Under **N1** it falls to 0.026. The difference is
the normalisation: `s_rd_n2 = X_rd / L_r_all` rewards a small microregion with
enormous per-worker exports to one transhipment terminal, which is exactly the
per-worker pathology of `[D-0-6]` reappearing on the destination axis.

This is `[D-25]`'s prediction confirmed: **petroleum reappearing under a
destination label**. Consequences, and they are not small:

1. **N1 should lead, not N2**, notwithstanding spec §D.4.1 making N2 primary.
   N2 reintroduces the per-worker denominator problem the packet exists to
   escape. Flagged for decision; not changed unilaterally.
2. The entrepôt leave-out is **load-bearing for S3_N2**, not a robustness
   afterthought.

### [D-41] Destination-characteristic balance: 1 of 3

`[D-34]` characteristic set, weighted by destination share of Brazil's 2010
exports. Coverage 177 of 207 destinations, **91.76%** of export value.

| shock | 2014 | 2018 | 2022 | passing |
|---|---|---|---|---|
| `g_dt` | 0.078 | **0.0025** | **0.013** | 1 / 3 |

Comparable to `g_jt` on trade characteristics (2 of 3) and better than `g_arc`
(0 of 3), on a different and larger characteristic set (6 regressors against 2).

The failure is **geographic, not economic**: 2018 is driven by `log_dist`
(t = −3.49) and `contig` (t = −4.36) — the 2018 shock is systematically weaker
in near and bordering destinations, which is the Argentine and Venezuelan
collapse. `log_gdpcap_d` is insignificant in all three cycles (|t| ≤ 1.24) and
**the China dummy is insignificant in all three** (|t| ≤ 0.35), which
independently corroborates `[D-38]`.

### [D-42] `[D-PRE-4]`: **ρ(EPW_S0, EPW_S3_N1) = −0.029** — passes decisively

On the N1 sample of 1,392 microregion-years (`[D-27]`). Against the 0.9 threshold
this is not close, and against the `ρ(S0, S1) = 0.373` benchmark the destination
design is **far more independent of the baseline than the arc respecification
is**. Branch A stands as an *identification* robustness check, not a measurement
one, and `[D-PRE-4]` does not fire.

Full matrix (Pearson, N1 sample): ρ(S0,S1) = 0.416, ρ(S0,S2) = −0.021,
ρ(S0,S3_N2) = −0.072, ρ(S1,S2) = 0.305, ρ(S2,S3_N1) = 0.303,
ρ(S3_N1,S3_N2) = 0.326 Pearson but **0.839 Spearman** — the two normalisations
rank microregions similarly and scale them very differently, which is the same
signature `[D-37]` identifies between `g_jt` and `g_arc`.

**Caveat to carry into §3.** ρ ≈ 0 is *almost too clean*. It means the
destination design is close to orthogonal to the published treatment, so Branch A
cannot confirm or refute the S0 null in the ordinary sense — it estimates the
effect of a different treatment. That is a strength for independence and a
limitation for interpretation, and both belong in the text.

### Sign-convention guard

`EPW⁺ + EPW⁻ = EPW` to `< 1e-11` on all five rungs; `EPW⁺ ≥ 0`, `EPW⁻ ≤ 0`
throughout. The v7 sign fix is intact.

---

## Section 2g — The entrepôt leave-out: is N2 reportable?

`D5_entrepot_leaveout.R`. S0 canary reproduces at 2.5896 before any new number.

### [D-43] The N2 leave-out is a column drop, not a renormalisation

N2 shares are incomplete by construction (`Σ_d s_rd = theta_r_dest`, not 1), so
dropping the entrepôt columns simply lowers `theta_r_dest` — which is the honest
statement that the exposure is gone. Renormalising would redistribute Saint
Lucia's value across each microregion's remaining destinations and quietly
preserve the exposure under test. N1 *is* a composition, so its leave-out does
renormalise; both are reported.

Cost: the five entrepôts carry **8.43%** of attributed 2010 export value.
`theta_r_dest` falls by a median of **3.48%**, mean 10.11%, and **max 100%** —
at least one microregion exported exclusively to entrepôts and loses all
exposure. That microregion must be reported in the N-reconciliation note.

### [D-44] Result: the leave-out repairs N2's concentration completely

| spec | 2014 | 2018 | 2022 | **mean eff. shocks** | cycles with α > 0.5 |
|---|---|---|---|---|---|
| S3_N2, all destinations | 7.94 | 5.72 | 3.16 | 5.61 | **1** (LCA 0.545) |
| **S3_N2, entrepôts dropped** | 6.80 | 8.50 | 6.77 | **7.36** | **0** |
| S3_N1, all destinations | 17.56 | 3.01 | 4.65 | 8.41 | **1** (VEN 0.558) |
| S3_N1, entrepôts dropped | 13.48 | 3.33 | 3.94 | 6.92 | **1** (VEN 0.519) |

Three things happen at once, and all three favour N2:

1. **Effective shocks rise from 5.61 to 7.36** — against S0's 2.59.
2. **The cycle-to-cycle collapse disappears.** N2-all falls to 3.16 by 2022;
   N2-ex is 6.80 / 8.50 / 6.77, the most stable rung in the packet.
3. **N2-ex is the only specification with no dominated cycle.** Maximum top-1 α
   is 0.324. Every other rung, including both N1 variants, has at least one cycle
   carried by a single unit.

The top-5 weights become economically legible: CHN, IRN, IND, GBR, JPN (2014);
VEN, CHN, IND, RUS, IRN (2018); CHN, VEN, RUS, IRN, SAU (2022). No transhipment
hub survives in the top five of any cycle. `[D-40]`'s diagnosis is confirmed —
LCA's dominance was the terminal, not a demand shock.

**N1 does not benefit.** Its effective count *falls* from 8.41 to 6.92 and
Venezuela still carries α = 0.519 in 2018. N1's own concentration problem is
Venezuela's import collapse, which is a real demand event and not removable.

### [D-45] What the leave-out does not fix, and what it costs

**Balance does not improve.** Destination-characteristic balance stays at 1 of 3,
and the pattern moves rather than lifting:

| sample | 2014 | 2018 | 2022 |
|---|---|---|---|
| all destinations | 0.078 | **0.0025** | **0.013** |
| entrepôts dropped | 0.112 | **0.036** | **0.00079** |

2018 improves (still fails); **2022 gets materially worse**. Whatever drives the
2022 destination-balance failure is not the entrepôts, and is not yet diagnosed —
the `[D-41]` decomposition was run on the full sample only. **Open item: re-run
the balance coefficients on the entrepôt-dropped sample before N2 is written up.**

**`α_China` rises**, which is the honest cost: 0.474 / 0.229 / 0.319 against
0.371 / 0.087 / −0.022. China holds a 15.6% exposure share, so an α near 0.47 is
roughly three times its exposure weight. It stays below the 0.5 dominance line in
all three cycles and China is a genuine destination rather than a terminal, so
this does not reopen `[D-38]` — but it should be stated, not buried.

**The treatment moves a lot.** ρ(N2-ex, N2-all) = **0.692**. Dropping 8.43% of
export value is not a perturbation; it is a different treatment series. The
leave-out therefore has to be presented as a specification choice with a reason,
not as a robustness check that left the estimate alone.

**Independence survives.** ρ(EPW_S0, EPW_S3_N2-ex) = **0.025** on the N1 sample
(was −0.072). `[D-PRE-4]` is nowhere near firing.

### [D-46] Consequence for the primary specification

On concentration, N2-with-entrepôts-dropped is the best-behaved rung in the
packet: 7.36 effective shocks, no dominated cycle, stable across cycles, top-5
weights that read as demand events. It is **reportable as primary**, which
`[D-40]` had put in doubt.

Two conditions attach, and both are the author's call:

1. The entrepôt exclusion becomes part of the **primary specification**, not the
   robustness battery, and spec §D.8 must be re-ordered accordingly. Justifying
   it on transhipment grounds is straightforward and was pre-registered as a
   threat at §D.7.2 — but it was pre-registered as a *robustness* check, and
   promoting it after seeing the Rotemberg weights is a specification choice made
   with knowledge of the diagnostics. That has to be said in the text.
2. The 2022 balance deterioration is **unexplained** and must be diagnosed before
   write-up.

---

## Section 2h — Ladder consistency and the 2022 balance diagnosis

`D6_entrepot_ladder_and_2022.R`. S0 canary 2.5896 before any new number.

### [D-47] The exclusion rule, stated once and applied consistently

`[D-43]` decided the N2 leave-out by column drop. The general rule, applied to
every share object in the packet:

| object | sums to | leave-out |
|---|---|---|
| `s_rd_n2` | `theta_r_dest` (incomplete) | **drop the column**; `theta_r_dest` falls |
| `s_rd_n1` | 1 (composition) | **renormalise** over survivors |
| `omega_jd` | 1 within industry (composition) | **renormalise** over survivors |

Dropping destinations from `ω_jd` without renormalising would shrink `Z_jt`
toward zero by an industry-specific factor — a scale distortion masquerading as
an exclusion, varying across industries by how much each sells through
entrepôts.

### [D-48] S2 exclusion applied: near-neutral, and the ladder is now consistent

| spec | 2014 | 2018 | 2022 | mean | top-1 α | dominant |
|---|---|---|---|---|---|---|
| S2, all destinations | 1.81 | 1.77 | 1.96 | 1.85 | 0.73 | 0141 |
| S2, entrepôts dropped | 1.77 | 1.86 | 2.02 | **1.88** | 0.73 | 0141 |

`ρ(Z_all, Z_ex) = 0.996`. The exclusion costs nothing and buys a ladder whose
rungs share one destination universe. S2 remains dead for a different reason —
ISIC **0141** (cattle) at α ≈ 0.73 in every cycle — which is the industry-unit
pathology, not an entrepôt problem.

### [D-49] The 2022 balance failure is Venezuela, and it lives entirely in the weights

Four diagnostics, and they converge.

**(a) Which term moves.** 2022 coefficients, all destinations → entrepôts
dropped:

| term | t (all) | t (dropped) |
|---|---|---|
| `contig` | −0.70 | **−2.71** |
| `log_gdpcap_d` | −1.04 | −1.87 |
| `log_dist` | +0.74 | −0.81 |
| `top5` | 1.98 | 1.97 |
| `china` | 0.03 | 0.13 |

`contig` is the mover, as the hypothesis predicted. The China dummy remains
insignificant, independently reconfirming `[D-38]`.

**(b) Leave-one-destination-out.** Dropping **Venezuela** takes the 2022 F from
4.063 to **2.090, p = 0.057 — it passes.** China is second (F → 2.550,
p = 0.030). No other destination moves F by more than 0.21. Venezuela holds only
**1.95%** of 2010 exports, so this is not a large-destination effect: it is one
country with an extreme shock that is also contiguous with Brazil.

**(c) Leave-one-entrepôt-out.** LCA alone accounts for most of the deterioration
(F 2.780 → 3.792); the other four contribute the remainder. But **2022 fails in
every configuration** — none dropped, any one dropped, all five dropped. The
exclusion did not create the failure; it sharpened one that was already there at
p = 0.013 and had been partly masked by Saint Lucia's weight.

**(d) Weighted versus unweighted — the decisive one.**

| weighting | 2014 | 2018 | 2022 |
|---|---|---|---|
| 2010 export share | 0.112 | **0.036** | **0.00079** |
| unweighted | 0.654 | 0.175 | 0.361 |

**Every cycle passes unweighted, in both samples.** The failure is not a property
of `g_dt` across destinations; it is a property of `g_dt` among the destinations
Brazil sells most to, which is exactly what the exposure-weighted test is built
to ask.

**Reading, and it is the one the design needs anyway.** The 2022 destination
shock is not orthogonal to gravity characteristics because the identifying
variation in that cycle is **geopolitical**: Venezuela's import collapse and,
behind it, Russia's sanctions-driven trade reorganisation. Gravity covariates
predict which countries have geopolitical events — `contig` picks up Venezuela
directly. This is not a data defect to be repaired but a statement about what
Branch A identifies off in 2022, and §3 should say so rather than reporting a
failed test.

### [D-50] The 2022 asymmetry across the ladder is informative

2022 now fails on both sides, for **different and diagnosable reasons**:

| rung | 2022 balance | cause |
|---|---|---|
| S0 `g_jt`, trade chars | **p = 0.013** | Brazilian supply expansion (pre-salt) |
| `z_A`, trade chars | p = 0.329 **passes** | Brazil removed from the numerator |
| S3 `g_dt`, destination chars | **p = 0.0008** | Venezuelan demand collapse |

`[D-PRE-1]` was confirmed because the exogenous *industry* shock removes
Brazil's own supply from the numerator and the 2022 failure goes with it. The
destination shock cannot do the same thing, because Venezuela's collapse **is**
foreign demand — it is the object the design is trying to measure, not
contamination of it. Removing it would remove the signal.

So: exogeneity fixes 2022 on the industry axis and cannot fix it on the
destination axis, and that asymmetry is a property of the two designs rather
than a defect in either. This belongs in §3 alongside `[D-49]`.

**Unchanged by any of this:** ρ(EPW_S0, EPW_S3_N2-ex) = 0.025. S3 remains a
different treatment that also returns a null, not corroboration of the same one.

### [D-51] Venezuela is the single most influential observation in the design

The diagnostics left this implicit. Venezuela is doing two jobs and they are the
same job:

| | 2018 | 2022 |
|---|---|---|
| α(VEN), S3_N2 entrepôts dropped | 0.278 | 0.278 |
| 2022 balance F with VEN dropped | — | 4.06 → **2.09** (p = 0.057, passes) |

It is simultaneously the top Rotemberg weight and the sole driver of the balance
failure, at **1.95%** of 2010 exports. Not two findings — one observation with
extreme leverage on both axes.

**Consequence 1 — temper the balance verdict.** A test that moves from
p = 0.0008 to p = 0.057 on the removal of one country is high leverage, not a
systematic pattern. This cuts both ways: it is weak evidence of imbalance in
exactly the way a marginal pass would be weak evidence of balance. Report it as
*"2022 fails, and the failure is one observation"*, never as *"2022 fails"*.
`[D-49]`'s geopolitical reading stands, but it is a reading of one country.

**Consequence 2 — Venezuela stays in.** The definitional argument that licenses
the entrepôt exclusion (`[D-46]`: an entrepôt is not a destination, so the shock
unit is ill-defined there) **explicitly does not extend to Venezuela**. It is a
genuine consuming market and its import collapse is genuine demand. Excluding it
because it is inconvenient would be precisely the opportunism the entrepôt
justification was constructed to avoid, and the contrast between the two cases is
worth stating in §3 as evidence that the exclusion rule has teeth.

**Consequence 3 — leave-one-out on Venezuela becomes the packet's single most
informative sensitivity**, and must run on Rotemberg weights, balance **and** the
Phase 2 estimates — not only on the balance test where it happened to be
discovered. Added to the Phase 2 robustness battery ahead of the
leave-one-industry-out checks it displaces in priority.

---

## Section 3 — Pre-registration

Written before the corresponding tests are run. Not to be edited afterwards;
dated additions are appended, never substituted.

```
[D-PRE-1]  2022 trade-balance conjecture.
  S0 fails BHJ trade balance at p = 0.013 in 2022; 2014 and 2018 pass.
  Prediction: 2022 passes at S2 and S3, because the failure reflects Brazilian
  supply expansion (pre-salt) rather than destination demand, and every
  exogenous rung removes Brazil from the numerator by construction.

[D-PRE-2]  Workforce-balance prediction.  [added 2026-08-10 after G4]
  S0 and S1 fail workforce balance in 5 of 6 cells (D-0-5).
  Prediction: S2 and S3 pass in at least 4 of 6, because an exogenous
  foreign-demand shock is not a function of Brazilian industry factor
  intensity, which is what drives the current failure (D-0-6).
  This is the sharper test and supersedes D-PRE-1 as the packet's headline.

  NOTE added 2026-08-10. The earlier IV-A / IV-B attempt does not bear on this
  prediction. Those variants failed on first-stage STRENGTH; no balance test was
  run on them, and none could have been, since sector_chars.rds did not exist
  until 2026-08-10. The exogeneity premise is therefore untested, not rejected.
  See [D-3a], [D-3b].

  DISPOSITION added 2026-08-10, before Phase 2 was run: NOT EVALUABLE.
  Appended, not substituted; the prediction above stands unedited.

  Registered on 10 August predicting that S2 and S3 would restore workforce
  balance in at least 4 of 6 cells. Neither half can be tested:

    S2  is not reportable. 1.88 effective shocks after the entrepot exclusion,
        with ISIC 0141 carrying alpha = 0.75 / 0.73 / 0.70 across the three
        cycles ([D-39], [D-48]). A balance test on a design that is not
        reported answers nothing.
    S3  has no industry dimension. The workforce balance test regresses a
        shock on industry workforce composition; a destination-indexed shock
        has no such composition, so the test is not defined on it, not merely
        inconvenient to run ([D-33]).

  The prediction is therefore NOT EVALUABLE, and NO SUBSTITUTE IS REGISTERED
  IN ITS PLACE.

  Both reasons were discovered after registration and neither was foreseeable
  when it was written. That makes "not evaluable" a legitimate third
  disposition alongside pass and fail - but it is recorded explicitly and
  before the Phase 2 results exist, because a pre-registered prediction that
  quietly disappears because it turned out to be untestable is
  indistinguishable, at a defence, from one that was dropped because it
  failed.

  What survives of the underlying question is recorded as evidence rather
  than as a test: [D-10] shows that exogeneity at fixed level scale does NOT
  restore workforce balance (z_A and z_B pass 1 of 6), and [D-11] shows it
  makes shock concentration worse. The prediction's stated MECHANISM - that an
  exogenous foreign-demand shock is not a function of Brazilian industry
  factor intensity - is falsified by z_A, which is exogenous and is such a
  function because it divides by L_j,2010. That falsification is reportable
  and is not conditional on this prediction being evaluable.

[D-PRE-3]  S2-IV first-stage criterion.

  PRIMARY (binding). Randomization inference on the exposure-weighted
  shock-level first stage: permute Z_j across industries within election
  year, B = 9999, set.seed(2026), statistic = the exposure-weighted
  first-stage coefficient. Require RI p < ____ pooled.
  [THRESHOLD UNSET - fix at 0.01 or 0.05 BEFORE estimating.]
  Rationale: with 2.6-5.6 effective shocks, any F calibrated to nominal
  J = 152 overstates precision by the same mechanism that drives the AKM
  placebo to 21% rejection. An F rule here would contradict the paper's
  own inference hierarchy.

  SECONDARY (reported, not decisive). Montiel Olea-Pflueger effective F,
  clustered by industry. Report the value; do not gate on it. Benchmark
  23.1 quoted for the reader.

  CONSISTENCY. Pooled criterion must pass AND the per-year first-stage
  coefficient must carry the same sign in at least 2 of 3 cycles.

  INTERPRETATION GUARD. A strong first stage is NOT evidence for S2-IV.
  Z_j and g_arc_j share a world-price component, so first-stage strength
  is consistent with price contamination rather than demand variation.
  What licenses S2-IV is Z_j passing the D-0-5 balance tests that g_j
  fails. If Z_j fails balance, S2-IV is not reported regardless of F.

  FALLBACK, fixed in advance. If any condition fails: S2 reduced-form
  leads, S2-IV moves to the appendix with its diagnostics shown, and
  the text states that the shock-level IV was specified, run, and not
  reported as headline - with the reason.

  SUPPORTING EVIDENCE added 2026-08-10. IV-A / IV-B reportedly failed on
  first-stage strength under a level per-worker normalisation with 2.59
  effective shocks. A conventional F rule would have treated that as
  decisive; under the effective shock count it is close to uninformative.
  This is why the binding criterion is RI-based and the effective F is
  reported but not decisive. See [D-3b].

  CLOSED BY NON-APPLICABILITY, 2026-08-10. Appended, not substituted; the
  threshold field above is left blank deliberately and permanently.
  S2-IV instruments the realised arc shock with Z_jt at the industry level.
  S2 is not reportable: 1.88 effective shocks after the entrepot exclusion,
  with ISIC 0141 carrying alpha = 0.75 / 0.73 / 0.70 across the three cycles
  ([D-39], [D-48]). A first stage estimated off fewer than two effective
  shock units cannot support the RI criterion specified above, and the
  INTERPRETATION GUARD already required Z_j to pass the D-0-5 balance tests
  before S2-IV could be reported at all.
  S2-IV therefore never runs and the threshold never binds. Recorded as
  closed rather than left blank, because an unfilled pre-registration field
  sitting in this file indefinitely is worse than one closed with a reason:
  a later reader cannot distinguish "not yet decided" from "never needed".
  The FALLBACK clause governs the write-up: S2 reduced-form appears in the
  appendix with its diagnostics shown, and the text states that the
  shock-level IV was specified, diagnosed and not reported - with the reason.

[D-PRE-4]  Independence threshold.
  If rho(EPW_S0, EPW_S3) > 0.9, Branch A is reframed in the write-up as a
  measurement robustness check rather than an identification robustness check.
  Benchmark: rho(S0, S1) = 0.373 Pearson, so the ladder is known to move.

[D-PRE-5]  Effective-shock claim.
  Settled by D-0-7: five to six, not five to nine. The manuscript sentence is
  corrected rather than softened.

DIAGNOSIS STAMPS  [added 2026-08-10; see the D-30 gate-design note]

  Every gate carries the state of the packet's diagnosis at the time it was
  written. When the diagnosis moves, every gate stamped against a superseded
  state is FLAGGED FOR RE-READ before it fires. Stamps are never back-dated.

  Diagnosis states, in order:
    (i)   pre-[D-0-6]  - the EPW shock treated as a generic shift-share
                         shifter; no articulated account of what organises it
    (ii)  [D-0-6]      - the shock identified as a CAPITAL-INTENSITY GRADIENT
                         driven by the L_j,2010 denominator; supersedes (i)
    (iii) [D-30]       - gates recognised as capable of conflating the threat
                         under test with the phenomenon under study;
                         supersedes (ii) for gate DESIGN, not for findings

  gate        written against   status
  ---------   ---------------   ------------------------------------------
  D-PRE-1     (i)               fired, CONFIRMED. Re-read at (ii): survives -
                                it asks about Brazilian SUPPLY, which the
                                gradient does not bear on.
  D-PRE-2     (i)               NOT EVALUABLE. Mechanism falsified at (ii).
  D-PRE-3     (i)               CLOSED by non-applicability.
  D-PRE-4     (i)               fired a PASS at rho = 0.025, but guarded only
                                the upper tail. Re-read at (iii): the pass
                                licenses "different treatment, so two nulls
                                are not corroboration", NOT "valid
                                identification check". Reading corrected in
                                [D-30]; threshold itself never bound.
  D-PRE-6     (iii)             fired, PASSED at 2.66% against 20%. Written
                                after the diagnosis matured; no re-read owed.

  Stage-0 workforce gate and the bridge gate carried no stamp because none
  existed; both were written against (i) and both were withdrawn as invalid.
  They are the reason this block exists.

  ANY GATE ADDED IN PHASE 2 CARRIES A STAMP AT REGISTRATION.

[D-PRE-6]  Production-capacity orphan threshold.  [added 2026-08-10, before the
           test was run; replaces the withdrawn bridge gate of D-30]

  PRIMARY (binding). If orphan value exceeds 20% of attributed 2010 export
  value nationally, the Comex municipality-attribution threat is material
  enough to reopen the Branch A share construction, and Branch A is not
  reported as an identification robustness check without a corrected
  share series or an explicit bound on the bias.

  Below 20%, the threat is carried into section 3 as a stated limitation
  and mitigated per spec D.7.1: leave-out of the top-20 declaring
  municipios, exclusion of port microregions, entrepot leave-out.

  Note that the statistic is a LOWER BOUND by construction (D-31 decision 1):
  attribution error between two microregions that both have capacity in the
  relevant industry is invisible to it. A breach is therefore decisive; a
  pass is reassuring rather than conclusive.

  SECONDARY (diagnostic, not binding). If the mechanism is attribution,
  orphan value concentrates in port and state-capital microregions.
  Roughly uniform orphan value across microregions points to crosswalk
  noise instead, and weakens the attribution reading whatever the
  headline number.

  ASYMMETRY TO STATE IN SECTION 3 REGARDLESS OF THE RESULT.
  Branch A trades crosswalk error for attribution error. The industry
  design's shares come from RAIS - employment location, reliably measured.
  Branch A's come from Comex - declaring municipio, which is firm domicile
  or port. "Crosswalk-free" is not free; it is a different threat, and the
  top-20 declaring municipios carrying 41.3% of attributed value says it
  is not a small one. This sentence belongs in the paper whatever the
  orphan test returns.
```

---

## Section 4 — Outstanding

| item | status |
|---|---|
| ~~Re-run `03b_instrument_construction.R`~~ | **closed** 2026-08-10 — `[D-9]` |
| ~~Balance-test `z_A` and `z_B` against `sector_chars.rds`~~ | **closed** 2026-08-10 — `[D-10]` |
| ~~rename `BACI_HS07_V202601/` → `baci/`~~ | **closed** — `[D-12]` |
| ~~move the 14 unused BACI year files out of `DATA_DIR`~~ | **closed** — `[D-12]` |
| ~~pin `N_MICRO_EXPECTED`~~ | **closed** — 557, `[D-7]` |
| manuscript "556 microregions" — correct to 557 or produce a source | **open** — `[D-7]` |
| **Stage-0 gate: `[D-PRE-2]` premise not supported at S2L** | **open, blocking** — `[D-10]` |
| **Run `[D-31]` orphan test alongside `D3`** | **open** |
| `D3` shock dispersion: `sd(g_dt)` vs `sd(g_jt)`, `sd(g_arc)`, before Rotemberg | open — `[A1]` |
| Re-read `[D-PRE-4]` against the current diagnosis before it fires | open — `[D-30]` gate-design note |
| ~~bridge gate `ρ < 0.5`~~ | **withdrawn as invalid** — `[D-30]`, replaced by `[D-31]` |
| ~~correct `D_data_contracts.md` §1b: BACI is not ISO 3166-1 numeric~~ | **closed** 2026-08-10 — `[D-20]` |
| ~~pin the arc baseline in the spec and contracts~~ | **closed** 2026-08-10 — `[D-32]`, cumulative 2010 |
| ~~`[D-PRE-3]` RI threshold: 0.01 or 0.05~~ | **closed by non-applicability** — S2 not reportable |
| Phase 2 contracts: "inspect first, then assert" rule | open — `D_data_contracts.md` §0a |
| confirm `gdpcap_d` in `Gravity_V202211.rds`; drop the WDI pull if present | open — `[D-4]` |
| copy `EXP_YYYY_MUN.csv` into canonical `DATA_DIR` | open — `[D-4]` |
| `cnae_isic_crosswalk 2.rds` rename or delete | open — `[D-0-2]` |
| stale `output/revision/G4/G4_PENDING.txt` | open — delete |
| national FTE-weighted shares in `[D-0-4]` | open — paste from run log |
| `[D-PRE-3]` RI threshold: 0.01 or 0.05 | open — fix before running S2-IV |
| §3.4 paragraph folding the four diagnostics into `[D-0-6]` | open |
| `G2_first_stage.R` re-run now that the RAIS panel exists | open — `[D-3]` |
| delete `RATIONALE_D_amendments.md`, folded into this file | open |
| ~~BACI vintage decision~~ | **closed** — HS07 V202601, `[D-4]` |
| append this file to `RATIONALE.md` at packet close | open |
