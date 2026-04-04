#
# EPW_{rt} = sum_j [ (L_{rj,2010} / L_{r,2010}) * (delta_EXP_{jt} / L_{j,2010}) ]
#


library(tidyverse)
library(readxl)
library(janitor)
library(wbstats)

setwd("C:/Users/Yago Ramalho/Documents/tema mestrado/data")

paths <- list(
  exports  = "exports_national_ncm.rds",
  rais     = "rais_2010_micro.rds",
  ncm_cnae = "NCM2012XCNAE20.xls"
)

#padronizando o nome das colunas

# exports : year | ncm | value | value_nominal
# rais    : micro | cnae | workers


exports <- readRDS(paths$exports)
rais    <- readRDS(paths$rais)

names(exports)
#ano, id_ncm, valor_fob_dolar
names(rais)
# "microregion_code" "microregion_name" "cnae_2" "total_vinculos" 

# exports 
exports <- exports %>%
  rename(
    year  = ano,            
    ncm   = id_ncm,
    value = valor_fob_dolar
  ) %>%
  mutate(ncm = str_pad(as.character(ncm), width = 8, pad = "0"))


# rais 
rais <- rais %>%
  rename(
    micro   = microregion_code,
    cnae    = cnae_2,
    workers = total_vinculos
  ) %>%
  mutate(cnae = str_remove_all(str_remove_all(as.character(cnae), "\\."), "-"))


n_distinct(exports$ncm) #10191
n_distinct(rais$cnae) #670
n_distinct(rais$micro) #558
sort(unique(exports$year)) #2010-2022



#deflacionar valores nominais


cpi <- wb_data(indicator = "FP.CPI.TOTL", country = "US", start_date = 2009, end_date = 2023) %>%
  select(year = date, cpi = FP.CPI.TOTL)

cpi_base <- cpi %>% filter(year == 2010) %>% pull(cpi)


exports <- exports %>%
  left_join(cpi, by = "year") %>%
  mutate(cpi_base = 100, 
         deflator = cpi/cpi_base,
    value_real = value*deflator
  )


#conferir valores "meio doidos" 
#revisar se usa IPCA ou CPI

# NCM 8-digit -> CNAE 2.0


ncm_cnae_raw <- read_excel(paths$ncm_cnae) %>% clean_names()

#  Skip header row 
ncm_cnae <- ncm_cnae_raw %>%
  slice(-1) %>%                          
  select(
    ncm  = 1,                            # col 1: NCM code (7-digit in IBGE file)
    cnae = 3                             # col 3: CNAE 2.0 code
  ) %>%
  mutate(
    # faz com que os códigos NCM tenham 8 dígitos
    ncm  = str_pad(str_trim(as.character(ncm)), width = 8, pad = "0"),
    cnae = as.character(cnae)
  ) %>%
  filter(!is.na(ncm), !is.na(cnae), ncm != "NA", cnae != "NA") %>%
  # Split concatenated CNAE codes (e.g. "0111.3; 0112.1") into separate rows
  separate_rows(cnae, sep = ";") %>%
  mutate(
    cnae = str_trim(cnae),
    cnae = str_remove_all(cnae, "\\."),
    cnae = str_remove_all(cnae, "-")
  ) %>%
  filter(cnae != "", nchar(cnae) >= 4) %>%   # drop any residual empty/malformed
  distinct(ncm, cnae)

n_distinct(ncm_cnae$ncm) #10044

#montando a correspondência
all_ncm <- exports %>% distinct(ncm)

xwalk <- all_ncm %>%
  left_join(ncm_cnae, by = "ncm") %>%
  mutate(matched = !is.na(cnae))

nrow(all_ncm) #10191
sum(xwalk$matched) #10098
sum(!xwalk$matched) #1167

# proporção da exportação total que encontrou correspondência
 round(sum(exports$value[exports$ncm %in% xwalk$ncm[xwalk$matched]], na.rm = TRUE) /
        sum(exports$value, na.rm = TRUE) * 100, 1) #96,5%

 
 
# Unmatched NCM ranked by export value — save for manual review
unmatched_ncm <- xwalk %>%
  filter(!matched) %>%
  distinct(ncm) %>%
  left_join(
    exports %>% group_by(ncm) %>%
      summarise(total_exports_usd = sum(value, na.rm = TRUE), .groups = "drop"),
    by = "ncm"
  ) %>%
  arrange(desc(total_exports_usd)) %>%
  mutate(cnae_manual = NA_character_)

write_csv(unmatched_ncm, "unclassified_ncm_for_review.csv")
cat("Saved", nrow(unmatched_ncm), "unmatched NCM codes to unclassified_ncm_for_review.csv\n")


ncm_to_cnae <- xwalk %>% filter(matched) %>% select(ncm, cnae) #apenas as correspondências aplicadas

##relatar quantos % de classificações com mais de uma entrada (que não 1:1)

# STEP 4 — SECTORAL EXPORT SHOCKS: g_jt = delta_EXP_jt / L_j,2010
# =============================================================================
# [DESIGN] When one NCM maps to multiple CNAEs, export value is split equally.
# This is a reasonable default but introduces measurement error. If you later
# obtain a more granular crosswalk, consider value-weighted splitting instead.
#

# =============================================================================

exports_cnae <- exports %>%
  inner_join(ncm_to_cnae, by = "ncm") %>%
  group_by(ncm, year) %>%
  mutate(n_cnae          = n_distinct(cnae),
         value_allocated = value / n_cnae) %>%
  ungroup()


national_exports <- exports_cnae %>%
  group_by(cnae, year) %>%
  summarise(exp_national = sum(value_allocated, na.rm = TRUE), .groups = "drop")

exp_2010 <- national_exports %>%
  filter(year == 2010) %>%
  select(cnae, exp_2010 = exp_national)

L_j_2010 <- rais %>%
  group_by(cnae) %>%
  summarise(L_j_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

shocks <- national_exports %>%
  left_join(exp_2010,  by = "cnae") %>%
  left_join(L_j_2010, by = "cnae") %>%
  mutate(delta_exp = exp_national - exp_2010,
         g_jt      = delta_exp / L_j_2010) %>%
  filter(!is.na(L_j_2010), L_j_2010 > 0)

cat("CNAE industries with valid shocks: ", n_distinct(shocks$cnae), "\n")

cat("\nShock distribution by year (real 2010 USD FOB per worker):\n")
shocks %>%
  group_by(year) %>%
  summarise(mean   = mean(g_jt,   na.rm = TRUE),
            sd     = sd(g_jt,     na.rm = TRUE),
            min    = min(g_jt,    na.rm = TRUE),
            median = median(g_jt, na.rm = TRUE),
            max    = max(g_jt,    na.rm = TRUE)) %>%
  print()

# =============================================================================
# STEP 5 — EXPOSURE SHARES: s_rj = L_rj,2010 / L_r,2010
# =============================================================================
# [DESIGN] Shares are computed from rais which you've confirmed is already
# filtered to 2010. If the rais object ever changes to a multi-year file,
# add: filter(year == 2010) here.
# =============================================================================

cat("\n======= STEP 5: EXPOSURE SHARES =======\n")

L_r_2010 <- rais %>%
  group_by(micro) %>%
  summarise(L_r_2010 = sum(workers, na.rm = TRUE), .groups = "drop")

shares <- rais %>%
  rename(L_rj_2010 = workers) %>%
  left_join(L_r_2010, by = "micro") %>%
  mutate(s_rj = L_rj_2010 / L_r_2010) %>%
  select(micro, cnae, L_rj_2010, L_r_2010, s_rj)

cat("Microregions in shares:       ", n_distinct(shares$micro), "\n")
cat("Industry x microregion cells: ", nrow(shares), "\n")

share_sums <- shares %>%
  group_by(micro) %>%
  summarise(sum_shares = sum(s_rj, na.rm = TRUE))

cat("\nShare sum per microregion (all should be ~1.0):\n")
print(summary(share_sums$sum_shares))

# =============================================================================
# STEP 6 — COMPUTE EPW AND ASSEMBLE PANEL
# =============================================================================
# [FIX] The original crossing()/left_join() joined on c("cnae_2", "year") but
# the shocks table uses column name "cnae" (not "cnae_2"). This would produce
# all-NA g_jt values, making every EPW = 0 regardless of year — a silent,
# catastrophic failure. Standardised join key to "cnae_2" throughout this step.
#
# [DESIGN] Industries in RAIS with no matched export shock contribute zero to
# EPW (g_jt = 0 via replace_na). This is correct: non-exporting sectors have
# no export shock by definition.
# =============================================================================

cat("\n======= STEP 6: COMPUTING EPW =======\n")

election_years <- c(2010, 2014, 2018, 2022)

# Align shocks column name to canonical 'cnae' — already correct, no rename needed
epw_panel <- shares %>%
  crossing(year = election_years) %>%
  left_join(
    shocks %>% select(cnae, year, g_jt),
    by = c("cnae", "year")
  ) %>%
  mutate(g_jt          = replace_na(g_jt, 0),
         epw_component = s_rj * g_jt) %>%
  group_by(micro, year) %>%
  summarise(EPW          = sum(epw_component, na.rm = TRUE),
            n_industries = n_distinct(cnae[g_jt != 0]),
            .groups = "drop")

cat("EPW panel rows: ", nrow(epw_panel), "\n")
cat("Microregions:   ", n_distinct(epw_panel$micro), "\n")
cat("Years:          ", sort(unique(epw_panel$year)), "\n")

cat("\nEPW distribution by year:\n")
epw_panel %>%
  group_by(year) %>%
  summarise(mean   = mean(EPW,   na.rm = TRUE),
            sd     = sd(EPW,     na.rm = TRUE),
            min    = min(EPW,    na.rm = TRUE),
            median = median(EPW, na.rm = TRUE),
            max    = max(EPW,    na.rm = TRUE)) %>%
  print()

# Sanity check 1: EPW in 2010 must be zero everywhere
epw_2010 <- epw_panel %>% filter(year == 2010) %>% pull(EPW)
cat("\nSanity check 1 — EPW in 2010 = 0:",
    ifelse(all(epw_2010 == 0), "PASS", "FAIL — check delta_exp"), "\n")

zero_check <- epw_panel %>%
  filter(year > 2010) %>%
  group_by(micro) %>%
  summarise(all_zero = all(EPW == 0), .groups = "drop")

cat("Sanity check 2 — microregions with EPW = 0 across ALL post-2010 years:",
    sum(zero_check$all_zero), "(should be 0 or very few)\n")

# =============================================================================
# SAVE OUTPUTS
# =============================================================================

saveRDS(epw_panel,     "epw_panel.rds")
saveRDS(ncm_to_cnae,  "ncm_to_cnae_crosswalk.rds")
saveRDS(shocks,       "sectoral_shocks.rds")
saveRDS(shares,       "exposure_shares.rds")

write_csv(epw_panel,    "epw_panel.csv")
write_csv(ncm_to_cnae, "ncm_to_cnae_crosswalk.csv")

cat("\nAll outputs saved.\n")
