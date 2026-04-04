library(basedosdados)
library(jsonlite)
library(dplyr)
library(writexl)

#projeto no google studio
set_billing_id("gen-lang-client-0768793544")

setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")

# Query para coletar apenas os vínculos empregatícios em 2010
#inclui CNAE 2.0 para match com os demais dados

query <- "
SELECT 
  dados.ano,
  dados.sigla_uf,
  dados.id_municipio,
  diretorio_id_municipio.nome AS municipio_nome,
  dados.cnae_2,
  dados.cnae_2_subclasse,
  diretorio_cnae.descricao_classe AS cnae_descricao,
  COUNT(*) as total_vinculos
FROM `basedosdados.br_me_rais.microdados_vinculos` AS dados
LEFT JOIN `basedosdados.br_bd_diretorios_brasil.municipio` AS diretorio_id_municipio 
  ON dados.id_municipio = diretorio_id_municipio.id_municipio
LEFT JOIN `basedosdados.br_bd_diretorios_brasil.cnae_2` AS diretorio_cnae
  ON dados.cnae_2_subclasse = diretorio_cnae.subclasse
WHERE dados.ano = 2010
  AND dados.vinculo_ativo_3112 = '1'  -- Apenas vínculos ativos em 31/12
GROUP BY 
  dados.ano,
  dados.sigla_uf,
  dados.id_municipio,
  diretorio_id_municipio.nome,
  dados.cnae_2,
  dados.cnae_2_subclasse,
  diretorio_cnae.descricao_classe
"

# Registrando
rais_2010 <- read_sql(query)

# 
rais_2010 <- rais_2010 |>
  mutate(total_vinculos = as.numeric(total_vinculos))  

# Estrutura
names(rais_2010)
head(rais_2010, 20)
nrow(rais_2010) 

# Verifica se tem NAs em colunas importantes
rais_2010 |>
  summarise(
    na_municipio = sum(is.na(id_municipio)),
    na_cnae = sum(is.na(cnae_2)),
    na_vinculos = sum(is.na(total_vinculos))
  )


saveRDS(rais_2010, "rais_2010.rds")

##conversão para microrregião 
#basicamente o exercício que será repetido nos demais casos

# 1. Baixa municípios do IBGE com ID de microrregião
municipios_ibge <- fromJSON(
  "https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado"
) |>
  select(
    municipality_code_ibge = `municipio-id`,
    microregion_code       = `microrregiao-id`,
    microregion_name       = `microrregiao-nome`
  ) |>
  mutate(municipality_code_ibge = as.character(municipality_code_ibge))


#salvar em .rds 
saveRDS(municipios_ibge, "municipios_ibge.rds")
municipios_ibge <- readRDS("municipios_ibge.rds")

# 2. Cruza RAIS com microrregião e agrega
rais_2010_micro <- rais_2010 |>
  left_join(municipios_ibge, by = c("id_municipio" = "municipality_code_ibge")) |>
  group_by(microregion_code, microregion_name, cnae_2) |>
  summarise(
    total_vinculos = sum(total_vinculos, na.rm = TRUE),
    .groups = "drop"
  )

# Verifica o resultado
head(rais_2010_micro, 20)
nrow(rais_2010_micro)

# Verifica se há municípios sem correspondência
rais_2010 |>
  left_join(municipios_ibge, by = c("id_municipio" = "municipality_code_ibge")) |>
  filter(is.na(microregion_code)) |>
  distinct(id_municipio, municipio_nome, sigla_uf)


# Salva os dados de emprego por microrregião
write_xlsx(
  rais_2010_micro,
  path = "rais_2010_emprego_microregiao_cnae.xlsx"
)

saveRDS(rais_2010_micro, "rais_2010_micro.rds")


