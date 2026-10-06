/* --------------------------------------------------------------------------
   BRFSS 2024 survey-weighted prevalence in SAS — the cloud-friendly variant.

   Same estimates as 01_estimate.sas, reading the six prepared columns instead
   of the 1 GB XPT. Use this when SAS lives somewhere the source file does not,
   which in practice means SAS OnDemand for Academics.

   WHAT THIS STILL PROVES, AND WHAT IT DOES NOT.

   Still proves: two independent *estimators* agree. SAS computes the design
   effect, the variance and the confidence bounds with its own code, and if the
   two disagree, one of them declared the design wrong.

   No longer proves: that both programs read and recoded the source file the
   same way, because the recode happened once, in R. A transcription error
   there would appear in both answers and cancel out.

   That is a smaller claim and the README says so. Run 01_estimate.sas against
   the XPT once a local SAS licence is available, and the full claim is back.

   Steps:
     1. upload data/exports/brfss_for_sas.csv to /home/<your-id>/brfss/
     2. edit the two paths below
     3. run
     4. download sas_estimates.csv into data/exports/
     5. Rscript R/reconcile.R
   -------------------------------------------------------------------------- */

%let IN_PATH  = /home/YOUR_ID/brfss/brfss_for_sas.csv;
%let OUT_PATH = /home/YOUR_ID/brfss/sas_estimates.csv;

proc import datafile="&IN_PATH."
    out=analysis
    dbms=csv
    replace;
    getnames=yes;
    guessingrows=max;   /* the weight column is wide; do not let SAS guess from 20 rows */
run;

/* The recode already happened in R. Assert the shape SAS received rather than
   trusting it: these three numbers are in the R validation output, and if they
   do not match here, the upload truncated. */
proc sql;
    create table shape as
    select count(*)                                            as n_rows,
           sum(case when cost_barrier is not missing then 1 else 0 end) as n_cost,
           sum(case when diabetes     is not missing then 1 else 0 end) as n_diab,
           min(weight)                                         as min_weight,
           count(distinct state_fips)                          as n_states
    from analysis;
quit;

proc print data=shape noobs;
    title "Expect 457,670 rows / 455,997 cost / 441,934 diabetes / 53 jurisdictions";
run;

/* ---- national ------------------------------------------------------------ */
ods output OneWay = nat_cost;
proc surveyfreq data=analysis;
    strata stratum;
    cluster psu;
    weight weight;
    tables cost_barrier / cl;
run;
ods output close;

ods output OneWay = nat_diab;
proc surveyfreq data=analysis;
    strata stratum;
    cluster psu;
    weight weight;
    tables diabetes / cl;
run;
ods output close;

/* ---- per jurisdiction ---------------------------------------------------- */
ods output CrossTabs = st_cost;
proc surveyfreq data=analysis;
    strata stratum;
    cluster psu;
    weight weight;
    tables state_fips * cost_barrier / row cl;
run;
ods output close;

ods output CrossTabs = st_diab;
proc surveyfreq data=analysis;
    strata stratum;
    cluster psu;
    weight weight;
    tables state_fips * diabetes / row cl;
run;
ods output close;

/* ---- reshape to one tidy row per (measure, scope, state_fips) ------------- */
data tidy_national;
    length measure $20 scope $10;
    set nat_cost(in=a) nat_diab(in=b);
    if a then do; measure = "cost_barrier"; value = cost_barrier; end;
    else          do; measure = "diabetes";     value = diabetes;     end;
    if value ne 1 then delete;          /* the "yes" level only */
    scope      = "national";
    state_fips = .;
    pct = Percent; se = StdErr; ci_low = LowerCL; ci_high = UpperCL;
    keep measure scope state_fips pct se ci_low ci_high;
run;

data tidy_state;
    length measure $20 scope $10;
    set st_cost(in=a) st_diab(in=b);
    if a then do; measure = "cost_barrier"; value = cost_barrier; end;
    else          do; measure = "diabetes";     value = diabetes;     end;
    if value ne 1 then delete;
    if missing(state_fips) then delete;  /* drop the ODS total rows */
    scope  = "state";
    pct = RowPercent; se = RowStdErr; ci_low = RowLowerCL; ci_high = RowUpperCL;
    keep measure scope state_fips pct se ci_low ci_high;
run;

data sas_estimates;
    set tidy_national tidy_state;
run;

proc export data=sas_estimates outfile="&OUT_PATH." dbms=csv replace;
run;

proc print data=tidy_national noobs;
    title "National prevalence, SAS - expect 12.3338% cost barrier and 12.9807% diabetes";
run;
