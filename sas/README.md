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

**If the upload is impractical**, there is a weaker but honest alternative. The
value of this check is an independent *estimator*, not an independent *read* of
the file: export the design and measure columns from R as a CSV and point SAS at
that instead. The `PROC SURVEYFREQ` calls do not change. Say so in the main
README if you do it that way — a shared input is a smaller claim than two
programs reading the source file, and the difference should be stated rather
than quietly swapped.

## 4. Run

Edit the two paths at the top of `01_estimate.sas`, then run it. It writes
`sas_estimates.csv`.

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
