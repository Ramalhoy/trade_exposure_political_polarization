# Step 5: Reconciliation of the dissertation text against raw material and the plan

*02/11/2026. Text checked: `yago_ramalho_dissertação.tex` as sent on 02/11 (tex line numbers below). Page numbers are the printed numbers of the 01/10 PDF. That PDF has the same chapters and the same decimal figures as the .tex; the only differences found were TikZ coordinates and section numbers. Scripts are in `step5/`, outputs in `step5/out/`. The full list is `step5/out/05_reconciliation.csv` (207 rows), reproduced in §5. Nothing in the dissertation text was edited.*

## 0. How to read this

Each row is one sentence, number, table block or figure, with a status:

| Status | Rows | Meaning |
|---|---|---|
| **CONFIRMED** | 55 | Reproduced from raw or stored material, and consistent with the plan. |
| **CHANGED** | 88 | Old → new, with the source of the new value. This includes cases where the old number is arithmetically right but describes the superseded design. |
| **REMOVED** | 27 | No counterpart under the plan, or unsupported. |
| **NOT VERIFIED** | 37 | Flagged, not approximated. These are mostly literature characterisations (outside raw-material scope), plus figures whose files were not checked. |

**Granularity.**
- Chapters 3–7 and the appendices: one row per sentence or number.
- Abstract, résumé and introduction: one row per claim.
- Literature-review paragraphs: one row each. Their numerical claims were checked against the cited PDF where it is in your folder.

**How old and new relate.** "New" values come from the pre-registered analysis (step 4a, under A4), so the deputy-vote Dalton is primary.
- Where the text reports a superseded quantity, I re-ran the old number when that was cheap. For example, old Table 4 reproduces exactly (`s5_table4_repro.csv`).
- The row then records both facts: the old number was computed correctly, and it is replaced.

## 1. Factual errors in the current text, independent of the plan

These would be errors under any design.

1. **The dropped microregion is Japurá (AM, 13002), not "Médio Amazonas".** No microregion has that name. Japurá has 866 formal jobs in 2010, none of them in a tradable industry. It is *not* "retained with ΔEPW = 0": it has no rows in the share matrix or the EPW panel. (§3.1, Table 3 note, App. B; `s5_data.csv` rows 3–7)
2. **PSL in 2018 is scored with Bolsonaro's BLS 9 (2021) score, 0.862.** That wave was fielded *after* the election, which breaks the Table 2 rule. BLS 8 contains neither PSL nor Bolsonaro, and the text should say so. (`s5_votes.csv`)
3. **Table C1 (EPW by state) cannot be reproduced from the v7 objects under either share convention.** It comes from an older treatment: PI 4.154 vs 0.182 now; SE 0.407 now ranks first. The microregion counts per state are right. The exposure map (Fig. 6) probably comes from the same older treatment. (`s5_tableA3_total.csv`)
4. **The crosswalk figures do not reproduce.**
   - "176 matched industries" is in fact 177 ISIC classes in 152 groups.
   - "≈192 classes in sections A–C" is in fact 189.
   - "9,346 NCM codes, 1,200 orphaned, ≈13% of value": the CONCLA table in your folder gives 9,628 codes, 1,245 orphaned, and 15.7% of value.
   - These orphan figures are cited to Rettl, but they do not appear in Rettl.
   - (`s5_data.csv`)
5. **Two citations misdescribe their sources.**
   - Rettl (2025) is cited for "declining exports amplify anti-system sentiment". The paper is about PT vote share and evangelical concentration, and the phrase does not appear in it.
   - Costa–Garred–Pessoa report *wage growth and lower cash-transfer take-up across microregions*, not "poverty reduction in municipalities".
6. **§2.2 contradicts itself.** "The only Brazilian evidence that separates import from export exposure finds the latter inert" is refuted three paragraphs earlier: Jones et al. report export effects on PT of 2.0–3.4 pp per SD.
7. **The exports narrative is wrong.** "Decline since the 2010s followed by stagnation" / "onset of the decline": real exports peak in 2011 (245.9 bn, 2010 USD), fall to 163.1 bn in 2016, and reach a new high of 249.0 bn in 2022. (`s5_exports_series.csv`)
8. **The GDP control's source is not IPEADATA.** It is IBGE PIB Municipal 2010 summed and divided by Census population. (`01_controls_micro2.R`, read, not re-run)
9. **Small numerical slips.**
   - Table A2's 2014 total is 1.38, not 1.39.
   - PATRIOTA (1.26%) also exceeds 1% but is not noted.
   - In-transit votes exist in 2014 too (73,706), recorded under municipalities.
   - Table 3: manufacturing share mean 0.642 (not 0.643); ln pop P75 12.605 (not 12.606).
   - BLS waves are not all odd-year (the first is 1990).
   - The Figure 2 text says "candidates by election, right-extreme concentrations absent before 2018". The figure shows party positions by wave, and scores above 0.6 exist in every wave.
   - The introduction promises a micro-foundation appendix that is commented out.
10. **"≈2.4 effective shocks" is a mean of three within-year counts.** For the pooled estimator the figure is about 3 (Rotemberg 3.13 / 3.01; AKM 2.86). (`step1_log.txt` L13, L16, L62, L160)

## 2. What the plan changes in the text

- **Primary outcome.** The presidential Dalton becomes the federal-deputy Dalton. In 2022 the presidential index is nearly a function of the winner's share (within-state-year R² 0.96; `step2_construct_log.txt` L21).
  - Chapters 1, 3, 4, 5 and 6, both abstracts and Table 1 need this change.
  - The deputy outcome is not described anywhere in the current text. It needs a §3.2 paragraph, coverage figures (90.2 / 93.7 / 91.3 / 86.4%) and a map.
- **Treatment and inference.**
  - Raw ΔEPW becomes two recentred designs (S0, S3).
  - Mesoregion×year clusters and coefficient RI become studentized within-stratum RI, Holm, TOST and BH.
  - This affects equations (3)–(4), §4.2, §4.3, the Table 4 note and Figure 5.
- **Results.** Old Table 4 and Table 5 and §5.1–5.2 are replaced by:

  | | β̂ | Studentized p (Holm) | 90% set | 95% set | Class |
  |---|---|---|---|---|---|
  | S0 | 0.0336 | 0.631 (0.631) | [−0.100, 0.239] | [−0.157, 0.280] | INC |
  | S3 | −0.0289 | 0.296 (0.592) | [−0.075, 0.045] | [−0.088, 0.094] | EQ at 0.162 |

  - Secondary family: no test survives BH; the smallest q is 0.952.
  - Score uncertainty (BLS bootstrap) changes no class.
  - The symmetry test, control coefficients, leave-out t-statistics and Table 6 have no counterpart in the plan (REMOVED, or descriptive only).
- **Robustness.** Pre-trend controls and the leave-out exercise are replaced by:
  - gate (d) falsification (S0 p 0.813 / 0.879; S3 p 0.436 / 0.096);
  - the leverage inspection (top-10 microregions carry 57% / 94% of the variation; β̂ without them −0.079 / −0.092);
  - the AKM0 sets (S0 bounded, S3 unbounded).
- **Interpretation (§5.4).**
  - Reading 2 ("the outcome may be wrong; a directional outcome is next") has now been tested: Δȳ is null for all three offices.
  - Reading 3 ("lack of power") is now measured: rejection at β = 0.038 is 0.115 and 0.091.
  - The S3 bound is the substantive result. A4 was a post-result change and must be stated as one.

## 3. Confirmed as written (selection)

- Sample arithmetic: 1,671 / 1,668 / 557, with DF as the singleton.
- Presidential coverage: 99.7 / 98.6 / 96.1 / 99.4%. NOVO 2.50% and PATRIOTA 1.26%.
- All of Table A1: overseas votes and VT 2010.
- Table 2 wave matching.
- In 2018, P^N = 1 in every microregion.
- Table 3: all rows except the two slips above.
- The balance-test p-values (0.30 / 0.29 / 0.01) and oil's α = 0.66 in 2022.
- Constant-dollar shock units.
- Crosswalk loss below 1% (0.60–0.79%).
- ISIC 419 / 21 / 88 / 238.
- Zucco's r = 0.97 (PREPPS) and the Appendix E bands.
- Jones et al.: 558 microregions and 2.0–3.4 pp.
- Rettl: 174 industries.
- Old Table 4 under its own (superseded) specification: treatment coefficients and SEs, symmetry p, education and within-R². The other control coefficients were not re-checked.

## 4. Not done, and why

| Item | Why |
|---|---|
| 37 NOT VERIFIED rows (literature characterisations, the 54.3%→65.2% export-composition figure, FVA < 20%, CSES coverage) | Cited sources are absent from your folder, or the claim is interpretive. They were not approximated. |
| Figures 2, 3, 4, 6 | Figure files were not opened. Figures 3 and 6 must be regenerated anyway (deputy map; v7 treatment). |
| Figure 5 under the plan (studentized RI distribution) | `step4_primary.R` does not save the permutation draws; it needs a rerun with that output. |
| UN HS–ISIC 0.5/0.5 split for NCM 260111 (App. B example) | The `concordance` R package is not installable here (CRAN unreachable). The final pipeline mapping (0710, w = 1) is confirmed. |
| Conley SEs, alternative centre bands, Table 6 and year slopes under the plan | Reference-only or descriptive in the plan, and not run. The text should either drop these promises or have them run as descriptive items. |
| Gate (b) replication | Inputs missing (A1.1), unchanged. |

## 5. Full list (207 rows)
