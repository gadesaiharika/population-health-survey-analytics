# Survey-weighted and unweighted estimation.
#
# Two decisions in here are the whole project, and both are easy to get wrong
# in a way that still produces a plausible number.
#
# nest = TRUE. BRFSS primary sampling units are numbered only within a stratum:
# 25,800 of 43,913 PSU ids appear in more than one stratum. Without nesting,
# `survey` treats same-numbered PSUs in different strata as a single cluster and
# the variance is wrong — the point estimate looks fine, which is what makes it
# dangerous. A validation check asserts the ids really do repeat, so this stays
# necessary rather than becoming cargo cult.
#
# One design per jurisdiction for the state step. svyby() on the national design
# subsets a 457,670-row, 43,913-PSU object 53 times per measure and runs for
# longer than half an hour. Building a design per jurisdiction is exact, not an
# approximation, because no stratum spans two jurisdictions — also a validation
# check — and it drops the state step from unusable to seconds.

suppressPackageStartupMessages(library(survey))

# Some strata contribute a single PSU, which leaves no within-stratum variance
# to estimate. Without this, the run either errors or silently drops them.
options(survey.lonely.psu = "adjust")

make_design <- function(d) {
  svydesign(ids = ~psu, strata = ~stratum, weights = ~weight, data = d, nest = TRUE)
}

#' Weighted and unweighted prevalence for one measure, nationally.
estimate_national <- function(d, measure) {
  analytic <- d[!is.na(d[[measure]]), ]
  design <- make_design(analytic)

  f <- as.formula(paste0("~", measure))
  est <- svymean(f, design, na.rm = TRUE)
  ci <- confint(est)

  data.frame(
    measure      = measure,
    scope        = "national",
    state_fips   = NA_integer_,
    state_name   = NA_character_,
    n_analytic   = nrow(analytic),
    n_excluded   = nrow(d) - nrow(analytic),
    pct_unweighted = 100 * mean(analytic[[measure]]),
    pct_weighted   = 100 * as.numeric(est),
    se_pp          = 100 * as.numeric(survey::SE(est)),
    ci_low         = 100 * ci[1, 1],
    ci_high        = 100 * ci[1, 2],
    stringsAsFactors = FALSE
  )
}

#' Weighted and unweighted prevalence for one measure, per jurisdiction.
estimate_states <- function(d, measure) {
  analytic <- d[!is.na(d[[measure]]), ]
  fips <- sort(unique(analytic$state_fips))

  rows <- lapply(fips, function(code) {
    sub <- analytic[analytic$state_fips == code, ]
    design <- make_design(sub)
    est <- svymean(as.formula(paste0("~", measure)), design, na.rm = TRUE)
    ci <- confint(est)
    data.frame(
      measure      = measure,
      scope        = "state",
      state_fips   = code,
      state_name   = sub$state_name[1],
      n_analytic   = nrow(sub),
      n_excluded   = NA_integer_,
      pct_unweighted = 100 * mean(sub[[measure]]),
      pct_weighted   = 100 * as.numeric(est),
      se_pp          = 100 * as.numeric(survey::SE(est)),
      ci_low         = 100 * ci[1, 1],
      ci_high        = 100 * ci[1, 2],
      weight_total   = sum(sub$weight),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  # Ranks are what a state official actually reads off a table like this, so
  # they are computed here rather than left to the BI tool. Rank 1 is highest
  # prevalence under each method.
  out$rank_unweighted <- rank(-out$pct_unweighted, ties.method = "first")
  out$rank_weighted   <- rank(-out$pct_weighted,   ties.method = "first")
  out$rank_shift      <- out$rank_unweighted - out$rank_weighted
  out$pct_difference  <- out$pct_weighted - out$pct_unweighted
  out
}

estimate_run <- function(d, measures, cache_dir, refresh = FALSE) {
  cache_path <- file.path(cache_dir, "estimates.rds")
  if (file.exists(cache_path) && !refresh) {
    message("       cached estimates")
    return(readRDS(cache_path))
  }

  national <- list()
  states <- list()
  for (nm in names(measures)) {
    t0 <- Sys.time()
    message("       national: ", nm, " (variance over 43,913 sampling units, slow)")
    national[[nm]] <- estimate_national(d, nm)
    message(sprintf("         %.1f%% weighted vs %.1f%% unweighted in %.0fs",
                    national[[nm]]$pct_weighted, national[[nm]]$pct_unweighted,
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))

    t0 <- Sys.time()
    message("       per-jurisdiction: ", nm)
    states[[nm]] <- estimate_states(d, nm)
    message(sprintf("         %d jurisdictions in %.0fs", nrow(states[[nm]]),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  out <- list(national = do.call(rbind, national), states = do.call(rbind, states))
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(out, cache_path)
  out
}
