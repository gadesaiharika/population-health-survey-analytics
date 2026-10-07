# Running the SAS half

SAS is the independent check on the R estimates. You need an account; the rest
is mechanical.

## 1. Get access

Register at <https://welcome.oda.sas.com> — **SAS OnDemand for Academics**, free,
browser-based. Approval takes about a day, so do this before anything else.

## 2. Build the R side first

```powershell
Rscript run.R
```

SAS needs `data/raw/LLCP2024.XPT` — the **extracted XPT, not the zip**. `run.R`
leaves it there.

## 3. Upload

In SAS Studio: **Files → Upload** into `/home/<your-id>/brfss/`.

The XPT is about 1 GB and the upload is slow. The default quota is 5 GB, which
is enough.

**If the upload is impractical — and in SAS OnDemand it usually is —** use
`02_estimate_from_csv.sas` instead. Generate its input first:

```powershell
Rscript R/export_for_sas.R
```

That writes `data/exports/brfss_for_sas.csv`: the six columns SAS needs,
**19.5 MB instead of 1 GB**, which uploads in seconds. The `PROC SURVEYFREQ`
calls are identical.

Be straight about the trade. The strongest version of this check has two
programs reading the source file independently, so a transcription error in
either one shows up as disagreement. The CSV route shares R's read and recode,
so it still proves the two *estimators* agree — design effect, variance,
confidence bounds — but no longer proves both read the file the same way. The
program says so at the top, and the main README says so too. Run
`01_estimate.sas` against the XPT once a local licence is available and the
full claim is back.

## 4. Run

Edit the two paths at the top of `01_estimate.sas`, then run it. It writes
`sas_estimates.csv`.

## A trap worth knowing: apostrophes in paths

`%let` values are read by the macro processor, and an apostrophe starts a
quoted string. One in a folder name — `Master Resume and prompt's` is a real
example — swallows the rest of the program. The `LIBNAME` never executes, and
the errors SAS prints point at `PROC SURVEYFREQ` statements fifty lines below
the actual problem:

```
ERROR 22-7: Invalid option name COST_BARRIER.
ERROR: Libref BRFSS is not assigned.
```

Either mask it with `%str(...%'...)`, or run SAS with its working directory
set to the folder holding the file and pass a bare filename. The second is
what this project does locally:

```powershell
cd data\raw
& "C:\Program Files\SASHome\SASFoundation\9.4\sas.exe" -sysin 01_estimate.sas
```

## 5. Reconcile

Download that CSV into `data/exports/`, then:

```powershell
Rscript R/reconcile.R
```

Tolerance is **0.01 percentage points** on the point estimate. The two should
agree far more tightly; the tolerance absorbs the different degrees-of-freedom
conventions SAS and the `survey` package use for confidence bounds.

A point estimate off by more than rounding is not a tolerance problem. It means
the designs were declared differently, and the usual causes, in order:

1. **The recode drifted.** Do 7 and 9 leave the denominator in both programs?
   Does diabetes drop 2 and 4 in both?
2. **STRATA / CLUSTER / WEIGHT** do not match `ids` / `strata` / `weights`.
3. SAS read a different file than R did.

## Why the asymmetry matters

`PROC SURVEYFREQ` nests clusters inside strata by default, so SAS has no
equivalent of R's `nest = TRUE` to forget. BRFSS PSU ids repeat across strata —
25,800 of 43,913 — and in R, omitting `nest = TRUE` silently gets the variance
wrong while leaving the point estimate looking fine.

That is the single best reason to run both: the two tools fail in different
places, so agreement between them is worth more than either one alone.
