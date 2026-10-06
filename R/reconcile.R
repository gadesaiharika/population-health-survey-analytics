#!/usr/bin/env Rscript
#
# Compare the SAS estimates against the R estimates.
#
#     Rscript R/reconcile.R
#
# Tolerance is 0.01 percentage points on the point estimate. The two should
# agree far more tightly than that; the tolerance exists to absorb the fact
# that SAS and the survey package use slightly different degrees-of-freedom
# conventions for confidence bounds.
#
# A point estimate off by more than rounding does not mean "widen the
# tolerance". It means the two programs did not declare the same design, or the
# recodes drifted apart, and the gap is the evidence of which.

TOLERANCE_PP <- 0.01

REPO <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])), ".."), mustWork = FALSE)
EXPORTS <- file.path(REPO, "data", "exports")

r_path   <- file.path(EXPORTS, "national_estimates.csv")
sas_path <- file.path(EXPORTS, "sas_estimates.csv")

if (!file.exists(r_path)) stop("run `Rscript run.R` first - ", basename(r_path), " is missing")
if (!file.exists(sas_path)) {
  message("sas_estimates.csv is not here yet.\n",
          "Run sas/01_estimate.sas in SAS OnDemand and download its CSV into data/exports/.\n",
          "Until then the README must not claim the two agree.")
  quit(status = 2)
}

r_est   <- utils::read.csv(r_path, stringsAsFactors = FALSE)
sas_est <- utils::read.csv(sas_path, stringsAsFactors = FALSE)

sas_nat <- sas_est[sas_est$scope == "national", ]
merged <- merge(
  r_est[, c("measure", "pct_weighted", "se_pp", "ci_low", "ci_high")],
  sas_nat[, c("measure", "pct", "se", "ci_low", "ci_high")],
  by = "measure", suffixes = c("_r", "_sas")
)

if (!nrow(merged)) stop("no measures matched between the two files - check the measure names")

merged$diff_pp <- merged$pct_weighted - merged$pct
merged$agrees <- abs(merged$diff_pp) <= TOLERANCE_PP

cat("\nNational prevalence, R against SAS\n\n")
cat(sprintf("  %-14s %>12s %>12s %>12s  %s\n", "measure", "R", "SAS", "difference", ""))
for (i in seq_len(nrow(merged))) {
  row <- merged[i, ]
  cat(sprintf("  %-14s %12.4f %12.4f %12.2e  %s\n",
              row$measure, row$pct_weighted, row$pct, row$diff_pp,
              if (row$agrees) "agrees" else "DISAGREES"))
}

failed <- sum(!merged$agrees)
cat(sprintf("\n  tolerance %.2f pp - %d of %d measures agree\n",
            TOLERANCE_PP, nrow(merged) - failed, nrow(merged)))

if (failed > 0) {
  cat("\nThe designs are not the same in both programs. Check, in this order:\n",
      "  1. the recode - do 7 and 9 leave the denominator in both?\n",
      "  2. STRATA / CLUSTER / WEIGHT against ids / strata / weights\n",
      "  3. that SAS read the same file R did\n")
  quit(status = 1)
}
quit(status = 0)
