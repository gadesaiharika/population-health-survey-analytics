# The validation suite: 41 checks across four groups.
#
# A survey estimate is the kind of number nobody can eyeball. 12.3% and 9.5% are
# equally plausible-looking, and the difference between them is whether the
# design was declared correctly. So the checks are not decoration here; they are
# the only thing standing between a correct figure and a confident wrong one.
#
#   Design integrity    the file is shaped the way the estimator assumes
#   Recode integrity    every respondent is counted as yes, no, or nobody
#   National estimates  the arithmetic is internally consistent
#   State estimates     53 parts reconcile back to the whole
#
# One check asserts the project's own premise: that weighting materially changes
# the answer. If it ever stopped mattering, there would be nothing to report,
# and the build should say so rather than publish an empty finding.

check_results <- new.env(parent = emptyenv())
check_results$rows <- list()

check <- function(group, label, pass, observed = "") {
  check_results$rows[[length(check_results$rows) + 1]] <-
    list(group = group, label = label, pass = isTRUE(pass), observed = as.character(observed))
  invisible(pass)
}

fmt <- function(x, digits = 4) format(round(x, digits), big.mark = ",", trim = TRUE)

validate_run <- function(d, est, measures) {
  check_results$rows <- list()
  n_rows <- nrow(d)

  # ---- design integrity (11) ------------------------------------------------
  g <- "design"
  check(g, "weights are present on every row",
        !any(is.na(d$weight)), sprintf("%d missing", sum(is.na(d$weight))))
  check(g, "weights are strictly positive",
        min(d$weight) > 0, sprintf("min %s", fmt(min(d$weight), 6)))
  check(g, "stratum is present on every row",
        !any(is.na(d$stratum)), sprintf("%d missing", sum(is.na(d$stratum))))
  check(g, "psu is present on every row",
        !any(is.na(d$psu)), sprintf("%d missing", sum(is.na(d$psu))))
  check(g, "jurisdiction is present on every row",
        !any(is.na(d$state_fips)), sprintf("%d missing", sum(is.na(d$state_fips))))

  psu_strata <- tapply(d$stratum, d$psu, function(s) length(unique(s)))
  repeated <- sum(psu_strata > 1)
  check(g, "psu ids repeat across strata, so nest = TRUE is required",
        repeated > 0, sprintf("%s of %s psu ids appear in more than one stratum",
                              fmt(repeated, 0), fmt(length(psu_strata), 0)))

  n_clusters <- nrow(unique(d[, c("stratum", "psu")]))
  check(g, "stratum + psu identifies more clusters than psu alone",
        n_clusters > length(unique(d$psu)),
        sprintf("%s clusters vs %s psu ids", fmt(n_clusters, 0), fmt(length(unique(d$psu)), 0)))

  stratum_states <- tapply(d$state_fips, d$stratum, function(s) length(unique(s)))
  spanning <- sum(stratum_states > 1)
  check(g, "no stratum spans two jurisdictions, so per-jurisdiction designs are exact",
        spanning == 0, sprintf("%d of %s strata span", spanning, fmt(length(stratum_states), 0)))

  n_juris <- length(unique(d$state_fips))
  check(g, "jurisdiction count is 53 (50 states, DC, and three territories)",
        n_juris == 53, sprintf("%d", n_juris))

  wt_total <- sum(d$weight)
  check(g, "weight total is a plausible US adult population",
        wt_total > 2e8 && wt_total < 3.5e8, sprintf("%.1f million", wt_total / 1e6))

  per_state <- tapply(d$weight, d$state_fips, sum)
  check(g, "every jurisdiction carries a positive weight total",
        all(per_state > 0), sprintf("min %s", fmt(min(per_state), 0)))

  # ---- recode integrity (5 per measure) -------------------------------------
  g <- "recode"
  for (nm in names(measures)) {
    spec <- measures[[nm]]
    v <- d[[nm]]
    raw <- d[[paste0(nm, "_raw")]]

    check(g, sprintf("%s: recode yields only 0, 1 or NA", nm),
          all(v %in% c(0L, 1L, NA_integer_)),
          paste(sort(unique(v[!is.na(v)])), collapse = "/"))
    check(g, sprintf("%s: yes count matches the raw yes codes", nm),
          sum(v == 1, na.rm = TRUE) == sum(raw %in% spec$yes, na.rm = TRUE),
          sprintf("%s", fmt(sum(v == 1, na.rm = TRUE), 0)))
    check(g, sprintf("%s: no count matches the raw no codes", nm),
          sum(v == 0, na.rm = TRUE) == sum(raw %in% spec$no, na.rm = TRUE),
          sprintf("%s", fmt(sum(v == 0, na.rm = TRUE), 0)))

    analytic <- sum(!is.na(v)); excluded <- sum(is.na(v))
    check(g, sprintf("%s: analytic plus excluded accounts for every row", nm),
          analytic + excluded == n_rows,
          sprintf("%s + %s = %s", fmt(analytic, 0), fmt(excluded, 0), fmt(n_rows, 0)))

    dk_refused <- sum(raw %in% c(7L, 9L), na.rm = TRUE)
    check(g, sprintf("%s: don't-know and refused leave the denominator", nm),
          all(is.na(v[raw %in% c(7L, 9L)])),
          sprintf("%s excluded", fmt(dk_refused, 0)))
  }

  # ---- national estimates (4 per measure) -----------------------------------
  g <- "national"
  for (nm in names(measures)) {
    row <- est$national[est$national$measure == nm, ]
    check(g, sprintf("%s: weighted prevalence lies between 0 and 100", nm),
          row$pct_weighted > 0 && row$pct_weighted < 100, sprintf("%.4f%%", row$pct_weighted))
    check(g, sprintf("%s: the confidence interval brackets the point estimate", nm),
          row$ci_low < row$pct_weighted && row$pct_weighted < row$ci_high,
          sprintf("%.4f - %.4f", row$ci_low, row$ci_high))
    check(g, sprintf("%s: standard error is positive", nm),
          row$se_pp > 0, sprintf("%.4f pp", row$se_pp))
    check(g, sprintf("%s: analytic plus excluded equals the file row count", nm),
          row$n_analytic + row$n_excluded == n_rows,
          sprintf("%s + %s", fmt(row$n_analytic, 0), fmt(row$n_excluded, 0)))
  }

  # ---- state estimates (6 per measure) --------------------------------------
  g <- "state"
  for (nm in names(measures)) {
    s <- est$states[est$states$measure == nm, ]
    nat <- est$national[est$national$measure == nm, ]

    check(g, sprintf("%s: one row per jurisdiction", nm), nrow(s) == 53, sprintf("%d", nrow(s)))
    check(g, sprintf("%s: every state prevalence lies between 0 and 100", nm),
          all(s$pct_weighted > 0 & s$pct_weighted < 100),
          sprintf("%.2f - %.2f", min(s$pct_weighted), max(s$pct_weighted)))
    check(g, sprintf("%s: state respondent counts sum to the national analytic n", nm),
          sum(s$n_analytic) == nat$n_analytic,
          sprintf("%s vs %s", fmt(sum(s$n_analytic), 0), fmt(nat$n_analytic, 0)))
    check(g, sprintf("%s: rank shifts sum to zero, because ranks are a permutation", nm),
          sum(s$rank_shift) == 0, sprintf("%d", sum(s$rank_shift)))

    # The real reconciliation: re-weight the state estimates by their share of
    # the total weight and the national figure has to reappear.
    rebuilt <- sum(s$pct_weighted * s$weight_total) / sum(s$weight_total)
    diff <- abs(rebuilt - nat$pct_weighted)
    check(g, sprintf("%s: state estimates re-weight back to the national figure", nm),
          diff < 5e-3, sprintf("difference %.2e pp", diff))

    gap <- nat$pct_weighted - nat$pct_unweighted
    check(g, sprintf("%s: weighting materially changes the estimate", nm),
          abs(gap) > 0.5, sprintf("%+.4f pp", gap))
  }

  rows <- check_results$rows
  passed <- sum(vapply(rows, function(r) r$pass, logical(1)))
  list(rows = rows, passed = passed, failed = length(rows) - passed)
}

validate_print <- function(res) {
  group_label <- c(design = "Design integrity", recode = "Recode integrity",
                   national = "National estimates", state = "State estimates")
  for (g in names(group_label)) {
    rows <- Filter(function(r) r$group == g, res$rows)
    if (!length(rows)) next
    message(sprintf("\n       %s (%d)", group_label[[g]], length(rows)))
    for (r in rows) {
      mark <- if (r$pass) "PASS" else "FAIL"
      pad <- strrep(" ", max(0, 62 - nchar(r$label)))
      message(sprintf("         %s  %s%s %s", mark, r$label, pad, r$observed))
    }
  }
  invisible(res)
}
