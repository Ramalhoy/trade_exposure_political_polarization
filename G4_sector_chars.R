# =============================================================================
# G4 — BUILD sector_chars.rds AND TURN ON THE DEAD BHJ BALANCE TEST
#
# Save to: data/códigos/revision/G4_sector_chars.R
# Run as:  Rscript códigos/revision/G4_sector_chars.R   (from DATA_DIR)
#
# Fills the gap flagged in Dissertation_Code_Assessment_V1.md §44 and in the
# `else` branch of 07_regression_inference.R §6:
#     "TODO: build sector_chars.rds from RAIS 2010."
#
# TARGET SCHEMA (consumed by 07_regression_inference.R §6, unchanged):
#     sector_chars.rds : isic4 | sh_loweduc | sh_white | sh_male | mean_lnwage
#
# WHY A NEW PULL IS REQUIRED
#   No local artefact carries worker characteristics. Checked:
#     rais_2010.rds                 municipio x CNAE, total_vinculos only
#     rais_2010_micro.rds           micro x CNAE, total_vinculos only
#     rais_fte.rds                  micro x CNAE, total_fte only
#     rais_isic_v7.rds              micro x ISIC4, workers only
#     rais_fte_panel_2010_2022.rds  micro x year x CNAE; fte, vinculos,
#                                   vinculos_3112, wagebill_nominal
#   The last supports a mean wage but carries no education, race or sex. Those
#   need columns 01_extraction.R BLOCK A never pulled.
#
# COMPLEMENTARITY WITH G3
#   G3_arc_shock.R balances the shocks on TRADE characteristics (commodity
#   dummy, log 2010 exports; plus a mechanical set adding log L_j and exports
#   per worker). This script balances on WORKFORCE characteristics. Different
#   tests, both belong in the paper. G4 does not touch anything G3 wrote.
#
# ADDITIVE. Nothing existing is modified. New file, new output directory,
# new audit tags [D-0-*].
# =============================================================================

source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("G4")

RAW_CHARS <- "sector_chars_raw_cnae_2010.rds"   # national, CNAE 2.0 level
TARGET    <- "sector_chars.rds"                 # DATA_DIR root, where 07 looks

# Set TRUE only after reading the dry-run scan estimate printed by STEP 1.
# This query is billed to GCP_BILLING. Do not flip it blind.
CONFIRM_SCAN <- FALSE

# [D-0-1] Education cut. RAIS `grau_instrucao_apos_2005` runs 1..11; 7 is
# completed secondary. "Low education" = strictly below completed secondary.
# A coding choice, not a default. Change here, not inline.
LOWEDUC_MAX <- 6

target_isic <- sort(unique(readRDS("rais_isic_v7.rds")$isic4))
cat("[G4] target industry set:", length(target_isic), "ISIC4 codes\n")

# =============================================================================
# STEP 0 — SCHEMA GUARD
#   basedosdados column names have changed across releases. Fail loudly with
#   the actual field list rather than silently returning zeros.
# =============================================================================
NEEDED <- c("ano", "cnae_2", "vinculo_ativo_3112", "mes_admissao",
            "mes_desligamento", "valor_remuneracao_media",
            "grau_instrucao_apos_2005", "raca_cor", "sexo")

check_schema <- function() {
  if (!requireNamespace("bigrquery", quietly = TRUE)) return(invisible(NULL))
  fl <- try(bigrquery::bq_table_fields(
    bigrquery::bq_table("basedosdados", "br_me_rais", "microdados_vinculos")),
    silent = TRUE)
  if (inherits(fl, "try-error")) {
    cat("[G4] could not read table schema (no credentials?) — continuing\n")
    return(invisible(NULL))
  }
  have <- vapply(fl, function(x) x$name, character(1))
  writeLines(have, file.path(OUT, "G4_available_columns.txt"))
  miss <- setdiff(NEEDED, have)
  if (length(miss)) {
    cat("\n[G4] MISSING COLUMNS:", paste(miss, collapse = ", "), "\n")
    cat("[G4] full field list -> G4_available_columns.txt\n")
    stop("[G4] schema mismatch — fix the query before spending a scan.")
  }
  cat("[G4] schema OK, all", length(NEEDED), "columns present\n")
  invisible(have)
}

# =============================================================================
# STEP 1 — PULL (idempotent; skipped entirely if RAW_CHARS exists)
#
#   Weighted by annualised FTE, identically to 01_extraction.R BLOCK A2, so the
#   characteristics carry the same employment measure as the exposure shares.
#   Weighting by link counts instead would silently reweight seasonal industries.
#
#   Denominators are carried per variable, because item non-response differs
#   across education, race and sex. Do not collapse them into one N.
# =============================================================================
q_chars <- sprintf("
WITH v AS (
  SELECT
    dados.cnae_2 AS cnae_2,
    CASE
      WHEN mes_admissao > 0 AND mes_desligamento > 0
        THEN (mes_desligamento - mes_admissao + 1) / 12.0
      WHEN mes_admissao > 0 AND (mes_desligamento = 0 OR mes_desligamento IS NULL)
        THEN (12 - mes_admissao + 1) / 12.0
      WHEN (mes_admissao = 0 OR mes_admissao IS NULL) AND mes_desligamento > 0
        THEN mes_desligamento / 12.0
      ELSE 1.0 END AS fte,
    SAFE_CAST(dados.grau_instrucao_apos_2005 AS INT64) AS educ,
    SAFE_CAST(dados.raca_cor AS INT64)                 AS raca,
    SAFE_CAST(dados.sexo AS INT64)                     AS sexo,
    dados.valor_remuneracao_media                      AS wage
  FROM `basedosdados.br_me_rais.microdados_vinculos` AS dados
  WHERE dados.ano = 2010
)
SELECT
  cnae_2,
  SUM(fte)                                                          AS fte_total,
  SUM(CASE WHEN educ IS NOT NULL THEN fte ELSE 0 END)               AS fte_educ_known,
  SUM(CASE WHEN educ BETWEEN 1 AND %d THEN fte ELSE 0 END)          AS fte_loweduc,
  SUM(CASE WHEN raca IS NOT NULL AND raca <> 9 THEN fte ELSE 0 END) AS fte_raca_known,
  SUM(CASE WHEN raca = 2 THEN fte ELSE 0 END)                       AS fte_white,
  SUM(CASE WHEN sexo IS NOT NULL THEN fte ELSE 0 END)               AS fte_sexo_known,
  SUM(CASE WHEN sexo = 1 THEN fte ELSE 0 END)                       AS fte_male,
  SUM(CASE WHEN wage > 0 THEN fte * LN(wage) ELSE 0 END)            AS fte_sum_lnwage,
  SUM(CASE WHEN wage > 0 THEN fte ELSE 0 END)                       AS fte_wage_pos
FROM v
GROUP BY cnae_2
", LOWEDUC_MAX)

if (!file.exists(RAW_CHARS)) {
  check_schema()

  if (requireNamespace("bigrquery", quietly = TRUE)) {
    dr <- try(bigrquery::bq_perform_query_dry_run(q_chars, billing = GCP_BILLING),
              silent = TRUE)
    if (!inherits(dr, "try-error"))
      cat(sprintf("[G4] dry run: %.2f GB will be scanned\n", as.numeric(dr) / 2^30))
    else
      cat("[G4] dry run unavailable. Authenticate first, interactively:\n",
          "     bigrquery::bq_auth(email = 'yagoramalho8@gmail.com')\n")
  }

  if (!CONFIRM_SCAN) {
    cat("\n########################################################\n")
    cat("[G4] STOPPING BEFORE THE BILLED QUERY.\n")
    cat("     Read the scan estimate above, then set CONFIRM_SCAN <- TRUE\n")
    cat("     at the top of this script and re-run.\n")
    cat("########################################################\n")
    writeLines("G4 STATUS: awaiting CONFIRM_SCAN", file.path(OUT, "G4_PENDING.txt"))
    quit(save = "no", status = 0)
  }

  library(basedosdados); set_billing_id(GCP_BILLING)
  raw <- read_sql(q_chars) |>
    mutate(cnae_2 = as.character(cnae_2), across(-cnae_2, as.numeric))
  saveRDS(raw, RAW_CHARS)
  cat("[G4] wrote", RAW_CHARS, "|", nrow(raw), "CNAE classes\n")
}

raw <- readRDS(RAW_CHARS)

# ---- sanity: catch a silent categorical-encoding failure ---------------------
# If sexo / raca_cor are stored as labels rather than codes, SAFE_CAST returns
# NULL and these shares collapse to zero. That must not pass quietly.
stopifnot(
  "[G4] sex encoding failed - sexo is probably a label, not a code" =
    sum(raw$fte_male)    / sum(raw$fte_sexo_known) > 0.20,
  "[G4] race encoding failed - raca_cor is probably a label, not a code" =
    sum(raw$fte_white)   / sum(raw$fte_raca_known) > 0.20,
  "[G4] education encoding failed" =
    sum(raw$fte_loweduc) / sum(raw$fte_educ_known) > 0.05
)
cat(sprintf("[G4] national FTE-weighted: male %.3f | white %.3f | loweduc %.3f\n",
            sum(raw$fte_male)    / sum(raw$fte_sexo_known),
            sum(raw$fte_white)   / sum(raw$fte_raca_known),
            sum(raw$fte_loweduc) / sum(raw$fte_educ_known)))

# =============================================================================
# STEP 2 — CNAE-5 -> CNAE-4 -> ISIC-4
#   Replicates 00_epw_calculo_v7.R STEP 5 exactly, including the uniform
#   w_cnae = 1/n split across multi-ISIC CNAE classes. COUNTS (not shares) are
#   carried through the split, so the fractional weights aggregate correctly.
#
#   libxls cannot open the workbook from the decomposed-UTF8 path (revision
#   README quirk 2), so it is copied to an ASCII temp path first.
# =============================================================================
xls_tmp <- file.path(tempdir(), "CNAE20_ISIC4.xls")
stopifnot("[G4] CNAE20_ISIC4.xls not found" = file.exists(paths$cnae_isic))
file.copy(paths$cnae_isic, xls_tmp, overwrite = TRUE)

clean_code <- function(x) gsub("[^0-9]", "", as.character(x))

cnae_isic <- readxl::read_excel(xls_tmp, skip = 1) |>
  janitor::clean_names() |>
  slice(-1) |>
  select(cnae_raw = 1, isic_raw = 3) |>
  filter(!is.na(cnae_raw), !is.na(isic_raw)) |>
  tidyr::separate_rows(isic_raw, sep = ";") |>
  mutate(cnae4 = str_sub(clean_code(cnae_raw), 1, 4),
         isic4 = str_sub(clean_code(isic_raw), 1, 4)) |>
  filter(str_detect(cnae4, "^[0-9]{4}$"), str_detect(isic4, "^[0-9]{4}$")) |>
  select(cnae4, isic4) |>
  distinct()

# =============================================================================
# [D-0-2] CROSSWALK INTEGRITY — ABSOLUTE, NOT COMPARATIVE
#
#   The earlier version of this check compared the fresh build against
#   `cnae_isic_crosswalk 2.rds` and warned on any difference. That check was
#   wrong: the artefact it compares to is itself defective, so it warned on
#   every run.
#
#   DIAGNOSIS. The saved copy holds 1,146 pairs against the fresh build's 743.
#   All 743 are contained in the 1,146, so it is a strict superset with 403
#   spurious pairs, and every one of the 403 is explained by LEFT-PADDING:
#   the old script used str_pad(code, 4, pad = "0") where v7 uses
#   str_sub(code, 1, 4). Padding promotes CNAE and ISIC *aggregates* to fake
#   4-digit *class* codes -- "01" -> "0001", "011" -> "0011". Breakdown of the
#   403: 283 from 3-digit groups, 104 from 2-digit divisions, 8 from 1-digit,
#   8 from blank rows. Hence the impossible codes 0001, 0011, 0025 and the
#   large number of rows where cnae4 == isic4.
#
#   IT IS NOT COSMETIC. The phantom targets inflate the denominator in
#   w_cnae = 1/n() for 10 live classes, e.g. 0111 (2 -> 3), 0121 (3 -> 4),
#   0141 (7 -> 9), 0721 (1 -> 2). Joining to it would misallocate employment.
#
#   PUBLISHED RESULTS ARE UNAFFECTED: v7 rebuilds from the workbook on every
#   run and no script in the tree reads the .rds. It is an orphan from the
#   epw_calculo.r era; the " 2" suffix is macOS duplicate-file naming.
#
#   The check below therefore pins the fresh build against absolute expected
#   values and explicitly rejects the padding failure mode.
# =============================================================================
XW_N_PAIRS <- 743L   # cnae4-isic4 pairs surviving the 4-digit filter
XW_N_CNAE  <- 672L   # distinct CNAE 2.0 classes
XW_N_ISIC  <- 416L   # distinct ISIC rev.4 classes
XW_MAX_N   <- 7L     # largest 1/n split for any single CNAE class

cat(sprintf("[G4] crosswalk: %d pairs | %d cnae4 | %d isic4 | max split 1/%d\n",
            nrow(cnae_isic), n_distinct(cnae_isic$cnae4),
            n_distinct(cnae_isic$isic4),
            max(count(cnae_isic, cnae4)$n)))

stopifnot(
  "[D-0-2] crosswalk pair count changed - the workbook or the parse moved" =
    nrow(cnae_isic) == XW_N_PAIRS,
  "[D-0-2] distinct cnae4 count changed" =
    n_distinct(cnae_isic$cnae4) == XW_N_CNAE,
  "[D-0-2] distinct isic4 count changed" =
    n_distinct(cnae_isic$isic4) == XW_N_ISIC,
  "[D-0-2] implausible 1/n split - padded aggregates have leaked in" =
    max(count(cnae_isic, cnae4)$n) == XW_MAX_N
)

# Direct guard on the padding failure mode. A real CNAE 2.0 class code never
# begins "00"; a real ISIC rev.4 class never does either. If str_pad ever
# replaces str_sub above, these fire immediately.
padded <- cnae_isic |> filter(str_starts(cnae4, "00") | str_starts(isic4, "00"))
if (nrow(padded)) {
  print(padded, n = 30)
  stop("[D-0-2] zero-padded aggregate codes in the crosswalk - the parse is ",
       "promoting sections/divisions/groups to class codes. Use str_sub(x,1,4), ",
       "never str_pad(x,4,pad='0').")
}

# Stale-artefact warning. Nothing reads this file today; flag it so nobody
# joins to it later, and so Packet D never picks it up by name.
if (file.exists("cnae_isic_crosswalk 2.rds")) {
  cat("[G4] NOTE: `cnae_isic_crosswalk 2.rds` is present and is DEFECTIVE",
      "(403 padded pairs). Nothing reads it. Rename or delete it. [D-0-2]\n")
}

cnae_isic_w <- cnae_isic |> group_by(cnae4) |> mutate(w_cnae = 1 / n()) |> ungroup()

CNT <- c("fte_total", "fte_educ_known", "fte_loweduc", "fte_raca_known",
         "fte_white", "fte_sexo_known", "fte_male", "fte_sum_lnwage",
         "fte_wage_pos")

chars_isic <- raw |>
  mutate(cnae4 = str_sub(clean_code(cnae_2), 1, 4)) |>
  group_by(cnae4) |> summarise(across(all_of(CNT), sum), .groups = "drop") |>
  inner_join(cnae_isic_w, by = "cnae4", relationship = "many-to-many") |>
  mutate(across(all_of(CNT), ~ .x * w_cnae)) |>
  group_by(isic4) |> summarise(across(all_of(CNT), sum), .groups = "drop")

# =============================================================================
# STEP 3 — [E-1] IDENTIFIED-COMPOSITE AGGREGATION
#   Reuse the committed map. Do NOT recompute it: the export-side signature
#   that generated it is not reconstructible from this script's inputs.
#
#   [D-0-3] Do not be alarmed that ISIC 0143 is absent from the crosswalk built
#   in STEP 2 while it appears in rais_isic_v7.rds. 0143 is camelid rearing;
#   row 60 of the workbook carries "-" in both CNAE columns because Brazil has
#   no corresponding class, so v7 correctly drops it. It re-enters here as a
#   COMPOSITE LABEL heading the group {0143, 0145, 0146, 0149}, whose other
#   members are reachable from CNAE. The industry-set assertion in STEP 5 runs
#   AFTER this mapping and therefore passes. Do not "fix" STEP 2 to admit it.
# =============================================================================
cmap <- readRDS("composite_map_v7.rds")
chars_comp <- chars_isic |>
  left_join(cmap, by = "isic4") |>
  mutate(isic4 = coalesce(isic_composite, isic4)) |>
  group_by(isic4) |> summarise(across(all_of(CNT), sum), .groups = "drop")

# =============================================================================
# STEP 4 — ASSEMBLE
# =============================================================================
sector_chars <- chars_comp |>
  filter(isic4 %in% target_isic) |>
  transmute(
    isic4,
    sh_loweduc  = fte_loweduc     / fte_educ_known,
    sh_white    = fte_white       / fte_raca_known,
    sh_male     = fte_male        / fte_sexo_known,
    mean_lnwage = fte_sum_lnwage  / fte_wage_pos,
    # diagnostics; harmless to 07 §6, which names its regressors explicitly
    fte_total,
    cov_educ = fte_educ_known / fte_total,
    cov_raca = fte_raca_known / fte_total,
    cov_sexo = fte_sexo_known / fte_total,
    cov_wage = fte_wage_pos   / fte_total)

# =============================================================================
# STEP 5 — VALIDATION
# =============================================================================
missing_isic <- setdiff(target_isic, sector_chars$isic4)
if (length(missing_isic))
  cat("[G4] WARNING - no RAIS characteristics for:",
      paste(missing_isic, collapse = ", "), "\n")

sh_all <- c(sector_chars$sh_loweduc, sector_chars$sh_white, sector_chars$sh_male)
stopifnot(
  "[G4] duplicate isic4"        = !any(duplicated(sector_chars$isic4)),
  "[G4] shares outside [0,1]"   = all(sh_all >= 0 & sh_all <= 1, na.rm = TRUE),
  "[G4] non-finite mean_lnwage" = all(is.finite(sector_chars$mean_lnwage)),
  "[G4] industry set mismatch"  = length(missing_isic) == 0
)

cat("\n=== G4 sector_chars summary ===\n")
print(summary(sector_chars[, 2:5]))
cat(sprintf("[G4] item-response coverage (min): educ %.3f | raca %.3f | sexo %.3f | wage %.3f\n",
            min(sector_chars$cov_educ), min(sector_chars$cov_raca),
            min(sector_chars$cov_sexo), min(sector_chars$cov_wage)))

saveRDS(sector_chars, TARGET)
write_csv(sector_chars, file.path(OUT, "G4_sector_chars.csv"))
cat("[G4] wrote", TARGET, "|", nrow(sector_chars), "industries\n")

# =============================================================================
# STEP 6 — RUN THE TEST THAT WAS DEAD
#   Mirrors 07_regression_inference.R §6 verbatim, including the [A-6] national
#   employment weights, so re-running 07 reproduces this table exactly. Also
#   run on the G3 arc shock, so the two characteristic sets can be read side
#   by side against G3_bhj_balance.csv.
# =============================================================================
shocks_lvl <- readRDS("sectoral_shocks_isic_v7.rds")      # isic4 | year | g_jt
arc_path   <- file.path(REV_DIR("G3"), "G3_shocks_arc.csv")
shocks_arc <- if (file.exists(arc_path))
  read.csv(arc_path, colClasses = c(isic4 = "character")) else NULL

s_nat <- readRDS("rais_isic_v7.rds") |>
  group_by(isic4) |> summarise(L_j = sum(workers), .groups = "drop") |>
  mutate(s_bar = L_j / sum(L_j))                          # [A-6]

run_balance <- function(sh, dv, tag) {
  d <- sh |> inner_join(sector_chars, by = "isic4") |> inner_join(s_nat, by = "isic4")
  map_dfr(c(2014, 2018, 2022), function(t) {
    m <- feols(as.formula(paste(dv, "~ sh_loweduc + sh_white + sh_male + mean_lnwage")),
               data = filter(d, year == t), weights = ~ s_bar)
    f <- fitstat(m, "f")[[1]]
    tibble(spec = tag, shock = dv, year = t,
           F = f$stat, df1 = f$df1, df2 = f$df2, p = f$p, r2 = fixest::r2(m, "r2"))
  })
}

bal <- run_balance(shocks_lvl, "g_jt", "workforce_chars")
if (!is.null(shocks_arc))
  bal <- bind_rows(bal, run_balance(shocks_arc, "g_arc", "workforce_chars"))

cat("\n=== G4 BHJ shock-balance test on WORKFORCE characteristics ===\n")
print(as.data.frame(bal), digits = 4)
write_csv(bal, file.path(OUT, "G4_bhj_balance_workforce.csv"))

cat("\n[G4] done. 07_regression_inference.R §6 now executes its live branch.\n")
