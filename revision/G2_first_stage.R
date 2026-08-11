# =============================================================================
# G2 — labour-market first stage. Referee item R1-M5.
#
# STATUS: BLOCKED ON DATA, not on code. See the audit below.
#
# The first stage requires microregional formal employment / wage bill in the
# ELECTION years 2014, 2018 and 2022, differenced against 2010. The repository
# contains RAIS for 2010 ONLY:
#     rais_fte.rds        (2010, microregion x CNAE 2.0, annualised FTE)
#     rais_2010_micro.rds (2010, microregion x CNAE 2.0, 31/12 headcount)
#     rais_isic_v7.rds    (2010, microregion x ISIC 4, derived from the above)
# 01_extraction.R BLOCK A hard-codes `WHERE dados.ano = 2010` in both RAIS
# queries, so no post-2010 extract has ever been produced by this pipeline.
# Nor does any other local file carry post-2010 employment (checked: the whole
# data tree contains no CAGED, PNAD or multi-year RAIS artefact).
#
# The pull is a BigQuery query against `basedosdados.br_me_rais.microdados_vinculos`
# billed to GCP project GCP_BILLING. It cannot run in this session: bigrquery
# reports "Can't get Google credentials" because the OAuth flow is interactive
# and this is a non-interactive session. A dry run to price the scan is
# therefore also unavailable.
#
# WHAT TO RUN to unblock, from an interactive R session:
#     bigrquery::bq_auth(email = "yagoramalho8@gmail.com")   # once
#     Rscript códigos/revision/G2_first_stage.R
# The script below then executes end to end. Everything after the pull is
# written and tested against the 2010 slice; only the extract is missing.
#
# INFORMALITY PROXY: none exists in the current data build. Per the task file
# ("if not, say so, do not construct a new one") nothing is constructed here.
# RAIS covers formal employment only; an informality rate needs PNAD/Census
# denominators that are not in the repo.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("G2")
B_RI <- 9999

RAIS_PANEL <- "rais_fte_panel_2010_2022.rds"   # produced by the pull below

# ---- audit: what employment data actually exists ----------------------------
emp_files <- c("rais_fte.rds", "rais_2010_micro.rds", "rais_isic_v7.rds", RAIS_PANEL)
audit <- tibble(file = emp_files) |>
  mutate(exists = file.exists(file),
         years  = map_chr(file, function(f) {
           if (!file.exists(f)) return(NA_character_)
           x <- readRDS(f)
           if ("year" %in% names(x)) paste(sort(unique(x$year)), collapse = ", ")
           else if ("ano" %in% names(x)) paste(sort(unique(x$ano)), collapse = ", ")
           else "no year column (single cross-section, 2010 by construction)"
         }))
cat("\n=== G2 employment-data audit ===\n"); print(as.data.frame(audit))
write_csv(audit, file.path(OUT, "G2_employment_data_audit.csv"))

# =============================================================================
# STEP 1 — RAIS PULL (2010, 2014, 2018, 2022).  Runs only if authenticated.
# =============================================================================
if (!file.exists(RAIS_PANEL)) {
  ok <- requireNamespace("basedosdados", quietly = TRUE) &&
    !inherits(try({
      bigrquery::bq_perform_query_dry_run(
        "SELECT 1", billing = GCP_BILLING)
    }, silent = TRUE), "try-error")

  if (!ok) {
    cat("\n############################################################\n")
    cat("[G2] BLOCKED: no BigQuery credentials in this session and no\n")
    cat("     local post-2010 RAIS extract. The first stage CANNOT be\n")
    cat("     estimated. Run bq_auth() interactively, then re-run.\n")
    cat("############################################################\n")
    writeLines(c(
      "G2 STATUS: BLOCKED",
      "Reason: microregional formal employment exists for 2010 only.",
      "01_extraction.R BLOCK A pins `WHERE dados.ano = 2010` in both RAIS queries.",
      "No local file carries post-2010 employment (full data tree checked).",
      "BigQuery credentials unavailable non-interactively (bq_auth is an OAuth flow).",
      "Unblock: bigrquery::bq_auth(email='yagoramalho8@gmail.com') then re-run this script.",
      "Informality proxy: does not exist in the current build; none constructed."),
      file.path(OUT, "G2_BLOCKED.txt"))
    quit(save = "no", status = 0)
  }

  library(basedosdados)
  set_billing_id(GCP_BILLING)

  # Same FTE definition as 01_extraction.R BLOCK A2, generalised to four years,
  # and carrying the wage bill so that the wage-bill and mean-wage first stages
  # come from one scan rather than three.
  q <- "
  SELECT
    dados.ano, dados.id_municipio, dados.cnae_2,
    SUM(CASE
      WHEN mes_admissao > 0 AND mes_desligamento > 0
        THEN (mes_desligamento - mes_admissao + 1) / 12.0
      WHEN mes_admissao > 0 AND (mes_desligamento = 0 OR mes_desligamento IS NULL)
        THEN (12 - mes_admissao + 1) / 12.0
      WHEN (mes_admissao = 0 OR mes_admissao IS NULL) AND mes_desligamento > 0
        THEN mes_desligamento / 12.0
      ELSE 1.0 END) AS total_fte,
    COUNT(*) AS total_vinculos,
    SUM(CASE WHEN vinculo_ativo_3112 = '1' THEN 1 ELSE 0 END) AS vinculos_3112,
    SUM(valor_remuneracao_media) AS wagebill_nominal
  FROM `basedosdados.br_me_rais.microdados_vinculos` AS dados
  WHERE dados.ano IN (2010, 2014, 2018, 2022)
  GROUP BY dados.ano, dados.id_municipio, dados.cnae_2
  "
  raw <- read_sql(q)
  municipios <- readRDS(paths$municipios)
  panel <- raw |>
    mutate(across(c(total_fte, total_vinculos, vinculos_3112, wagebill_nominal), as.numeric),
           id_municipio = as.character(id_municipio)) |>
    left_join(municipios, by = c("id_municipio" = "municipality_code_ibge")) |>
    group_by(micro = as.character(microregion_code), year = as.integer(ano), cnae_2) |>
    summarise(across(c(total_fte, total_vinculos, vinculos_3112, wagebill_nominal), sum),
              .groups = "drop")
  saveRDS(panel, RAIS_PANEL)
  cat("[G2] wrote", RAIS_PANEL, "\n")
}

panel <- readRDS(RAIS_PANEL)

# =============================================================================
# STEP 2 — microregional outcomes, differenced 2010 -> t, tradable split by the
# SAME CNAE -> ISIC map the treatment uses (so "tradables" means the same thing
# in the first stage and in the shock).
# =============================================================================
# NOTE: libxls cannot open a file whose path contains the decomposed-UTF8
# "dissertação"/"versão" segments on this machine, so the workbook is copied to
# an ASCII temp path before reading. Parsing then replicates 03 exactly
# (skip = 1, drop the second header row, columns 1 and 3, split ";" multi-maps,
# 4-digit truncation, uniform 1/n weights across a CNAE class's ISIC matches).
clean_code <- function(x) as.character(x) |> str_trim() |> str_remove_all("[.\\-/ ]")
xls_tmp <- file.path(tempdir(), "CNAE20_ISIC4.xls")
file.copy(paths$cnae_isic, xls_tmp, overwrite = TRUE)
cnae_isic <- suppressWarnings(readxl::read_excel(xls_tmp, skip = 1)) |>
  janitor::clean_names() |> slice(-1) |>
  select(cnae_raw = 1, isic_raw = 3) |>
  filter(!is.na(cnae_raw), !is.na(isic_raw)) |>
  tidyr::separate_rows(isic_raw, sep = ";") |>
  mutate(cnae4 = str_sub(clean_code(cnae_raw), 1, 4),
         isic4 = str_sub(clean_code(isic_raw), 1, 4)) |>
  filter(str_detect(cnae4, "^[0-9]{4}$"), str_detect(isic4, "^[0-9]{4}$")) |>
  distinct(cnae4, isic4) |>
  group_by(cnae4) |> mutate(w_cnae = 1 / n()) |> ungroup()

tradable_isic <- unique(readRDS("rais_isic_v7.rds")$isic4)   # composite groups
composite_map <- readRDS("composite_map_v7.rds")

panel <- panel |>
  mutate(cnae4 = str_sub(clean_code(cnae_2), 1, 4)) |>
  left_join(cnae_isic, by = "cnae4", relationship = "many-to-many") |>
  left_join(composite_map |> select(isic4, isic_composite), by = "isic4") |>
  mutate(w_cnae = replace_na(w_cnae, 1),
         isic_group = coalesce(isic_composite, isic4),
         is_tradable = !is.na(isic_group) & isic_group %in% tradable_isic)

cat(sprintf("\n[G2] CNAE->ISIC map: %d cnae4 classes, %d ISIC classes; %.1f%% of 2010 FTE tradable\n",
            n_distinct(cnae_isic$cnae4), n_distinct(cnae_isic$isic4),
            100 * with(filter(panel, year == 2010),
                       sum(total_fte * w_cnae * is_tradable) / sum(total_fte * w_cnae))))

agg <- panel |> group_by(micro, year) |>
  summarise(emp_total    = sum(total_fte * w_cnae),
            emp_tradable = sum(total_fte * w_cnae * is_tradable),
            wagebill     = sum(wagebill_nominal * w_cnae),
            .groups = "drop") |>
  mutate(mean_wage = wagebill / emp_total)

# deflate the wage bill and mean wage to constant 2010 BRL if an IPCA series is
# available locally; otherwise report nominal and say so.
cat("\n[G2] NOTE: wage variables are NOMINAL BRL (no local deflator series).\n")

base <- agg |> filter(year == 2010) |>
  select(micro, emp_total_0 = emp_total, emp_tradable_0 = emp_tradable,
         wagebill_0 = wagebill, mean_wage_0 = mean_wage)

fs <- agg |> filter(year != 2010) |> left_join(base, by = "micro") |>
  transmute(micro, year,
            d_ln_emp        = log(emp_total)    - log(emp_total_0),
            d_ln_emp_trad   = log(emp_tradable) - log(emp_tradable_0),
            d_ln_wagebill   = log(wagebill)     - log(wagebill_0),
            d_mean_wage     = mean_wage - mean_wage_0,
            d_ln_mean_wage  = log(mean_wage)    - log(mean_wage_0))

d_fs <- df_scaled |> select(micro, year, delta_EPW, delta_EPW_raw, state,
                            mesoregion_code, all_of(ctrl_ext)) |>
  inner_join(fs, by = c("micro", "year"))
fs_outcomes <- c("d_ln_emp", "d_ln_emp_trad", "d_ln_wagebill",
                 "d_mean_wage", "d_ln_mean_wage")
d_fs <- d_fs |> mutate(across(all_of(fs_outcomes), ~ as.numeric(scale(.)),
                              .names = "{.col}_z"))
stopifnot(nrow(d_fs) == nrow(df_scaled))

# =============================================================================
# STEP 3 — estimate, identical specification to the main results
# =============================================================================
d_fs <- d_fs |> mutate(epw_boom = pmax( delta_EPW_raw, 0) / sd_epw,
                       epw_bust = pmax(-delta_EPW_raw, 0) / sd_epw)

est <- map_dfr(fs_outcomes, function(oc) {
  map_dfr(c("base", "ext"), function(ck) {
    ctrls <- if (ck == "base") ctrl_base else ctrl_ext
    cz <- paste(ctrls, collapse = " + ")
    ocz <- paste0(oc, "_z")
    mp <- feols(as.formula(paste(ocz, "~ delta_EPW +", cz, "| state^year")),
                data = d_fs, cluster = ~ mesoregion_code^year)
    md <- feols(as.formula(paste(ocz, "~ epw_boom + epw_bust +", cz, "| state^year")),
                data = d_fs, cluster = ~ mesoregion_code^year)
    b <- coef(md)[c("epw_boom", "epw_bust")]
    V <- vcov(md)[c("epw_boom", "epw_bust"), c("epw_boom", "epw_bust")]
    cc <- sum(b); s <- sqrt(sum(V))
    bind_rows(
      tibble(outcome = oc, ctrls = ck, term = "pooled", beta = coef(mp)[["delta_EPW"]],
             se = se(mp)[["delta_EPW"]], n = nobs(mp),
             within_r2 = fitstat(mp, "wr2")$wr2),
      tibble(outcome = oc, ctrls = ck, term = "boom", beta = b[["epw_boom"]],
             se = se(md)[["epw_boom"]], n = nobs(md), within_r2 = fitstat(md, "wr2")$wr2),
      tibble(outcome = oc, ctrls = ck, term = "bust", beta = b[["epw_bust"]],
             se = se(md)[["epw_bust"]], n = nobs(md), within_r2 = fitstat(md, "wr2")$wr2),
      tibble(outcome = oc, ctrls = ck, term = "symmetry", beta = cc, se = s,
             n = nobs(md), within_r2 = NA_real_,
             p_sym = 2 * pt(-abs(cc / s), df = fixest::degrees_freedom(md, type = "t"))))
  })
})

# ---- RI, same permutation scheme --------------------------------------------
ri_fs <- function(ctrls) {
  set.seed(2026)
  cz <- paste(ctrls, collapse = " + ")
  t(replicate(B_RI, {
    raw <- make_epw_star(sample(nrow(g_mat)))
    d <- d_fs |> mutate(epw_star  = raw / sd_epw,
                        boom_star = pmax( raw, 0) / sd_epw,
                        bust_star = pmax(-raw, 0) / sd_epw)
    unlist(lapply(fs_outcomes, function(oc) {
      p <- coef(feols(as.formula(paste0(oc, "_z ~ epw_star + ", cz, " | state^year")),
                      data = d, lean = TRUE))
      a <- coef(feols(as.formula(paste0(oc, "_z ~ boom_star + bust_star + ", cz,
                                        " | state^year")), data = d, lean = TRUE))
      setNames(c(p[["epw_star"]], a[["boom_star"]], a[["bust_star"]]),
               paste0(oc, c("_pooled", "_boom", "_bust")))
    }))
  }))
}
cat("\n[G2] running RI (base controls)...\n");  ri_b <- ri_fs(ctrl_base)
cat("[G2] running RI (ext controls)...\n");     ri_e <- ri_fs(ctrl_ext)
saveRDS(list(base = ri_b, ext = ri_e), file.path(OUT, "G2_ri.rds"))

est <- est |> rowwise() |>
  mutate(ri_p = { k <- paste0(outcome, "_", term)
                  m <- if (ctrls == "base") ri_b else ri_e
                  if (!k %in% colnames(m)) NA_real_ else p_ri(m[, k], beta) },
         ri_sd = { k <- paste0(outcome, "_", term)
                   m <- if (ctrls == "base") ri_b else ri_e
                   if (!k %in% colnames(m)) NA_real_ else sd(m[, k]) }) |>
  ungroup() |> mutate(sd_ratio = ri_sd / se)

cat("\n=== G2 FIRST STAGE ===\n")
print(as.data.frame(est), digits = 4)

# raw-unit version of the pooled employment coefficient, for magnitude reading
mraw <- feols(d_ln_emp ~ delta_EPW + ln_gdp_pc + ln_pop + tradable_emp_share |
                state^year, data = d_fs, cluster = ~ mesoregion_code^year)
cat("\n=== G2 magnitude: log employment (raw LHS) per SD of exposure ===\n")
print(summary(mraw))

write_csv(est, file.path(OUT, "G2_first_stage.csv"))
write_csv(d_fs |> select(micro, year, all_of(fs_outcomes), delta_EPW_raw),
          file.path(OUT, "G2_first_stage_panel.csv"))
cat("\n[G2] wrote", OUT, "\n")
