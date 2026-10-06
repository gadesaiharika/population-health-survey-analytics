#!/usr/bin/env Rscript
#
# Build the whole survey analysis in one command.
#
#     Rscript run.R
#
# Steps:
#   1. ingest    download the CDC BRFSS public-use file, cache it, read the XPT
#   2. prepare   map design columns, recode the measures, cache a slim frame
#   3. estimate  national and per-jurisdiction prevalence, weighted and not
#   4. validate  41 checks across design, recode, and both estimate levels
#   5. export    three CSVs to data/exports/
#
# The first run downloads 79 MB, expands it to a 1 GB XPT, and spends most of
# its time on the national variance over 43,913 sampling units. Budget 25-30
# minutes. Everything expensive is cached afterwards:
#
#   --refresh         ignore every cache and rebuild from the download
#   --validate-only   reuse cached estimates, re-run the checks
#   --export-only     reuse cached estimates, rewrite the CSVs
#   --year YYYY       a different BRFSS year (2022 and 2023 are also published)

suppressWarnings(suppressMessages({
  args <- commandArgs(trailingOnly = TRUE)
}))

REPO <- normalizePath(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])), mustWork = FALSE)
if (is.na(REPO) || !nzchar(REPO)) REPO <- getwd()

RAW_DIR    <- file.path(REPO, "data", "raw")
CACHE_DIR  <- file.path(REPO, "data", "cache")
EXPORT_DIR <- file.path(REPO, "data", "exports")

opt <- list(
  refresh       = "--refresh"       %in% args,
  validate_only = "--validate-only" %in% args,
  export_only   = "--export-only"   %in% args,
  year          = 2024L
)
if ("--year" %in% args) opt$year <- as.integer(args[which(args == "--year") + 1])

banner <- function(step, text) message(sprintf("\n[%s] %s", step, text))

# A clone on a fresh machine should not need a setup ritual. If the two
# packages are missing, install them into the user library and carry on.
ensure_packages <- function(pkgs = c("haven", "survey")) {
  user_lib <- Sys.getenv("R_LIBS_USER")
  if (nzchar(user_lib)) {
    dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(user_lib, .libPaths()))
  }
  missing <- setdiff(pkgs, rownames(installed.packages()))
  if (length(missing)) {
    message("       installing: ", paste(missing, collapse = ", "))
    install.packages(missing, repos = "https://cloud.r-project.org",
                     lib = if (nzchar(user_lib)) user_lib else .libPaths()[1])
  }
  invisible(lapply(pkgs, function(p) suppressPackageStartupMessages(
    library(p, character.only = TRUE))))
}

started <- Sys.time()
ensure_packages()

for (f in c("ingest.R", "prepare.R", "estimate.R", "validate.R", "export.R")) {
  source(file.path(REPO, "R", f))
}

elapsed <- function() as.numeric(difftime(Sys.time(), started, units = "secs"))

if (opt$validate_only || opt$export_only) {
  frame_path <- file.path(CACHE_DIR, "frame.rds")
  est_path   <- file.path(CACHE_DIR, "estimates.rds")
  if (!file.exists(frame_path) || !file.exists(est_path)) {
    stop("no cache to reuse - run `Rscript run.R` once first")
  }
  d <- readRDS(frame_path)
  est <- readRDS(est_path)
} else {
  banner("1/5", sprintf("Ingesting BRFSS %d", opt$year))
  ing <- ingest_run(opt$year, RAW_DIR, refresh = opt$refresh)

  banner("2/5", "Preparing the analysis frame")
  d <- prepare_run(ing$data, CACHE_DIR, refresh = opt$refresh)
  rm(ing); invisible(gc())

  banner("3/5", "Estimating prevalence")
  est <- estimate_run(d, MEASURES, CACHE_DIR, refresh = opt$refresh)
}

if (!opt$export_only) {
  banner("4/5", "Validating")
  res <- validate_run(d, est, MEASURES)
  validate_print(res)
  message(sprintf("\n       %d passed, %d failed", res$passed, res$failed))
  if (res$failed > 0) {
    message("\nFAILED - the estimates do not agree with the file they came from; not exporting.")
    quit(status = 1)
  }
}

if (!opt$validate_only) {
  banner("5/5", "Exporting")
  written <- export_run(est, MEASURES, EXPORT_DIR)
  for (nm in names(written)) message(sprintf("       %-20s %4d rows", nm, written[[nm]]))
}

message(sprintf("\nOK - built, validated, and exported in %.0fs", elapsed()))
