# Claude Code — Packet D, Phase 1 (instruments only)

Paste as the opening message of a Claude Code session in the dissertation repo.

---

## Context

You are working in the repository for a master's dissertation in economics:
*Trade Exposure and Political Polarization: Evidence from the Brazilian Case*
(PPGE/UFES). The design is a reduced-form shift-share study of how regional
export shocks affect political polarization across Brazilian microregions over
the 2014, 2018 and 2022 election cycles. The published pipeline is complete and
has passed a multi-round audit.

Read these three files in full before writing any code. They are in
`data/códigos/`:

- `RATIONALE_D.md` — **read this first.** The change log, the diagnosis that
  motivates the packet, and the pre-registration block. It also records which
  local artefacts are defective.
- `packet_D_spec.md` — the construction, including the S0→S3 ladder
- `D_data_contracts.md` — exact schemas, assertions and output paths

## Scope of this phase — read carefully

**Build the instruments and diagnose them. Do not estimate any outcome
regression.** No `delta_P_dalton`, no `delta_P_center`, no Esteban–Ray, no β of
any kind. Phase 2 does estimation and is not authorised yet.

The reason is not caution about compute. The packet's decisive question —
`[D-PRE-2]`, does an exogenous foreign-demand shock restore shock balance where
the realised shock fails — is answerable from the shocks alone. Answering it
before touching the outcomes also makes specification search structurally
impossible, which is worth stating in the log.

If you find yourself about to join a shock series to a polarization outcome,
stop and report instead.

## Hard constraints

1. **Locked files.** Do not edit `00_epw_calculo_v7.R`, `01_extraction.R`,
   `03_epw_construction.R`, `07_regression_inference.R`, or anything in
   `códigos/revision/`. Read their outputs; never modify them.
2. **Additive only.** New scripts in `data/códigos/packet_D/`, new outputs under
   `output/packet_D/`, new audit tags `[D-*]`. If a target output path exists,
   abort rather than overwrite.
3. **Do not rebuild the crosswalk or the employment shares.** Load the saved v7
   objects. Rebuilding breaks the comparability that gives the ladder meaning.
4. **`cnae_isic_crosswalk 2.rds` is DEFECTIVE — never read it.** It carries 403
   counterfeit pairs from a zero-padding bug. See `[D-0-2]`. If you need a
   CNAE→ISIC map, rebuild from `CNAE20_ISIC4.xls` with `str_sub(x, 1, 4)`, never
   `str_pad`, and assert 743 pairs / 672 cnae4 / 416 isic4 / max split 1/7.
5. **Do not tune anything toward significance.** The project's finding is a null
   under randomization inference and that is the contribution.
6. **Assertions are not optional.** Every `stopifnot()` block in
   `D_data_contracts.md` goes into the code as written. On failure, stop and
   report; never coerce, never `left_join` a gap and fill with zero.
7. `set.seed(2026)`, `B = 9999` permutations, throughout.

## STAGE 0 — re-run `03b`, before building anything new

`03b_instrument_construction.R` is a complete, never-executed implementation of
the ADH-style demand instrument. It was blocked on BACI files that are now
present. Running it settles three open questions at zero build cost.

**Path fixes required first** (`[D-4]`):

- The download extracted to `DATA_DIR/BACI_HS07_V202601/`. `03b` expects
  `DATA_DIR/baci/`. **Rename the directory; do not edit `03b`** — it must stay
  byte-comparable to its committed form.
- Move the fourteen unused year files out of the working tree. Only 2010, 2014,
  2018, 2022 are needed. A stray `list.files()` glob over 6 GB will otherwise
  pull the full panel.

Then:

1. Run `03b_instrument_construction.R` end to end. It writes
   `epw_iv_panel_v1.rds`, `sectoral_demand_iv_v1.rds`,
   `output/03b_iv_run_log.txt` and `output/iv_orphan_hs6_v1.csv`.
2. **Report the actual first-stage F for IV-A and IV-B.** `[D-3a]` currently
   records "weak first stage" as unverified recollection from another machine.
   This converts it to record.
3. **Balance-test `z_A` and `z_B` against `sector_chars.rds`** — newly possible,
   since that artefact was only built on 2026-08-10. Use the `07` §6 form
   exactly: `feols(z ~ sh_loweduc + sh_white + sh_male + mean_lnwage,
   weights = ~ s_bar)`, per election year, national employment weights `[A-6]`.
   Also run the `G3` trade-characteristic form (`commodity + log_exp2010`) so the
   two are comparable.
4. **Report Rotemberg weights and effective shock count for `z_A` and `z_B`.**
   This isolates whether exogeneity alone touches the 0710/0610 concentration,
   or whether the level normalisation is doing all the work.

**Gate: report Stage 0 results and stop.** If `z_A` and `z_B` fail balance as
badly as `g_jt` does, tell me before proceeding — the premise of the whole packet
would be in question and `[D-PRE-2]` would need rewriting.

## STAGE 1 — build the two new shocks

Only after the Stage 0 gate. Four scripts, in order, each independently runnable
and idempotent, reading from and writing to disk rather than session state.

| script | purpose |
|---|---|
| `D1_baci_destino.R` | BACI ingest carrying the **destination** dimension: `m_dp_row` (Brazil excluded), `ω_pd`, `ω_jd` |
| `D2_shocks.R` | Branch B `Z_jt` (destination-weighted, arc-%) and Branch A `g_dt` |
| `D3_shares_destino.R` | Comex `EXP_YYYY_MUN.csv` → `X_rd,2010` → `s_rd` (N1, N2) + the employment-imputed bridge |
| `D4_diagnostics.R` | Rotemberg, effective shocks, balance tests, independence correlations, shock-distribution figures |

**What separates the new shocks from IV-A/IV-B**, and therefore what must not be
lost in implementation (`[D-3b]`): IV-A and IV-B are level-per-worker and
aggregate to world totals. The new constructions are **proportional (arc-%)** and
**destination-weighted**. If you find yourself dividing by `L_j,2010`, you have
rebuilt IV-A.

## Four data facts, confirmed — assert on them, do not rediscover

1. **BACI schema:** `t, i, j, k, v, q`. Brazil is country code `76`. Values are
   **thousand USD, current**. Quantities in metric tons.
2. **Zero-padding on `k`.** BACI strips leading zeros. Pad to width 6 *before*
   any crosswalk join, then `stopifnot(all(nchar(k) == 6))`. Without this, every
   product in HS chapters 01–09 silently fails to match.
3. **Deflation.** Values are current USD. Deflate with `cpi_us.rds`, as `03b`
   does. Both endpoints of any arc growth rate must be in the same constant
   currency — a deflated numerator over a nominal denominator breaks an arc rate
   silently.
4. **Country codes join cleanly.** BACI `country_code` is the numeric ISO 3166-1
   code (4 Afghanistan, 76 Brazil). It matches `CO_PAIS_ISON3` in sheet 10 of
   `data/misc/TABELAS_AUXILIARES.xlsx` directly — no name matching. CEPII Gravity
   keys on alphabetic `iso3`; route via `Countries_V202211.csv` `iso3num`. Still
   write `log_d_unmatched_codes.csv`, but expect it near-empty.

## What I want reported back

After each gate, a short status: what passed, the numbers, what surprised you.
Not a narration of the code.

At the end, answer these four directly:

1. **Stage 0:** what were IV-A and IV-B's actual first-stage F values, and do
   `z_A` / `z_B` pass the balance tests that `g_jt` fails?
2. **Does exogenous demand restore workforce balance?** Six cells, `[D-PRE-2]`
   predicts at least four pass. Report all of them either way.
3. **Does the effective number of shocks rise**, and where does the
   concentration go? Give the count for `g_jt`, `g_arc`, `z_A`, `z_B`, the new
   `Z_jt` and `g_dt`. Benchmarks: 2.59 level, 5.57 arc.
4. **Is Branch A independent of the baseline**, or does China dominate the
   destination weights the way iron ore dominates the industry weights? Report
   `ρ(EPW_S0, EPW_S3)`; `[D-PRE-4]` reframes Branch A if it exceeds 0.9.
   Benchmark: `ρ(S0, S1) = 0.373` Pearson.

## Things that will go wrong

- **`Gravity_V202211.rds` may already contain `gdpcap_d`.** Check before
  arranging any World Bank pull: `grep("gdpcap|gdp_|pop_", names(g), value=TRUE)`.
  If present, the destination-characteristic set for the balance test comes from
  one object along with `dist`, `contig`, `comlang_off`.
- **Comex `EXP_YYYY_MUN.csv` is SH4, not HS6.** The `ω_pd` basket weighting is
  therefore coarser than `packet_D_spec.md` §D.4.2 specifies. Either aggregate
  BACI to HS4 for that weighting, or take `ω_pd` from BACI's own Brazil rows
  (`i == 76`) at HS6 — the second is cleaner and avoids a Comex/BACI product
  mismatch. Say which you chose and why.
- **The `EXP_*_MUN.csv` files live outside canonical `DATA_DIR`**, in
  `tema mestrado/data/exportações/`. Copy them in; do not point a script across
  trees.
- **The município → microrregião correspondence changed over the period.** Pin
  the 2010 territorial division and say which vintage you used.
- **`N_MICRO_EXPECTED` is ambiguous in the existing work** — 556 and 558 both
  appear, and N varies across tables at 1,668 / 1,671 / 1,674. Pick one, document
  why, assert it everywhere, and flag the inconsistency as a separate finding.
  Do not propagate the ambiguity.
- **The `EPW⁻` sign convention** was the subject of a v7 audit fix. `epw_neg`
  stays negative. Read the relevant `RATIONALE.md` entry before touching any
  decomposition.

## Style

- R, tidyverse-compatible, explicitness over elegance
- Every non-obvious decision carries a bracketed audit tag in a comment and a
  matching entry appended to `RATIONALE_D.md`
- No hidden defaults: if a choice could reasonably go two ways, make it a named
  constant at the top of the script
- Tables as markdown, figures as vector PDF
- Comments in English; the manuscript is written in Portuguese and translated

## What not to do

- **Do not run any outcome regression.** That is Phase 2.
- Do not write manuscript text. Produce tables, figures and numbers.
- Do not cite anything. The reference list is settled in `packet_D_spec.md` §D.10.
- Do not "fix" the existing null by searching specifications.
- Do not proceed past a gate without telling me.
