# =============================================================================
# 07z_results_manifest.R  —  merge the per-convention manifest fragments
# -----------------------------------------------------------------------------
# Packet T2 [T-9]. Reads output/manifest_<denom>.rds (written at the end of
# 07_regression_inference.R, one per SHARE_DENOM) and emits
# output/RESULTS_MANIFEST.md: every number that may reach the manuscript, for
# both share conventions, with the sanity chain that certifies it.
#
# Pure reporting — no estimation, no side effects beyond the .md file.
# Run AFTER 07 has been run under both conventions.
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")
library(tidyverse)

CONV <- c(total = "incomplete shares (main)", tradable = "complete shares (robustness)")
frag <- map(names(CONV), ~ {
  f <- file.path("output", sprintf("manifest_%s.rds", .x))
  if (file.exists(f)) readRDS(f) else NULL
}) |> set_names(names(CONV))

have <- names(frag)[!map_lgl(frag, is.null)]
if (!length(have)) stop("no manifest fragments found -- run 07 first")
cat("[T-9] fragments found:", paste(have, collapse = ", "), "\n")

fmt  <- function(x, d = 4) formatC(as.numeric(x), format = "f", digits = d)
star <- function(b, se) {                  # clustered t, normal critical values
  t <- abs(b / se)
  ifelse(t >= 2.576, "***", ifelse(t >= 1.960, "**", ifelse(t >= 1.645, "*", "")))
}
COEF_LAB <- c(pooled_D = "pooled, dP^D", pooled_N = "pooled, dP^N",
              boom_D = "boom, dP^D", bust_D = "bust, dP^D",
              boom_N = "boom, dP^N", bust_N = "bust, dP^N")

L <- c()
add <- function(...) L <<- c(L, ...)

add("# RESULTS MANIFEST — share-denominator conventions compared",
    "",
    sprintf("Generated %s by `07z_results_manifest.R` from `output/manifest_<denom>.rds`.",
            format(Sys.time(), "%Y-%m-%d %H:%M")),
    "Every figure below is produced by a committed script and logged; see `RATIONALE.md`",
    "for the audit trail and `EXECUTOR_PACKET_T2_theta.md` for the work order.",
    "",
    "| Convention | Shares | Σ_j s_rj | BHJ control | Role |",
    "|---|---|---|---|---|",
    "| `total` | s_rj = L_rj/L_r^total | θ_r < 1, varies | `tradable_emp_share` **is** Σ_j s_rj | **main** |",
    "| `tradable` | s_rj = L_rj/L_r^tradable | 1 by construction | degenerate; variable is intensity only | robustness |",
    "")

# ---- run metadata -----------------------------------------------------------
add("## Run metadata", "")
for (k in have) {
  m <- frag[[k]]$meta
  add(sprintf("**`%s`** — %s. B = %d, seed = %d, FE = `%s`, cluster = `%s`. Run %s.",
              k, CONV[[k]], m$B, m$seed, m$fe, m$cluster, m$timestamp),
      "", "Controls:",
      sprintf("- base: `%s`", paste(m$ctrl_base, collapse = "`, `")),
      sprintf("- ext:  `%s`", paste(m$ctrl_ext,  collapse = "`, `")),
      "", "Input MD5:", "",
      "| file | md5 |", "|---|---|",
      paste0("| `", basename(names(m$input_md5)), "` | `", unname(m$input_md5), "` |"),
      "")
}

# ---- estimates --------------------------------------------------------------
add("## Estimates", "",
    "`sd_ratio` = placebo SD ÷ clustered SE: how much wider the design-based",
    "null is than the cluster-robust one. `p_RI` = mean(|β*| ≥ |β̂|); `p_RI+1` =",
    "(1+#)/(B+1), the convention the tables print. Stars are the clustered t with",
    "normal critical values (10/5/1%).", "")
est <- map_dfr(have, ~ mutate(frag[[.x]]$ri, convention = .x))
for (ct in c("base", "ext")) {
  add(sprintf("### %s controls", ct), "",
      "| coefficient | convention | β̂ | clustered SE | | placebo SD | sd_ratio | p_RI | p_RI+1 |",
      "|---|---|---|---|---|---|---|---|---|")
  for (cf in names(COEF_LAB)) for (k in have) {
    r <- est |> filter(coef == cf, ctrls == ct, convention == k)
    if (!nrow(r)) next
    add(sprintf("| %s | `%s` | %s | %s | %s | %s | %.2fx | %.4f | %.4f |",
                COEF_LAB[[cf]], k, fmt(r$beta), fmt(r$se_cl),
                star(r$beta, r$se_cl), fmt(r$placebo_sd), r$sd_ratio,
                r$p_ri, r$p_ri_plus1))
  }
  add("")
}
add("Fit:", "", "| convention | model | N | within adj. R² |", "|---|---|---|---|")
for (k in have) for (i in seq_len(nrow(frag[[k]]$fit))) {
  f <- frag[[k]]$fit[i, ]
  add(sprintf("| `%s` | %s | %d | %s |", k, f$model, f$n, fmt(f$war2, 5)))
}
add("")

# ---- diagnostics ------------------------------------------------------------
add("## Diagnostics", "", "### Rotemberg weights and effective shock count", "",
    "Functions of `W`, so they move with the denominator. Residualisation on the",
    "stated control set + `factor(state)`, via `lm()` (see `RATIONALE.md` [T-6]).", "",
    "| convention | controls | year | HHI(|α|) | eff. shocks 1/HHI | top-3 share |",
    "|---|---|---|---|---|---|")
for (k in have) { r <- frag[[k]]$rotemberg
  for (i in seq_len(nrow(r))) add(sprintf("| `%s` | %s | %s | %s | **%s** | %s |",
    k, r$ctrls[i], r$year[i], fmt(r$hhi_abs_alpha[i]), fmt(r$eff_n[i], 2),
    fmt(r$top3_share[i], 3))) }
add("")
for (k in have) { r <- frag[[k]]$rotemberg |> group_by(ctrls) |>
    summarise(m = mean(eff_n), .groups = "drop")
  add(sprintf("Mean effective shocks, `%s`: %s.", k,
              paste(sprintf("%s = %s", r$ctrls, fmt(r$m, 2)), collapse = "; "))) }
add("", "Top-5 |α| by year:", "",
    "| convention | controls | year | ISIC | α |", "|---|---|---|---|---|")
for (k in have) { r <- frag[[k]]$rotemberg_top5
  for (i in seq_len(nrow(r))) add(sprintf("| `%s` | %s | %s | %s | %s |",
    k, r$ctrls[i], r$year[i], r$isic4[i], fmt(r$alpha[i]))) }
add("")

add("### AKM / AKM0 (secondary inference regime)", "",
    "Read from `output/akm_<denom>.csv` (`07x_akm.R`), which indexes `reg_ss()`'s",
    "length-5 named output BY NAME. An earlier version of this table reported every",
    "AKM SE as NA: the extractor took the first non-AKM0 slot, which is",
    "`Homoscedastic` — NA by design, because only `method = c(\"akm\",\"akm0\")` was",
    "requested. `Inf` in the SE column and a non-compact set in the CI column are",
    "NOT failures: `ci.l > ci.r` is how the package encodes an unbounded",
    "test-inversion set, printed as `(-Inf, ci.r] u [ci.l, Inf)`. With ~2.5",
    "effective shocks an unbounded AKM0 set is the expected weak-identification",
    "signature and corroborates the RI null. The `set` column states which case",
    "each row is, so the bounds are never read as a plain interval.", "")
akm_csv <- map(have, ~ { f <- file.path("output", sprintf("akm_%s.csv", .x))
                         if (file.exists(f)) read_csv(f, show_col_types = FALSE) else NULL }) |>
  set_names(have)
if (any(!map_lgl(akm_csv, is.null))) {
  add("| convention | specification | statistic | β̂ | SE | p | confidence set | set |",
      "|---|---|---|---|---|---|---|---|")
  for (k in have) { a <- akm_csv[[k]]; if (is.null(a)) next
    for (i in seq_len(nrow(a))) add(sprintf("| `%s` | %s | %s | %s | %s | %s | `%s` | %s |",
      k, a$spec[i], a$stat[i], fmt(a$beta[i], 5),
      if (is.finite(a$se[i])) fmt(a$se[i], 5) else "Inf",
      fmt(a$p[i], 4), a$ci[i], a$ci_type[i])) }
  add("")
  n_unb <- sum(map_int(akm_csv[!map_lgl(akm_csv, is.null)],
                       ~ sum(grepl("^unbounded", .x$ci_type))))
  add(sprintf("Unbounded confidence sets: **%d** across both conventions, all AKM0 and all in the by-year specifications — the thinnest first stage in the design.",
              n_unb), "")
} else {
  add("_`output/akm_<denom>.csv` not found — run `07x_akm.R` for each convention._",
      "", "Fallback, from the manifest fragments (may carry the extraction bug):", "",
      "| convention | statistic | SE | p | ci_l | ci_r |", "|---|---|---|---|---|---|")
  for (k in have) { a <- frag[[k]]$akm_pooled
    for (i in seq_len(nrow(a))) add(sprintf("| `%s` | %s | %s | %s | %s | %s |",
      k, toupper(a$stat[i]), fmt(a$se[i], 5), fmt(a$p[i], 4),
      fmt(a$ci_l[i], 5), fmt(a$ci_r[i], 5))) }
  add("")
}

add("### Conley spatial SEs (ΔP^D, base controls)", "",
    "| convention | cutoff | β̂ | SE |", "|---|---|---|---|")
for (k in have) { c0 <- frag[[k]]$conley
  for (i in seq_len(nrow(c0))) add(sprintf("| `%s` | %s | %s | %s |",
    k, c0$cutoff[i], fmt(c0$beta[i]), fmt(c0$se[i]))) }
add("", "### Mesoregion-pooled clustering (common-base-year robustness)", "",
    "| convention | model | β̂ | SE |", "|---|---|---|---|")
for (k in have) { p <- frag[[k]]$meso_pooled
  for (i in seq_len(nrow(p))) add(sprintf("| `%s` | %s | %s | %s |",
    k, p$model[i], fmt(p$beta[i]), fmt(p$se[i]))) }
add("")

add("### BHJ shock balance", "",
    "**Invariant to the share denominator.** The weights are national employment",
    "shares `s_bar_j = L_j,2010 / Σ_j L_j,2010` built from the shock table",
    "(`03c_shock_exogeneity.R:196`), and `g_jt` has national denominators, so",
    "neither moves when the regional shares are renormalised. Reported once.", "")
bal <- frag[[have[1]]]$balance
if (!is.null(bal)) {
  add("| spec | year | F | df1 | df2 | p |", "|---|---|---|---|---|---|")
  for (i in seq_len(nrow(bal))) add(sprintf("| %s | %s | %s | %s | %s | %s |",
    bal$spec[i], bal$year[i], fmt(bal$F[i], 3), bal$df1[i], bal$df2[i],
    fmt(bal$p[i], 4)))
} else add("_`output/03c_balance_test.csv` not present — re-run `03c_shock_exogeneity.R`._")
add("")

add("### Symmetry test  H₀: β₊ = −β₋", "",
    "The formal test of the asymmetry hypothesis; in magnitude coding",
    "`β_boom + β_bust = 0`. Restored from the 16 Jun table (base controls).", "",
    "| convention | outcome | β_boom | β_bust | sum | SE(sum) | t | p |",
    "|---|---|---|---|---|---|---|---|")
for (k in have) { s <- frag[[k]]$symmetry
  for (i in seq_len(nrow(s))) add(sprintf("| `%s` | %s | %s | %s | %s | %s | %s | **%s** |",
    k, s$outcome[i], fmt(s$b_boom[i]), fmt(s$b_bust[i]), fmt(s$sum[i]),
    fmt(s$se_sum[i]), fmt(s$t[i], 2), fmt(s$p[i], 4))) }
add("")

# ---- sanity chain -----------------------------------------------------------
add("## Sanity chain", "",
    "| check | total | tradable |", "|---|---|---|")
cell <- function(k, g) {
  if (!k %in% have) return("—")
  v <- tryCatch(g(frag[[k]]$sanity), error = function(e) NA)
  if (length(v) != 1 || is.na(v)) "—" else as.character(v)
}
row2 <- function(lab, g)
  add(sprintf("| %s | %s | %s |", lab, cell("total", g), cell("tradable", g)))
row2("max&#124;rowSums(W) − invariant&#124;", function(s) sprintf("%.2e", s$W_rowsum_gap))
row2("Σ_j s_rj min",    function(s) fmt(s$share_sum_min, 6))
row2("Σ_j s_rj mean",   function(s) fmt(s$share_sum_mean, 6))
row2("Σ_j s_rj max",    function(s) fmt(s$share_sum_max, 6))
fd_rows <- function() {          # the 1,674 step lives in 06, not 07
  f <- file.path("output", "06_run_log_total.txt")
  if (!file.exists(f)) return("—")
  m <- str_match(paste(readLines(f, warn = FALSE), collapse = "\n"),
                 "First-differences panel: (\\d+) rows")
  if (is.na(m[1, 2])) "—" else m[1, 2]
}
add(sprintf("| first-difference rows (558 × 3, before the estimation-universe rule) | %s | %s |",
            fd_rows(), fd_rows()))
add("| after dropping micro 13002 (no base-year tradable employment) | 1671 | 1671 |")
row2("rows entering 07 (N_SAMPLE input)", function(s) s$n_rows_prefilter)
row2("sample rows (N_SAMPLE)",  function(s) s$N_SAMPLE)
row2("estimated N (N_EST)",     function(s) s$N_EST)
row2("microregions",            function(s) s$n_micros)
row2("state×year cells in the sample (3 Distrito Federal singletons drop in estimation, leaving 78)",
     function(s) s$n_fe_cells)
row2("industries (cols of W)",  function(s) s$n_industries)
row2("sd(ΔEPW) on estimation sample", function(s) fmt(s$sd_epw, 6))
row2("bust obs, pooled",  function(s) s$bust_counts[["pooled"]])
row2("bust obs, 2014",    function(s) s$bust_counts[["2014"]])
row2("bust obs, 2018",    function(s) s$bust_counts[["2018"]])
row2("bust obs, 2022",    function(s) s$bust_counts[["2022"]])
ncell <- function(k) { g <- frag[[k]]$nesting_gap
  if (!k %in% have || is.null(g)) "—" else sprintf("%.2e", max(g)) }
add(sprintf("| nesting gap max&#124;b(boom−bust) − b_pooled&#124; | %s | %s |",
            ncell("total"), ncell("tradable")))
add("", "θ_r moments on the estimation sample:", "",
    "| convention | mean | SD | min | P25 | median | P75 | max |", "|---|---|---|---|---|---|---|---|")
for (k in have) { t0 <- frag[[k]]$sanity$theta
  add(sprintf("| `%s` | %s | %s | %s | %s | %s | %s | %s |", k,
              fmt(t0[["mean"]], 3), fmt(t0[["sd"]], 3), fmt(t0[["min"]], 3),
              fmt(t0[["p25"]], 3), fmt(t0[["median"]], 3), fmt(t0[["p75"]], 3),
              fmt(t0[["max"]], 3))) }
add("")

# ---- descriptives -----------------------------------------------------------
add("## Descriptives, raw units", "")
for (k in have) { d <- frag[[k]]$descriptives
  add(sprintf("### `%s`", k), "",
      "| variable | N | mean | SD | min | P25 | median | P75 | max |",
      "|---|---|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(d))) add(sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
    gsub("\\\\", "", d$Variable[i]), format(d$N[i], big.mark = ","),
    fmt(d$Mean[i]), fmt(d$SD[i]), fmt(d$Min[i]), fmt(d$P25[i]),
    fmt(d$Median[i]), fmt(d$P75[i]), fmt(d$Max[i])))
  add("") }

# ---- deltas vs the current draft -------------------------------------------
# Old values are the ones currently IN main.tex / the frozen tables on disk.
# Sourced by hand once, and each one is labelled with where it came from, so the
# rewrite has a checklist rather than a diff to eyeball.
add("## Deltas — what the re-run changes in `main.tex`", "",
    "Old = the value in the current draft or in the frozen table on disk.",
    "New = this run under `SHARE_DENOM = \"total\"` (main). Where a cell has no",
    "counterpart in the draft it is marked NEW.", "")
if ("total" %in% have) {
  g <- function(cf, ct, col) { r <- frag$total$ri |> filter(coef == cf, ctrls == ct)
                               if (nrow(r)) r[[col]] else NA_real_ }
  gt <- function(cf, ct) sprintf("%s%s", fmt(g(cf, ct, "beta")),
                                 star(g(cf, ct, "beta"), g(cf, ct, "se_cl")))
  mnf <- filter(frag$total$descriptives, grepl("Manuf", Variable))
  d <- tibble::tribble(
    ~item, ~old, ~old_src, ~new,
    "boom, dP^D (base ctrls)", "0.006", "tab_decomposition_v3.tex", gt("boom_D", "base"),
    "bust, dP^D (base ctrls)", "0.0009", "tab_decomposition_v3.tex", gt("bust_D", "base"),
    "boom, dP^N (base ctrls)", "-0.016*", "tab_decomposition_v3.tex", gt("boom_N", "base"),
    "bust, dP^N (base ctrls)", "-0.043***", "tab_decomposition_v3.tex", gt("bust_N", "base"),
    "RI p, bust dP^D", "0.973", "tab_decomposition_v3.tex note",
      fmt(g("bust_D", "base", "p_ri_plus1")),
    "RI p, bust dP^N", "0.426", "tab_decomposition_v3.tex note",
      fmt(g("bust_N", "base", "p_ri_plus1")),
    "RI p, boom dP^D", "NEW (never permuted)", "—", fmt(g("boom_D", "base", "p_ri_plus1")),
    "RI p, boom dP^N", "NEW (never permuted)", "—", fmt(g("boom_N", "base", "p_ri_plus1")),
    "RI p, pooled dP^N", "NEW (never permuted)", "—", fmt(g("pooled_N", "base", "p_ri_plus1")),
    "sd(dEPW), estimation sample (UNITS CHANGE, not a discrepancy: the treatment is now per total worker)",
      "1.866", "Table 2 / packet T anchor", fmt(frag$total$sanity$sd_epw, 3),
    "mean effective shocks", "~2.4", "main.tex 3.4, 5.2, 6",
      fmt(mean(filter(frag$total$rotemberg, ctrls == "base")$eff_n), 2),
    "theta_r mean", "0.25", "main.tex 3.1",
      fmt(frag$total$sanity$theta[["mean"]], 3),
    "theta_r max", "0.68", "main.tex 3.1",
      fmt(frag$total$sanity$theta[["max"]], 3),
    # MEMO_v2 §2.3: main.tex's row reads 0.637 / 0.257 / 0.449 / 0.692 / 0.852,
    # i.e. mean / SD / P25 / median / P75 -- none of which is reproducible.
    "manuf. share of tradable: mean", "0.637", "main.tex Table 2",
      fmt(mnf$Mean, 4),
    "manuf. share of tradable: SD", "0.257", "main.tex Table 2", fmt(mnf$SD, 4),
    "manuf. share of tradable: P25", "0.449", "main.tex Table 2", fmt(mnf$P25, 4),
    "manuf. share of tradable: median", "0.692", "main.tex Table 2",
      fmt(mnf$Median, 4),
    "manuf. share of tradable: P75", "0.852", "main.tex Table 2", fmt(mnf$P75, 4))
  add("| item | old | source of old | new (`total`) |", "|---|---|---|---|")
  for (i in seq_len(nrow(d)))
    add(sprintf("| %s | %s | %s | **%s** |", d$item[i], d$old[i], d$old_src[i], d$new[i]))
  add("",
      "Text claims that must be rewritten regardless of these numbers, per",
      "`RATIONALE.md` [T-1b]:", "",
      "1. §2.3 — the manufacturing share is *not* the sum-of-shares control and θ_r",
      "   is *not* excluded; under the main specification θ_r **is** the BHJ control.",
      "2. §3.1 — the reported treatment now normalises over total formal employment;",
      "   the complete-shares variant is the robustness. Equation (7) and the 0.93",
      "   correlation stand.",
      "3. §6 — the \"most consequential item outstanding\" is settled, and the",
      "   instability argument built on boom-Center losing significance is an",
      "   artifact of a run that omitted the BHJ control. See [T-1b].",
      "4. Table 3 note — the boom/bust partition is identical across conventions",
      "   because θ_r ≥ 0; only the magnitudes are reweighted.",
      "5. Table 2, manufacturing-share row — the draft's 0.637 / 0.257 / 0.449 /",
      "   0.692 / 0.852 matches no computable universe (`MEMO_v2_main_tex_vs_v7.md`",
      "   §2.3). `manuf_share_of_tradable` is invariant to the share denominator",
      "   (built from raw employment counts, `04_controls.R:259`), so the values in",
      "   the descriptives table above are the correct ones under BOTH conventions;",
      "   the draft's row has no reproducible provenance and should be replaced.",
      "")
} else add("_`manifest_total.rds` missing — run 07 under `SHARE_DENOM = \"total\"`._", "")

add("## Files", "")
for (k in have) add(sprintf("- `%s`: `output/07_run_log_%s.txt`, `output/manifest_%s.rds`, `output/ri_summary_%s.csv`, `output/ri_beta_distribution_%s_{base,ext}.rds`, `tables/tab_{ols_baseline,decomposition,desc_stats}_%s.tex`",
                            k, k, k, k, k, k))
add("", "Frozen, not rewritten: `output/ri_beta_distribution.rds`,",
    "`tables/tab_ols_baseline.tex`, `tables/tab_decomposition_v3.tex`,",
    "`tables/tab_desc_stats.tex` — the pre-[T-2b] vintage, kept for provenance.", "")

writeLines(L, file.path("output", "RESULTS_MANIFEST.md"))
cat("[T-9] wrote output/RESULTS_MANIFEST.md (", length(L), "lines )\n")
