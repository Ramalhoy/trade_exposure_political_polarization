# =============================================================================
# packet_I/I8_governor_min.R  —  [I-8] WHAT THE GOVERNOR TRACK WOULD NEED.
#
# READ-ONLY. This script builds NOTHING. 06b/07b depend on four artefacts that
# do not exist in this data directory because 03a and 03d have never run here.
# The packet's instruction is explicit: do not try to reconstruct them; state the
# minimum required to run 07b with the EXPORT treatment alone, and stop for a
# decision.
#
# It therefore (1) verifies the inventory rather than trusting it, (2) resolves
# each missing artefact to the stage that writes it and checks whether THAT
# stage's own inputs are present, (3) tests the one environmental obstacle on
# record (revision/README quirk 2: libxls reportedly cannot open
# CNAE20_ISIC4.xls from this path), and (4) lists the code changes an
# export-only 07b would need, since 06b and 07b both read the import artefacts
# unconditionally.
# =============================================================================
source("/Users/solenoide/Documents/dissertação/data/códigos/packet_I/I0_setup.R")
OUT <- I_DIR("I8")
log_con <- file(file.path(OUT, "I8_governor_min_log.txt"), open = "wt"); sink(log_con, split = TRUE)
cat("=== I8 governor minimum:", format(Sys.time()), "===\n\n")

inv <- tribble(
  ~artefato,                          ~escrito_por, ~exigido_por,          ~canal,
  "epw_common_panel_v8.rds",          "03a",        "06b, 07b",            "exportacao",
  "exposure_shares_common_v8.rds",    "03a",        "07b",                 "exportacao",
  "share_sum_theta_common_v9.rds",    "03a",        "06b (ss_bhj_control)","exportacao",
  "rais_isic_full_tradable_v8.rds",   "03a",        "03d",                 "exportacao",
  "ipw_panel_isic_v1.rds",            "03d",        "06b",                 "importacao",
  "sectoral_import_shocks_v1.rds",    "03d",        "07b",                 "importacao",
  "df_estimation_gov_v1.rds",         "06b",        "07b",                 "-",
  "governor_coverage_stateyear.rds",  "06b",        "07b (regra amostral)","-") |>
  mutate(existe = file.exists(artefato))

deps_03a <- c("rais_fte.rds", "CNAE20_ISIC4.xls", "ncm_isic_match_v7.rds",
              "composite_map_v7.rds", "sectoral_shocks_isic_v7.rds",
              "epw_panel_isic_v7.rds")
deps_03d <- c("imports_national_ncm.rds", "ncm_isic_match_v7.rds", "composite_map_v7.rds",
              "exposure_shares_common_v8.rds", "rais_isic_full_tradable_v8.rds")
deps_06b <- c("dalton_panel_governador.rds", "painel_ideologico_governador.rds",
              "epw_common_panel_v8.rds", "ipw_panel_isic_v1.rds", "controls_micro.rds")
deps_07b <- c("df_estimation_gov_v1.rds", "exposure_shares_common_v8.rds",
              "sectoral_shocks_isic_v7.rds", "sectoral_import_shocks_v1.rds",
              "epw_common_panel_v8.rds", "micro_centroids.rds")
dep_tbl <- bind_rows(
  tibble(estagio = "03a", input = deps_03a), tibble(estagio = "03d", input = deps_03d),
  tibble(estagio = "06b", input = deps_06b), tibble(estagio = "07b", input = deps_07b)) |>
  mutate(existe = file.exists(input))

cat("=== I8(1) artefactos do trilho governador ===\n"); print(as.data.frame(inv))
cat("\n=== I8(2) inputs de cada estagio ===\n"); print(as.data.frame(dep_tbl))
cat("\n--- resumo ---\n")
print(as.data.frame(dep_tbl |> group_by(estagio) |>
  summarise(inputs = n(), presentes = sum(existe),
            faltando = paste(input[!existe], collapse = ", "), .groups = "drop")))

# ---- the one environmental obstacle on record -------------------------------
cat("\n=== I8(3) libxls / CNAE20_ISIC4.xls (revision/README quirk 2) ===\n")
direct <- try(suppressMessages(readxl::read_excel("CNAE20_ISIC4.xls", skip = 1, n_max = 5)),
              silent = TRUE)
tmp <- file.path(tempdir(), "cnae_ascii.xls")
file.copy("CNAE20_ISIC4.xls", tmp, overwrite = TRUE)
viatmp <- try(suppressMessages(readxl::read_excel(tmp, skip = 1, n_max = 5)), silent = TRUE)
cat(sprintf("leitura direta do DATA_DIR: %s\nleitura via copia ASCII:    %s\n",
            if (inherits(direct, "try-error")) "FALHA" else "OK",
            if (inherits(viatmp, "try-error")) "FALHA" else "OK"))
cat(sprintf("locale: LC_ALL=%s LANG=%s LC_CTYPE=%s\n",
            Sys.getenv("LC_ALL"), Sys.getenv("LANG"), Sys.getlocale("LC_CTYPE")))
if (!inherits(direct, "try-error"))
  cat("=> sob locale UTF-8 a leitura direta funciona; a quirk 2 do revision/README\n",
      "   e dependente de locale, nao um bloqueio. 03a e executavel nesta maquina.\n")

# ---- what an export-only 07b would still need -------------------------------
gate <- tribble(
  ~item, ~tipo, ~detalhe,
  "rodar 03a_shares_common.R", "execucao",
  "entradas todas presentes; escreve os quatro artefactos de shares comuns (canal exportacao)",
  "06b: leitura de ipw_panel_isic_v1.rds", "edicao de codigo",
  "06b:51 le o painel IPW e 06b:128 seleciona IPW_total/final/interm/capital/china/IV; sem 03d o join precisa ser condicional",
  "07b: leitura de sectoral_import_shocks_v1.rds", "edicao de codigo",
  "07b:49 e o bloco conjunto EPW+IPW e a exposicao liquida (07b:99-100, 148-190) dependem do choque de importacao",
  "07b: RI conjunta EPW+IPW", "edicao de codigo",
  "ss_ri e chamada com list(EPW, IPW); a versao so-exportacao passa apenas EPW",
  "02: indice governador sob a variante escolhida", "execucao",
  "dalton_panel_governador.rds e painel_ideologico_governador.rds existem sob V0; a variante do Packet I precisa ser reconstruida antes de 06b")
cat("\n=== I8(4) minimo para rodar 07b so com o tratamento de exportacao ===\n")
print(as.data.frame(gate))

cat("\n=== I8(5) o que NAO e recuperavel sem decisao ===\n")
cat("03d exige imports_national_ncm.rds (existe: ", file.exists("imports_national_ncm.rds"),
    ") e BACI HS07 (extracao externa). O canal de importacao esta fora do escopo\n",
    "deste pacote de qualquer forma: [I-8] pede apenas o tratamento de exportacao.\n", sep = "")

write_csv(inv,     file.path(OUT, "I8_artefact_inventory.csv"))
write_csv(dep_tbl, file.path(OUT, "I8_stage_inputs.csv"))
write_csv(gate,    file.path(OUT, "I8_minimum_to_run_07b.csv"))
cat("\n[I8] wrote", OUT, "\n")
cat("\n[I-8] STOP: nenhuma reconstrucao tentada. Decisao pendente do orientador/autor.\n")
sink(); close(log_con)
