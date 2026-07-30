# =============================================================================
# 10_report_tables_tex.R
# -----------------------------------------------------------------------------
# Turns the CSVs produced by 08 and 09 into LaTeX tables ready to \input{} into
# a conference paper. Booktabs + threeparttable, no external dependencies beyond
# what main_anpec.tex already loads.
#
# INPUTS : output/report_pres_exports/*.csv   (from 08 and 09)
# OUTPUTS: tables/rep_*.tex
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
library(tidyverse)

RDIR <- file.path("output", "report_pres_exports")
dir.create("tables", showWarnings = FALSE)
rd <- function(n) read_csv(file.path(RDIR, paste0(n, ".csv")), show_col_types = FALSE)

# ---- helpers ----------------------------------------------------------------
stars <- function(p) ifelse(is.na(p), "", ifelse(p < .01, "$^{***}$",
                     ifelse(p < .05, "$^{**}$", ifelse(p < .10, "$^{*}$", ""))))
fm  <- function(x, d = 3) formatC(x, format = "f", digits = d)
est <- function(b, p, d = 3) paste0(fm(b, d), stars(p))
par_ <- function(s, d = 3) paste0("(", fm(s, d), ")")
LBL <- c(delta_P_dalton = "$\\Delta P^{D}$ (Dalton)",
         delta_P_center = "$\\Delta P^{N}$ (centre-emptying)")
esc <- function(x) str_replace_all(x, "_", "\\\\_")

wtex <- function(lines, f) {
  writeLines(lines, file.path("tables", f))
  cat("wrote tables/", f, "\n", sep = "")
}

# =============================================================================
# T1 — DESCRIPTIVE STATISTICS
# =============================================================================
d <- rd("B_descriptives")
nice <- c(delta_P_dalton = "$\\Delta$ Dalton index",
          delta_P_center = "$\\Delta$ Centre-emptying index",
          delta_EPW = "$\\Delta$ EPW (Bartik)",
          P_dalton_2010 = "Dalton index, 2010",
          P_center_2010 = "Centre-emptying index, 2010",
          ln_gdp_pc = "Log GDP per capita",
          ln_pop = "Log population",
          urban_share = "Urban share",
          educ_share = "Education share",
          manuf_share_of_tradable = "Manuf.\\ share of tradable emp.",
          tradable_emp_share = "Tradable emp.\\ share of total")
body <- d |> mutate(lab = coalesce(nice[variable], esc(variable))) |>
  transmute(row = sprintf("%-34s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
                          lab, format(N, big.mark = ","), fm(mean), fm(sd),
                          fm(min), fm(p25), fm(median), fm(p75), fm(max))) |> pull(row)
wtex(c("\\begin{table}[htbp]\\centering",
       "\\caption{Descriptive statistics, presidential estimation panel}",
       "\\label{tab:rep-desc}",
       "\\begin{threeparttable}\\small",
       "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrrrrr@{}}",
       "\\toprule",
       "Variable & $N$ & Mean & SD & Min & p25 & Median & p75 & Max \\\\",
       "\\midrule", body, "\\bottomrule", "\\end{tabular*}",
       "\\begin{tablenotes}[flushleft]\\footnotesize",
       "\\item Stacked first differences relative to 2010 for 2014, 2018 and 2022;",
       "557 microregions $\\times$ 3 differences. Controls are 2010 levels.",
       "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab1_descriptives.tex")

# =============================================================================
# T2 — BASELINE OLS ACROSS INFERENCE REGIMES
# =============================================================================
b <- rd("C_baseline_all_regimes"); r <- rd("E_randomization_inference")
rp <- r |> filter(coefficient == "pooled") |> select(control_set, outcome, ri_p)
b <- b |> left_join(rp, by = c("control_set", "outcome"))
blk <- function(cs) {
  x <- b |> filter(control_set == cs) |> arrange(match(outcome, names(LBL)))
  c(sprintf("\\multicolumn{3}{l}{\\emph{%s controls}} \\\\[2pt]",
            if (cs == "base") "Baseline" else "Extended"),
    sprintf("$\\Delta$ EPW & %s & %s \\\\", est(x$beta[1], x$p_meso_year[1]),
            est(x$beta[2], x$p_meso_year[2])),
    sprintf("\\quad meso $\\times$ year cluster & %s & %s \\\\",
            par_(x$se_meso_year[1]), par_(x$se_meso_year[2])),
    sprintf("\\quad mesoregion cluster & %s & %s \\\\",
            par_(x$se_meso_pooled[1]), par_(x$se_meso_pooled[2])),
    sprintf("\\quad Conley 250\\,km & %s & %s \\\\",
            par_(x$se_conley250[1]), par_(x$se_conley250[2])),
    sprintf("\\quad Conley 500\\,km & %s & %s \\\\",
            par_(x$se_conley500[1]), par_(x$se_conley500[2])),
    sprintf("\\quad AKM & %s & %s \\\\", par_(x$se_akm[1]), par_(x$se_akm[2])),
    sprintf("RI $p$-value & %s & %s \\\\", fm(x$ri_p[1]), fm(x$ri_p[2])),
    sprintf("AKM0 $p$-value & %s & %s \\\\", fm(x$p_akm0[1]), fm(x$p_akm0[2])),
    sprintf("AKM0 95\\%% set & [%s, %s] & [%s, %s] \\\\",
            fm(x$akm0_lo[1]), fm(x$akm0_hi[1]), fm(x$akm0_lo[2]), fm(x$akm0_hi[2])),
    sprintf("Within $R^2$ & %s & %s \\\\", fm(x$within_r2[1]), fm(x$within_r2[2])),
    "\\addlinespace[3pt]")
}
wtex(c("\\begin{table}[htbp]\\centering",
       "\\caption{Export exposure and polarization: pooled treatment under every inference regime}",
       "\\label{tab:rep-baseline}",
       "\\begin{threeparttable}\\small",
       "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lcc@{}}",
       "\\toprule",
       sprintf(" & %s & %s \\\\", LBL[["delta_P_dalton"]], LBL[["delta_P_center"]]),
       "\\midrule", blk("base"), blk("extended"),
       sprintf("Observations & %s & %s \\\\", format(b$N[1], big.mark = ","),
               format(b$N[2], big.mark = ",")),
       "State $\\times$ year FE & Yes & Yes \\\\",
       "\\bottomrule", "\\end{tabular*}",
       "\\begin{tablenotes}[flushleft]\\footnotesize",
       "\\item Point estimate reported once per control set; each subsequent row is",
       "the standard error under a different variance estimator. Stars follow the",
       "meso $\\times$ year cluster $p$-value. RI is design-based randomization",
       "inference over industry identities, $B=9{,}999$. AKM/AKM0 follow Adao,",
       "Kolesar \\& Morales (2019); AKM0 is the weak-identification-robust",
       "confidence set. $^{*}p<0.10$, $^{**}p<0.05$, $^{***}p<0.01$.",
       "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab2_baseline.tex")

# =============================================================================
# T3 — ASYMMETRIC DECOMPOSITION
# =============================================================================
dc <- rd("D_decomposition")
rb <- r |> filter(coefficient %in% c("boom", "bust")) |>
  select(coefficient, control_set, outcome, ri_p) |>
  pivot_wider(names_from = coefficient, values_from = ri_p, names_prefix = "ri_")
dc <- dc |> left_join(rb, by = c("control_set", "outcome"))
dblk <- function(cs) {
  x <- dc |> filter(control_set == cs) |> arrange(match(outcome, names(LBL)))
  c(sprintf("\\multicolumn{3}{l}{\\emph{%s controls}} \\\\[2pt]",
            if (cs == "base") "Baseline" else "Extended"),
    sprintf("$\\Delta$ EPW$^{+}$ (boom) & %s & %s \\\\",
            est(x$beta_boom[1], x$p_boom[1]), est(x$beta_boom[2], x$p_boom[2])),
    sprintf(" & %s & %s \\\\", par_(x$se_boom[1]), par_(x$se_boom[2])),
    sprintf("$\\Delta$ EPW$^{-}$ (bust) & %s & %s \\\\",
            est(x$beta_bust[1], x$p_bust[1]), est(x$beta_bust[2], x$p_bust[2])),
    sprintf(" & %s & %s \\\\", par_(x$se_bust[1]), par_(x$se_bust[2])),
    sprintf("RI $p$: boom & %s & %s \\\\", fm(x$ri_boom[1]), fm(x$ri_boom[2])),
    sprintf("RI $p$: bust & %s & %s \\\\", fm(x$ri_bust[1]), fm(x$ri_bust[2])),
    sprintf("Within $R^2$ & %s & %s \\\\", fm(x$within_r2[1]), fm(x$within_r2[2])),
    "\\addlinespace[3pt]")
}
wtex(c("\\begin{table}[htbp]\\centering",
       "\\caption{Asymmetric decomposition: boom and bust magnitudes}",
       "\\label{tab:rep-decomp}",
       "\\begin{threeparttable}\\small",
       "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lcc@{}}",
       "\\toprule",
       sprintf(" & %s & %s \\\\", LBL[["delta_P_dalton"]], LBL[["delta_P_center"]]),
       "\\midrule", dblk("base"), dblk("extended"),
       sprintf("Observations & %s & %s \\\\", format(dc$N[1], big.mark = ","),
               format(dc$N[2], big.mark = ",")),
       "\\bottomrule", "\\end{tabular*}",
       "\\begin{tablenotes}[flushleft]\\footnotesize",
       "\\item $\\Delta$EPW$^{+}=\\max(\\Delta\\text{EPW},0)$ and",
       "$\\Delta$EPW$^{-}=\\max(-\\Delta\\text{EPW},0)$ are non-negative magnitudes,",
       "each divided by the SD of $\\Delta$EPW. Proposition 1 predicts",
       "$\\beta^{-}>0$ and $\\beta^{-}\\ge|\\beta^{+}|$. Meso $\\times$ year",
       "clustered standard errors in parentheses; RI $p$-values from $B=9{,}999$",
       "industry permutations.",
       "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab3_decomposition.tex")

# =============================================================================
# T4 — SHOCK CONCENTRATION AND EXOGENEITY DIAGNOSTICS
# =============================================================================
cc <- rd("F_rotemberg_concentration"); bal <- rd("G_balance"); pl <- rd("G_placebo")
top <- rd("F_rotemberg_top8") |> group_by(year) |> slice_head(n = 3) |>
  summarise(t3 = paste(sprintf("%s (%.2f)", isic4, alpha), collapse = "; "), .groups = "drop")
tt <- cc |> left_join(bal |> select(year, F, p), by = "year") |> left_join(top, by = "year")
wtex(c("\\begin{table}[htbp]\\centering",
       "\\caption{Shock concentration and shock-level exogeneity, by election year}",
       "\\label{tab:rep-diag}",
       "\\begin{threeparttable}\\small",
       "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lccccl@{}}",
       "\\toprule",
       "Year & HHI$(|\\alpha|)$ & Eff.\\ \\# shocks & Top-3 share & Balance $F$ ($p$) & Top-3 industries ($\\alpha$) \\\\",
       "\\midrule",
       sprintf("%d & %s & %s & %s & %s (%s) & %s \\\\", tt$year, fm(tt$hhi_abs_alpha),
               fm(tt$eff_n, 2), fm(tt$top3_share), fm(tt$F, 2), fm(tt$p), tt$t3),
       "\\bottomrule", "\\end{tabular*}",
       "\\begin{tablenotes}[flushleft]\\footnotesize",
       sprintf(paste0("\\item Rotemberg weights $\\alpha_{jt}$ from the treatment ",
                      "residualized on controls and state effects; the effective ",
                      "number of shocks is $1/\\mathrm{HHI}(|\\alpha|)$, mean %.2f ",
                      "across years. Balance $F$ tests the non-mechanical industry ",
                      "observables (commodity dummy and log 2010 export level). ",
                      "AKM placebo rejection rate at the 5\\%% nominal level: %.3f ",
                      "($\\Delta P^{D}$) and %.3f ($\\Delta P^{N}$), i.e.\\ cluster ",
                      "standard errors over-reject by roughly sevenfold."),
               mean(cc$eff_n), pl$reject_rate_5pct[pl$outcome == "delta_P_dalton"],
               pl$reject_rate_5pct[pl$outcome == "delta_P_center"]),
       "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab4_diagnostics.tex")

# =============================================================================
# T5 — INSTRUMENT: FIRST STAGE, 2SLS, REDUCED FORM
# =============================================================================
fs <- rd("H_first_stage"); tsl <- rd("H_2sls"); rf <- rd("H_reduced_form")
ZL <- c(EPW_IV_A = "$z^{A}$ (RoW demand)", EPW_IV_B = "$z^{B}$ (Brazil mix)",
        EPW_IV_CHN = "$z^{CHN}$ (China demand)")
lines <- c()
for (z in fs$instrument) {
  f <- fs |> filter(instrument == z)
  a <- tsl |> filter(instrument == z, outcome == "delta_P_dalton")
  bb <- tsl |> filter(instrument == z, outcome == "delta_P_center")
  ra <- rf |> filter(instrument == z, outcome == "delta_P_dalton")
  rb2 <- rf |> filter(instrument == z, outcome == "delta_P_center")
  lines <- c(lines,
    sprintf("%s & %s & %s & %s & %s & %s & %s \\\\", ZL[[z]],
            est(f$beta, 2 * pnorm(-abs(f$t))), fm(f$F_wald_clustered, 1),
            est(a$beta_2sls, a$p), est(bb$beta_2sls, bb$p),
            est(ra$beta, ra$p), est(rb2$beta, rb2$p)),
    sprintf(" & %s & & %s & %s & %s & %s \\\\", par_(f$se), par_(a$se), par_(bb$se),
            par_(ra$se), par_(rb2$se)))
}
wtex(c("\\begin{table}[htbp]\\centering",
       "\\caption{External-demand instruments: first stage, 2SLS and reduced form}",
       "\\label{tab:rep-iv}",
       "\\begin{threeparttable}\\small",
       "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lcccccc@{}}",
       "\\toprule",
       " & \\multicolumn{2}{c}{First stage} & \\multicolumn{2}{c}{2SLS} & \\multicolumn{2}{c}{Reduced form} \\\\",
       "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}",
       "Instrument & $\\Delta$EPW & $F$ & $\\Delta P^{D}$ & $\\Delta P^{N}$ & $\\Delta P^{D}$ & $\\Delta P^{N}$ \\\\",
       "\\midrule", lines, "\\bottomrule", "\\end{tabular*}",
       "\\begin{tablenotes}[flushleft]\\footnotesize",
       "\\item All specifications include baseline controls and state $\\times$ year",
       "fixed effects; standard errors clustered by mesoregion $\\times$ year.",
       "Instruments are standardized. Only $z^{CHN}$ has a first stage strong",
       "enough to interpret; $z^{A}$ and $z^{B}$ are reported for completeness and",
       "their 2SLS estimates should not be read as identified. The reduced form is",
       "immune to first-stage weakness and is the more informative column.",
       "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab5_iv.tex")

# =============================================================================
# T6 — CENTRE-INDEX DEGENERACY (from 09)
# =============================================================================
if (file.exists(file.path(RDIR, "J3_baseline_conditioning.csv"))) {
  occ <- rd("J1_centre_band_occupancy"); dg <- rd("J2_degeneracy_by_stack")
  sv <- rd("J3_baseline_conditioning")
  # occ covers all four waves (2010 is the base year); dg only the three stacked
  # differences. Join so the row counts cannot silently diverge.
  pa <- occ |> left_join(dg |> select(year, sd_delta_P_center, r2_center_on_baseline),
                         by = "year") |> arrange(year)
  p1 <- sprintf("%d & %d & %s & %s & %s & %s \\\\", pa$year, pa$n_in_band,
                ifelse(is.na(pa$parties_in_band) | pa$parties_in_band == "",
                       "---", esc(pa$parties_in_band)),
                fm(pa$centre_vote_share),
                ifelse(is.na(pa$sd_delta_P_center), "---", fm(pa$sd_delta_P_center)),
                ifelse(is.na(pa$r2_center_on_baseline), "--- (base year)",
                       fm(pa$r2_center_on_baseline, 4)))
  sub <- sv |> filter(outcome == "delta_P_center") |> arrange(control_set, baseline_control)
  # 4 decimals here: conditioning on the baseline drives the bust coefficient to
  # -0.0001, which renders as "-0.000" at 3 digits and reads like a typo.
  p2 <- sprintf("%s & %s & %s & %s & %s & %s \\\\",
                ifelse(sub$control_set == "base", "Baseline", "Extended"),
                ifelse(sub$baseline_control, "Yes", "No"),
                est(sub$beta_bust, sub$p_bust, 4), par_(sub$se_bust, 4),
                est(sub$beta_boom, sub$p_boom, 4), par_(sub$se_boom, 4))
  wtex(c("\\begin{table}[htbp]\\centering",
         "\\caption{The centre-emptying index is baseline-determined in 2018 and 2022}",
         "\\label{tab:rep-centre}",
         "\\begin{threeparttable}\\small",
         "\\textbf{Panel A. Occupancy of the centre band $[-0.25,0.25]$}\\\\[2pt]",
         "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lclccc@{}}",
         "\\toprule",
         "Year & \\# in band & Parties in band & Centre vote share & SD($\\Delta P^{N}$) & $R^2$ on 2010 baseline \\\\",
         "\\midrule", p1, "\\bottomrule", "\\end{tabular*}",
         "\\\\[6pt]\\textbf{Panel B. $\\Delta P^{N}$ with and without the 2010 baseline}\\\\[2pt]",
         "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}llcccc@{}}",
         "\\toprule",
         "Controls & 2010 baseline & \\multicolumn{2}{c}{$\\Delta$EPW$^{-}$ (bust)} & \\multicolumn{2}{c}{$\\Delta$EPW$^{+}$ (boom)} \\\\",
         "\\midrule", p2, "\\bottomrule", "\\end{tabular*}",
         "\\begin{tablenotes}[flushleft]\\footnotesize",
         "\\item Every microregion faces the same national candidate menu, so",
         "$P^{N}$ varies across space only if some party sits inside the centre",
         "band. In 2018 none does, so $P^{N}\\equiv 1$ and",
         "$\\Delta P^{N}=1-P^{N}_{2010}$ exactly; in 2022 only MDB qualifies.",
         "Conditioning on the 2010 baseline therefore removes the mechanical",
         "channel, and the bust coefficient collapses to zero.",
         "\\end{tablenotes}\\end{threeparttable}\\end{table}"), "rep_tab6_centre_index.tex")
}

cat("\nAll report tables written to tables/rep_*.tex\n")
