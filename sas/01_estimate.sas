/* --------------------------------------------------------------------------
   BRFSS 2024 survey-weighted prevalence in SAS.

   This is the independent half of the cross-check. The point is not that SAS
   can do it too; it is that two different implementations of the same survey
   design, written against the same documented recode, have to land on the same
   number. If they do not, one of them has declared the design wrong, and the
   difference says which.

   One asymmetry worth knowing, because it is the thing most likely to make the
   two disagree: PROC SURVEYFREQ nests clusters inside strata by default, so
   there is no SAS equivalent of R's nest = TRUE to forget. BRFSS PSU ids repeat
   across strata, and in R that omission silently inflates or deflates the
   variance. Here it cannot happen. The reverse trap is the recode: SAS will
   happily treat 7 and 9 as ordinary values, so the IF/ELSE below has to mirror
   R/prepare.R exactly.

   Run order:
     1. upload LLCP2024.XPT to /home/<your-id>/brfss/ in SAS OnDemand
     2. edit BRFSS_PATH and OUT_PATH below
     3. run this program
     4. download sas_estimates.csv into data/exports/
     5. Rscript R/reconcile.R
   -------------------------------------------------------------------------- */

%let BRFSS_PATH = /home/YOUR_ID/brfss/LLCP2024.XPT;
%let OUT_PATH   = /home/YOUR_ID/brfss/sas_estimates.csv;

/* The XPT is a transport library; copy the member into WORK once. */
libname brfss xport "&BRFSS_PATH.";
proc copy in=brfss out=work;
run;

/* ---- recode: must match R/prepare.R code for code ------------------------ */
data analysis;
    set work.llcp2024;

    /* MEDCOST1: 1 = yes, 2 = no, 7 = don't know, 9 = refused.
       7 and 9 leave the denominator rather than counting as no. */
    if      MEDCOST1 = 1 then cost_barrier = 1;
    else if MEDCOST1 = 2 then cost_barrier = 0;
    else                      cost_barrier = .;

    /* DIABETE4: 1 = yes, 2 = yes but only during pregnancy, 3 = no,
       4 = no, pre-diabetes or borderline, 7 = don't know, 9 = refused.
       Only 1 is a yes and only 3 is a no; 2 and 4 are neither. */
    if      DIABETE4 = 1 then diabetes = 1;
    else if DIABETE4 = 3 then diabetes = 0;
    else                      diabetes = .;

    keep _STSTR _PSU _LLCPWT _STATE cost_barrier diabetes;
run;

/* ---- national ------------------------------------------------------------ */
ods output OneWay = nat_cost;
proc surveyfreq data=analysis;
    strata _STSTR;
    cluster _PSU;
    weight _LLCPWT;
    tables cost_barrier / cl;
run;
ods output close;

ods output OneWay = nat_diab;
proc surveyfreq data=analysis;
    strata _STSTR;
    cluster _PSU;
    weight _LLCPWT;
    tables diabetes / cl;
run;
ods output close;

/* ---- per jurisdiction ---------------------------------------------------- */
ods output CrossTabs = st_cost;
proc surveyfreq data=analysis;
    strata _STSTR;
    cluster _PSU;
    weight _LLCPWT;
    tables _STATE * cost_barrier / row cl;
run;
ods output close;

ods output CrossTabs = st_diab;
proc surveyfreq data=analysis;
    strata _STSTR;
    cluster _PSU;
    weight _LLCPWT;
    tables _STATE * diabetes / row cl;
run;
ods output close;

/* ---- reshape to one tidy row per (measure, scope, state_fips) ------------- */
data tidy_national;
    length measure $20 scope $10;
    set nat_cost(in=a) nat_diab(in=b);
    if a then do; measure = "cost_barrier"; value = cost_barrier; end;
    else          do; measure = "diabetes";     value = diabetes;     end;
    if value ne 1 then delete;              /* keep the "yes" level only */
    scope      = "national";
    state_fips = .;
    pct        = Percent;
    se         = StdErr;
    ci_low     = LowerCL;
    ci_high    = UpperCL;
    keep measure scope state_fips pct se ci_low ci_high;
run;

data tidy_state;
    length measure $20 scope $10;
    set st_cost(in=a) st_diab(in=b);
    if a then do; measure = "cost_barrier"; value = cost_barrier; end;
    else          do; measure = "diabetes";     value = diabetes;     end;
    if value ne 1 then delete;
    if missing(_STATE) then delete;         /* drop the ODS total rows */
    scope      = "state";
    state_fips = _STATE;
    pct        = RowPercent;                /* within-state, not of the nation */
    se         = RowStdErr;
    ci_low     = RowLowerCL;
    ci_high    = RowUpperCL;
    keep measure scope state_fips pct se ci_low ci_high;
run;

data sas_estimates;
    set tidy_national tidy_state;
run;

proc export data=sas_estimates
    outfile="&OUT_PATH."
    dbms=csv replace;
run;

proc print data=tidy_national noobs;
    title "National prevalence, SAS - compare against R/data/exports/national_estimates.csv";
run;
