# Column mapping, measure definitions, and the recode.
#
# The design columns are renamed once, here. BRFSS names them `_LLCPWT`,
# `_STSTR` and `_PSU`; a leading underscore has to be backticked inside every
# survey formula, which makes `svydesign(ids = ~`_PSU`, ...)` both unreadable
# and easy to get subtly wrong. They become weight / stratum / psu and stay that
# way for the rest of the pipeline.
#
# MEASURES is the extension point. Each entry names its raw column and, just as
# importantly, says which codes are yes, which are no, and which leave the
# denominator entirely. Adding a third measure is a few lines; every recode
# check loops over this list.

DESIGN_COLUMNS <- c(weight = "_LLCPWT", stratum = "_STSTR", psu = "_PSU", state_fips = "_STATE")

# 7 = "don't know / not sure" and 9 = "refused" appear on almost every BRFSS
# question. Folding them into "no" is the most common way to understate a
# prevalence, so they leave the denominator and a validation check asserts it.
MEASURES <- list(
  cost_barrier = list(
    label  = "Could not see a doctor in the past 12 months due to cost",
    column = "MEDCOST1",
    yes    = 1L,
    no     = 2L,
    drop   = c(7L, 9L)
  ),
  diabetes = list(
    label  = "Ever told they have diabetes",
    column = "DIABETE4",
    yes    = 1L,
    no     = 3L,
    # 2 = "yes, but only during pregnancy" and 4 = "no, pre-diabetes or
    # borderline". Neither is a yes and neither is a no, so both leave the
    # denominator rather than being forced to one side.
    drop   = c(2L, 4L, 7L, 9L)
  )
)

# Jurisdiction names, keyed by FIPS. BRFSS carries the 50 states, DC, and three
# territories.
STATE_NAMES <- c(
  "1" = "Alabama", "2" = "Alaska", "4" = "Arizona", "5" = "Arkansas", "6" = "California",
  "8" = "Colorado", "9" = "Connecticut", "10" = "Delaware", "11" = "District of Columbia",
  "12" = "Florida", "13" = "Georgia", "15" = "Hawaii", "16" = "Idaho", "17" = "Illinois",
  "18" = "Indiana", "19" = "Iowa", "20" = "Kansas", "21" = "Kentucky", "22" = "Louisiana",
  "23" = "Maine", "24" = "Maryland", "25" = "Massachusetts", "26" = "Michigan",
  "27" = "Minnesota", "28" = "Mississippi", "29" = "Missouri", "30" = "Montana",
  "31" = "Nebraska", "32" = "Nevada", "33" = "New Hampshire", "34" = "New Jersey",
  "35" = "New Mexico", "36" = "New York", "37" = "North Carolina", "38" = "North Dakota",
  "39" = "Ohio", "40" = "Oklahoma", "41" = "Oregon", "42" = "Pennsylvania",
  "44" = "Rhode Island", "45" = "South Carolina", "46" = "South Dakota", "47" = "Tennessee",
  "48" = "Texas", "49" = "Utah", "50" = "Vermont", "51" = "Virginia", "53" = "Washington",
  "54" = "West Virginia", "55" = "Wisconsin", "56" = "Wyoming", "66" = "Guam",
  "72" = "Puerto Rico", "78" = "Virgin Islands"
)

#' Resolve a column that the CDC may have renamed between years.
#'
#' BRFSS suffixes question variables with a version number (MEDCOST1 was
#' MEDCOST, DIABETE4 was DIABETE3). Failing loudly with the candidates listed
#' beats silently analysing the wrong column.
resolve_column <- function(d, wanted) {
  if (wanted %in% names(d)) return(wanted)
  stem <- sub("[0-9]+$", "", wanted)
  candidates <- grep(paste0("^", stem, "[0-9]*$"), names(d), value = TRUE)
  if (length(candidates) == 1) {
    message(sprintf("       note: %s not present; using %s", wanted, candidates))
    return(candidates)
  }
  stop(sprintf("cannot resolve column %s. Candidates in this file: %s",
               wanted, if (length(candidates)) paste(candidates, collapse = ", ") else "none"))
}

recode_measure <- function(values, spec) {
  out <- rep(NA_integer_, length(values))
  out[values %in% spec$yes] <- 1L
  out[values %in% spec$no]  <- 0L
  # Everything else — the drop codes and any genuine NA — stays NA and is
  # therefore outside the denominator.
  out
}

prepare_run <- function(raw, cache_dir, refresh = FALSE) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_path <- file.path(cache_dir, "frame.rds")
  if (file.exists(cache_path) && !refresh) {
    message("       cached analysis frame")
    return(readRDS(cache_path))
  }

  missing <- setdiff(DESIGN_COLUMNS, names(raw))
  if (length(missing)) stop("design columns absent from the file: ", paste(missing, collapse = ", "))

  d <- data.frame(
    weight     = as.numeric(raw[[DESIGN_COLUMNS[["weight"]]]]),
    stratum    = as.integer(raw[[DESIGN_COLUMNS[["stratum"]]]]),
    psu        = as.numeric(raw[[DESIGN_COLUMNS[["psu"]]]]),
    state_fips = as.integer(raw[[DESIGN_COLUMNS[["state_fips"]]]]),
    stringsAsFactors = FALSE
  )
  d$state_name <- unname(STATE_NAMES[as.character(d$state_fips)])

  for (nm in names(MEASURES)) {
    spec <- MEASURES[[nm]]
    col <- resolve_column(raw, spec$column)
    values <- as.integer(raw[[col]])
    d[[nm]] <- recode_measure(values, spec)
    # Keep the raw codes alongside so the recode checks can compare against
    # them without re-reading the 1 GB file.
    d[[paste0(nm, "_raw")]] <- values
  }

  saveRDS(d, cache_path, compress = "xz")
  message(sprintf("       analysis frame: %s rows, %d columns (cached, %.1f MB)",
                  format(nrow(d), big.mark = ","), ncol(d), file.size(cache_path) / 1e6))
  d
}
