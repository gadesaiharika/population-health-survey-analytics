#!/usr/bin/env Rscript
#
# Write the six columns SAS needs, so the cross-check can run without uploading
# a 1 GB XPT into a cloud account.
#
#     Rscript R/export_for_sas.R
#
# Be clear about what this costs. The strongest version of the cross-check has
# two programs reading the source file independently: a transcription error in
# either one shows up as disagreement. This version shares R's read and recode,
# so what it still proves is that two different *estimators* agree on the same
# input — the survey design, the variance, the confidence bounds. What it no
# longer proves is that both read the file the same way.
#
# That is a smaller claim, and the README says so rather than quietly swapping
# one for the other. When the local SAS licence arrives, run 01_estimate.sas
# against the XPT and the full claim is back.

REPO <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])), ".."), mustWork = FALSE)

frame_path <- file.path(REPO, "data", "cache", "frame.rds")
if (!file.exists(frame_path)) stop("run `Rscript run.R` first - no cached frame")

d <- readRDS(frame_path)
out <- d[, c("weight", "stratum", "psu", "state_fips", "cost_barrier", "diabetes")]

dir.create(file.path(REPO, "data", "exports"), recursive = TRUE, showWarnings = FALSE)
path <- file.path(REPO, "data", "exports", "brfss_for_sas.csv")

# Missing values must reach SAS as empty fields, not as "NA" text, or the
# recode checks on the SAS side will read them as a character value.
utils::write.csv(out, path, row.names = FALSE, na = "")

cat(sprintf("wrote %s\n  %s rows x %d columns, %.1f MB\n",
            path, format(nrow(out), big.mark = ","), ncol(out), file.size(path) / 1e6))
cat(sprintf("  analytic n: cost_barrier %s, diabetes %s\n",
            format(sum(!is.na(out$cost_barrier)), big.mark = ","),
            format(sum(!is.na(out$diabetes)), big.mark = ",")))
