# =============================================================================
# D3b_orphan_capacity.R  —  Packet D, [D-31] production-capacity orphan test
# -----------------------------------------------------------------------------
# A VALID measure of the Comex municipality-attribution threat, replacing the
# bridge gate withdrawn as invalid at [D-30].
#
# Every regional EXPORT series in this tree inherits the same Comex declaring-
# municipio attribution, so no export series can test it. RAIS is independent of
# Comex and observes where productive capacity is. The threat has a signature
# RAIS can see: a microregion credited with exports of goods it has no capacity
# to produce.
#
#   C_r = { isic4 : workers_{r,isic4} > 0 }            from rais_isic_v7.rds
#   product p is ORPHAN in r   <=>   ISIC(p) INTERSECT C_r = empty
#   orphan_share = sum_{orphan} X_rp / sum_all X_rp
#
# Binding threshold pre-registered at [D-PRE-6]: 20% of attributed 2010 export
# value. LOWER BOUND by construction — attribution error between two
# microregions that BOTH have capacity in the relevant industry is invisible to
# it. A breach is decisive; a pass is reassuring, not conclusive.
#
# The crosswalk enters this DIAGNOSTIC only and never the Branch A shares;
# Branch A stays crosswalk-free where it counts.
#
# No outcome regression. Does not gate D3 — [D-PRE-6] governs what it implies.
#
# Run:  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 Rscript códigos/packet_D/D3b_orphan_capacity.R
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
  library(readxl)
})
set.seed(2026)

OUT_D            <- file.path("output", "packet_D")
BASE_YEAR        <- 2010L
N_MICRO_EXPECTED <- 557L
COMEX_FILE       <- "EXP_2010_MUN.csv"
ORPHAN_THRESHOLD <- 0.20      # [D-PRE-6] binding
TOP_ORPHAN_N     <- 20
TOP_MUN_N        <- 20
ENTREPOT_ISO3    <- c("NLD", "SGP", "HKG", "ARE", "LCA")   # [D-25]
FOCUS_ISIC       <- c("0610", "0710")                      # the two that dominate

# [D-31 decision 2] Strictly zero employment, not a positive cutoff. Zero is
# unambiguous; any cutoff is a tuning knob.
CAPACITY_MIN_WORKERS <- 0

# [D-19] repeated here rather than imported: D1 did not persist it. Consistency
# is ASSERTED below against D1's microregion set rather than assumed.
COMEX_UF_PREFIX_REMAP <- c("34" = "35", "52" = "50", "53" = "52", "54" = "53")

# [D-33] Port and state-capital microregions, for the [D-PRE-6] SECONDARY
# prediction. Pinned as an explicit list rather than inferred from the export
# data itself — inferring "ports" from export concentration and then testing
# whether orphan value concentrates in ports would be circular.
# State capitals: the 27 capital municipios. Ports: Brazil's principal maritime
# and river cargo terminals by 2010 throughput.
CAPITAL_MUN <- c("1200401","1302603","1600303","1501402","1100205","1400100",
                 "1721000","2111300","2211001","2304400","2408102","2507507",
                 "2611606","2704302","2800308","2927408","3106200","3205309",
                 "3304557","3550308","4106902","4205407","4314902","5002704",
                 "5103403","5208707","5300108")
PORT_MUN    <- c("3548500","3304557","4118204","4314902","4208203","4216602",
                 "3205309","2607901","2927408","2304400","1501402","1302603",
                 "2111300","3301702","3300456","2800308","2704302","2408102",
                 "2507507","2503209","2913606","4207304","4101408","2312908",
                 "1501709","1506807","1100205","3205002","2611606")

dir.create(OUT_D, showWarnings = FALSE, recursive = TRUE)
D3B_OUT <- c("D3b_orphan_by_micro.csv", "D3b_orphan_top_cells.csv",
             "D3b_orphan_summary.csv", "tab_d3b_orphan.md",
             "fig_d3b_orphan.pdf")
existing <- D3B_OUT[file.exists(file.path(OUT_D, D3B_OUT))]
if (length(existing))
  stop("[D3b] refusing to overwrite:\n  ", paste(existing, collapse = "\n  "))

log_con <- file(file.path(OUT_D, "D3b_run_log.txt"), open = "wt")
sink(log_con, split = TRUE)
cat("=== D3b [D-31] production-capacity orphan test:", format(Sys.time()), "===\n")
cat("[D-PRE-6] binding threshold:", 100 * ORPHAN_THRESHOLD, "% of attributed 2010 value\n\n")

write_csv_safe <- function(x, f) { if (file.exists(f)) unlink(f); readr::write_csv(x, f) }

# =============================================================================
# STEP 1 — CAPABILITY SETS FROM RAIS (independent of Comex)
# =============================================================================
rais <- readRDS("rais_isic_v7.rds")
capability <- rais |> filter(workers > CAPACITY_MIN_WORKERS) |>
  distinct(micro, isic4) |> mutate(capable = TRUE)
cat(sprintf("STEP 1: capability sets — %d microregions | %s (micro,isic) pairs | mean %.1f industries per micro\n",
            n_distinct(capability$micro), format(nrow(capability), big.mark = ","),
            nrow(capability) / n_distinct(capability$micro)))

# =============================================================================
# STEP 2 — SH4 -> ISIC SET, via the v7 dictionary, aggregated up from HS6
#   [D-31 decisions 3 and 4]: the ISIC set of an SH4 is the UNION over its HS6
#   children, with the composite map applied first so capability is assessed on
#   the same 152-industry universe as everything else.
# =============================================================================
ncm_isic_v7   <- readRDS("ncm_isic_match_v7.rds")
composite_map <- readRDS("composite_map_v7.rds")
universe      <- sort(unique(readRDS("sectoral_shocks_isic_v7.rds")$isic4))

sh4_isic <- ncm_isic_v7 |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(isic4 = coalesce(isic_composite, isic4)) |>
  filter(isic4 %in% universe) |>
  transmute(sh4 = str_sub(ncm6, 1, 4), isic4) |>
  distinct()
cat(sprintf("STEP 2: SH4 -> ISIC — %d SH4 codes | %s (sh4,isic) pairs | mean %.2f ISIC per SH4\n",
            n_distinct(sh4_isic$sh4), format(nrow(sh4_isic), big.mark = ","),
            nrow(sh4_isic) / n_distinct(sh4_isic$sh4)))

# =============================================================================
# STEP 3 — COMEX AT SH4 x MICRO x DESTINATION
# =============================================================================
d1 <- readRDS(file.path(OUT_D, "D1_s_rd.rds"))
baci_countries <- d1$baci_countries
micro_n1 <- sort(unique(d1$s_rd$micro))

aux_pais <- read_excel("/Users/solenoide/Documents/dissertação/data/misc/TABELAS_AUXILIARES.xlsx",
                       sheet = "10") |>
  transmute(CO_PAIS = str_trim(as.character(CO_PAIS)),
            comex_iso3 = str_trim(as.character(CO_PAIS_ISOA3)))
area_map <- tibble(comex_iso3 = names(d1$comex_baci_area_map),
                   destino_mapped = as.integer(d1$comex_baci_area_map))
fold <- d1$panel_persistent_fold
fold_destino <- function(d) {
  k <- as.character(d); hit <- k %in% names(fold)
  if_else(hit, fold[k], as.integer(d))
}
municipios <- readRDS("municipios_ibge.rds") |>
  transmute(ibge_code = str_trim(as.character(municipality_code_ibge)),
            micro = as.integer(microregion_code))
comex_to_ibge <- function(x) {
  pref <- substr(x, 1, 2); hit <- pref %in% names(COMEX_UF_PREFIX_REMAP)
  if_else(hit, paste0(COMEX_UF_PREFIX_REMAP[pref], substr(x, 3, 7)), x)
}

comex <- fread(COMEX_FILE, sep = ";", encoding = "Latin-1",
               colClasses = list(character = c("CO_ANO","CO_MES","SH4","CO_PAIS",
                                               "SG_UF_MUN","CO_MUN"))) |>
  as_tibble() |>
  mutate(VL_FOB = as.numeric(VL_FOB)) |>
  left_join(aux_pais, by = "CO_PAIS") |>
  left_join(baci_countries |> select(comex_iso3 = baci_iso3, destino_direct = destino),
            by = "comex_iso3") |>
  left_join(area_map, by = "comex_iso3") |>
  mutate(destino = fold_destino(coalesce(destino_direct, destino_mapped)),
         ibge_code = comex_to_ibge(CO_MUN)) |>
  left_join(municipios, by = "ibge_code") |>
  filter(comex_iso3 != "ZZZ", !is.na(destino), !is.na(micro), micro %in% micro_n1)

# The universe must be the one D1 built, or the shares and this test describe
# different samples.
stopifnot("[D3b] microregion set does not match D1" =
            setequal(unique(comex$micro), micro_n1))

x_rp <- comex |>
  group_by(micro, sh4 = SH4, destino, CO_MUN) |>
  summarise(x = sum(VL_FOB), .groups = "drop")
cat(sprintf("STEP 3: %s (micro, sh4, destino, municipio) cells | %.2f B USD\n",
            format(nrow(x_rp), big.mark = ","), sum(x_rp$x) / 1e9))

# =============================================================================
# STEP 4 — ORPHAN CLASSIFICATION
#   [D-31 decision 5]: SH4 with no ISIC match in the v7 dictionary leave BOTH
#   numerator and denominator, and are reported separately.
# =============================================================================
sh4_matched <- unique(sh4_isic$sh4)
x_unmatched <- x_rp |> filter(!sh4 %in% sh4_matched)
x_in        <- x_rp |> filter(sh4 %in% sh4_matched)

cat(sprintf("STEP 4: SH4 outside the v7 dictionary — %.3f%% of value, excluded from both sides\n",
            100 * sum(x_unmatched$x) / sum(x_rp$x)))

# capable if r employs anyone in ANY ISIC reachable from the product
# ([D-31 decision 1]: conservative, so the statistic is a lower bound)
cap_cells <- x_in |> distinct(micro, sh4) |>
  inner_join(sh4_isic, by = "sh4", relationship = "many-to-many") |>
  left_join(capability, by = c("micro", "isic4")) |>
  group_by(micro, sh4) |>
  summarise(capable = any(!is.na(capable)), .groups = "drop")

orphan <- x_in |>
  left_join(cap_cells, by = c("micro", "sh4")) |>
  mutate(capable = replace_na(capable, FALSE), orphan = !capable)

denom <- sum(orphan$x)
orphan_share_national <- sum(orphan$x[orphan$orphan]) / denom

cat("\n=== D3b HEADLINE — [D-PRE-6] ===\n")
cat(sprintf("Orphan share of attributed 2010 export value: %.4f%% (%.2f B of %.2f B)\n",
            100 * orphan_share_national, sum(orphan$x[orphan$orphan]) / 1e9,
            denom / 1e9))
cat(sprintf("Threshold %.0f%% -> %s\n", 100 * ORPHAN_THRESHOLD,
            if (orphan_share_national > ORPHAN_THRESHOLD)
              "BREACH — reopen the Branch A share construction" else
              "PASS — carry the threat into section 3 as a stated limitation"))
cat("LOWER BOUND: attribution between two microregions that both have capacity\n")
cat("in the relevant industry is invisible to this test ([D-31]).\n")

# =============================================================================
# STEP 5 — WHERE THE ORPHAN VALUE IS
# =============================================================================
by_micro <- orphan |> group_by(micro) |>
  summarise(x_total = sum(x), x_orphan = sum(x[orphan]),
            orphan_share = x_orphan / x_total, .groups = "drop") |>
  mutate(is_capital = micro %in% (municipios |> filter(ibge_code %in% CAPITAL_MUN) |>
                                    pull(micro)),
         is_port    = micro %in% (municipios |> filter(ibge_code %in% PORT_MUN) |>
                                    pull(micro)))

cat("\n--- orphan share by microregion ---\n")
print(as.data.frame(by_micro |> summarise(
  n = n(), mean = mean(orphan_share), median = median(orphan_share),
  p25 = quantile(orphan_share, .25), p75 = quantile(orphan_share, .75),
  p90 = quantile(orphan_share, .90), max = max(orphan_share),
  value_weighted = sum(x_orphan) / sum(x_total))), digits = 4)

# ---- [D-PRE-6] SECONDARY: ports and state capitals ---------------------------
cat("\n--- [D-PRE-6] SECONDARY: is orphan value concentrated in ports/capitals? ---\n")
sec <- by_micro |>
  mutate(grp = case_when(is_port & is_capital ~ "port AND capital",
                         is_port ~ "port only", is_capital ~ "capital only",
                         TRUE ~ "neither")) |>
  group_by(grp) |>
  summarise(n_micro = n(), x_total_B = sum(x_total) / 1e9,
            x_orphan_B = sum(x_orphan) / 1e9,
            orphan_share = sum(x_orphan) / sum(x_total),
            share_of_all_orphan = sum(x_orphan) / sum(by_micro$x_orphan),
            .groups = "drop") |> arrange(desc(x_orphan_B))
print(as.data.frame(sec), digits = 4)

port_cap <- by_micro |> filter(is_port | is_capital)
cat(sprintf("\nPort or capital microregions: %d of %d (%.1f%%), carrying %.1f%% of export value and %.1f%% of ALL orphan value\n",
            nrow(port_cap), nrow(by_micro), 100 * nrow(port_cap) / nrow(by_micro),
            100 * sum(port_cap$x_total) / sum(by_micro$x_total),
            100 * sum(port_cap$x_orphan) / sum(by_micro$x_orphan)))

# ---- top-20 declaring municipios --------------------------------------------
mun_rank <- orphan |> group_by(CO_MUN) |> summarise(x = sum(x), .groups = "drop") |>
  arrange(desc(x)) |> slice_head(n = TOP_MUN_N) |> pull(CO_MUN)
mun_cmp <- orphan |>
  mutate(grp = if_else(CO_MUN %in% mun_rank,
                       paste0("top-", TOP_MUN_N, " declaring municipios"), "all other")) |>
  group_by(grp) |>
  summarise(x_total_B = sum(x) / 1e9, orphan_share = sum(x[orphan]) / sum(x),
            .groups = "drop")
cat(sprintf("\n--- orphan share among the top-%d declaring municipios ---\n", TOP_MUN_N))
print(as.data.frame(mun_cmp), digits = 4)

# ---- entrepot destinations ---------------------------------------------------
ent_cmp <- orphan |>
  left_join(baci_countries |> select(destino, iso3 = baci_iso3), by = "destino") |>
  mutate(grp = if_else(iso3 %in% ENTREPOT_ISO3, "entrepot", "all other")) |>
  group_by(grp) |>
  summarise(x_total_B = sum(x) / 1e9, orphan_share = sum(x[orphan]) / sum(x),
            .groups = "drop")
cat("\n--- orphan share among entrepot destinations (NLD, SGP, HKG, ARE, LCA) ---\n")
print(as.data.frame(ent_cmp), digits = 4)

# ---- ISIC 0610 / 0710 --------------------------------------------------------
focus_sh4 <- sh4_isic |> filter(isic4 %in% FOCUS_ISIC) |> distinct(sh4, isic4)
foc <- orphan |> inner_join(focus_sh4, by = "sh4", relationship = "many-to-many") |>
  group_by(isic4) |>
  summarise(x_total_B = sum(x) / 1e9, orphan_share = sum(x[orphan]) / sum(x),
            .groups = "drop")
cat("\n--- orphan share in ISIC 0610 / 0710 (products reachable to them) ---\n")
print(as.data.frame(foc), digits = 4)

# ---- largest orphan cells ----------------------------------------------------
top_cells <- orphan |> filter(orphan) |>
  left_join(baci_countries |> select(destino, iso3 = baci_iso3), by = "destino") |>
  group_by(micro, sh4, iso3) |>
  summarise(x = sum(x), .groups = "drop") |>
  arrange(desc(x)) |> slice_head(n = TOP_ORPHAN_N) |>
  mutate(pct_of_orphan = 100 * x / sum(orphan$x[orphan$orphan]))
cat(sprintf("\n--- %d largest orphan cells ---\n", TOP_ORPHAN_N))
print(as.data.frame(top_cells), digits = 4)

# =============================================================================
# STEP 6 — WRITE
# =============================================================================
summary_tbl <- tibble(
  statistic = c("orphan share, national (value-weighted)",
                "orphan share, unweighted mean across microregions",
                "orphan share, median across microregions",
                "SH4 outside v7 dictionary (excluded both sides)",
                "share of all orphan value in port/capital microregions",
                "port/capital share of total export value"),
  value = c(orphan_share_national, mean(by_micro$orphan_share),
            median(by_micro$orphan_share), sum(x_unmatched$x) / sum(x_rp$x),
            sum(port_cap$x_orphan) / sum(by_micro$x_orphan),
            sum(port_cap$x_total) / sum(by_micro$x_total)))
write_csv_safe(summary_tbl, file.path(OUT_D, "D3b_orphan_summary.csv"))
write_csv_safe(by_micro,    file.path(OUT_D, "D3b_orphan_by_micro.csv"))
write_csv_safe(top_cells,   file.path(OUT_D, "D3b_orphan_top_cells.csv"))

p <- ggplot(by_micro, aes(x = orphan_share)) +
  geom_histogram(bins = 40) +
  geom_vline(xintercept = ORPHAN_THRESHOLD, linetype = "dashed") +
  facet_wrap(~ if_else(is_port | is_capital, "port or state capital",
                       "all other microregions"), ncol = 1, scales = "free_y") +
  labs(x = "share of 2010 export value in products the microregion cannot produce",
       y = "microregions",
       title = "[D-31] Production-capacity orphan share",
       subtitle = paste0("dashed = [D-PRE-6] threshold ", 100 * ORPHAN_THRESHOLD,
                         "%; national value-weighted = ",
                         round(100 * orphan_share_national, 2), "%")) +
  theme_minimal(base_size = 9)
ggsave(file.path(OUT_D, "fig_d3b_orphan.pdf"), p, width = 7, height = 5.5,
       device = grDevices::pdf)

md <- function(df, digits = 4) {
  d <- df |> mutate(across(where(is.double), ~ signif(.x, digits))) |>
    mutate(across(everything(), as.character))
  rows <- do.call(paste, c(unname(as.list(d)), sep = " | "))
  paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"),
          paste0("| ", paste(rep("---", ncol(d)), collapse = " | "), " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}
writeLines(c(
  "# `[D-31]` Production-capacity orphan test",
  "",
  paste0("Generated ", format(Sys.time()),
         " by `códigos/packet_D/D3b_orphan_capacity.R`."),
  "",
  "Replaces the bridge gate withdrawn as invalid at `[D-30]`. RAIS is independent",
  "of Comex, so a microregion credited with exports of goods it has no capacity",
  "to produce is a signature of declaring-município attribution error.",
  "",
  paste0("## Headline — `[D-PRE-6]`: **",
         round(100 * orphan_share_national, 2), "%** against a ",
         100 * ORPHAN_THRESHOLD, "% threshold -> **",
         if (orphan_share_national > ORPHAN_THRESHOLD) "BREACH" else "PASS", "**"),
  "",
  md(summary_tbl),
  "",
  paste0("**Lower bound by construction** (`[D-31]` decision 1): attribution ",
         "error between two microregions that both have capacity in the relevant ",
         "industry is invisible to this test. A breach is decisive; a pass is ",
         "reassuring rather than conclusive. This caveat travels with the number."),
  "",
  "## `[D-PRE-6]` secondary: ports and state capitals",
  "",
  md(sec),
  "",
  "## Top-20 declaring municípios",
  "",
  md(mun_cmp),
  "",
  "## Entrepôt destinations",
  "",
  md(ent_cmp),
  "",
  "## ISIC 0610 / 0710",
  "",
  md(foc),
  "",
  paste0("## ", TOP_ORPHAN_N, " largest orphan cells"),
  "",
  md(top_cells),
  ""
), file.path(OUT_D, "tab_d3b_orphan.md"))

cat("\n[D3b] wrote", OUT_D, "\n")
sink(); close(log_con)
