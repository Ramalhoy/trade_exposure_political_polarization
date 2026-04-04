library(electionsBR)
library(dplyr)
library(tidyr)
library(stringr)
library(readr)
library(sidrar)
library(writexl)
library(lubridate)
library(geobr)
library(jsonlite)

setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")

# Coleta de dados anual
years <- c(2010, 2014, 2018, 2022)

panel_raw <- lapply(years, \(y) {
  elections_tse(
    year       = y,
    type       = "vote_mun_zone",
    br_archive = TRUE
  ) |>
    filter(DS_CARGO == "Presidente") |>
    distinct(NR_TURNO, CD_MUNICIPIO, NR_ZONA, NM_CANDIDATO, SG_PARTIDO,
             QT_VOTOS_NOMINAIS, .keep_all = TRUE) |>  # <-- deduplica por chave natural
    transmute(
      year              = y,
      candidato         = NM_CANDIDATO,
      round             = as.integer(NR_TURNO),
      municipality      = as.character(NM_MUNICIPIO),
      municipality_code = as.character(CD_MUNICIPIO),
      state             = SG_UF,
      party             = SG_PARTIDO,
      votes             = as.numeric(QT_VOTOS_NOMINAIS)
    )
}) |>
  bind_rows()


#painel em formato longo
panel_mun <- panel_raw |>
  group_by(
    year,
    round,
    municipality_code,
    municipality,
    state,
    party,
    candidato
  ) |>
  summarise(
    votes = sum(votes, na.rm = TRUE),
    .groups = "drop"
  )

#salvando painel
write_xlsx(panel_mun,"painel_votos_presidenciais_2010_2022.xlsx")



panel_mun <- read_excel("painel_votos_presidenciais_2010_2022.xlsx")




## MAPEAMENTO TSE -> IBGE -> MICRORREGIÃO


# 1. Tabela de equivalência TSE <-> IBGE

###revisar
depara <- read.csv(
  "https://raw.githubusercontent.com/yuripassuelo/codigos_mun_tse_ibge/master/relacao_mun_tse_ibge.csv",
  encoding = "UTF-8"
) |>
  select(
    municipality_code      = cd_mun_tse,
    municipality_code_ibge = cd_mun_ibge
  ) |>
  mutate(
    municipality_code      = as.character(municipality_code),
    municipality_code_ibge = as.character(municipality_code_ibge)
  )

# 2. Municípios do IBGE com microrregião
municipios_ibge <- fromJSON(
  "https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado"
) |>
  select(
    municipality_code_ibge = `municipio-id`,
    municipality_name = `municipio-nome`,
    microregion_code       = `microrregiao-id`,
    microregion_name       = `microrregiao-nome`,
    UF = `UF-sigla`,
    intermediary_region_code = `regiao-intermediaria-id`
  ) |>
  mutate(municipality_code_ibge = as.character(municipality_code_ibge))


# 3. Remove municípios do exterior 
panel_mun <- panel_mun |>
  filter(!state %in% c("ZZ", "VT")) |> ##conferir número de votos considerando ZZ
  mutate(municipality_code = as.character(as.integer(municipality_code)))

# 4. Junta: TSE -> IBGE -> microrregião
mapeamento <- depara |>
  left_join(municipios_ibge, by = "municipality_code_ibge")




##checagem

# Verifica duplicatas na tabela de equivalência
depara |>
  count(municipality_code) |>
  filter(n > 1)

# Verifica duplicatas no mapeamento final
mapeamento |>
  count(municipality_code) |>
  filter(n > 1)

municipios_ibge |>
  count(municipality_code_ibge) |>
  filter(n > 1)

nrow(municipios_ibge)       # deve ser ~5570
n_distinct(municipios_ibge$municipality_code_ibge)  # deve ser igual


#uniocidade do mapeamento

mapeamento <- depara |>
  mutate(municipality_code = as.character(as.integer(municipality_code))) |>  # <-- mesma lógica
  left_join(
    municipios_ibge |> distinct(municipality_code_ibge, .keep_all = TRUE),
    by = "municipality_code_ibge"
  )




## PAINEL POR MICRORREGIÃO

# 5. Cruza com o painel e agrega por microrregião
panel_micro <- panel_mun |>
  left_join(mapeamento, by = "municipality_code") |>
  summarise(
    votes = sum(votes, na.rm = TRUE),
    .by   = c(year, round, microregion_code, microregion_name, party, candidato, state)
  )

# 6. Verifica NAs
panel_mun |>
  left_join(mapeamento, by = "municipality_code") |>
  filter(is.na(microregion_code)) |>
  distinct(municipality_code, municipality, state)


#salvando
write_xlsx(panel_micro, "painel_votos_presidenciais_microregioes_2010_2022.xlsx")


saveRDS(panel_micro, "painel_votos_presidenciais_microregioes_2010_2022.rds")
painel_votos <- readRDS("painel_votos_presidenciais_microregioes_2010_2022.rds")



# Verifica se há valores sem microrregião
sum(is.na(painel_votos$microregion_code)) #não há


panel_mun |>
  group_by(year, round) |>
  summarise(total = sum(votes), .groups = "drop")

painel_votos |>
  group_by(year, round) |>
  summarise(total = sum(votes), .groups = "drop")


panel_mun |>
  left_join(mapeamento, by = "municipality_code") |>
  filter(is.na(microregion_code)) |>
  summarise(votos_perdidos = sum(votes))




# Como os códigos estão no panel_mun
panel_mun |> distinct(municipality_code) |> head(20)

# Como estão no mapeamento
mapeamento |> distinct(municipality_code) |> head(20)

# Quantos códigos de panel_mun existem no mapeamento?
panel_mun |>
  distinct(municipality_code) |>
  summarise(
    total = n(),
    com_match = sum(municipality_code %in% mapeamento$municipality_code),
    sem_match = sum(!municipality_code %in% mapeamento$municipality_code)
  )
