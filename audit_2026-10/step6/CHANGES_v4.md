# yago_ramalho_dissertação_v4.tex: what changed and what is left

*07/11/2026. Built from the .tex sent on 02/11 (`step5/diss.tex`), following the step 5 reconciliation list (`step5/out/05_reconciliation.csv`) and the writing audit of 07/11 (`claude/2026-11-07_ai_writing_audit.md`). The original file is untouched.*

## What changed

**Front matter.**
- Both abstracts now report the registered result: S3 bounds the effect at 0.075 SD per SD (90% set [−0.075, 0.045]); S0 is inconclusive; nothing in the secondary family survives correction.
- The mention of imports is removed.
- Reference-line typos are fixed ("Jurídicas", "Universidade Federal").

**Chapter 1.**
- The research question, design and result paragraphs are rewritten: two recentred designs, deputy Dalton as the primary outcome, a registered plan, and a bounded null.
- The exports narrative is corrected (peak 2011, trough 2016, new high 2022).
- The "%%terminar" and "%%expandir" placeholders are resolved.
- The micro-foundation appendix is no longer listed.

**Chapter 2.**
- The Rettl and Costa–Garred–Pessoa citations are corrected.
- The §2.2 contradiction about export effects is resolved.
- The broken `fig:framework` reference is fixed.
- The hypotheses are restated as H1 (two-sided), H1b and H2, with heterogeneity marked as descriptive.
- The framework figure labels are updated.
- Writing-audit fixes are applied: opening sentence, "instructive", typos.

**Chapter 3.**
- The dropped microregion is now correctly Japurá (it was given as "Médio Amazonas").
- Table 1 is rewritten: deputy and governor outcomes, the S0 and S3 treatments, GDP from IBGE (not IPEADATA), and the top-4 pre-trend controls removed.
- Deputy coverage is added (90.2 / 93.7 / 91.3 / 86.4%).
- A paragraph explains why the deputy vote is the primary outcome (presidential index ≈ the winner's share; R² 0.96 in 2022).
- The PSL 2018 score is stated as coming from BLS 9.
- The BLS wave text is corrected, and the Figure 2 description is rewritten to match what the figure shows.
- The map text is restated per year (presidential; flagged for regeneration).
- The promise to report alternative centre bands is removed.
- The controls section is rewritten: base vs extended controls, and the S3 controls under A4.
- Table 3 now has deputy and governor rows, the recentred treatments and θ_dest, plus the two rounding fixes.
- The four limitations are updated.

**Chapter 4 (rewritten).**
- The S0 and S3 equations.
- Recentring and exchangeability units (149 / 201).
- The estimating equation.
- The bust coefficient (labelled unvalidated).
- Studentized randomization inference, with the reason for using it (Monte Carlo sizes 7.8% / 18.5% → 3.7% / 1.8%).
- Equivalence benchmarks and their attainability, Holm/BH and the decision table.
- The validation gates (a)–(e), including the falsification caveat for S3 and the post-result amendment A4.
- Crosswalk figures corrected (177 classes in 152 groups; 9,628 / 1,245 / 15.7% orphan figures).

**Chapter 5 (rewritten).**
- Table 4 (primary family) and the decision-table sentence.
- Table 5 (secondary family, BH).
- BLS bootstrap, AKM0, and the leverage table (new Table 6).
- A summary of the specification curve.
- §5.4 now tests reading 2 (Δȳ is null) and measures power for reading 3.
- Old Tables 4–5, the symmetry section and the heterogeneity section are removed.

**Chapter 6 (rewritten).** Result, limits and three extensions: S3 at destination × HS4 and import competition (from the design-only diagnostics), the oil and iron-ore case studies, and pass-through.

**Chapter 7 ("Novos resultados") removed.** Governor results now sit in the secondary family, using the repaired panel.

**Appendices.**
- Table A1 text: in-transit votes in 2014.
- Table A2: 2014 total 1.38%; PATRIOTA flagged; note clarified.
- New note on the governor 2022 repair.
- App. B: 189 classes; class dropping vs Japurá clarified; Table B1 filled in.
- Table C1 recomputed from the v7 treatment, with the source note fixed.

## Left to do

| Item | Where |
|---|---|
| Regenerate figures: deputy map (Fig. 3), exports series (Fig. 4), studentized RI distribution (Fig. 5; needs `step4_primary.R` rerun saving draws), exposure map (App. C); add a specification-curve figure | `% TODO(figure)` comments |
| Add a bib entry `borusyakhull2023` (Borusyak & Hull 2023, *Econometrica* 91(6)) and a CEPII BACI citation | `% TODO(bib)` |
| Check that `\cite{dippel}` is Dippel–Gold–Heblich and `\cite{colantone}` is Colantone–Stanig, and the three Brexit values (12.233, 0.14, 10.6) in `colantone2018.pdf` | tex L1233 |
| Chapter 2 literature characterisations not verified against sources (step 5, NOT VERIFIED rows) | Ch. 2 |
| The compile check used a stand-in for `abntex2ppgsi.cls`, an empty .bib and placeholder figures: no LaTeX errors from the text and no undefined labels; citations show as "?" | — |
