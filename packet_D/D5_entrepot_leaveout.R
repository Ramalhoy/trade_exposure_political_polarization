# =============================================================================
# D5_entrepot_leaveout.R  —  Packet D, Stage 1, step 5
# -----------------------------------------------------------------------------
# Does N2 survive the entrepot leave-out?
#
# [D-40] found Saint Lucia carrying mean |alpha| = 0.441 under N2, and alpha =
# 0.602 in 2022 as the single dominant unit, against 0.026 under N1. LCA is
# petroleum transhipment through one storage terminal, so under N2 the design's
# dominant "destination" is not a destination at all. This script asks whether
# removing the five entrepots repairs N2 or merely promotes the next pathology.
#
# THE LEAVE-OUT IS A COLUMN DROP, NOT A RENORMALISATION. [D-43]
# N2 shares are incomplete by construction (sum_d s_rd = theta_r_dest, not 1),
# so dropping entrepot columns simply lowers theta_r_dest for the affected
# microregions - which is the honest statement that the exposure is gone.
# Renormalising would redistribute Saint Lucia's value across a microregion's
# remaining destinations and quietly preserve the very exposure being tested.
# N1 IS a composition, so its leave-out must renormalise; both are reported.
#
# No outcome regression.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 REV_NTHREADS=4 \
#         Rscript códigos/packet_D/D5_entrepot_leaveout.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
suppressPackageStartupMessages(library(fixest))

OUT_D          <- file.path("output", "packet_D")
ELECTION_YEARS <- c(2014L, 2018L, 2022L)
YEARS_CHR      <- as.character(ELECTION_YEARS)
ENTREPOT_ISO3  <- c("NLD", "SGP", "HKG", "ARE", "LCA")   # [D-25]
BENCH_EFF_LEVEL <- 2.589602662949854
ALPHA_DOMINANT <- 0.50    # a single unit above this is not a diversified design
BAL_ALPHA      <- 0.05
GRAVITY_YEAR   <- 2010L
BAL_RHS_DEST   <- "log_gdpcap_d + log_dist + contig + comlang_off + china + top5"

dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D5_OUT <- c("D5_rotemberg.csv", "D5_top5.csv", "D5_comparison.csv",
            "tab_d5_entrepot.md")
existing <- D5_OUT[file.exists(file.path(OUT_D, D5_OUT))]
if (length(existing)) stop("[D5] refusing to overwrite:\n  ",
                           paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D5_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D5 entrepot leave-out:", format(Sys.time()), "===\n")
cat("Entrepots dropped:", paste(ENTREPOT_ISO3, collapse = ", "), "\n\n")

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }
md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}

# ---- inputs -----------------------------------------------------------------
d1   <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))
g_dt <- readRDS(file.path(OUT_D, "D3_g_dt.rds"))
s_rd <- d1$s_rd
baci_countries <- d1$baci_countries
micro_n1 <- sort(unique(s_rd$micro))
ent_codes <- baci_countries |> filter(baci_iso3 %in% ENTREPOT_ISO3) |> pull(destino)
chn_code  <- baci_countries |> filter(baci_iso3 == "CHN") |> pull(destino)

cat("Entrepot destinations dropped carry",
    sprintf("%.2f%%", 100 * sum(s_rd$x_rd[s_rd$destino %in% ent_codes]) / sum(s_rd$x_rd)),
    "of attributed 2010 export value\n")

# theta_r_dest before and after — the cost of the column drop, stated plainly
th <- s_rd |> group_by(micro) |>
  summarise(theta_all = sum(x_rd), theta_ex = sum(x_rd[!destino %in% ent_codes]),
            .groups = "drop") |>
  left_join(s_rd |> distinct(micro, L_r_denom = x_rd / s_rd_n2) |>
              group_by(micro) |> summarise(L = first(L_r_denom), .groups = "drop"),
            by = "micro") |>
  mutate(theta_all = theta_all / L, theta_ex = theta_ex / L,
         drop_pct = 100 * (1 - theta_ex / theta_all))
cat(sprintf("theta_r_dest falls by a median of %.2f%% (mean %.2f%%, max %.1f%%) across the %d exporting microregions\n\n",
            median(th$drop_pct), mean(th$drop_pct), max(th$drop_pct), nrow(th)))

# ---- exposure matrices ------------------------------------------------------
mk_W <- function(share_col, drop_ent, renorm) {
  d <- s_rd |> filter(destino %in% unique(g_dt$destino))
  if (drop_ent) d <- d |> filter(!destino %in% ent_codes)
  d <- d |> select(micro, destino, val = all_of(share_col))
  if (renorm) d <- d |> group_by(micro) |> mutate(val = val / sum(val)) |> ungroup()
  keep <- sort(unique(d$destino))
  wide <- d |> mutate(micro = as.character(micro), destino = paste0("d", destino)) |>
    pivot_wider(names_from = destino, values_from = val, values_fill = 0)
  M <- df_scaled |> select(micro) |> left_join(wide, by = "micro") |>
    select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |> as.matrix()
  M[, paste0("d", keep), drop = FALSE]
}
W_n2_all <- mk_W("s_rd_n2", FALSE, FALSE)
W_n2_ex  <- mk_W("s_rd_n2", TRUE,  FALSE)   # [D-43] column drop, no renormalisation
W_n1_all <- mk_W("s_rd_n1", FALSE, FALSE)
W_n1_ex  <- mk_W("s_rd_n1", TRUE,  TRUE)    # N1 is a composition -> renormalise

g_mat_dest_full <- g_dt |> select(destino, ano, g_dt) |>
  mutate(destino = paste0("d", destino)) |>
  pivot_wider(names_from = ano, values_from = g_dt, values_fill = 0) |>
  column_to_rownames("destino") |> as.matrix()
gm_for <- function(Wm) g_mat_dest_full[colnames(Wm), YEARS_CHR, drop = FALSE]

epw_of <- function(Wm, gm) {
  m <- sapply(YEARS_CHR, function(t) as.numeric(Wm %*% gm[, t]))
  m[cbind(seq_len(nrow(Wm)), match(as.character(df_scaled$year), YEARS_CHR))]
}

# ---- Rotemberg (transcribed from G3, verified against the S0 benchmark) ------
rotemberg_for <- function(treat_vec, gm, Wm, ctrls) {
  d_all <- df_scaled |> mutate(.treat = treat_vec)
  map_dfr(YEARS_CHR, function(t) {
    sel <- df_scaled$year == as.integer(t)
    d <- d_all[sel, ]; Wt <- Wm[sel, , drop = FALSE]
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = ".treat"), data = d))
    num <- gm[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(unit = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
conc <- function(rot) {
  by_year <- rot |> group_by(year) |>
    summarise(hhi = sum((abs(alpha)/sum(abs(alpha)))^2), eff_n = 1/hhi,
              top3 = sum(sort(abs(alpha), decreasing = TRUE)[1:3])/sum(abs(alpha)),
              top1 = max(abs(alpha))/sum(abs(alpha)), .groups = "drop")
  bind_rows(by_year, tibble(year = "mean of yearly", hhi = NA_real_,
                            eff_n = mean(by_year$eff_n), top3 = mean(by_year$top3),
                            top1 = mean(by_year$top1)))
}
r_s0 <- rotemberg_for(df_scaled$delta_EPW_raw, g_mat[colnames(W), YEARS_CHR], W, ctrl_base)
stopifnot("[D5] Rotemberg does not reproduce the S0 benchmark" =
            abs(conc(r_s0)$eff_n[4] - BENCH_EFF_LEVEL) < 1e-6)
cat("CANARY: S0 effective shocks reproduce at", round(conc(r_s0)$eff_n[4], 4), "\n\n")

SPECS <- list(
  "S3_N2 all destinations"     = W_n2_all,
  "S3_N2 entrepots dropped"    = W_n2_ex,
  "S3_N1 all destinations"     = W_n1_all,
  "S3_N1 entrepots dropped"    = W_n1_ex)

rot <- list(); cc <- list(); t5 <- list(); epws <- list()
for (nm in names(SPECS)) {
  Wm <- SPECS[[nm]]; gm <- gm_for(Wm)
  e <- epw_of(Wm, gm); epws[[nm]] <- e
  r <- rotemberg_for(e, gm, Wm, ctrl_base)
  rot[[nm]] <- r |> mutate(spec = nm)
  cc[[nm]]  <- conc(r) |> mutate(spec = nm, .before = 1)
  t5[[nm]]  <- r |> group_by(year) |> slice_max(abs(alpha), n = 5) |>
    arrange(year, desc(abs(alpha))) |> ungroup() |> mutate(spec = nm)
}
cc <- bind_rows(cc); t5 <- bind_rows(t5) |>
  left_join(baci_countries |> transmute(unit = paste0("d", destino), iso3 = baci_iso3),
            by = "unit") |> mutate(unit = coalesce(iso3, unit)) |> select(-iso3)

cat("=== D5(1) ROTEMBERG CONCENTRATION, WITH AND WITHOUT ENTREPOTS ===\n")
print(as.data.frame(cc |> select(spec, year, eff_n, top1, top3)), digits = 4)

cat("\n=== D5(2) TOP-5 WEIGHTS ===\n")
print(as.data.frame(t5 |> select(spec, year, unit, alpha)), digits = 4)

# ---- is the design dominated by any single unit? ----------------------------
dom <- bind_rows(rot) |> group_by(spec, year) |>
  summarise(top1 = max(abs(alpha)) / sum(abs(alpha)),
            top1_unit = unit[which.max(abs(alpha))], .groups = "drop") |>
  left_join(baci_countries |> transmute(top1_unit = paste0("d", destino), iso3 = baci_iso3),
            by = "top1_unit") |>
  mutate(top1_unit = coalesce(iso3, top1_unit),
         dominated = top1 > ALPHA_DOMINANT) |> select(-iso3)
cat(sprintf("\n=== D5(3) SINGLE-UNIT DOMINANCE (alpha > %.2f) ===\n", ALPHA_DOMINANT))
print(as.data.frame(dom), digits = 4)

# ---- alpha_China, unchanged reporting order ---------------------------------
cat("\n=== D5(4) alpha_China ===\n")
print(as.data.frame(bind_rows(rot) |> filter(unit == paste0("d", chn_code)) |>
                      select(spec, year, alpha)), digits = 4)

# ---- independence -----------------------------------------------------------
in_n1 <- df_scaled$micro %in% as.character(micro_n1)
indep <- map_dfr(names(SPECS), function(nm)
  tibble(spec = nm,
         rho_S0_all = cor(df_scaled$delta_EPW_raw, epws[[nm]]),
         rho_S0_n1  = cor(df_scaled$delta_EPW_raw[in_n1], epws[[nm]][in_n1]),
         rho_vs_N2all = cor(epws[["S3_N2 all destinations"]], epws[[nm]])))
cat("\n=== D5(5) INDEPENDENCE ===\n")
print(as.data.frame(indep), digits = 4)

# ---- destination balance, entrepots dropped ---------------------------------
grav_dir <- "CEPII Gravity database"
grav <- readRDS(file.path(grav_dir, "Gravity_V202211.rds"))
grav_bra <- grav |> filter(iso3_o == "BRA", year == GRAVITY_YEAR) |>
  select(iso3_d, gdpcap_d, dist, contig, comlang_off) |>
  distinct(iso3_d, .keep_all = TRUE)
rm(grav); gc()
x_d <- s_rd |> group_by(destino) |> summarise(x_d = sum(x_rd), .groups = "drop") |>
  mutate(share_2010 = x_d / sum(x_d))
top5_dest <- x_d |> slice_max(share_2010, n = 5) |> pull(destino)
bal_base <- g_dt |> left_join(x_d |> select(destino, share_2010), by = "destino") |>
  left_join(grav_bra, by = c("iso3" = "iso3_d")) |>
  mutate(log_gdpcap_d = log(gdpcap_d), log_dist = log(dist),
         china = as.integer(destino == chn_code),
         top5 = as.integer(destino %in% top5_dest), s_bar = share_2010) |>
  filter(is.finite(log_gdpcap_d), is.finite(log_dist), !is.na(contig),
         !is.na(comlang_off), !is.na(s_bar))
bal <- map_dfr(c("all destinations", "entrepots dropped"), function(sc) {
  d0 <- if (sc == "all destinations") bal_base else
    filter(bal_base, !destino %in% ent_codes)
  map_dfr(ELECTION_YEARS, function(t) {
    m <- feols(as.formula(paste("g_dt ~", BAL_RHS_DEST)),
               data = filter(d0, ano == t), weights = ~ s_bar)
    f <- fitstat(m, "f")[[1]]
    tibble(sample = sc, year = t, F = f$stat, p = f$p, passes = f$p >= BAL_ALPHA)
  })
})
cat("\n=== D5(6) DESTINATION BALANCE ===\n")
print(as.data.frame(bal), digits = 4)

# ---- write ------------------------------------------------------------------
cmp <- cc |> filter(year == "mean of yearly") |>
  select(spec, eff_n, top1, top3) |>
  left_join(indep |> select(spec, rho_S0_n1), by = "spec") |>
  left_join(dom |> group_by(spec) |> summarise(n_cycles_dominated = sum(dominated),
                                               .groups = "drop"), by = "spec")
write_csv_safe(cc,  file.path(OUT_D, "D5_rotemberg.csv"))
write_csv_safe(t5,  file.path(OUT_D, "D5_top5.csv"))
write_csv_safe(cmp, file.path(OUT_D, "D5_comparison.csv"))

writeLines(c(
  "# Packet D — entrepôt leave-out: is N2 reportable?",
  "",
  paste0("Generated ", format(Sys.time()),
         " by `códigos/packet_D/D5_entrepot_leaveout.R`."),
  paste0("Entrepôts dropped: ", paste(ENTREPOT_ISO3, collapse = ", "),
         " — ", round(100 * sum(s_rd$x_rd[s_rd$destino %in% ent_codes]) /
                        sum(s_rd$x_rd), 2), "% of attributed 2010 export value."),
  "",
  paste0("`[D-43]` The N2 leave-out is a **column drop, not a renormalisation**: ",
         "N2 shares are incomplete by construction, so dropping entrepôt columns ",
         "simply lowers `theta_r_dest` (median ",
         round(median(th$drop_pct), 2), "%, max ", round(max(th$drop_pct), 1),
         "%). Renormalising would redistribute Saint Lucia's value across a ",
         "microregion's remaining destinations and quietly preserve the exposure ",
         "under test. N1 is a composition and its leave-out does renormalise."),
  "",
  "## Headline comparison", "", md(cmp), "",
  "## Concentration by cycle", "", md(cc |> select(spec, year, eff_n, top1, top3)), "",
  "## Top-5 weights", "", md(t5 |> select(spec, year, unit, alpha)), "",
  paste0("## Single-unit dominance (alpha > ", ALPHA_DOMINANT, ")"), "",
  md(dom), "",
  "## Destination balance", "", md(bal), "",
  "## Independence", "", md(indep), ""
), file.path(OUT_D, "tab_d5_entrepot.md"))

cat("\n[D5] wrote", OUT_D, "\n")
sink(); close(log_con)
