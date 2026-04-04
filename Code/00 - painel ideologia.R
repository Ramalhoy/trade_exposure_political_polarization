library(dplyr)
library(tibble)
library(readxl)
library(writexl)

setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")


#subindo dados
painel_votos <- readRDS("painel_votos_presidenciais_microregioes_2010_2022.rds")

ideologia <- readRDS("C:/Users/Yago Ramalho/Documents/tema mestrado/data/bls9_estimates_partiespresidents_long.rds")


# Criar coluna auxiliar  
ideologia <- ideologia %>%
  mutate(ano_eleicao = year + 1)  #usar dados de replicação


# Nota metodológica: Os índices ideológicos são do ano anterior à eleição
# (ex: índice de 2009 usado para eleição de 2010), pois refletem o 
# posicionamento partidário no período pré-eleitoral.


#usar estimativa para o Bolsonaro como equivalente à posição do PL em 2018

psl <- ideologia %>%
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) %>%
  mutate(
    party.or.pres = "PSL",
    ano_eleicao = 2018
  )

ideologia_psl <- bind_rows(ideologia, psl)

#fazendo a junção das estimativas ideológicas

painel_ideologico <- painel_votos %>%
  left_join(ideologia_psl, by = c("party" = "party.or.pres", "year" = "ano_eleicao")) %>%
  select(-year.y) 

saveRDS(painel_ideologico, "painel_ideologico.rds")


##calculando indicador
painel_polarizacao <- painel_ideologico %>%
  filter(!is.na(ideo)) %>% ##removendo dados faltantes
  mutate(neutral = case_when(
    ideo >= -0.25 & ideo <= 0.25 ~ 1,  # neutro 
    TRUE ~ 0
  )) %>%
  group_by(microregion_code, microregion_name, year) %>%
  mutate(
    total_votes = sum(votes, na.rm = TRUE),
    neutral_votes = sum(votes * neutral, na.rm = TRUE), #número de votos para candidatos de centro
    S_neutral = neutral_votes / total_votes,
    P = 1 - S_neutral
  ) %>%
  ungroup() ##olhar round 2
#olhar versão anterior do artigo (2018)
#fazer gráfico de distribuição por ano 
#verificar variabilidade no caso de governador

# agregando por microregião e ano
polarizacao_agregada <- painel_polarizacao %>%
  group_by(microregion_code, microregion_name, year) %>%
  summarise(
    S_neutral = first(S_neutral),
    P = first(P),
    .groups = "drop"
  )


write_xlsx(polarizacao_agregada, "polarizacao_agregada.xlsx")
saveRDS(polarizacao_agregada, "polarizacao_agregada.rds")


# Ver contagem de NAs por coluna
colSums(is.na(painel_ideologico))

# Ou com percentual:
colMeans(is.na(painel_ideologico)) * 100

# Ver linhas com NA na coluna de índice político
# (substitua 'indice_politico' pelo nome real)
df_com_na <- painel_ideologico %>%
  filter(is.na(ideo))

# Ver quais partidos têm NA
unique(df_com_na$party)

##essas lacunas são significativas?

#filtrar primeiro turno
primeiro_turno <- painel_ideologico %>%
  filter(round == 1)

# Calcular total de votos por ano
total_votos_ano <- primeiro_turno %>%
  group_by(year) %>%
  summarise(total_votos = sum(votes, na.rm = TRUE))

# Calcular votos com NA por ano
votos_na_ano <- primeiro_turno %>%
  filter(is.na(ideo)) %>%
  group_by(year) %>%
  summarise(votos_na = sum(votes, na.rm = TRUE))

# Juntar e calcular percentual
resumo <- total_votos_ano %>%
  left_join(votos_na_ano, by = "year") %>%
  mutate(percentual_na = round(votos_na / total_votos * 100, 2))

print(resumo)

# Detalhado por partido e ano:
votos_por_partido_ano <- primeiro_turno %>%
  filter(is.na(ideo)) %>%
  group_by(year, party) %>%
  summarise(votos = sum(votes, na.rm = TRUE), .groups = 'drop') %>%
  left_join(total_votos_ano, by = "year") %>%
  mutate(percentual = round(votos / total_votos * 100, 2))

print(votos_por_partido_ano, n=26)


##partidos em que não foram realizados estimativas => excluir da amostra utilizando
## justificativa do artigo original
#informar % 
#tomar decisão sobre partidos representativos que estão em branco:
#usar informação de 2021 em 2017? Como?


#criar colunas novas: voto total da microrregião, criar uma coluna auxiliar (dummy)
#para votos em candidatos da direita, esquerda e centro. Depois utilizar essa dummy para somar 
#o alinhamento por microrregião

# Linhas antes do join
nrow(painel_votos)

# Linhas depois do join
nrow(painel_ideologico)

# A razão deve ser ~1 (ou levemente maior por NAs virem de partidos sem match)
nrow(painel_ideologico) / nrow(painel_votos)

# Quais são as colunas de ideologia?
names(ideologia)

# A chave composta (party + ano_eleicao) é única?
nrow(ideologia)
n_distinct(ideologia$party, ideologia$ano_eleicao)



# Total de votos no painel original, primeiro turno
painel_votos %>%
  filter(round == 1) %>%
  group_by(year) %>%
  summarise(total = sum(votes))

# Total de votos no painel ideológico, primeiro turno  
painel_ideologico %>%
  filter(round == 1) %>%
  group_by(year) %>%
  summarise(total = sum(votes))


painel_votos %>%
  filter(round == 1) %>%
  distinct(year, microregion_code, party, candidato, state) %>%
  count(year, microregion_code, party, candidato) %>%
  filter(n > 1)

