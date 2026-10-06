#!/usr/bin/env Rscript
#
# The README figure, and the state-level numbers that go in the text.
#
#     Rscript R/figure.R
#
# One panel per measure: each jurisdiction's unweighted estimate against its
# weighted one, with the 45-degree line. A point on the line means the survey
# design did not matter there. The distance from it is the error you would ship
# by treating a stratified, clustered, raked sample as if it were a simple
# random one.
#
# Base graphics on purpose - the project already asks a reviewer to install two
# packages, and a chart is not worth a third.

REPO <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])), ".."), mustWork = FALSE)
EXPORTS <- file.path(REPO, "data", "exports")
DOCS <- file.path(REPO, "docs")
dir.create(DOCS, showWarnings = FALSE)

states <- read.csv(file.path(EXPORTS, "state_estimates.csv"), stringsAsFactors = FALSE)
nat    <- read.csv(file.path(EXPORTS, "national_estimates.csv"), stringsAsFactors = FALSE)

labels <- c(cost_barrier = "Could not see a doctor due to cost",
            diabetes     = "Ever told they have diabetes")

# ---- the numbers the README quotes ----------------------------------------
cat("\nState-level effect of the survey design\n\n")
for (m in names(labels)) {
  s <- states[states$measure == m, ]
  big <- sum(abs(s$rank_shift) >= 10)
  worst <- s[which.max(abs(s$rank_shift)), ]
  widest <- s[which.max(abs(s$pct_difference)), ]
  cat(sprintf("  %s\n", labels[[m]]))
  cat(sprintf("    median absolute rank shift   %.1f places of 53\n", median(abs(s$rank_shift))))
  cat(sprintf("    jurisdictions moving >= 10   %d\n", big))
  cat(sprintf("    largest rank move            %s, %+d\n", worst$state_name, worst$rank_shift))
  cat(sprintf("    mean absolute difference     %.2f pp\n", mean(abs(s$pct_difference))))
  cat(sprintf("    largest difference           %s, %.2f pp\n",
              widest$state_name, abs(widest$pct_difference)))
  ms <- s[s$state_name == "Mississippi", ]
  cat(sprintf("    Mississippi                  %.2f%% (rank %d) unweighted -> %.2f%% (rank %d) weighted\n\n",
              ms$pct_unweighted, ms$rank_unweighted, ms$pct_weighted, ms$rank_weighted))
}

# ---- figure ----------------------------------------------------------------
png(file.path(DOCS, "design_effect_by_state.png"), width = 1500, height = 780, res = 150)
op <- par(mfrow = c(1, 2), mar = c(4.4, 4.6, 4.2, 1.4), oma = c(2.6, 0, 0, 0), family = "sans")

for (m in names(labels)) {
  s <- states[states$measure == m, ]
  n <- nat[nat$measure == m, ]
  lim <- range(c(s$pct_unweighted, s$pct_weighted)) + c(-0.7, 0.7)

  plot(s$pct_unweighted, s$pct_weighted, xlim = lim, ylim = lim,
       xlab = "Unweighted (%)", ylab = "Survey-weighted (%)",
       main = "", axes = FALSE, type = "n", asp = 1)
  abline(0, 1, col = "#b9c0c7", lwd = 1.4)
  grid(col = "#edf0f2", lty = 1)
  points(s$pct_unweighted, s$pct_weighted, pch = 21, cex = 1.15,
         bg = ifelse(s$pct_difference > 0, "#c0392b66", "#2a78d666"),
         col = ifelse(s$pct_difference > 0, "#c0392b", "#2a78d6"))

  # Name the jurisdictions that move furthest, plus Mississippi.
  flag <- unique(c(order(abs(s$pct_difference), decreasing = TRUE)[1:2],
                   which(s$state_name == "Mississippi")))
  text(s$pct_unweighted[flag], s$pct_weighted[flag], s$state_name[flag],
       pos = 4, cex = 0.72, col = "#3c4858", offset = 0.45)

  axis(1, col = "#c7cfd6", col.axis = "#3c4858", cex.axis = 0.85)
  axis(2, col = "#c7cfd6", col.axis = "#3c4858", cex.axis = 0.85, las = 1)
  title(main = labels[[m]], adj = 0, cex.main = 1.0, font.main = 2, col.main = "#1f2d3d")
  mtext(sprintf("national %.2f%% weighted vs %.2f%% unweighted  (%+.2f pp)",
                n$pct_weighted, n$pct_unweighted, n$pct_weighted - n$pct_unweighted),
        side = 3, adj = 0, line = 0.3, cex = 0.78, col = "#6b7785")
}

mtext("Each point is one of 53 jurisdictions. The line is where the survey design makes no difference.",
      side = 1, outer = TRUE, line = 1.0, cex = 0.78, col = "#6b7785")
par(op)
invisible(dev.off())
cat("wrote", file.path(DOCS, "design_effect_by_state.png"), "\n")
