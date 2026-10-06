# Download, cache, and read the BRFSS public-use file.
#
# Three things here exist because they went wrong the first time:
#
#   mode = "wb" on the download. Without it R performs newline translation on a
#   binary zip under Windows, and unzip() then fails with an error that points
#   nowhere near the cause.
#
#   The member name is read out of the archive, never hardcoded. CDC has
#   shipped "LLCP2023.XPT " with a trailing space; trimws() on the listed name
#   costs nothing and survives that.
#
#   The extracted XPT is ~1 GB and the download ~79 MB, so both are cached and
#   neither is ever written into the repository. data/ is gitignored.

BRFSS_URL <- function(year) {
  sprintf("https://www.cdc.gov/brfss/annual_data/%d/files/LLCP%dXPT.zip", year, year)
}

ingest_download <- function(year, raw_dir, refresh = FALSE) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  zip_path <- file.path(raw_dir, sprintf("LLCP%dXPT.zip", year))

  if (file.exists(zip_path) && !refresh) {
    message(sprintf("       cached zip: %s (%.1f MB)",
                    basename(zip_path), file.size(zip_path) / 1e6))
    return(zip_path)
  }

  url <- BRFSS_URL(year)
  message("       downloading ", url)
  # mode = "wb": see the note at the top of this file.
  utils::download.file(url, destfile = zip_path, mode = "wb", quiet = TRUE)
  message(sprintf("       downloaded %.1f MB", file.size(zip_path) / 1e6))
  zip_path
}

ingest_extract <- function(zip_path, raw_dir, refresh = FALSE) {
  listing <- utils::unzip(zip_path, list = TRUE)
  member <- trimws(listing$Name[grepl("\\.XPT\\s*$", listing$Name, ignore.case = TRUE)][1])
  if (is.na(member) || !nzchar(member)) {
    stop("no .XPT member found inside ", basename(zip_path))
  }

  xpt_path <- file.path(raw_dir, member)
  if (file.exists(xpt_path) && !refresh) {
    message(sprintf("       cached XPT: %s (%.0f MB)", member, file.size(xpt_path) / 1e6))
    return(xpt_path)
  }

  message("       extracting ", member)
  # junkpaths keeps the trailing-space case from creating a nested directory.
  utils::unzip(zip_path, exdir = raw_dir, junkpaths = TRUE)
  extracted <- list.files(raw_dir, pattern = "\\.XPT\\s*$", ignore.case = TRUE, full.names = TRUE)
  if (!length(extracted)) stop("extraction produced no XPT in ", raw_dir)

  # If the archive carried a trailing space in the name, normalise it on disk so
  # every later path is predictable.
  wanted <- file.path(raw_dir, trimws(basename(extracted[1])))
  if (extracted[1] != wanted) file.rename(extracted[1], wanted)
  message(sprintf("       extracted %.0f MB", file.size(wanted) / 1e6))
  wanted
}

ingest_read <- function(xpt_path) {
  message("       reading XPT (this takes a couple of minutes)")
  t0 <- Sys.time()
  d <- haven::read_xpt(xpt_path)
  message(sprintf("       %s rows x %d columns in %.0fs",
                  format(nrow(d), big.mark = ","), ncol(d),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  d
}

ingest_run <- function(year, raw_dir, refresh = FALSE) {
  zip_path <- ingest_download(year, raw_dir, refresh)
  xpt_path <- ingest_extract(zip_path, raw_dir, refresh)
  list(xpt_path = xpt_path, data = ingest_read(xpt_path))
}
