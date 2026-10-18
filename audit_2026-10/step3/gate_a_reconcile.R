# =============================================================================
# gate_a_reconcile.R — Gate (a): pipeline totals vs published aggregates.
# Thresholds (plan §5): exports 1%, RAIS 0.5%, TSE 0.1%.
# Official values are typed in below WITH their source; every one was read
# on 18/10/2026. "secondary" = a page that reproduces the agency figure
# because the agency site itself was unreachable from this workspace.
# =============================================================================
D <- Sys.getenv("SS_DATA_DIR", "D")
ex <- as.data.frame(readRDS(file.path(D, "exports_national_ncm.rds")))
xs <- tapply(ex$valor_fob_dolar, ex$ano, sum)
off_x <- c(`2010` = 200434134e3, `2014` = 220923236e3, `2018` = 231889523e3, `2022` = 334463079e3)
src_x <- "IBGE Anuario Estatistico 2023, tab. s7t4101 (Fonte: Secex, Comex Stat), US$ 1 000 FOB"
rais <- sum(as.data.frame(readRDS(file.path(D, "rais_2010_micro.rds")))$total_vinculos)
pv <- function(f) { p <- as.data.frame(readRDS(file.path(D, f))); p <- p[p$round == 1, ]; tapply(p$votes, p$year, sum) }
pres <- pv("painel_ideologico_presidencial.rds"); dep <- pv("painel_ideologico_deputado_federal.rds")
rows <- list(
  data.frame(item = paste("Comex exports", names(off_x)), pipeline = as.numeric(xs[names(off_x)]), official = off_x,
             tol = 0.01, source = src_x),
  data.frame(item = "RAIS 2010 active contracts 31/12", pipeline = rais, official = 44.068e6, tol = 0.005,
             source = "MTE announcement of RAIS 2010 ('44,068 milhoes'), reproduced by idealsoftwares.com.br/idealnews id=2884 (secondary); official precision 1,000"),
  data.frame(item = "TSE president 2010 R1, valid in Brazil", pipeline = pres[["2010"]], official = 101590153 - (30950 + 33850 + 17208 + 2141),
             tol = 0.001, source = "valid 101,590,153 minus abroad 84,149: en.wikipedia 'Results of the 2010 Brazilian general election' (TSE/Election Resources; secondary)"),
  data.frame(item = "TSE president 2018 R1, valid in Brazil", pipeline = pres[["2018"]], official = 107050749 - 193381,
             tol = 0.001, source = "valid 107,050,749 (TSE) minus 'Diaspora' row 193,381: en.wikipedia '2018 Brazilian general election' (secondary)"),
  data.frame(item = "TSE deputy 2010 R1, valid", pipeline = dep[["2010"]], official = 96580011, tol = 0.001,
             source = "en.wikipedia 'Results of the 2010 Brazilian general election' (Election Resources; secondary)"),
  data.frame(item = "TSE deputy 2014 R1, valid", pipeline = dep[["2014"]], official = 97263161, tol = 0.001,
             source = "en.wikipedia '2014 Brazilian general election' (Election Resources; secondary)"),
  data.frame(item = "TSE deputy 2018 R1, valid", pipeline = dep[["2018"]], official = 98338993, tol = 0.001,
             source = "en.wikipedia '2018 Brazilian general election' (Election Resources; secondary)"))
tse0206 <- read.csv("audit/out/gate_a_tse_2002_2006_internal.csv")
rows[[length(rows) + 1]] <- data.frame(item = paste("TSE deputy", tse0206$year, "party file vs detalhe valid (raw TSE)"),
  pipeline = tse0206$party_file_total, official = tse0206$detalhe_valid, tol = 0.001,
  source = "TSE votacao_partido_munzona vs detalhe_votacao_munzona (nominal + legenda valid), SHA-256 verified")
tab <- do.call(rbind, rows); tab$rel_diff <- tab$pipeline / tab$official - 1
tab$pass <- abs(tab$rel_diff) <= tab$tol
nd <- data.frame(item = c("TSE president 2014 / 2022 (votes abroad not obtained)", "TSE deputy 2022", "TSE governor 2010-2022"),
                 pipeline = NA, official = NA, tol = 0.001, source = "NOT DONE: no official figure reachable from this workspace",
                 rel_diff = NA, pass = NA)
tab <- rbind(tab, nd); rownames(tab) <- NULL
print(tab[, c("item", "pipeline", "official", "rel_diff", "pass")], digits = 10)
write.csv(tab, "audit/out/gate_a_reconciliation.csv", row.names = FALSE)
