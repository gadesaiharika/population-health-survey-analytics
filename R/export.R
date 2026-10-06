# Dashboard and reconciliation extracts.
#
# Three CSVs, all small. The analysis frame is 457,670 rows and nothing
# downstream needs it: every figure a reader cares about is an estimate, and
# there are 108 of those.

export_run <- function(est, measures, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  labels <- vapply(measures, function(m) m$label, character(1))

  national <- est$national
  national$label <- unname(labels[national$measure])
  national$pct_difference <- national$pct_weighted - national$pct_unweighted

  states <- est$states
  states$label <- unname(labels[states$measure])

  # One row per measure: the headline comparison, which is what the finding is.
  summary <- data.frame(
    measure        = national$measure,
    label          = national$label,
    n_analytic     = national$n_analytic,
    n_excluded     = national$n_excluded,
    pct_unweighted = round(national$pct_unweighted, 4),
    pct_weighted   = round(national$pct_weighted, 4),
    pct_difference = round(national$pct_difference, 4),
    se_pp          = round(national$se_pp, 4),
    ci_low         = round(national$ci_low, 4),
    ci_high        = round(national$ci_high, 4),
    stringsAsFactors = FALSE
  )

  files <- list(
    national_estimates = national,
    state_estimates    = states,
    measure_summary    = summary
  )

  written <- c()
  for (nm in names(files)) {
    path <- file.path(out_dir, paste0(nm, ".csv"))
    utils::write.csv(files[[nm]], path, row.names = FALSE, na = "")
    written[nm] <- nrow(files[[nm]])
  }
  written
}
