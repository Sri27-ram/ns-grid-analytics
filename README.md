# NS Grid Generation Analytics

SQL data pipeline and reconciliation layer behind a Tableau Public dashboard
on Nova Scotia's electricity generation mix, 2008–2026.

## Data source

[Statistics Canada Table 25-10-0015-01](https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=2510001501),
"Electric power generation, monthly generation by type of electricity,"
filtered to Nova Scotia. Published under the
[Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).
5,280 raw rows, 222 months (Jan 2008 – Jun 2026), covering generation by
producer class (electric utilities / industries / total) and by generation
type (hydro, wind, solar, tidal, biomass, combustible fuels, other).

## Pipeline

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

Run in order against Postgres: `01_schema.sql` → `02_load.sql` →
`03_reconciliation.sql` → `04_marts.sql`.

## Report reconciliation

StatCan publishes a "Total all classes of electricity producer" figure for
every month/generation-type, which should equal the sum of its two
components ("electric utilities" + "industries"). `v_reconciliation_check`
independently recomputes that sum and flags any row where it doesn't match
the reported total, and separately flags rows where a source component was
confidentiality-suppressed (`'..'`) rather than silently treating it as
zero.

Result across all 1,866 month/type combinations: **0 true mismatches**,
1,356 (72.7%) clean, 510 (27.3%) flagged `SUPPRESSED_SOURCE` — StatCan
withholds the utilities/industries split for some cells to avoid disclosing
a single producer's output, so those rows are flagged as
low-confidence rather than reconciled as if the missing side were zero.

## Data-quality finding from building the mix mart

StatCan's own category breakdown changed three times across the 2008–2026
series (confirmed by checking each generation_type's min/max reporting
date): a 2008–2015 era with only turbine-level fossil rows, a 2016–2019 era
that adds a combined combustible-fuels subtotal, and a 2020+ era that
further splits that subtotal into biomass vs. non-renewable combustible.
The mart's `non_renewable_mwh` column falls back through all three sources
via `COALESCE` so every month is covered by exactly one non-overlapping
source. Verified by reconciling `mv_monthly_generation_mix.total_mwh`
against StatCan's own reported grand total for all 222 months: **0
mismatches**. An earlier version of this view (summing the fossil
turbine-type rows *and* the non-renewable-combustible subtotal together)
double-counted recent months and was caught by this same validation step
before being fixed.

## Query optimization

`mv_monthly_generation_mix` is a materialized view, not a plain view,
specifically so the dashboard's repeated filter/refresh requests read one
pre-aggregated row per month instead of re-running the 8-way conditional
pivot over all 5,280 raw rows each time. Benchmarked with `EXPLAIN
ANALYZE`: the raw pivot query runs in ~1.73ms; the materialized view read
runs in ~0.12ms — about a 15x reduction, on a dataset this size, in the
work repeated on every dashboard interaction.

## Files for the dashboard

- `data/exports/ns_monthly_generation_mix.csv` — one row per month:
  generation by fuel type (MWh), renewable/non-renewable split, and
  `renewable_share_pct`. **Primary data source for the dashboard.**
- `data/exports/ns_reconciliation_check.csv` — per month/type reconciliation
  result and flag. Used for the data-quality tile.
- `data/exports/ns_reconciliation_summary.csv` — the 3-row flag summary
  above.

## Building the Tableau Public dashboard

1. Open Tableau Public Desktop → **Connect → Text File** → select
   `data/exports/ns_monthly_generation_mix.csv`. Confirm `ref_date` is typed
   as Date and every `*_mwh` column is typed as Number (Decimal).
2. **New Data Source** → also connect `ns_reconciliation_summary.csv` (used
   only for the data-quality tile in step 6).
3. On Sheet 1, build **"Generation Mix Over Time"**: `ref_date` (continuous
   month) on Columns, `hydro_mwh` / `wind_mwh` / `solar_mwh` / `tidal_mwh` /
   `biomass_mwh` / `non_renewable_combustible_mwh` / `other_mwh` on Rows as
   a stacked area chart (drag all seven onto Rows as Measure Values, put
   Measure Names on Color). Rename the Measure Names legend entries to
   Hydro/Wind/Solar/Tidal/Biomass/Fossil/Other. Use a sequential-to-diverging
   palette: greens/blues for the five renewable series, a neutral grey for
   Fossil and Other, so renewables visually group together.
4. New sheet, **"Renewable Share Trend"**: `ref_date` on Columns,
   `renewable_share_pct` on Rows as a line chart. Add a reference line at
   the current national/provincial average if you want a comparison point.
   Add a trend line (Analytics pane → Trend Line → Linear) since the story
   is the 2008→2026 climb.
5. New sheet, **"Reconciliation Data Quality"**: bar chart of
   `reconciliation_flag` (Columns) vs `row_count` (Rows) from the summary
   CSV, colored by flag (green=OK, amber=SUPPRESSED_SOURCE). This is the
   tile that visually backs up the reconciliation work in the SQL layer.
6. New **Dashboard**: combine all three sheets. Put "Generation Mix Over
   Time" large at top, "Renewable Share Trend" and "Reconciliation Data
   Quality" side by side below. Add a single Year filter (from
   `ref_date`) applied to all three sheets (right-click filter → Apply to
   Worksheets → All Using This Data Source). Title it "Nova Scotia
   Electricity Generation Mix, 2008–2026". Add a caption/footer crediting
   "Source: Statistics Canada Table 25-10-0015-01, Open Government Licence
   – Canada."
7. **Server → Publish Workbook** to Tableau Public. Grab the published
   dashboard's public URL for the resume/GitHub link.

## License / attribution

Contains information licensed under the Open Government Licence – Canada.
Source: Statistics Canada, Table 25-10-0015-01.
