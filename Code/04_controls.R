# =============================================================================
# 04_controls.R  (pipeline stage 2 — index building)
# Builds the 2010 cross-sectional controls per microregion: population,
# urban share, education share, GDP per capita, and manufacturing share.
# Formerly "01_controls_micro.R".
# =============================================================================
source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(tidyverse)
library(sidrar)
library(bigrquery)

billing <- GCP_BILLING


municipios_ibge <- readRDS("municipios_ibge.rds") |>
  mutate(across(any_of(c("municipality_code_ibge", "microregion_code",
                         "mesoregion_code")),
                as.character))
# =============================================================================
# STEP 1 — VERIFY TABLE STRUCTURE (run once; comment out after first run)
#
# info_sidra() prints the full metadata for a table: variable codes,
# classification codes, category codes, and available geographic levels.
# Use this to confirm the variable and category numbers before querying.
# =============================================================================

info_sidra(202)   # Population by situação domicílio
info_sidra(3547)  # Education level (nível de instrução), adults 25+


# =============================================================================
# BLOCK 1 — POPULATION AND URBANISATION
# Sidra Table 202: "População residente, por situação do domicílio e sexo"
# Source: Censo Demográfico 2010 (universe data — full count, not sample)
#
# Variable 93  : População residente (total persons)
# Classification c2: Situação do domicílio
#   Category 2112 = Total | 2113 = Urbana | 2114 = Rural
#   (run info_sidra(202) to confirm exact category codes in your sidrar version)
#
# Queried directly at the MicroRegion level → no municipality aggregation needed.
# =============================================================================

#querying population

# Total population
pop_total_raw <- get_sidra(
  x         = 202,
  variable  = 93,
  period    = "2010",
  geo       = "MicroRegion",
  classific = "c1",
  category  = list(c1 = "0"),      # 0 = Total
  header    = TRUE,
  format    = 3
)

# Urban population
pop_urban_raw <- get_sidra(
  x         = 202,
  variable  = 93,
  period    = "2010",
  geo       = "MicroRegion",
  classific = "c1",
  category  = list(c1 = "1"),      # 1 = Urbana
  header    = TRUE,
  format    = 3
)

# Join and compute shares
pop_micro <- pop_total_raw |>
  select(microregion_code = `Microrregião Geográfica (Código)`,
         pop_total = Valor) |>
  mutate(microregion_code = as.character(microregion_code),
         pop_total = as.numeric(pop_total)) |>
  left_join(
    pop_urban_raw |>
      select(microregion_code = `Microrregião Geográfica (Código)`,
             pop_urban = Valor) |>
      mutate(microregion_code = as.character(microregion_code),
             pop_urban = as.numeric(pop_urban)),
    by = "microregion_code"
  ) |>
  mutate(
    ln_pop      = log(pop_total),
    urban_share = pop_urban / pop_total
  )


# =============================================================================
# BLOCK 2 — EDUCATION SHARE
# Sidra Table 3548: "Pessoas de 25 anos ou mais de idade, por nível de
#   instrução, segundo a situação do domicílio, o sexo e os grupos de idade"
# Source: Censo Demográfico 2010 (sample data — amostra)
#
# Variable 3548 (person count by instruction level)
# Classification c287: Nível de instrução
#   Run info_sidra(3548) to confirm exact category codes. Typical values:
#   93223 = Total
#   93225 = Sem instrução e fundamental incompleto
#   93226 = Fundamental completo e médio incompleto
#   93227 = Médio completo e superior incompleto   ← secondary complete
#   93228 = Superior completo                       ← tertiary complete
#   93229 = Não determinado
#
# Education share = (93227 + 93228) / 93223
#   i.e. share of adults 25+ with at least complete secondary schooling.
# =============================================================================

#querying education




educ_raw <- get_sidra(
  x         = 3547,                    
  variable  = 1643,                
  period    = "2010",
  geo       = "City",
  classific = "c1568",
  category  = list(c1568 = "all"),
  header    = TRUE,
  format    = 3
)


# Check what instruction level labels look like
educ_raw |> distinct(`Nível de instrução`)



#aggregate microregion

educ_micro <- educ_raw |>
  select(
    id_municipio = `Município (Código)`,
    nivel        = `Nível de instrução`,
    pessoas      = Valor
  ) |>
  mutate(
    id_municipio = as.character(id_municipio),
    pessoas      = as.numeric(pessoas),
    category     = case_when(
      nivel == "Total"                                         ~ "total",
      str_detect(nivel, regex("médio completo",    ignore_case = TRUE)) ~ "secondary_plus",
      str_detect(nivel, regex("superior completo", ignore_case = TRUE)) ~ "secondary_plus",
      TRUE ~ NA_character_
    )
  ) |>
  filter(!is.na(category)) |>
  left_join(
    municipios_ibge |> select(municipality_code_ibge, microregion_code),
    by = c("id_municipio" = "municipality_code_ibge")
  ) |>
  group_by(microregion_code, category) |>
  summarise(pessoas = sum(pessoas, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = category, values_from = pessoas) |>
  mutate(educ_share = secondary_plus / total) |>
  select(microregion_code, educ_share)



print(summary(educ_micro$educ_share))



educ_micro |>
  left_join(pop_micro |> select(microregion_code, pop_total), by = "microregion_code") |>
  summarise(weighted_share = sum(educ_share * pop_total, na.rm = TRUE) /
              sum(pop_total,             na.rm = TRUE)) |>
  print()


# =============================================================================
# BLOCK 3 — GDP PER CAPITA
# BigQuery: br_ibge_pib.municipio, ano = 2010
# PIB is in current BRL thousands. Divide by Census population (already
# computed in Block 1) for per capita, then take log.
# CAST AS FLOAT64 avoids the list-column type error.
# =============================================================================

pib_query <- "
SELECT
  id_municipio,
  CAST(pib AS FLOAT64) AS gdp_brl_thousands
FROM `basedosdados.br_ibge_pib.municipio`
WHERE ano = 2010
"

cat("Querying IBGE PIB Municipal 2010...\n")
pib_mun <- bq_project_query(billing, pib_query) |>
  bq_table_download()
cat("PIB rows returned:", nrow(pib_mun), "\n\n")


pib_mun %>% mutate(id_municipio = as.character(id_municipio))

# Aggregate to microregion and compute per capita using Census population


pib_micro <- pib_mun |>
  mutate(id_municipio = as.character(id_municipio)) |>
  left_join(
    municipios_ibge |>
      mutate(municipality_code_ibge = as.character(municipality_code_ibge),
             microregion_code       = as.character(microregion_code)) |>
      select(municipality_code_ibge, microregion_code),
    by = c("id_municipio" = "municipality_code_ibge")
  ) |>
  group_by(microregion_code) |>
  summarise(
    gdp_total_brl = sum(gdp_brl_thousands, na.rm = TRUE),
    .groups = "drop"
  ) |>
  left_join(
    pop_micro |>
      mutate(microregion_code = as.character(microregion_code)) |>
      select(microregion_code, pop_total),
    by = "microregion_code"
  ) |>
  mutate(
    gdp_pc_brl = gdp_total_brl * 1000 / pop_total,
    ln_gdp_pc  = log(gdp_pc_brl)
  ) |>
  select(microregion_code, gdp_pc_brl, ln_gdp_pc)

glimpse(pib_micro)




cat("PIB aggregated:", nrow(pib_micro), "microregions\n")
print(summary(pib_micro[, c("gdp_pc_brl", "ln_gdp_pc")]))
cat("\n")


# =============================================================================
# BLOCK 4 — MANUFACTURING SHARE (from EPW pipeline)
# Formal employment share in ISIC Section C (codes 1000-3399), from RAIS 2010.
# =============================================================================


#manufacturing as a share of tradable formal employment
# [FIX] read the v7 exposure shares so manuf_share is built on the SAME
# industry universe as the treatment (was reading the stale v4 file).
shares <- readRDS("exposure_shares_isic_v7.rds")

manuf_share_micro <- shares |>
  mutate(is_manuf = as.integer(isic4) >= 1000 & as.integer(isic4) <= 3399) |>
  group_by(micro) |>
  summarise(
    L_manuf      = sum(L_rj_2010[is_manuf], na.rm = TRUE),
    L_total_rais = sum(L_rj_2010,           na.rm = TRUE),
    manuf_share  = L_manuf / L_total_rais,
    .groups = "drop"
  )

cat("Manufacturing share computed for", nrow(manuf_share_micro), "microregions\n")
print(summary(manuf_share_micro$manuf_share))
cat("\n")


# =============================================================================
# STEP 5 — COMBINE ALL CONTROLS INTO ONE MICROREGION TABLE
# =============================================================================

controls_micro <- pop_micro |>
  mutate(micro = as.character(microregion_code)) |>
  select(micro, pop_total, ln_pop, urban_share) |>
  left_join(
    educ_micro |>
      mutate(micro = as.character(microregion_code)) |>
      select(micro, educ_share),
    by = "micro"
  ) |>
  left_join(
    pib_micro |>
      mutate(micro = as.character(microregion_code)) |>
      select(micro, gdp_pc_brl, ln_gdp_pc),
    by = "micro"
  ) |>
  left_join(
    manuf_share_micro |>
      mutate(micro = as.character(micro)) |>
      select(micro, manuf_share),
    by = "micro"
  )




cat("Final controls table:", nrow(controls_micro), "microregions |",
    ncol(controls_micro), "columns\n\n")

cat("Coverage check (NAs per variable):\n")
controls_micro |>
  summarise(across(everything(), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") |>
  print()

cat("\nDistributions:\n")
controls_micro |>
  select(-micro) |>
  summary() |>
  print()


# =============================================================================
# STEP 6 — SAVE
# =============================================================================

saveRDS(controls_micro, "controls_micro.rds")
write_csv(controls_micro,  "controls_micro.csv")

