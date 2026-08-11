# =============================================================================
# H3 — environment freeze. Records R, package versions and input provenance.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/revision/R00_setup.R")
OUT <- REV_DIR("H3")

pkgs <- c("tidyverse", "dplyr", "tidyr", "purrr", "fixest", "ShiftShareSE",
          "geobr", "sf", "concordance", "basedosdados", "bigrquery",
          "readxl", "writexl", "ggplot2")
ver <- vapply(pkgs, function(p)
  tryCatch(as.character(utils::packageVersion(p)), error = function(e) "NOT INSTALLED"),
  character(1))

inputs <- c("df_estimation_v7.rds", "exposure_shares_isic_v7.rds",
            "sectoral_shocks_isic_v7.rds", "epw_panel_isic_v7.rds",
            "tradable_emp_share_2010_v7.rds", "rais_fte.rds",
            "rais_isic_v7.rds", "exports_national_ncm.rds",
            "dalton_panel_presidencial.rds",
            "painel_votos_presidenciais_microregioes_2010_2022.rds",
            "bls9_estimates_partiespresidents_long.rds",
            "un_hs2012_isic4_weighted.csv", "CNAE20_ISIC4.xls",
            "micro_centroids.rds", "controls_micro.rds")
inp <- tibble(file = inputs) |>
  mutate(exists = file.exists(file),
         mtime  = if_else(exists, format(file.mtime(file), "%Y-%m-%d %H:%M"), NA_character_),
         md5    = if_else(exists, tools::md5sum(file), NA_character_),
         bytes  = if_else(exists, file.size(file), NA_real_))

env <- tibble(item = c("R version", "platform", "SHARE_DENOM", "DATA_DIR",
                       "RI B", "RI seed", "FE", "cluster",
                       "RAIS extract (rais_fte.rds mtime)",
                       "RAIS reference year (data content)"),
              value = c(R.version.string, R.version$platform, SHARE_DENOM, DATA_DIR,
                        "9999", "2026", "state^year", "mesoregion_code^year",
                        format(file.mtime("rais_fte.rds"), "%Y-%m-%d %H:%M"),
                        "2010 only — no post-2010 RAIS extract is present locally"))

cat("\n=== H3 ENVIRONMENT ===\n"); print(as.data.frame(env))
cat("\n=== PACKAGE VERSIONS ===\n"); print(data.frame(package = pkgs, version = ver))
cat("\n=== INPUT PROVENANCE ===\n"); print(as.data.frame(inp))

write_csv(env, file.path(OUT, "H3_environment.csv"))
write_csv(tibble(package = pkgs, version = ver), file.path(OUT, "H3_packages.csv"))
write_csv(inp, file.path(OUT, "H3_inputs.csv"))
writeLines(capture.output(sessionInfo()), file.path(OUT, "H3_sessionInfo.txt"))
cat("\n[H3] wrote", OUT, "\n")
