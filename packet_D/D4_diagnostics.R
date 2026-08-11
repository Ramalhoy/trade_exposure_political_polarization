# =============================================================================
# D4_diagnostics.R  —  Packet D, Phase 1, STAGE 1, step 4
# -----------------------------------------------------------------------------
# Rotemberg weights over DESTINATIONS (Branch A) and industries (Branch B),
# effective shock counts, destination-characteristic balance, and the
# independence correlations that decide [D-PRE-4].
#
# alpha_China is reported FIRST, not last: [D-PRE-4] has a prior pointing the
# unfavourable way, since z_CHN carries alpha(0610) ~ 0.90 ([D-11]).
#
# The Rotemberg machinery is transcribed from revision/G3_arc_shock.R lines
# 74-100 without alteration and is verified against the published benchmarks
# (level 2.5896, arc 5.5689) before any new number is reported.
#
# No outcome regression. No polarization series is loaded.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 REV_NTHREADS=4 \
#         Rscript códigos/packet_D/D4_diagnostics.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
suppressPackageStartupMessages({ library(fixest); library(readxl) })

OUT_D           <- file.path("output", "packet_D")
ELECTION_YEARS  <- c(2014L, 2018L, 2022L)
YEARS_CHR       <- as.character(ELECTION_YEARS)
N_MICRO_EXPECTED <- 557L
BENCH_EFF_LEVEL <- 2.589602662949854
BENCH_EFF_ARC   <- 5.568901834676357
RHO_PRE4        <- 0.90        # [D-PRE-4] threshold
BAL_ALPHA       <- 0.05
ENTREPOT_ISO3   <- c("NLD", "SGP", "HKG", "ARE", "LCA")   # [D-25]
GRAVITY_YEAR    <- 2010L       # baseline destination characteristics

# [D-34] Destination-characteristic balance set. From CEPII Gravity V202211,
# which carries gdpcap_d, gdp_d, pop_d, dist, contig and comlang_off in ONE
# object — the World Bank WDI pull contemplated in [D-4] is unnecessary and is
# dropped. Keyed on alphabetic iso3 and routed to BACI's numeric code via
# Countries_V202211.csv iso3num, as [D-4] item 4 prescribes.
BAL_RHS_DEST <- "log_gdpcap_d + log_dist + contig + comlang_off + china + top5"

dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D4_OUT <- c("D4_rotemberg.csv", "D4_rotemberg_top5.csv", "D4_balance_dest.csv",
            "D4_independence.csv", "tab_d_rotemberg.md", "tab_d_balance.md",
            "tab_d_independence.md", "fig_d4_epw.pdf")
existing <- D4_OUT[file.exists(file.path(OUT_D, D4_OUT))]
if (length(existing))
  stop("[D4] refusing to overwrite:\n  ", paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D4_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D4 diagnostics:", format(Sys.time()), "===\n\n")

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }
md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}

# =============================================================================
# STEP 1 — INPUTS AND EXPOSURE MATRICES
# =============================================================================
d1   <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))
g_dt <- readRDS(file.path(OUT_D, "D3_g_dt.rds"))
Z_jt <- readRDS(file.path(OUT_D, "D3_Z_jt.rds"))
s_rd <- d1$s_rd
baci_countries <- d1$baci_countries
micro_n1 <- sort(unique(s_rd$micro))

cat("STEP 1: estimation frame N =", nrow(df_scaled), "| micros =",
    n_distinct(df_scaled$micro), "| N1 exporting micros =", length(micro_n1), "\n")

# Destination exposure matrices on the df_scaled row order, exactly as R00
# builds W for industries. Destinations with no g_dt are dropped from BOTH
# sides rather than zero-filled.
dest_keep <- sort(intersect(unique(s_rd$destino), unique(g_dt$destino)))
mk_W <- function(share_col) {
  wide <- s_rd |> filter(destino %in% dest_keep) |>
    select(micro, destino, val = all_of(share_col)) |>
    mutate(micro = as.character(micro), destino = paste0("d", destino)) |>
    pivot_wider(names_from = destino, values_from = val, values_fill = 0)
  M <- df_scaled |> select(micro) |> left_join(wide, by = "micro") |>
    select(-micro) |> mutate(across(everything(), ~ replace_na(., 0))) |>
    as.matrix()
  M[, paste0("d", dest_keep), drop = FALSE]
}
W_n2 <- mk_W("s_rd_n2")
W_n1 <- mk_W("s_rd_n1")
stopifnot("[D4] destination exposure matrix misaligned" =
            nrow(W_n2) == nrow(df_scaled), !anyNA(W_n2), !anyNA(W_n1))

g_mat_dest <- g_dt |> filter(destino %in% dest_keep) |>
  select(destino, ano, g_dt) |>
  mutate(destino = paste0("d", destino)) |>
  pivot_wider(names_from = ano, values_from = g_dt, values_fill = 0) |>
  column_to_rownames("destino") |> as.matrix()
g_mat_dest <- g_mat_dest[colnames(W_n2), YEARS_CHR, drop = FALSE]

g_mat_Z <- Z_jt |> select(isic4, ano, Z_jt) |>
  pivot_wider(names_from = ano, values_from = Z_jt, values_fill = 0) |>
  column_to_rownames("isic4") |> as.matrix()
g_mat_Z <- g_mat_Z[colnames(W), YEARS_CHR, drop = FALSE]

arc_path   <- file.path("output", "revision", "G3", "G3_shocks_arc.csv")
shocks_arc <- read.csv(arc_path, colClasses = c(isic4 = "character")) |> as_tibble()
g_mat_arc <- shocks_arc |> filter(year %in% ELECTION_YEARS) |>
  select(isic4, year, g_arc) |>
  pivot_wider(names_from = year, values_from = g_arc, values_fill = 0) |>
  column_to_rownames("isic4") |> as.matrix()
g_mat_arc <- g_mat_arc[colnames(W), YEARS_CHR, drop = FALSE]

# Exposure series. make_epw_star() is R00's, with the exposure matrix swapped.
epw_of <- function(Wm, gm) {
  epw_mat <- sapply(YEARS_CHR, function(t) as.numeric(Wm %*% gm[, t]))
  epw_mat[cbind(seq_len(nrow(Wm)), match(as.character(df_scaled$year), YEARS_CHR))]
}
epw_S0    <- df_scaled$delta_EPW_raw
epw_S1    <- epw_of(W, g_mat_arc)
epw_S2    <- epw_of(W, g_mat_Z)
epw_S3_N2 <- epw_of(W_n2, g_mat_dest)
epw_S3_N1 <- epw_of(W_n1, g_mat_dest)

# =============================================================================
# STEP 2 — ROTEMBERG, transcribed from G3, benchmark-verified
# =============================================================================
rotemberg_for <- function(treat_vec, gm, Wm, ctrls) {
  d_all <- df_scaled |> mutate(.treat = treat_vec)
  map_dfr(YEARS_CHR, function(t) {
    sel <- df_scaled$year == as.integer(t)
    d   <- d_all[sel, ]
    Wt  <- Wm[sel, , drop = FALSE]
    x_perp <- resid(lm(reformulate(c(ctrls, "factor(state)"), response = ".treat"),
                       data = d))
    num <- gm[colnames(Wt), t] * as.numeric(t(Wt) %*% x_perp)
    tibble(unit = colnames(Wt), year = t, alpha = num / sum(num))
  })
}
conc <- function(rot) {
  by_year <- rot |> group_by(year) |>
    summarise(hhi = sum((abs(alpha) / sum(abs(alpha)))^2), eff_n = 1 / hhi,
              top3 = sum(sort(abs(alpha), decreasing = TRUE)[1:3]) / sum(abs(alpha)),
              top1 = max(abs(alpha)) / sum(abs(alpha)), .groups = "drop")
  bind_rows(by_year,
            tibble(year = "mean of yearly", hhi = NA_real_,
                   eff_n = mean(by_year$eff_n), top3 = mean(by_year$top3),
                   top1 = mean(by_year$top1)))
}

SERIES <- list(
  "S0 g_jt (industry, level)"        = list(tv = epw_S0,    gm = g_mat,      Wm = W),
  "S1 g_arc (industry, arc)"         = list(tv = epw_S1,    gm = g_mat_arc,  Wm = W),
  "S2 Z_jt (industry, dest-wtd arc)" = list(tv = epw_S2,    gm = g_mat_Z,    Wm = W),
  "S3_N2 g_dt (destination)"         = list(tv = epw_S3_N2, gm = g_mat_dest, Wm = W_n2),
  "S3_N1 g_dt (destination)"         = list(tv = epw_S3_N1, gm = g_mat_dest, Wm = W_n1))

rot_all <- list(); conc_all <- list(); top5 <- list()
for (nm in names(SERIES)) {
  s <- SERIES[[nm]]
  r <- rotemberg_for(s$tv, s$gm, s$Wm, ctrl_base)
  rot_all[[nm]]  <- r |> mutate(rung = nm)
  conc_all[[nm]] <- conc(r) |> mutate(rung = nm, .before = 1)
  top5[[nm]] <- r |> group_by(year) |> slice_max(abs(alpha), n = 5) |>
    arrange(year, desc(abs(alpha))) |> ungroup() |> mutate(rung = nm)
}
conc_all <- bind_rows(conc_all); top5_all <- bind_rows(top5)
rot_tbl  <- bind_rows(rot_all)

eff_mean <- conc_all |> filter(year == "mean of yearly") |> select(rung, eff_n) |> deframe()
cat(sprintf("\nBENCHMARK CHECK  S0 %.4f (G3 %.4f) | S1 %.4f (G3 %.4f)\n",
            eff_mean[[1]], BENCH_EFF_LEVEL, eff_mean[[2]], BENCH_EFF_ARC))
stopifnot("[D4] Rotemberg does not reproduce the G3 benchmarks" =
            abs(eff_mean[[1]] - BENCH_EFF_LEVEL) < 1e-6 &&
            abs(eff_mean[[2]] - BENCH_EFF_ARC)   < 1e-6)

# ---- alpha_China FIRST -------------------------------------------------------
chn_code <- baci_countries |> filter(baci_iso3 == "CHN") |> pull(destino)
alpha_chn <- rot_tbl |> filter(str_starts(rung, "S3"), unit == paste0("d", chn_code)) |>
  group_by(rung, year) |>
  summarise(alpha_China = alpha,
            share_of_total_abs = abs(alpha) /
              sum(abs(rot_tbl$alpha[rot_tbl$rung == first(rung) &
                                      rot_tbl$year == first(year)])), .groups = "drop")
cat("\n=== D4(2a) ALPHA_CHINA — reported first ([D-PRE-4] prior) ===\n")
print(as.data.frame(alpha_chn), digits = 4)

cat("\n=== D4(2b) ROTEMBERG CONCENTRATION AND EFFECTIVE SHOCK COUNT ===\n")
print(as.data.frame(conc_all |> select(rung, year, hhi, eff_n, top1, top3)), digits = 4)

# Label destination units for readability
lbl <- baci_countries |> transmute(unit = paste0("d", destino), iso3 = baci_iso3)
top5_lab <- top5_all |> left_join(lbl, by = "unit") |>
  mutate(unit_label = coalesce(iso3, unit)) |> select(rung, year, unit_label, alpha)
cat("\n=== D4(2c) top-5 |alpha| by rung and cycle ===\n")
print(as.data.frame(top5_lab), digits = 4)

# [D-25] entrepot check: is petroleum reappearing under a destination label?
ent_alpha <- rot_tbl |> filter(str_starts(rung, "S3")) |>
  left_join(lbl, by = "unit") |> filter(iso3 %in% ENTREPOT_ISO3) |>
  group_by(rung, iso3) |>
  summarise(mean_abs_alpha = mean(abs(alpha)), .groups = "drop") |>
  arrange(rung, desc(mean_abs_alpha))
cat("\n=== D4(2d) [D-25] entrepot destinations in the Rotemberg weights ===\n")
print(as.data.frame(ent_alpha), digits = 4)

write_csv_safe(conc_all, file.path(OUT_D, "D4_rotemberg.csv"))
write_csv_safe(top5_lab, file.path(OUT_D, "D4_rotemberg_top5.csv"))
write_csv_safe(rot_tbl,  file.path(OUT_D, "D4_rotemberg_weights_full.csv"))

# =============================================================================
# STEP 3 — DESTINATION-CHARACTERISTIC BALANCE  [D-34]
# =============================================================================
grav_dir <- "CEPII Gravity database"
ctry <- read_csv(file.path(grav_dir, "Countries_V202211.csv"), show_col_types = FALSE) |>
  transmute(iso3 = iso3, iso3num = as.integer(iso3num)) |> distinct()
grav <- readRDS(file.path(grav_dir, "Gravity_V202211.rds"))
grav_bra <- grav |>
  filter(iso3_o == "BRA", year == GRAVITY_YEAR) |>
  select(iso3_d, gdpcap_d, gdp_d, pop_d, dist, contig, comlang_off) |>
  distinct(iso3_d, .keep_all = TRUE)
rm(grav); gc()

x_d <- s_rd |> group_by(destino) |> summarise(x_d = sum(x_rd), .groups = "drop") |>
  mutate(share_2010 = x_d / sum(x_d)) |>
  left_join(baci_countries |> select(destino, iso3 = baci_iso3), by = "destino")
top5_dest <- x_d |> slice_max(share_2010, n = 5) |> pull(destino)

# g_dt already carries iso3 from D3; take only share_2010 from x_d or the join
# produces iso3.x / iso3.y and the Gravity join then fails on a missing column.
bal_dest <- g_dt |>
  left_join(x_d |> select(destino, share_2010), by = "destino") |>
  left_join(grav_bra, by = c("iso3" = "iso3_d")) |>
  mutate(log_gdpcap_d = log(gdpcap_d), log_dist = log(dist),
         china = as.integer(destino == chn_code),
         top5  = as.integer(destino %in% top5_dest),
         s_bar = share_2010) |>
  filter(is.finite(log_gdpcap_d), is.finite(log_dist),
         !is.na(contig), !is.na(comlang_off), !is.na(s_bar))

cat(sprintf("\n=== D4(3) [D-34] DESTINATION-CHARACTERISTIC BALANCE ===\nCoverage: %d of %d destinations, %.2f%% of 2010 export value\n",
            n_distinct(bal_dest$destino), n_distinct(g_dt$destino),
            100 * sum(x_d$share_2010[x_d$destino %in% bal_dest$destino])))

balance_dest <- map_dfr(ELECTION_YEARS, function(t) {
  d <- filter(bal_dest, ano == t)
  m <- feols(as.formula(paste("g_dt ~", BAL_RHS_DEST)), data = d, weights = ~ s_bar)
  f <- fitstat(m, "f")[[1]]
  tibble(shock = "g_dt", year = t, F = f$stat, df1 = f$df1, df2 = f$df2,
         p = f$p, r2 = fixest::r2(m, "r2"), passes = f$p >= BAL_ALPHA)
})
print(as.data.frame(balance_dest), digits = 4)

bal_coefs_dest <- map_dfr(ELECTION_YEARS, function(t) {
  m <- feols(as.formula(paste("g_dt ~", BAL_RHS_DEST)),
             data = filter(bal_dest, ano == t), weights = ~ s_bar)
  tibble(year = t, term = names(coef(m)), beta = as.numeric(coef(m)),
         t = as.numeric(tstat(m))) |> filter(term != "(Intercept)")
})
cat("\n--- destination-balance coefficients ---\n")
print(as.data.frame(bal_coefs_dest), digits = 4)
write_csv_safe(bind_rows(balance_dest |> mutate(kind = "F"),
                         bal_coefs_dest |> mutate(kind = "coef")),
               file.path(OUT_D, "D4_balance_dest.csv"))

# =============================================================================
# STEP 4 — INDEPENDENCE  [D-PRE-4]
# =============================================================================
# [D-27] N1 and N2 are different samples. rho(EPW_S0, EPW_S3) is computable only
# on the 464 exporting microregions; the N2 column spans all 557.
in_n1 <- df_scaled$micro %in% as.character(micro_n1)
E <- tibble(S0 = epw_S0, S1 = epw_S1, S2 = epw_S2,
            S3_N2 = epw_S3_N2, S3_N1 = epw_S3_N1)

cor_pairs <- function(idx, tag) {
  M <- as.matrix(E[idx, ])
  keep <- apply(M, 2, function(z) sd(z) > 0)
  M <- M[, keep, drop = FALSE]
  p <- cor(M); s <- cor(M, method = "spearman")
  expand_grid(a = colnames(M), b = colnames(M)) |> filter(a < b) |>
    mutate(sample = tag, n = nrow(M),
           pearson = map2_dbl(a, b, ~ p[.x, .y]),
           spearman = map2_dbl(a, b, ~ s[.x, .y]))
}
independence <- bind_rows(
  cor_pairs(rep(TRUE, nrow(E)), paste0("all micros (N=", nrow(E), ")")),
  cor_pairs(in_n1, paste0("N1 exporting micros (N=", sum(in_n1), ")")))

cat("\n=== D4(4) INDEPENDENCE — [D-PRE-4] at rho >", RHO_PRE4, "===\n")
print(as.data.frame(independence), digits = 4)

rho_pre4 <- independence |>
  filter(a == "S0", b == "S3_N1", str_starts(sample, "N1")) |> pull(pearson)
cat(sprintf("\n[D-PRE-4] rho(EPW_S0, EPW_S3_N1) = %.4f on the N1 sample -> %s\n",
            rho_pre4,
            if (abs(rho_pre4) > RHO_PRE4)
              "EXCEEDS 0.9: Branch A is reframed as a MEASUREMENT robustness check"
            else "below 0.9: Branch A stands as an IDENTIFICATION robustness check"))
cat(sprintf("Benchmark rho(S0, S1) = 0.373 Pearson, 0.572 Spearman.\n"))
write_csv_safe(independence, file.path(OUT_D, "D4_independence.csv"))

# ---- sign-convention guard on the decomposition ------------------------------
# [A-1]/v7: EPW- retains its NEGATIVE sign. Assert EPW+ + EPW- = EPW.
dec <- map_dfr(names(SERIES), function(nm) {
  s <- SERIES[[nm]]
  pos <- epw_of(s$Wm, pmax(s$gm, 0)); neg <- epw_of(s$Wm, pmin(s$gm, 0))
  tibble(rung = nm, max_abs_resid = max(abs((pos + neg) - s$tv)),
         min_pos = min(pos), max_neg = max(neg))
})
cat("\n=== D4(4b) decomposition sign guard (EPW+ + EPW- = EPW; EPW- stays negative) ===\n")
print(as.data.frame(dec), digits = 4)
stopifnot("[D4] EPW decomposition does not close" = all(dec$max_abs_resid < 1e-9),
          "[D4] EPW+ went negative" = all(dec$min_pos >= -1e-12),
          "[D4] EPW- went positive — the v7 sign bug is back" =
            all(dec$max_neg <= 1e-12))

# =============================================================================
# STEP 5 — FIGURE AND TABLES
# =============================================================================
figd <- E |> mutate(year = df_scaled$year) |>
  pivot_longer(-year, names_to = "rung", values_to = "epw") |>
  group_by(rung) |> mutate(epw = epw / sd(epw)) |> ungroup()
p <- ggplot(figd, aes(x = epw)) + geom_histogram(bins = 45) +
  facet_grid(year ~ rung, scales = "free") +
  labs(x = "EPW, standardised within rung", y = "microregions",
       title = "Packet D: regional exposure across the ladder",
       subtitle = "S3 is the destination design; S3_N1 excludes the 93 zero-export microregions") +
  theme_minimal(base_size = 8)
ggsave(file.path(OUT_D, "fig_d4_epw.pdf"), p, width = 10, height = 5.5,
       device = grDevices::pdf)

writeLines(c("# Packet D — Rotemberg weights and effective shocks (`tab_d_rotemberg.md`)", "",
             paste0("Generated ", format(Sys.time()), " by `códigos/packet_D/D4_diagnostics.R`."),
             "Benchmarks reproduced: S0 2.5896, S1 5.5689 (mean of yearly, base controls).", "",
             "## alpha_China", "", md(alpha_chn), "",
             "## Concentration", "", md(conc_all |> select(rung, year, hhi, eff_n, top1, top3)), "",
             "## Top-5 weights", "", md(top5_lab), "",
             "## Entrepot destinations (`[D-25]`)", "", md(ent_alpha), ""),
           file.path(OUT_D, "tab_d_rotemberg.md"))
writeLines(c("# Packet D — destination-characteristic balance (`tab_d_balance.md`)", "",
             paste0("Generated ", format(Sys.time()), "."),
             paste0("Weights: destination share of Brazil's 2010 exports. RHS: `",
                    BAL_RHS_DEST, "`, from CEPII Gravity V202211 at ", GRAVITY_YEAR,
                    " (`[D-34]`; the WDI pull of `[D-4]` is unnecessary)."), "",
             md(balance_dest), "", "## Coefficients", "", md(bal_coefs_dest), ""),
           file.path(OUT_D, "tab_d_balance.md"))
writeLines(c("# Packet D — independence across rungs (`tab_d_independence.md`)", "",
             paste0("Generated ", format(Sys.time()), "."),
             paste0("`[D-27]`: N1 and N2 are different samples. ",
                    "rho(EPW_S0, EPW_S3) is computable only on the ",
                    length(micro_n1), " exporting microregions."), "",
             md(independence), "",
             paste0("`[D-PRE-4]`: rho(S0, S3_N1) = ", round(rho_pre4, 4),
                    if (abs(rho_pre4) > RHO_PRE4)
                      " — EXCEEDS 0.9, Branch A reframed as a measurement check."
                    else " — below 0.9, Branch A stands as an identification check."),
             "Benchmark rho(S0, S1) = 0.373 Pearson.", ""),
           file.path(OUT_D, "tab_d_independence.md"))

cat("\n[D4] wrote", OUT_D, "\n")
sink(); close(log_con)
