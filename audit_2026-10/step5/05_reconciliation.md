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

### Resumo (PT)  (CHANGED 6)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 1 | 406 | front matter (pdf p.5) | **CHANGED** | Centro de Ciências Jurícias e Econômicas, Universidade de Federal do Espírito Santo | Centro de Ciências Jurídicas e Econômicas, Universidade Federal do Espírito Santo | typo (the Abstract's reference line, tex L450, already spells 'Jurídicas') |
| 2 | 409 | front matter (pdf p.5) | **CHANGED** | efeito da exposição ao comércio internacional em indicadores de polarização ... eleições de 2010 a 2022 | Objetiva-se estimar o efeito de choques de exportação sobre a dispersão ideológica do voto para deputado federal (resultado primário) nas microrregiões brasileiras, 2010–2022; presidente e governador são resultados secundários/descritivos. | 02_analysis_plan.md §1 (primary office = deputy) |
| 3 | 411 | front matter (pdf p.5) | **CHANGED** | variações do desempenho exportador e importador | variações da exposição local a choques de exportação (nenhum choque de importação é estimado) | 01_estimand_statement.md 'Claims that exceed' #1; no import treatment in df_estimation_v7.rds or E0 |
| 4 | 412 | front matter (pdf p.5) | **CHANGED** | uma medida (EPW) ... estimada por primeiras diferenças empilhadas | duas medidas shift-share, recentradas (Borusyak–Hull): S0 (exportações brasileiras por trabalhador, 152 indústrias) e S3 (demanda de importação do resto do mundo por destino, 201 destinos); primeiras diferenças empilhadas com EF estado×ano; inferência por randomização studentizada. | 02_analysis_plan.md §1–2; A2 (02b), A4 (02e) |
| 5 | 413 | front matter (pdf p.5) | **CHANGED** | Dalton ponderado ... e índice de esvaziamento do centro, ambos do BLS | Dalton ponderado pelos votos (deputado federal, primário); esvaziamento do centro e Esteban–Ray são descritivos/secundários; escores BLS com incerteza propagada por bootstrap (500 sorteios). | 02_analysis_plan.md §1, §3; step4a/out/step4_bls_stability.csv |
| 6 | 414 | front matter (pdf p.5) | **CHANGED** | resultados preliminares ... efeito agregado estatisticamente insignificante; testes ainda serão realizados | Row-2 sentence (see Abstract row below, in Portuguese). | step4a/out/step4_primary.csv (S0 INC, S3 EQ); 02_analysis_plan.md §4 row 2 |

### Abstract (EN)  (CHANGED 4, CONFIRMED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 7 | 454 | front matter (pdf p.6) | **CHANGED** | variations in local export and import performance | local exposure to export shocks (no import treatment is estimated) | 01_estimand_statement.md 'Claims that exceed' #1 |
| 8 | 455 | front matter (pdf p.6) | **CONFIRMED** | commodity supercycle ... spatially uneven trade shocks | — | step5/out/s5_data.csv 'Real exports' (200.4 → 245.9 in 2011 → 163.1 in 2016 → 249.0 bn in 2022); spatial spread: step5/out/s5_table3.csv dEPW sd 0.494 |
| 9 | 455 | front matter (pdf p.6) | **CHANGED** | constructs a shift-share measure (EPW) ... stacked first-differences model | constructs two recentred shift-share measures — S0, realised Brazilian exports per worker by industry (152 industries), and S3, rest-of-world import demand by destination (201 destinations) — in a stacked first-difference model with state×year fixed effects; inference is studentized randomization inference over the shocks. | 02_analysis_plan.md §1–2; A2, A4 |
| 10 | 456 | front matter (pdf p.6) | **CHANGED** | Dalton Index and an index of center erosion | the vote-share-weighted Dalton index of the federal-deputy vote (primary); presidential and gubernatorial indices, centre-emptying and Esteban–Ray are secondary or descriptive | 02_analysis_plan.md §1, §3 |
| 11 | 456 | front matter (pdf p.6) | **CHANGED** | results are preliminary ... not statistically significant ... tests remain to be conducted | "The destination-demand design rules out effects on the ideological dispersion of federal-deputy votes larger than 0.075 SD per SD (90% randomization set [−0.075, 0.045]), which excludes the effect size reported for Brexit (0.162) but not those reported for PT vote share (0.038) or the extreme right in Germany (0.059); the industry-export design is too imprecise to bound the effect ([−0.100, 0.239])." No secondary sentence (no test survives BH). | step4a/out/step4_primary.csv rows S0, S3 (ci90, class); step4a/out/step4_secondary.csv q_BH ≥ 0.952; benchmarks 0.038/0.059/0.162 from 02_analysis_plan.md §3 |

### 1 Introduction  (CHANGED 9, CONFIRMED 2, NOT VERIFIED 3, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 12 | 507 | 10 | **NOT VERIFIED** | framing paragraph with press citations | keep as framing | literature/press characterisation; outside raw-material scope |
| 13 | 509 | 10 | **NOT VERIFIED** | public-finance motivation paragraph | keep as framing; it states no estimate | literature characterisation (hunter, ZUCCO, melloespektor2018, Novaes); not checked |
| 14 | 511 | 11 | **NOT VERIFIED** | literature summary | keep | literature characterisation |
| 15 | 513 | 11 | **CHANGED** | how do changes in export and import performance relate | how does local exposure to export shocks relate to the ideological dispersion of the vote | 01_estimand_statement.md #1 (no import treatment) |
| 16 | 515 | 11 | **CONFIRMED** | H1b as stated (bust > 0, boom ≤ 0) | —; this is the plan's H1b, tested as a secondary-family bust coefficient | 02_analysis_plan.md §3 |
| 17 | 515 | 11 | **CHANGED** | the estimates do not confirm this prediction %%terminar | Neither design detects a bust effect on deputy dispersion: S0 b_bust −0.012 (RI p 0.856), S3 +0.022 (p 0.502); the bust estimator did not pass validation and is reported as unvalidated. | step4a/out/step4_secondary.csv rows 'Bust coefficient' (validated = FALSE) |
| 18 | 517 | 11 | **CHANGED** | window spans the peak and unwinding of the commodity supercycle and a pronounced decline and recomposition of Brazilian exports | Real exports (2010 USD) peaked in 2011 (245.9 bn), fell to 163.1 bn in 2016 and recovered to 249.0 bn in 2022: the window covers a decline and a recovery, not only an unwinding. | step5/out/s5_data.csv 'Real exports, USD bn 2010 prices' |
| 19 | 519 | 11 | **CHANGED** | one EPW measure; four election years; presidential Dalton; centre-emptying supplementary | two recentred measures (S0, S3); three stacked differences from 2010; deputy Dalton primary; presidential/governor Dalton, centre-emptying and Esteban–Ray descriptive or secondary | 02_analysis_plan.md §1, §3 |
| 20 | 521 | 12 | **CHANGED** | coefficient statistically indistinguishable from zero on both polarization measures | S0: β̂ = 0.034 (studentized RI p 0.631; 90% set [−0.100, 0.239], INC). S3: β̂ = −0.029 (p 0.296; 90% set [−0.075, 0.045], EQ at 0.162). Both on deputy Dalton; Holm-adjusted p 0.631 / 0.592. | step4a/out/step4_primary.csv; benchmark 0.162 from 02_analysis_plan.md §3 |
| 21 | 524 | 12 | **CHANGED** | the shock is a contraction in external demand ... exposed workers are concentrated in agriculture and extraction | S0's identifying variation is two realised export paths (oil, AKM weight 0.508; iron ore 0.293), and the dominant 2022 shock is an oil expansion (g = +53.6); S3 is foreign import demand by destination. Agriculture carries little weight (soy 0.051). | step1_log.txt L45–51, L188–190 |
| 22 | 524 | 12 | **CHANGED** | all 557 microregions in four presidential elections | 557 microregions in the estimation sample (558 in the panels), for federal deputy (primary), president and governor, 2010–2022 | step5/out/s5_data.csv rows 1–2; step5/out/s5_votes.csv '2010 stored panel: microregions' |
| 23 | 524 | 12 | **REMOVED** | documents how far apart cluster-robust and design-based inference are | Cluster/Conley errors are reference-only under the plan and are not used as evidence; the contribution is the validated studentized RI (gates c, d) and the equivalence bound. | 02_analysis_plan.md §2 item 3 |
| 24 | 524 | 12 | **CHANGED** | 152 tradable industry groups ... avoids the orphaning of roughly 13 per cent of export value \cite{Rettl} | 177 ISIC classes merged into 152 industry groups (149 exchangeability units after merging identical share columns). The chained route's orphan rate is 15.7% of 2010/14/18/22 export value (1,245 of 9,628 NCM codes absent from the CONCLA NCM 2011–CNAE 2.0 table); the 13% figure was not reproduced and does not appear in Rettl (2025). | step5/out/s5_data.csv 'ISIC classes inside the 152 retained groups', 'NCM-8 codes exported ... (4 yrs)'; step4a/out/step4_cleanroom_beta.csv units 149; step5/lit/rettl_2025_hbs_wp25-038.txt (no such figure) |
| 25 | 524 | 13 | **CONFIRMED** | decomposition by sign | —; enters only as H1b, secondary family | 02_analysis_plan.md §3 |
| 26 | 526 | 13 | **CHANGED** | Three appendices ... and a formal micro-foundation for the hypotheses | The micro-foundation appendix is commented out (tex L2317–2959) and is not in the PDF; the appendices are supplementary tables, the classification harmonisation and the EPW-by-state table. | diss.tex L2317–2959 (all lines begin with %) |

### 2.1 Globalization and backlash  (NOT VERIFIED 9)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 27 | 533 | 14 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 28 | 536 | 14 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 29 | 539 | 14 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 30 | 541 | 15 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 31 | 545 | 15 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 32 | 548 | 16 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 33 | 550 | 16 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 34 | 552 | ~16 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |
| 35 | 554 | 16 | **NOT VERIFIED** | literature characterisation (paragraph) | keep; no estimate of this dissertation is involved | outside raw-material scope; the cited papers' content was not re-read |

### 2.2 Brazilian evidence  (CHANGED 3, CONFIRMED 1, NOT VERIFIED 7)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 36 | 558 | 17 | **NOT VERIFIED** | literature characterisation (paragraph) | keep | outside raw-material scope |
| 37 | 560 | 17 | **NOT VERIFIED** | literature characterisation (paragraph) | keep | outside raw-material scope |
| 38 | 590 | 18 | **NOT VERIFIED** | literature characterisation (paragraph) | keep | outside raw-material scope |
| 39 | 592 | 18 | **NOT VERIFIED** | literature characterisation (paragraph) | keep | outside raw-material scope |
| 40 | 586 | 19 | **NOT VERIFIED** | costa2025 characterisation; claim that supply responses are absorbed by FE | keep as literature; the FE-absorption reading is an assumption, not a result | costa2025 not in folder |
| 41 | 588 | 52 | **CONFIRMED** | 558 microregions; 2000 Census shares incl. informal; IV with China's trade with RoW; export exposure lowers PT share by 2.0–3.4 pp per SD; import exposure raises invalid ballots | — | step5/lit/The_China_Shock_in_Emerging_Economies.txt L367, L375, L390, L555, L129 |
| 42 | 594 | 18 | **CHANGED** | Brazil has suffered a decline in exports since the 2010s, followed by stagnation | Real exports fell from 245.9 bn (2011) to 163.1 bn (2016) and recovered to 249.0 bn by 2022 (2010 USD): decline then recovery, not stagnation. | step5/out/s5_data.csv 'Real exports' |
| 43 | 596 | 19 | **NOT VERIFIED** | synthesis of cited studies | keep | literature |
| 44 | 603 | 19 | **NOT VERIFIED** | gap statement | keep, but see next row | literature |
| 45 | 618 | ~19 | **CHANGED** | the only Brazilian evidence that separates import from export exposure finds the latter politically inert \cite{costa2025} | Contradicted by the text's own §2.2 (tex L588): Jones et al. separate the two and find export exposure lowers PT share by 2.0–3.4 pp per SD. Rewrite as: 'evidence on export exposure is mixed: inert for candidate supply (costa2025), directional for PT vote (Jones et al.)'. | step5/lit/The_China_Shock_in_Emerging_Economies.txt L555; diss.tex L588 |
| 46 | 619 | 19 | **CHANGED** | a continuous, non-directional polarization outcome computed for all 557 microregions; an export-demand shock built for a commodity exporter; ... symmetry restriction tested | deputy-vote dispersion for 557 microregions; two export shocks (realised exports by industry; foreign import demand by destination); the bust coefficient tested as H1b (the symmetry Wald test is not in the plan) | 02_analysis_plan.md §1, §3 |

### 2.3 Brazilian context  (CHANGED 3, NOT VERIFIED 5)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 47 | 630 | 20 | **CHANGED** | four presidential elections and their respective trade shocks | four general elections (deputy, governor, president), three stacked differences from 2010 | 02_analysis_plan.md §1 |
| 48 | 632 | 20 | **NOT VERIFIED** | political-context paragraph | keep | literature characterisation |
| 49 | 646 | 20 | **NOT VERIFIED** | political-context paragraph | keep | literature characterisation |
| 50 | 659 | 20 | **NOT VERIFIED** | political-context paragraph | keep | literature characterisation |
| 51 | 670 | 21 | **NOT VERIFIED** | 54.3% in 2014 to 65.2% in 2021 \cite{callegari,iedi} | keep with citation only; the definition of 'mineral and agricultural products' is not given, so it cannot be rebuilt from Comex | cited sources not in folder (searched step5/lit/cdpp...txt: no match) |
| 52 | 678 | 21 | **NOT VERIFIED** | foreign value added under 20% of gross exports | keep with citation; fix 'emerging economies,meanign' | TiVA data not in folder |
| 53 | 681 | 21 | **CHANGED** | municipalities benefiting from China's export demand experienced higher wage growth and faster poverty reduction \citeonline{costa2012} | microregions benefiting from Chinese export demand saw faster wage growth and lower take-up of cash transfers (Costa, Garred & Pessoa 2016); use \cite not \citeonline | step5/lit/costa_garred_2016.txt L22, L170, L402 |
| 54 | 691 | 21 | **CHANGED** | identification relies on the contrast between a soy (MT) and a textile (SC) microregion | S0 identification rests on oil and iron-ore microregions (top-10 carry 57% of leverage: Japaratuba, Coari, Parauapebas, Macaé, Itabira…); S3 on port/terminal microregions (top-10 carry 94%). Soy carries ~5% of S0's estimand weight. | step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv; step1_log.txt L45–51 |

### 2.4 Hypothesis  (CHANGED 4, CONFIRMED 1, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 55 | 702 | 21 | **CHANGED** | negative export shocks → wider dispersion (presidential) | H1: export exposure changes the dispersion of the federal-deputy vote (two-sided); H1b: bust > 0; H2: direction (Δȳ). Result: H1 — S0 INC, S3 EQ; H1b, H2 — nothing survives BH. | 02_analysis_plan.md §1, §3; step4a/out/step4_primary.csv; step4a/out/step4_secondary.csv |
| 56 | 711 | 22 | **CHANGED** | declining exports amplify anti-system sentiment \cite{Rettl} | Rettl (2025) studies PT vote share and evangelical concentration (Table 1, col. 1: ΔEPW 0.0378); the term 'anti-system' does not appear. Restate what it reports. | step5/lit/rettl_2025_hbs_wp25-038.txt L1038–1054 (grep 'anti-system': 0 hits) |
| 57 | 714 | 22 | **NOT VERIFIED** | holland; cultural channel | keep | literature |
| 58 | 726 | 23 | **CONFIRMED** | Figure 1 (framework, supply side absorbed by FE) | —; caption box should read 'Dalton index of the deputy vote' | diagram, no data |
| 59 | 807 | 23 | **CHANGED** | an export-demand shock ... a negative export shock compresses local labour demand | S0 is realised export value per worker (not demand); S3 is foreign import demand. Fix 'shockin'. | 01_estimand_statement.md 'Narrowest claims' |
| 60 | 814 | 24 | **CHANGED** | three supplementary hypotheses (asymmetry; right flank; heterogeneity by structure) | Asymmetry = H1b (secondary, BH); right flank = H2, tested as Δȳ (secondary, BH); heterogeneity by structure is descriptive only (no inferential claim). | 02_analysis_plan.md §3 |

### 3.1 Sample  (CHANGED 3, CONFIRMED 2)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 61 | 836 | 25 | **CHANGED** | four cycles ... for presidential elections; control variables will be defined at a later stage | deputy (primary), governor and president, first round, 2010–2022; controls are defined (ln GDP pc, ln pop, θ_r for S0; log(1+θ_dest), 1{θ_dest=0} for S3) | 02_analysis_plan.md §1; A4 (02e) |
| 62 | 836 | 25 | **CHANGED** | aligns with the onset of the decline | Real exports peaked in 2011 and recovered past that peak by 2022 | step5/out/s5_data.csv 'Real exports' |
| 63 | 838 | 25 | **CONFIRMED** | 1,671 rows, 557 microregions, 1,668 after singletons; 1,674 = 558 × 3 | — | step5/out/s5_data.csv rows 1–2, 8; fixest NOTE '3 fixed-effect singletons' (s5_table4_repro.R) |
| 64 | 847 | 25 | **CHANGED** | Médio Amazonas (AM) ... retained in the treatment with ΔEPW = 0 ... drops because it has no base-year manufacturing share | The dropped microregion is Japurá (AM, 13002); no microregion is named 'Médio Amazonas'. It has 866 formal jobs in 2010, none in a tradable industry, so θ = 0, it has no rows in the share matrix or the EPW panel (not 'retained with ΔEPW = 0'), and its manufacturing share of tradables is 0/0. | step5/out/s5_data.csv rows 3–7 |
| 65 | 853 | 25 | **CONFIRMED** | DF: single microregion, 3 singleton observations | — | step5/out/s5_data.csv 'States with a single microregion' |

### Table 1 (data sources)  (CHANGED 3, CONFIRMED 2, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 66 | 870 | 26 | **CHANGED** | Dalton polarization (P^D), 2010–2022 | Add the deputy and governor rows; primary outcome = deputy Dalton (TSE detalhe/candidate files, round 1) | 02_analysis_plan.md §1; step3b/out/gate_a_tse_primary.csv |
| 67 | 873 | 26 | **CHANGED** | one treatment, ΔEPW | Two treatments: S0 (RAIS 2010 × Comex Stat, ISIC Rev. 4) and S3 (Comex municipal 2010 exports by destination × BACI rest-of-world imports); both recentred | 02_analysis_plan.md §1 |
| 68 | 875 | 26 | **CHANGED** | Log GDP per capita: IPEADATA, population-weighted | IBGE PIB Municipal 2010 summed to the microregion and divided by Census 2010 population (per 01_controls_micro2.R L66–163; code read, not re-run: BigQuery source unreachable) | device: data/dados consolidados/01_controls_micro2.R L66–163 |
| 69 | 876 | 26 | **CONFIRMED** | Census 2010 | —; definition: adults 25+ with complete secondary or above | 01_controls_micro2.R L42 (code read) |
| 70 | 879 | 26 | **CONFIRMED** | θ_r = tradable employment share | —; Σ_j s_rj = θ_r to 3e-16 | step1_log.txt L4 |
| 71 | 881 | 26 | **REMOVED** | pre-trend controls: top-4 sector shares × year | Not in any estimated specification (§4.3.1 itself says outstanding); the plan replaces the pre-trend check with the 2002/2006→2010 falsification test (gate d) | 02_analysis_plan.md §5 gate (d); step4a/out/gate_d_studentized.csv |

### 3.2 Outcome  (CHANGED 6, CONFIRMED 8, NOT VERIFIED 5, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 72 | 931 | 27 | **CONFIRMED** | first-round returns throughout | — | step4a/step4_outcomes.R canaries reproduce stored panels from round-1 rows (≈1e-16) |
| 73 | 936 | 27 | **CONFIRMED** | 99.7 / 98.6 / 96.1 / 99.4 per cent of valid first-round votes (president) | —; add the deputy figures, which are lower: 90.2 / 93.7 / 91.3 / 86.4 | step5/out/s5_votes.csv rows '20xx stored panel: scored share' (99.72/98.62/96.13/99.37); step2_construct_log.txt L15–18 |
| 74 | 939 | 27 | **CONFIRMED** | NOVO 2.5%, PATRIOTA 1.3% | — | step5/out/s5_votes.csv '2018 parties with no score' (NOVO 2.50%, PATRI 1.26%) |
| 75 | 940 | 27 | **NOT VERIFIED** | omission understates dispersion in 2018 | keep as conjecture; NOVO's first BLS score is 0.711 (2021), so the effect could be computed but was not | step5/out/s5_votes.csv '2022 stored panel: party scores used' (NOVO=0.711) |
| 76 | 945 | 27 | **CHANGED** | fielded in odd years | fielded in odd years since 1993 (the first wave is 1990) | step5/out/s5_votes.csv 'Waves in the BLS file' (1990,1993,…,2021) |
| 77 | 958 | 28 | **CONFIRMED** | Table 2: 2010↔BLS 6 (2009), 2014↔BLS 7 (2013), 2018↔BLS 8 (2017), 2022↔BLS 9 (2021) | — | step5/out/s5_votes.csv 'Waves in the BLS file'; s5_votes.R uses these waves and reproduces the panels' scored shares |
| 78 | 978 | 28 | **CHANGED** | Bolsonaro's individual BLS score is used | PSL 2018 is assigned 0.862, Bolsonaro's score in BLS 9 (2021) — a wave fielded after the 2018 election, contrary to the alignment rule of Table 2; BLS 8 (2017) contains neither PSL nor Bolsonaro. Say so explicitly. | step5/out/s5_votes.csv 'BLS 2017 contains PSL? FALSE', 'contains BOLSONARO? FALSE', 'Waves containing BOLSONARO 2021', '2018 stored panel: party scores used PSL=0.862' |
| 79 | 980 | 28 | **CHANGED** | candidates in each presidential election from 1990 to 2021; 2018 and 2022 show concentrations at the right extreme absent in earlier cycles | The figure shows party/president positions by BLS wave (1990–2021), not candidates by election. The mean position moves right from −0.126 (2009) to 0.163 (2021); scores above 0.6 number 4, 4, 3, 2, 2, 1, 3, 1, 3 by wave, so right-extreme concentrations are not absent before 2018. | step5/out/s5_data.csv 'BLS mean score by wave', 'BLS entries with score > 0.6' |
| 80 | 989 | 29 | **NOT VERIFIED** | Figure 2 (violin) | regenerate from bls9_estimates_partiespresidents_long.rds | figure file not checked |
| 81 | 1003 | 29 | **NOT VERIFIED** | feres characterisation | keep | literature |
| 82 | 1007 | 29 | **CHANGED** | Dalton index of the presidential vote | Same formula, applied to the federal-deputy party vote (primary); president/governor descriptive | 02_analysis_plan.md §1 |
| 83 | 1036 | 30 | **CONFIRMED** | zero for a single party; maximum when split evenly between the two most distant | — | math (variance of a bounded distribution is maximised by equal mass at the endpoints) |
| 84 | 1052 | 30 | **CONFIRMED** | r = 0.97 against an independent expert survey | —; it is PREPPS, 17 parties and two presidents | step5/lit/The_Ideology_of_Brazilian_Parties_and_Pr.txt L271–277 |
| 85 | 1053 | 30 | **NOT VERIFIED** | CSES coverage | keep | external |
| 86 | 1067 | 30 | **CHANGED** | argument for presidential elections | For the deputy vote, the median microregion has 13–22 scored parties, so the 'single extreme candidate' case does not arise; the presidential index is close to a transform of the winner's share (within-state-year R² 0.96 in 2022) | step2_construct_log.txt L15–23 |
| 87 | 1072 | 30 | **CHANGED** | most polarized: North and Centre-West frontier and far South; Northeast low; band broadens to Centre-West and Southeast interior in 2018/2022 | Northeast lowest in every year (mean quintile 1.5–2.2) ✓; South highest in 2010/2014 (Q5 share 0.65/0.69) but not in 2018/2022 (0.23/0.31); Centre-West Q5 share 0.42/0.10/0.33/0.38; Southeast 0.01/0.22/0.19/0.27. Restate per year; the 'commodity frontier' association was not tested. Presidential map; add the deputy map. | step5/out/s5_map_quintiles.csv |
| 88 | 1081 | 31 | **NOT VERIFIED** | Figure 3 (map) | regenerate for the deputy index | figure file not checked |
| 89 | 1092 | 31 | **CONFIRMED** | centre band [−0.25, 0.25]; Zucco Appendix E robust to wider bands up to [−0.40, 0.40] | — | step5/lit/The_Ideology_of_Brazilian_Parties_and_Pr.txt L936–950 |
| 90 | 1111 | 32 | **CONFIRMED** | all major 2018 parties outside the band; P^N = 1 everywhere | —; all eight scored parties are outside the band and P_center = 1 in all 558 microregions | step5/out/s5_votes.csv '2018 stored panel: party scores used', 'P_center == 1 in 2018: 558' |
| 91 | 1117 | 32 | **REMOVED** | promise to report alternative bands | Not in the plan and not run; drop the promise or add it as a descriptive item | 02_analysis_plan.md §3 (centre-emptying descriptive) |

### 3.3 Controls  (CHANGED 3, CONFIRMED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 92 | 1126 | 32 | **CONFIRMED** | controls fixed at 2010 | — | df_estimation_v7.rds (constant within microregion) |
| 93 | 1128 | 32 | **CHANGED** | urban share and education are controls | Base controls are ln GDP pc and ln pop (+ θ_r for S0; + log(1+θ_dest), 1{θ_dest=0} for S3). Urban share, education and manufacturing share enter only the 'extended' arm of the specification curve. | 02_analysis_plan.md §1; step4a/out/step4_speccurve.csv controls = extended |
| 94 | 1130 | 33 | **CHANGED** | θ_r control (BHJ) + m_r + top-4 shares × year | θ_r stays (and, after recentring, the treatment's expectation under the permutation is removed); m_r and the top-4 × year terms are not in the base specification | 02_analysis_plan.md §1 (Recentring); D2 |
| 95 | 1132 | 33 | **CHANGED** | balance tests and Rotemberg diagnostics | falsification on 2002/2006 → 2010 (S0 p 0.813/0.879; S3 p 0.436/0.096), leverage of the top-10 microregions, and the shock-balance test (descriptive) | step4a/out/gate_d_studentized.csv; step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv; step5/out/s5_balance_repro.csv |

### 3.4 Descriptive statistics (Table 3)  (CHANGED 4, CONFIRMED 14, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 96 | 1149 | ~33 | **CONFIRMED** | ΔDalton row (president) | —; label it 'president' and add the deputy Dalton row (primary) | step5/out/s5_table3.csv row delta_P_dalton |
| 97 | 1150 | 34 | **CONFIRMED** | ΔCentre row | — | step5/out/s5_table3.csv row delta_P_center |
| 98 | 1152 | 34 | **CONFIRMED** | ΔEPW 0.112 / 0.494 / −4.726 / 0.004 / 0.039 / 0.146 / 9.107 | —; add rows for the recentred S0 and S3 treatments actually used | step5/out/s5_table3.csv row delta_EPW; step1_log.txt L5 |
| 99 | 1154 | 34 | **CONFIRMED** | θ_r row | — | step5/out/s5_table3.csv |
| 100 | 1155 | 34 | **CHANGED** | mean 0.643 | 0.642 | step5/out/s5_data.csv 'Mean manuf_share_of_tradable' 0.64248 |
| 101 | 1156 | 34 | **CONFIRMED** | row | — | step5/out/s5_table3.csv |
| 102 | 1157 | ~34 | **CHANGED** | P75 12.606 | 12.605 | step5/out/s5_data.csv 'P75 ln_pop' 12.60545 |
| 103 | 1158 | 47 | **CONFIRMED** | row | — | step5/out/s5_table3.csv |
| 104 | 1159 | 34 | **CONFIRMED** | row | — | step5/out/s5_table3.csv |
| 105 | 1164 | 34 | **CHANGED** | Médio Amazonas dropped because no base-year formal employment in the matched tradable universe | Japurá (AM) — the mechanism is right (θ = 0, no exposure shares), the name is wrong | step5/out/s5_data.csv rows 3–7 |
| 106 | 1184 | 33 | **CONFIRMED** | both increase; overwhelmingly positive | —; ΔDalton > 0 in 96.3% of rows, ΔCentre > 0 in 84.4% | step5/out/s5_data.csv 'Share of rows with dDalton>0' |
| 107 | 1188 | 34 | **NOT VERIFIED** | level increase reflects widening of the range on offer | keep as conjecture | not tested |
| 108 | 1194 | 34 | **CONFIRMED** | mean 0.112, sd 0.494 (> 4×), range −4.73 to 9.11, median 0.039, P25 0.004, θ averages one quarter | — | step5/out/s5_table3.csv; step5/out/s5_data.csv 'sd/mean of dEPW' 4.39 |
| 109 | 1201 | 34 | **CHANGED** | a right tail of strongly exposed microregions | About nine microregions carry the identifying variation (top-10 leverage share 57% for S0 and 94% for S3 after recentring), on both tails (iron-ore busts, oil booms) | step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv; step1_log.txt L162–163, L194–195 |
| 110 | 1206 | 34 | **CONFIRMED** | urban 0.22–1, mean 0.72; ln pop span > 8; ln GDP span ≈ 3; education mean 0.262, range 0.098–0.554; θ up to 0.68, mean 0.25; manufacturing share 0.64, full unit interval | — | step5/out/s5_table3.csv; step5/out/s5_data.csv 'Range ln_pop / ln_gdp_pc' 8.57 / 3.30 |
| 111 | 1220 | 35 | **CONFIRMED** | CNAE 2.0 vs NCM; both to ISIC Rev. 4 | — | ncm_isic_match_v7.rds; composite_map_v7.rds |
| 112 | 1225 | 35 | **CONFIRMED** | formal employment only | — | rais_2010_micro.rds (contracts only) |
| 113 | 1233 | 35 | **CONFIRMED** | national party scores, no subnational variation | — | bls9_estimates_partiespresidents_long.rds (party × wave) |
| 114 | 1241 | 35 | **CONFIRMED** | 0.3% (2010) vs 3.9% (2018); NOVO largest | —; add deputy coverage (unscored = 1 − coverage: 9.8 / 6.3 / 8.8 / 13.6%) | step5/out/s5_votes.csv; step2_construct_log.txt L15–18 |

### 4 Empirical strategy  (CHANGED 10, CONFIRMED 6, NOT VERIFIED 1, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 115 | 1251 | 36 | **CHANGED** | causal effect of trade exposure ... four presidential elections | the effect of export-shock exposure on the dispersion of the deputy vote, identified from the shocks (BHJ), with three stacked differences | 01_estimand_statement.md |
| 116 | 1259 | 36 | **CHANGED** | robustness checks validate the design | a pre-registered validation suite (gates a–e) with thresholds fixed before any estimate | 02_analysis_plan.md §5; 03, 03b |
| 117 | 1276 | 36 | **CONFIRMED** | incomplete shares; sum of shares must be controlled (BHJ) | —; Σ_j s_rj = θ_r | step1_log.txt L4 |
| 118 | 1285 | 36 | **CHANGED** | shocks capture foreign demand ... plausibly exogenous | S0's g_jt is realised Brazilian export value per worker, not foreign demand; its exogeneity is assumed for two series (oil, iron ore). S3's g_dt is rest-of-world import growth by destination. | 01_estimand_statement.md 'Narrowest claims'; step1_log.txt L45–51 |
| 119 | 1290 | 36 | **CONFIRMED** | shares vs shocks perspectives | —; this dissertation uses the shocks perspective with recentring | 02_analysis_plan.md D2 |
| 120 | 1303 | 37 | **CHANGED** | one measure following Rettl | S0 follows Rettl; S3 is the destination-demand design (same shares logic, destination shocks) | 02_analysis_plan.md §1 |
| 121 | 1307 | ~37 | **CHANGED** | Equation (3): ΔEPW = Σ_j s_rj g_jt | Keep, and add the recentred treatment z̃_rt = z_rt − μ_rt, μ_rt = Σ_k (Σ_{j∈k} s_rj) ḡ_kt (strata A/B/C), and the S3 analogue | 02_analysis_plan.md §1 'Recentring' |
| 122 | 1318 | 37 | **CHANGED** | industry j at the ISIC four-digit level | j indexes 152 industry groups (177 ISIC classes merged); 149 exchangeability units after merging identical share columns | step5/out/s5_data.csv; step4a/out/step4_cleanroom_beta.csv |
| 123 | 1322 | 37 | **CONFIRMED** | constant tens of thousands of USD FOB, ÷ L_j,2010 | —; shock-table exports × 1e4 equal 97–99% of real total exports | step5/out/s5_data.csv 'Shock-table exports x 1e4 / real total exports' 0.974/0.972/0.983/0.993 |
| 124 | 1322 | 38 | **CHANGED** | reflect variation in international demand | they are realised export values (see row above) | 01_estimand_statement.md |
| 125 | 1327 | 38 | **CONFIRMED** | exposure as function of base-year structure | — | eq. (3) |
| 126 | 1327 | 38 | **CHANGED** | not directly determined by any single microregion's actions | Three microregions carry 51% of S0's leverage (Japaratuba, Coari, Macaé), so the 'no single region' argument needs evidence, not assertion | step1_log.txt L164–167 |
| 127 | 1338 | 38 | **CHANGED** | 176 matched tradable industries | 177 ISIC classes (A 31, B 13, C 133) in 152 industry groups; Rettl's 174 confirmed | step5/out/s5_data.csv 'ISIC classes inside the 152 retained groups'; step5/lit/rettl_2025_hbs_wp25-038.txt L753 (174) |
| 128 | 1342 | 38 | **REMOVED** | manual conversion pending; universe will grow | Manual overrides are already in ncm_isic_match_v7.rds (e.g. 260111 → 0710, w = 1); the universe is final | step5/out/s5_data.csv 'ncm_isic_match: NCM-6 260111 mapping' |
| 129 | 1351 | 39 | **CONFIRMED** | single-hop NCM-6 → ISIC with occurrence-share weights | —; weights sum to 1 for all 6,726 NCM-6 codes; plus the waterfall and overrides (Appendix B) | ncm_isic_match_v7.rds (sum w by ncm6 = 1) |
| 130 | 1368 | 39 | **CHANGED** | 9,346 codes; 1,200 absent from NCM 2012–CNAE 2.0 table; ~13% orphan value \cite{Rettl} | On the CONCLA table in the folder (NCM 2011 × CNAE 2.0): 9,628 NCM codes exported in 2010/14/18/22, 1,245 absent, 15.7% of export value (10,191 / 1,346 / 15.4% over 2010–2022). Rettl does not report these figures; drop the citation. | step5/out/s5_data.csv 'NCM-8 codes exported'; step5/lit/rettl_2025_hbs_wp25-038.txt |
| 131 | 1374 | 39 | **CONFIRMED** | constant 2010 USD (US CPI) | —; series 200.4, 245.9, 227.9, 217.7, 203.5, 171.8, 163.1, 191.3, 201.4, 188.6, 176.2, 226.0, 249.0 bn | step5/out/s5_data.csv 'Real exports' |
| 132 | 1378 | 40 | **NOT VERIFIED** | Figure 4 | regenerate from step5/out/s5_exports_series.csv | figure file not checked |

### 4.2 Estimating equation and inference  (CHANGED 3, CONFIRMED 1, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 133 | 1390 | 40 | **CHANGED** | presidential elections | federal-deputy Dalton (primary) | 02_analysis_plan.md §1 |
| 134 | 1399 | ~40 | **CHANGED** | eq. (4) with ΔEPW | Δy_rt = α_s(r)t + β · z̃_rt / sd(z̃) + γ′X_r,2010 + ε_rt (recentred treatment; S3 controls log(1+θ_dest), 1{θ_dest=0}, θ_dest summed over the 201 design destinations) | 02_analysis_plan.md §1; A4 (02e) |
| 135 | 1407 | 40 | **CONFIRMED** | β in SD per SD | — | 02_analysis_plan.md §1 |
| 136 | 1411 | 41 | **CHANGED** | mesoregion×year clusters throughout; 'two-way cluster structure' | Primary inference: studentized RI (t = β̂/se_AKM), B = 9,999 within-stratum permutations of whole shock paths, inverted into 90/95% sets. Mesoregion×year is a one-way cluster on the interaction, not two-way; it is reference-only. | 02_analysis_plan.md §2; A2 (02b) |
| 137 | 1419 | 41 | **REMOVED** | mesoregion clustering reported alongside the baseline | reference-only; not reported as evidence | 02_analysis_plan.md §2 item 3 |

### 4.2.1 Decomposition  (CONFIRMED 1, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 138 | 1428 | 41 | **CONFIRMED** | EPW⁺/EPW⁻ magnitudes scaled by SD(ΔEPW); predicted b₋ > 0 | —; reproduces the old Table 4 boom/bust columns | step5/out/s5_table4_repro.csv |
| 139 | 1447 | 41 | **REMOVED** | symmetry Wald test reported for both outcomes | Not in the plan; H1b is the bust coefficient alone (secondary family) | 02_analysis_plan.md §3 |

### 4.3 Identification and robustness  (CHANGED 2, CONFIRMED 1, REMOVED 3)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 140 | 1457 | 42 | **CHANGED** | five robustness dimensions | validation gates (a) reconciliation, (b) replication — not done, (c) Monte Carlo, (d) falsification, (e) clean-room; then BLS bootstrap, AKM0, leverage, specification curve | 03_validation_report.md, 03b; step4a report |
| 141 | 1471 | 42 | **REMOVED** | top-4 shares × year added to the specification ... outstanding | Replaced by gate (d): S0 p 0.813 (2002→10), 0.879 (2006→10); S3 p 0.436, 0.096 — both pass | step4a/out/gate_d_studentized.csv |
| 142 | 1483 | 42 | **CONFIRMED** | AKM over-rejection argument | — | Adão–Kolesár–Morales (cited) |
| 143 | 1489 | 42 | **CHANGED** | 152 groups permuted 9,999 times jointly; coefficient statistic | 149 units (S0) and 201 destinations (S3) permuted within strata (S0: ISIC sections A/B/C; S3: five World Bank region groups), whole paths, B = 9,999, seed 2026; statistic = studentized t, because the coefficient statistic over-rejected in gate (c) (size 0.078 / 0.185) | 02_analysis_plan.md §1–2; A2; 03_validation_report.md (c) |
| 144 | 1497 | 43 | **REMOVED** | procedure is conservative where the crosswalk is coarsest | Unsupported. What was measured: studentized size 0.037 (S0) and 0.018 (S3), i.e. S3 is conservative | step3b/out/gate_c_studentized_S0.csv; step4a/out/gate_c_stud_S3_log.txt L2 |
| 145 | 1503 | 43 | **REMOVED** | SE ladder 0.0027 / 0.0048 / 0.0059 / 0.0068 / 0.0076 / 0.0142; 'thirty per cent'; 2.6–6.2 ratios | Of these, only 0.0048 and 0.0059 were reproduced (old spec); the others were not. All refer to the superseded presidential, uncentred design. Under the plan: S0 se_AKM 0.0433, S3 0.0358 (deputy). | step5/out/s5_table4_repro.csv se_mesoyr 0.00481, se_meso 0.00592; step4a/out/step4_primary.csv |

### 4.3.3 AKM/AKM0  (CHANGED 1, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 146 | 1517 | 43 | **CHANGED** | pooled Dalton: β 0.001, AKM p 0.75, AKM0 p 0.75; ext −0.003 (0.33/0.40); centre p ≥ 0.90 | Deputy Dalton, recentred: S0 AKM0 set [−0.198, 0.103], p 0.516; S3 AKM0 set (−∞, ∞), p 0.445. S0 secondary sets all contain 0; every S3 set is unbounded. | step4a/out/step4_akm0.csv |
| 147 | 1523 | 43 | **REMOVED** | year-by-year AKM0 unbounded; 2022 AKM p 0.036 'under the within-tradable share convention' | Within-tradable shares are an error by decision D1; year-specific slopes are descriptive and were not re-estimated; also the sentence 'not to interpret ... with caution' inverts its meaning | 02_analysis_plan.md D1, §3 |

### 4.3.4 Conley  (REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 148 | 1534 | 44 | **REMOVED** | Conley 250/500 km: 0.0068, 0.0076 | Not reproduced; reference-only under the plan and not computed for the plan's specification (flag) | 02_analysis_plan.md §2 item 3 |

### 4.3.5 BHJ balance  (CONFIRMED 4, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 149 | 1546 | 44 | **CONFIRMED** | balance of g on commodity dummy and log 2010 exports, weighted by national employment shares | — | step5/out/s5_balance_repro.csv |
| 150 | 1560 | 44 | **CONFIRMED** | p = 0.30, 0.29, 0.01 | —; 0.298 / 0.295 / 0.013 (152 industries, homoskedastic weighted F). Descriptive: not a plan test. | step5/out/s5_balance_repro.csv |
| 151 | 1561 | 44 | **CONFIRMED** | oil α = 0.66 in 2022 | —; 0.657 (extended controls, within-year) | step1_log.txt L160 |
| 152 | 1566 | 44 | **CONFIRMED** | invariant to the share denominator | — | weights = L_j/ΣL_j (s5_balance_repro) |
| 153 | 1568 | 44 | **NOT VERIFIED** | demographic balance test pending | drop the promise or run it; not in the plan | G4_sector_chars.R exists on device but its output was not found |

### 4.3.6 Rotemberg / leave-out  (CHANGED 1, REMOVED 3)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 154 | 1576 | 45 | **REMOVED** | leave-out results: Dalton 0.0005 to −0.004; centre 0.002 (t 0.23) → 0.026 (2.72) → 0.029 (2.97) → 0.015 (1.26) → 0.003 (0.33); correlations 0.41–0.71 | Not reproduced; superseded design and cluster t. Replaced by the leverage inspection: top-10 microregions carry 57% (S0) / 94% (S3); β̂ without them −0.079 (S0) / −0.092 (S3) | step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv |
| 155 | 1590 | 45 | **REMOVED** | Dalton null robust/invariant to industry composition | Dropping oil or iron ore changes the estimand; S3's β̂ without its top-10 microregions (−0.092) lies outside its own 90% set | 01_estimand_statement.md #7; step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv |
| 156 | 1593 | 45 | **CHANGED** | ≈2.4 effective shocks (extended controls); 152 groups 'behaving as though it had between two and three' | 2.43 is the mean of three within-year counts; for the pooled estimator it is 3.13 (base) / 3.01 (extended) Rotemberg, 2.86 by AKM weights — 'about three'. Effective microregions ≈ 9. | step1_log.txt L13, L16, L62, L160, L162 |
| 157 | 1595 | 45 | **REMOVED** | bullet list reconciling cluster/RI divergence, AKM0 years, leave-out | Rests on removed results; replace with gate (c) evidence (coefficient RI size 0.078/0.185 → studentized 0.037/0.018) | 03_validation_report.md (c); 03b (c) |

### 5.1 Main estimates  (CHANGED 6, CONFIRMED 2, REMOVED 9)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 158 | 1614 | 46 | **CHANGED** | RI p from 9,999 industry permutations (coefficient statistic) | studentized RI, within-stratum, recentred; Holm on the primary family; TOST equivalence at 0.038 / 0.059 / 0.162; BH on 10 secondary tests | 02_analysis_plan.md §2–3; A2, A3 |
| 159 | 1618 | 46 | **REMOVED** | pre-trend controls and demographic balance still in progress | falsification (gate d) done; demographic balance not in plan | step4a/out/gate_d_studentized.csv |
| 160 | 1624 | 47 | **CHANGED** | Table 4 (president Dalton & centre; ΔEPW; mesoregion×year SE; old RI p) | New Table 4 = primary family: deputy Dalton, S0 and S3 — β̂ 0.0336 / −0.0289; se_AKM 0.0433 / 0.0358; studentized p 0.631 / 0.296; Holm 0.631 / 0.592; 90% set [−0.100, 0.239] / [−0.075, 0.045]; 95% [−0.157, 0.280] / [−0.088, 0.094]; class INC / EQ (0.162). Panel B = secondary family with BH q. | step4a/out/step4_primary.csv; step4a/out/step4_secondary.csv; benchmark 0.162 from 02_analysis_plan.md §3 |
| 161 | 1637 | ~47 | **CHANGED** | Panel A: 0.001 / −0.003 / 0.002 / 0.001 (SE 0.005/0.005/0.009/0.009) | Old values reproduce (0.00086 / −0.00284 / 0.00193 / 0.00123; SE 0.0048/0.0050/0.0086/0.0086) but are superseded. Recentred, studentized (B = 999, base controls): president Dalton S0 −0.024 (p 0.324), S3 0.010 (p 0.252); president centre-emptying S0 −0.033 (p 0.439), S3 0.011 (p 0.495) — descriptive | step5/out/s5_table4_repro.csv; step4a/out/step4_speccurve.csv office=president, base, recentred, primary, full |
| 162 | 1639 | ~47 | **REMOVED** | RI p 0.914 / 0.707 / 0.901 / 0.925 | coefficient-statistic RI failed gate (c); not reproduced; replaced by studentized p (row above) | 03_validation_report.md (c) |
| 163 | 1642 | ~47 | **REMOVED** | Panel B boom/bust for president Dalton and centre (0.003/0.002/−0.013/−0.018; 0.005/0.015/−0.041/−0.047) with stars and RI p | Old values reproduce under the old spec but have no plan counterpart; the plan's decomposition is the deputy-Dalton bust coefficient: S0 −0.012 (p 0.856), S3 +0.022 (p 0.502), unvalidated | step5/out/s5_table4_repro.csv; step4a/out/step4_secondary.csv |
| 164 | 1649 | ~47 | **REMOVED** | symmetry p 0.488 / 0.004 | Reproduced (0.488; 0.0034, base columns) but not in the plan | step5/out/s5_table4_repro.csv p_sym_normal |
| 165 | 1652 | 47 | **REMOVED** | control coefficients (GDP, pop, θ, urban, education, manufacturing) with stars | Controls are not interpreted (no design for them); education 0.071 / −0.109 reproduce but are dropped | step5/out/s5_table4_repro.csv b_edu |
| 166 | 1666 | ~47 | **REMOVED** | within R² 0.102 / 0.142 / 0.057 / 0.079 | reproduce (0.102/0.142/0.057/0.079) but carry no claim | step5/out/s5_table4_repro.csv r2w_B |
| 167 | 1665 | ~47 | **CONFIRMED** | 1,668 | — | step5/out/s5_data.csv; fixest singleton NOTE |
| 168 | 1673 | 47 | **CHANGED** | note: stars cluster-robust; 152 groups permuted; 'every coefficient null' | note for the new table: studentized RI, within-stratum, recentred; θ_dest over the 201 design destinations (A4, a post-result change — say so) | 02_analysis_plan.md; 02e_plan_amendment_A4.md |
| 169 | 1695 | 46 | **CHANGED** | a tight null on both indices ... RI p 0.71–0.93 | S3 bounds the deputy effect within ±0.075 SD per SD (EQ at 0.162); S0 cannot bound it (INC). 'Tight null' is not supported for S0. | step4a/out/step4_primary.csv; benchmark 0.162 from 02_analysis_plan.md §3 |
| 170 | 1698 | 46 | **REMOVED** | three of eight decomposed coefficients significant under clusters; sign-restriction discussion (two paragraphs) | superseded design; no counterpart | 02_analysis_plan.md §3 |
| 171 | 1713 | 46 | **REMOVED** | RI p 0.62 / 0.43 / 0.42; placebo SD 2.6–6.2 × cluster SE | not reproduced; superseded | — |
| 172 | 1726 | 48 | **CHANGED** | Figure 5: coefficient placebo distribution, president; SD 0.0142 vs 0.0048 | Replace with the studentized RI distribution for deputy Dalton, S0 and S3 (NOT DONE: draws not saved by step4_primary.R; regenerate) | flag |
| 173 | 1736 | 48 | **CONFIRMED** | P^N identically one in 2018 (all 557); 2018 stack driven by base year | —; 558 in the panel, 557 in the sample | step5/out/s5_votes.csv 'P_center == 1 in 2018: 558'; step5/out/s5_data.csv 'Estimation rows / microregions' 557 |
| 174 | 1744 | 48 | **REMOVED** | controls 'behave sensibly'; education flips sign; 'null cannot be attributed to an insensitive outcome' | Controls are not interpreted; the argument for outcome sensitivity is replaced by the power analysis of gate (c) | step4a/out/gate_c_stud_S3_log.txt; step3b/out/gate_c_studentized_S0.csv |

### 5.2 Symmetry  (REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 175 | 1760 | ~48 | **REMOVED** | symmetry section (p 0.488 / 0.004; magnitude reading of centre-emptying; asymmetry satisfied on both outcomes) | Not in the plan. Replace with H1b: bust coefficient S0 −0.012 (p 0.856), S3 +0.022 (p 0.502); BH q 0.952; estimator not validated | step4a/out/step4_secondary.csv |

### 5.3 Heterogeneity  (CHANGED 1, REMOVED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 176 | 1793 | 49 | **CHANGED** | year interactions and m_r interactions; 'superseded within-tradable treatment' | Descriptive only; not re-estimated under the plan (flag). Dominant shock by year confirmed: iron ore 2014 and 2018, crude petroleum 2022. | step1_log.txt L159–160 |
| 177 | 1805 | 50 | **REMOVED** | AKM0 unbounded every year | not recomputed under the plan | — |

### 5.4 Interpreting the null  (CHANGED 4, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 178 | 1817 | 50 | **CHANGED** | reading 1 (national events); 'urbanisation and education estimated more precisely' | Keep the reading; drop the control-coefficient support | 02_analysis_plan.md |
| 179 | 1826 | 50 | **CHANGED** | Dalton blind to directional shift; a signed outcome is 'the natural next outcome' | The directional outcome was run: Δȳ for president, governor and deputy, both designs — no test survives BH (smallest q 0.952; p 0.51–0.97) | step4a/out/step4_secondary.csv |
| 180 | 1837 | 50 | **CHANGED** | effective number ≈ 2.4; null 'undetectable at this resolution' | Power is now measured: rejection at β = 0.038 is 0.115 (S0) and 0.091 (S3). S3 nevertheless bounds \|β\| ≤ 0.075; S0 does not. Effective shocks ≈ 3, microregions ≈ 9. | step3b/out/gate_c_studentized_S0.csv; step4a/out/gate_c_stud_S3_log.txt L7; step4a/out/step4_primary.csv |
| 181 | 1844 | 51 | **CHANGED** | 'a null on an outcome that responds precisely to its covariates is a substantive result' | drop the covariate argument; the substantive result is the S3 bound | step4a/out/step4_primary.csv |
| 182 | 1850 | 51 | **NOT VERIFIED** | feres reading | keep as conjecture | literature |

### 6 Conclusion  (CHANGED 3)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 183 | 1855 | 52 | **CHANGED** | presidential cycle; Dalton and centre-emptying | the federal-deputy vote (primary), with president and governor secondary; two recentred designs | 02_analysis_plan.md |
| 184 | 1861 | 52 | **CHANGED** | null on both; symmetry 'genuinely flat'; leave-out invariance; three cluster-significant coefficients; 2.4 shifts | Row-2 sentence (S3 bounds the effect within ±0.075; S0 INC), plus: secondary family null after BH; BLS score uncertainty changes no class (S0 0.6% of draws, S3 0%) | step4a/out/step4_primary.csv; step4a/out/step4_secondary.csv; step4a/out/step4_bls_stability.csv |
| 185 | 1874 | 52 | **CHANGED** | limits list (few shifts; 2022 balance; centre fragility; 2018 degenerate; pending checks); 'cluster estimates differ only in the third decimal' | Limits: about three effective shocks and nine microregions; 94% of S3 leverage in ten terminal/port microregions (exporter domicile); AKM0 cannot bound S3; only the 0.162 benchmark was attainable; gate (b) not done; A4 was a post-result change | step4a/out/step4_leverage_top10.csv + step4_leverage_beta.csv; step4a/out/step4_akm0.csv; step4a/out/gate_c_stud_S3_log.txt L17–19; 02e |

### 7 Novos resultados (governor)  (REMOVED 2)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 186 | 1900 | 53 | **REMOVED** | Table 5: governor Dalton / centre / Δȳ, ΔEPW, cluster stars, RI p, symmetry p, placebo/cluster ratio 1.88–4.74 | Provenance unresolved (07b_regression_governador.R reads files that do not exist) and the 2022 governor panel counted annulled votes (+0.180%). Replace with the repaired outcome: governor Δȳ (secondary) S0 −0.007 (p 0.756), S3 +0.010 (p 0.512); governor Dalton (descriptive, B = 999) S0 −0.021 (p 0.256), S3 +0.003 (p 0.452) | 01_estimand_statement.md flags; 03b gate (a); step4a/out/step4_secondary.csv; step4a/out/step4_speccurve.csv |
| 187 | 1954 | 54 | **REMOVED** | Table 6: bust heterogeneity (0.143 / 0.142 / 0.097 / 0.092; differences −0.146 … −0.082) with stars, no RI | Descriptive only under the plan; not rerun; the bust regressor is 72% iron ore, so the split partly relabels iron-ore regions (flag) | step1_log.txt L194; 02_analysis_plan.md §3 |

### App. A Supplementary tables  (CHANGED 4, CONFIRMED 4, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 188 | 2029 | 60 | **CONFIRMED** | ZZ 0.083% (2010) → 0.249% (2022) | — | step5/out/s5_votes.csv '20xx ZZ share' |
| 189 | 2032 | 60 | **CHANGED** | VT only in 2010 (0.064%) | The VT code appears only in 2010 (64,698); in 2014, 73,706 in-transit votes exist in the raw file but are recorded under the municipality where cast and are included in the panel | step5/out/s5_votes.csv '2014 VT (in-transit) valid votes' 73706, '2014 stored panel total votes vs raw' 73706 |
| 190 | 2033 | 60 | **CONFIRMED** | never above 0.5% | — | step5/out/s5_votes.csv |
| 191 | 2047 | ~60 | **CONFIRMED** | Table A1, all five rows | — | step5/out/s5_votes.csv rows 2–7, 15–18, 27–30, 39–42 |
| 192 | 2059 | 60 | **CHANGED** | 0.28% (2010), 0.63% (2022); 2018 3.88%; NOVO 2.50% | Confirmed except the 2014 total (row below); note that the table's vote counts exclude votes abroad while shares use national totals including them | step5/out/s5_votes.csv |
| 193 | 2083 | 61 | **CHANGED** | 2014 total excluded 1.39% | 1.38% | step5/out/s5_votes.csv '2014 unscored share of national valid' 1.38 |
| 194 | 2077 | 61 | **CONFIRMED** | party rows 2010–2022 (votes, shares) | —; votes = microregion-assigned (excl. abroad), e.g. NOVO 2,666,108 vs 2,679,745 nationally | step5/out/pres_party_votes_panel.csv (stored panel); step5/out/pres_party_votes_20xx.csv (raw national) |
| 195 | 2111 | 61 | **CHANGED** | all below 1% except where noted | PATRI (2018, 1.26%) also exceeds 1% and is not noted | step5/out/s5_votes.csv '2018 parties with no score' |
| 196 | 2063 | 60 | **NOT VERIFIED** | slight downward bias in 2018 indices | keep as conjecture (see 3.2 row) | not computed |

### App. B Classification  (CHANGED 3, CONFIRMED 4, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 197 | 2135 | 62 | **CONFIRMED** | CNAE → ISIC via CONCLA; NCM-6 → ISIC via UN table | — | composite_map_v7.rds; ncm_isic_match_v7.rds |
| 198 | 2152 | 62 | **CONFIRMED** | 419 classes, 21 sections, 88 divisions, 238 groups | — | step5/lit/ISIC_Rev_4_publication_English.txt L1102, L14992 |
| 199 | 2158 | 62 | **CHANGED** | ≈192 classes in A, B, C | 189 (A 38, B 14, C 137) | step5/out/s5_data.csv 'Distinct 4-digit ISIC codes in CONCLA table' (420 codes; A/B/C 38/14/137) |
| 200 | 2169 | 63 | **CHANGED** | class dropping; 'exactly what happens with microregion Médio Amazonas' | Class dropping and the dropped microregion are different things: 0721 is the only composite group without shares; the dropped microregion is Japurá, which has no employment in any retained class | step5/out/s5_data.csv 'Composite group in map without shares' 0721; rows 3–7 |
| 201 | 2177 | 63 | **NOT VERIFIED** | UN table maps 260111 to 0710 and 0990 with w = 0.5 each | Not checked: the concordance package is not installed (CRAN unreachable). The final pipeline mapping (0710, w = 1) is confirmed. | step5/out/s5_data.csv 'ncm_isic_match: NCM-6 260111 mapping' 0710 1 |
| 202 | 2224 | 63 | **CONFIRMED** | chapters 98/99 excluded | —; 0–2.2% of export value by year; none in the match table | step5/out/s5_data.csv 'ncm_isic_match: chapter 98/99 rows' 0; step5/out/s5_exports_series.csv |
| 203 | 2231 | 64 | **CONFIRMED** | loss below 1% | —; 0.60–0.79% of non-98/99 export value, every year 2010–2022 | step5/out/s5_data.csv 'Unmatched value after crosswalk' |
| 204 | 2239 | 64 | **CHANGED** | Table B1 with 'xx' placeholders | Total classes A 38, B 14, C 137 (189); retained classes A 31, B 13, C 133 (177) in 152 groups (A 11, B 11, C 130) | step5/out/s5_data.csv rows 'Distinct 4-digit ISIC codes', 'ISIC classes inside the 152 retained groups', 'Units by ISIC section' |

### App. C EPW by state  (CHANGED 2, NOT VERIFIED 1)

| # | tex | p. | Status | Old | New | Source |
|---|---|---|---|---|---|---|
| 205 | 2261 | 65 | **CHANGED** | Table C1: PI 4.154, MT 4.089, TO 2.778, …, MG −0.024 | Not reproducible under either share convention from the stored v7 objects (an older treatment). Total-convention means: SE 0.407, MT 0.336, AM 0.310, BA 0.191, RJ 0.183, PI 0.182, … AL −0.169; the microregion counts per state are confirmed | step5/out/s5_tableA3_total.csv; step5/out/s5_tableA3_both_conventions.csv |
| 206 | 2300 | 65 | **CHANGED** | Source: Comex Stat/MDIC and BLS/RAIS | Source: Comex Stat/MDIC and RAIS (BLS plays no part in EPW) | eq. (3) |
| 207 | 2310 | 66 | **NOT VERIFIED** | Figure 6 (exposure map) | regenerate from the v7 treatment (likely built from the same older treatment as Table C1) | figure file not checked |
