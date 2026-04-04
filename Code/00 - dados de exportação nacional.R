#pacotes
library(ComexstatR)
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(glue)
library(sidrar)
library(writexl)
library(DBI)
library(basedosdados)
library(vroom)


setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")
set_billing_id("gen-lang-client-0768793544")


# Para carregar o dado direto no R
query <- "
SELECT
    dados.ano AS ano,
    dados.id_ncm AS id_ncm,
    SUM(dados.valor_fob_dolar) AS valor_fob_dolar
FROM `basedosdados.br_me_comex_stat.ncm_exportacao` AS dados
WHERE dados.ano BETWEEN 2010 AND 2022
GROUP BY
    dados.ano,
    dados.id_ncm
"


# Registrando
exports <- read_sql(query, billing_project_id = get_billing_id())

exports <- exports %>%
  mutate(ano = as.numeric(ano), valor_fob_dolar = as.numeric(valor_fob_dolar))

saveRDS(exports, "exports_national_ncm.rds")

write_xlsx(
  exports,
  path = "exports_national.xlsx"
)



