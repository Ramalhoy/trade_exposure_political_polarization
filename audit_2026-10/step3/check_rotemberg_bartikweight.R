# cross-check: step-1 Rotemberg alpha (2022, base controls, within-year) vs bartik.weight::bw
source("audit/ss_core.R")
r <- yi == 3; W <- stack3(W0_1)[r, ]; g <- G0[, "2022"]
ctrl <- data.frame(ctrl_base0[r, ], st = factor(df$state[r]))
X <- model.matrix(~ ., ctrl)[, -1]
x <- as.numeric(W %*% g)
yplac <- rnorm(sum(r))
bw <- bartik.weight::bw(master = data.frame(y = yplac, x = x, X), y = "y", x = "x", controls = colnames(X),
       weight = NULL, local = W, global = data.frame(g = g), G = "g")
xp <- lm.fit(cbind(1, X), x)$residuals; a <- g * as.numeric(crossprod(W, xp)); a <- a / sum(a)
cat(sprintf("max|alpha_bw - alpha_mine| = %.3e | top alpha bw %.4f (%s)\n", max(abs(bw$alpha - a)),
            max(bw$alpha), colnames(W)[which.max(bw$alpha)]))
