# =============================================================================
# 02_polarization_indices.R  (pipeline stage 2 — index building)
# Builds the polarization indices (Dalton dispersion P_dalton + center-emptying
# P_center, plus S_neutral/P) for BOTH presidential and governor levels, from
# the microregion vote panels and the BLS ideology scores.
# Formerly "00_-_painel_ideologia_gov_revisar.R" (the function-based revision
# that supersedes the April "00 - painel ideologia.R").
# =============================================================================
source("C:/Users/Yago Ramalho/Documents/tema mestrado/data/códigos/_config.R")

library(dplyr)
library(tibble)
library(readxl)
library(writexl)


# =============================================================================
# IDEOLOGIA (compartilhada entre os dois niveis)
# O mapeamento ideologia->partido e o mesmo para presidente e governador:
# os partidos sao os mesmos, so muda o cargo na cedula. Por isso a base de
# ideologia e a correcao do PSL ficam aqui fora, aplicadas igualmente aos dois.
# =============================================================================

ideologia <- readRDS("bls9_estimates_partiespresidents_long.rds") %>%
  mutate(ano_eleicao = year + 1)

# Nota metodológica: Os índices ideológicos são do ano anterior à eleição
# (ex: índice de 2009 usado para eleição de 2010), pois refletem o
# posicionamento partidário no período pré-eleitoral.

#usar estimativa para o Bolsonaro como equivalente à posição do PSL em 2018
psl <- ideologia %>%
  filter(party.or.pres == "BOLSONARO", ano_eleicao == 2022) %>%
  mutate(
    party.or.pres = "PSL",
    ano_eleicao   = 2018
  )

ideologia_psl <- bind_rows(ideologia, psl)


# =============================================================================
# FUNCAO: mesma regra de construcao, qualquer nivel eleitoral
# Recebe o caminho do painel de votos por microrregiao e um rotulo de nivel,
# devolve o painel Dalton/center e salva tudo com sufixo do nivel.
# =============================================================================

construir_polarizacao <- function(caminho_votos, nivel) {

  painel_votos <- readRDS(caminho_votos)

  # --- juncao das estimativas ideologicas (1o turno) -------------------------
  painel_ideologico <- painel_votos %>%
    filter(round == 1) %>%
    left_join(ideologia_psl, by = c("party" = "party.or.pres", "year" = "ano_eleicao")) %>%
    select(-year.y)

  saveRDS(painel_ideologico, paste0("painel_ideologico_", nivel, ".rds"))

  # --- indice de esvaziamento do centro (S_neutral, P) -----------------------
  painel_polarizacao <- painel_ideologico %>%
    filter(!is.na(ideo)) %>%                       # remove faltantes de ideologia
    mutate(neutral = case_when(
      ideo >= -0.25 & ideo <= 0.25 ~ 1,            # neutro / centro
      TRUE ~ 0
    )) %>%
    group_by(microregion_code, microregion_name, year) %>%
    mutate(
      total_votes   = sum(votes, na.rm = TRUE),
      neutral_votes = sum(votes * neutral, na.rm = TRUE),
      S_neutral     = neutral_votes / total_votes,
      P             = 1 - S_neutral
    ) %>%
    ungroup()

  polarizacao_agregada <- painel_polarizacao %>%
    group_by(microregion_code, microregion_name, year) %>%
    summarise(
      S_neutral = first(S_neutral),
      P         = first(P),
      .groups   = "drop"
    )

  write_xlsx(polarizacao_agregada, paste0("polarizacao_agregada_", nivel, ".xlsx"))
  saveRDS(polarizacao_agregada, paste0("polarizacao_agregada_", nivel, ".rds"))

  # --- Dalton (dispersao) + center (esvaziamento) ----------------------------
  dalton <- painel_ideologico %>%
    filter(!is.na(ideo)) %>%
    group_by(microregion_code, year) %>%
    mutate(
      total_votes = sum(votes, na.rm = TRUE),
      v_rpt       = votes / total_votes            # vote share
    ) %>%
    mutate(
      y_bar = sum(v_rpt * ideo, na.rm = TRUE)       # weighted mean ideology
    ) %>%
    summarise(
      P_dalton = sqrt(sum(v_rpt * (ideo - y_bar)^2, na.rm = TRUE)),
      P_center = first(1 - sum(v_rpt * (ideo >= -0.25 & ideo <= 0.25))),
      .groups  = "drop"
    )

  saveRDS(dalton, paste0("dalton_panel_", nivel, ".rds"))

  return(list(
    painel_ideologico    = painel_ideologico,
    polarizacao_agregada = polarizacao_agregada,
    dalton               = dalton
  ))
}


# =============================================================================
# FUNCAO DE DIAGNOSTICO: cobertura da ideologia (votos sem score por ano/partido)
# Importante rodar para governador: corridas estaduais trazem mais partidos
# pequenos sem score BLS, entao a fracao excluida tende a ser maior.
# =============================================================================

diagnostico_na <- function(painel_ideologico, nivel) {

  cat("\n==== Diagnostico de cobertura ideologica:", nivel, "====\n")

  total_votos_ano <- painel_ideologico %>%
    group_by(year) %>%
    summarise(total_votos = sum(votes, na.rm = TRUE), .groups = "drop")

  # % de votos excluidos por ausencia de score, por ano
  resumo <- painel_ideologico %>%
    filter(is.na(ideo)) %>%
    group_by(year) %>%
    summarise(votos_na = sum(votes, na.rm = TRUE), .groups = "drop") %>%
    right_join(total_votos_ano, by = "year") %>%
    mutate(
      votos_na      = coalesce(votos_na, 0),
      percentual_na = round(votos_na / total_votos * 100, 2)
    ) %>%
    arrange(year)

  print(resumo)

  # detalhe por partido e ano (partidos sem score)
  detalhe <- painel_ideologico %>%
    filter(is.na(ideo)) %>%
    group_by(year, party) %>%
    summarise(votos = sum(votes, na.rm = TRUE), .groups = "drop") %>%
    left_join(total_votos_ano, by = "year") %>%
    mutate(percentual = round(votos / total_votos * 100, 2)) %>%
    arrange(year, desc(percentual))

  print(detalhe, n = 40)

  invisible(list(resumo = resumo, detalhe = detalhe))
}


# =============================================================================
# EXECUCAO PARA OS DOIS NIVEIS
# =============================================================================

pol_presidencial <- construir_polarizacao(
  "painel_votos_presidenciais_microregioes_2010_2022.rds", "presidencial"
)

pol_governador <- construir_polarizacao(
  "painel_votos_governador_microregioes_2010_2022.rds", "governador"
)

# diagnosticos de cobertura
diagnostico_na(pol_presidencial$painel_ideologico, "presidencial")
diagnostico_na(pol_governador$painel_ideologico,   "governador")
