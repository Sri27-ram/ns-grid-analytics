# NS Grid Generation Analytics

A SQL pipeline feeding a Tableau dashboard on Nova Scotia's electricity
generation mix from 2008 to 2026 (dashboard in progress - the SQL side is
done, the exported CSVs are ready, Tableau build steps are below). Built
this to get real practice with the kind of work a Data Analyst co-op
actually does: pulling in a messy government dataset, reconciling numbers
that are supposed to match but don't always, and turning it into something
a dashboard can actually use.

## Where the data comes from

I used [Statistics Canada Table 25-10-0015-01](https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=2510001501)
("Electric power generation, monthly generation by type of electricity"),
filtered down to just Nova Scotia. It's published under the
[Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada),
so it's free to use as long as I credit the source (doing that below too).
After filtering, that's 5,280 rows covering 222 months (Jan 2008 - Jun
2026), broken down by producer class (electric utilities vs. industries
vs. the total) and by generation type (hydro, wind, solar, tidal, biomass,
combustible fuels, other).

## How the pipeline is put together

```
data/raw/nova_scotia_generation.csv   -- raw StatCan extract, NS rows only
        │  sql/01_schema.sql  → generation_raw (staging table + indexes)
        │  sql/02_load.sql    → \copy load + type conversion
        ▼
sql/03_reconciliation.sql              sql/04_marts.sql
  v_reconciliation_check                 mv_monthly_generation_mix
  v_reconciliation_summary
        │                                       │
        ▼                                       ▼
data/exports/ns_reconciliation_*.csv   data/exports/ns_monthly_generation_mix.csv
```

Run the SQL files in order against Postgres: `01_schema.sql` →
`02_load.sql` → `03_reconciliation.sql` → `04_marts.sql`.

## Reconciling the numbers

StatCan reports a "Total all classes of electricity producer" number for
every month and generation type, and that number is supposed to equal
"electric utilities" + "industries" added together. I didn't want to just
trust that it always adds up, so `v_reconciliation_check` recomputes the
sum itself and flags anything that doesn't match. It also separately flags
rows where one of the source numbers was confidentiality-suppressed by
StatCan (shown as `'..'` in the raw data) instead of just treating a
missing number as zero, which would have quietly skewed things.

Across all 1,866 month/type combinations: 0 actual mismatches. 1,356 rows
(72.7%) reconcile cleanly, and 510 (27.3%) get flagged `SUPPRESSED_SOURCE`
because StatCan hides the utilities/industries split for some cells so a
single producer's output can't be identified. Those get flagged as
low-confidence instead of being reconciled as if the missing half were
zero.

## A bug I caught while building the mart

While building the monthly mix mart I found that StatCan changed how it
breaks this data down three separate times between 2008 and 2026 - I
noticed by checking the earliest/latest month each generation_type
actually shows up for. From 2008-2015 only the turbine-level fossil rows
exist. From 2016-2019 it adds a combined "combustible fuels" subtotal.
From 2020 on, that subtotal splits further into biomass vs.
non-renewable combustible. My first version of the mart summed the
turbine-type rows *and* the newer subtotal together for recent months,
which double-counted the same generation. I only caught it because I ran
a sanity check comparing my computed monthly total against StatCan's own
reported total and the numbers didn't line up for anything after 2020.
Fixed it so `non_renewable_mwh` falls back through the three eras with
`COALESCE` instead, picking whichever source actually exists for that
month. Re-ran the same check afterward: 0 mismatches across all 222
months.

## Making the queries faster

`mv_monthly_generation_mix` is a materialized view instead of a regular
view, so the dashboard reads one pre-computed row per month instead of
re-running an 8-way conditional pivot over all 5,280 raw rows every time
someone touches a filter. I checked this with `EXPLAIN ANALYZE`: the raw
pivot query takes about 1.73ms, the materialized view read takes about
0.12ms - roughly 15x faster. Not a huge deal at this data size, but the
point is the same optimization matters a lot more once you're not
re-aggregating from scratch on every dashboard click.

## Files the dashboard actually uses

- `data/exports/ns_monthly_generation_mix.csv` - one row per month:
  generation by fuel type in MWh, the renewable/non-renewable split, and
  `renewable_share_pct`. This is the main file Tableau connects to.
- `data/exports/ns_reconciliation_check.csv` - per month/type
  reconciliation result and flag.
- `data/exports/ns_reconciliation_summary.csv` - just the 3-row summary of
  how many rows landed in each flag category.

## Building the Tableau dashboard from here

1. Tableau Public Desktop → **Connect → Text File** → pick
   `data/exports/ns_monthly_generation_mix.csv`. Make sure `ref_date` comes
   in as a Date and the `*_mwh` columns come in as Numbers.
2. Add a second data source connection to `ns_reconciliation_summary.csv`
   (only needed for the data-quality tile in step 6).
3. Sheet 1, "Generation Mix Over Time": `ref_date` (continuous month) on
   Columns, and `hydro_mwh` / `wind_mwh` / `solar_mwh` / `tidal_mwh` /
   `biomass_mwh` / `non_renewable_combustible_mwh` / `other_mwh` all
   dragged onto Rows as Measure Values, Measure Names on Color, as a
   stacked area chart. Rename the legend entries to
   Hydro/Wind/Solar/Tidal/Biomass/Fossil/Other, greens and blues for the
   renewables so they group together visually, grey for Fossil/Other.
4. Sheet 2, "Renewable Share Trend": `ref_date` on Columns,
   `renewable_share_pct` on Rows as a line chart, plus a linear trend line
   since the whole point is the climb from ~10% to ~36%.
5. Sheet 3, "Reconciliation Data Quality": bar chart, `reconciliation_flag`
   on Columns, `row_count` on Rows, colored green for OK / amber for
   SUPPRESSED_SOURCE. This is the chart that backs up the reconciliation
   work from the SQL side.
6. New Dashboard, combine all three: mix chart big at the top, the other
   two side by side underneath. One Year filter on `ref_date` applied to
   all three sheets. Title it "Nova Scotia Electricity Generation Mix,
   2008-2026" with a footer crediting Statistics Canada.
7. Publish to Tableau Public, link goes here once it's up: _(TODO)_

## License

Contains information licensed under the Open Government Licence – Canada.
Source: Statistics Canada, Table 25-10-0015-01.
