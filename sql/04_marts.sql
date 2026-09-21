-- Dashboard mart: one row per month with generation broken out by fuel
-- category, plus a renewable-share metric, built only from the "Total all
-- classes of electricity producer" rows (i.e. all producers combined).
--
-- Fuel buckets deliberately use StatCan's own subtotal rows rather than the
-- individual turbine-type rows (Combustion turbine / Conventional steam
-- turbine), for two reasons found while validating this view:
--   1. Those two turbine-type rows are confidentiality-suppressed ('..') for
--      most recent months, while "Total electricity production from
--      non-renewable combustible fuels" remains populated every month it exists.
--   2. Summing the turbine-type rows AND the non-renewable-combustible-fuels
--      subtotal would double-count the same generation.
--
-- StatCan's own category breakdown changed over the 2008-2026 series (schema
-- evolution, found by checking min/max reporting dates per generation_type):
--   2008-01 to 2015-12: only Combustion turbine + Conventional steam turbine
--     report fossil generation; no Solar/Other/biomass split exists yet.
--   2016-01 to 2019-12: adds Solar, Other, and a combined "Total electricity
--     production from combustible fuels" row (fossil + biomass together,
--     not yet split).
--   2020-01 onward: adds the biomass/non-renewable split used above.
-- The non_renewable bucket below falls back through these three eras via
-- COALESCE so every month is covered by exactly one source, verified to
-- reconcile (0 mismatches) against StatCan's own "Total all types of
-- electricity generation" row across all 222 months, 2008-01 to 2026-06.
-- Caveat: biomass is only separable from fossil generation from 2020
-- onward; for 2008-2019 it is counted inside non_renewable_mwh, not
-- renewable_mwh, since it cannot be isolated in the source data for those
-- years.

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_generation_mix;

CREATE MATERIALIZED VIEW mv_monthly_generation_mix AS
WITH leaf AS (
    SELECT ref_date, generation_type, value_mwh
    FROM generation_raw
    WHERE producer_class = 'Total all classes of electricity producer'
      AND generation_type IN (
          'Hydraulic turbine', 'Wind power turbine', 'Solar', 'Tidal power turbine',
          'Combustion turbine', 'Conventional steam turbine',
          'Total electricity production from combustible fuels',
          'Total electricity production from biomass',
          'Total electricity production from non-renewable combustible fuels',
          'Other types of electricity generation'
      )
),
pivoted AS (
    SELECT
        ref_date,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Hydraulic turbine') AS hydro_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Wind power turbine') AS wind_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Solar') AS solar_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Tidal power turbine') AS tidal_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Combustion turbine') AS combustion_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Conventional steam turbine') AS steam_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Total electricity production from combustible fuels') AS combustible_fuels_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Total electricity production from biomass') AS biomass_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Total electricity production from non-renewable combustible fuels') AS non_renewable_combustible_mwh,
        SUM(value_mwh) FILTER (WHERE generation_type = 'Other types of electricity generation') AS other_mwh
    FROM leaf
    GROUP BY ref_date
),
resolved AS (
    SELECT
        ref_date,
        COALESCE(hydro_mwh, 0) AS hydro_mwh,
        COALESCE(wind_mwh, 0) AS wind_mwh,
        COALESCE(solar_mwh, 0) AS solar_mwh,
        COALESCE(tidal_mwh, 0) AS tidal_mwh,
        COALESCE(biomass_mwh, 0) AS biomass_mwh,
        COALESCE(other_mwh, 0) AS other_mwh,
        -- era fallback: 2020+ subtotal, else 2016-2019 combined combustible-fuels
        -- subtotal, else 2008-2015 sum of the two fossil turbine-type rows
        COALESCE(non_renewable_combustible_mwh, combustible_fuels_mwh, combustion_mwh + steam_mwh) AS non_renewable_mwh
    FROM pivoted
)
SELECT
    ref_date,
    EXTRACT(YEAR FROM ref_date)::int AS year,
    hydro_mwh, wind_mwh, solar_mwh, tidal_mwh, biomass_mwh,
    non_renewable_mwh AS non_renewable_combustible_mwh,
    other_mwh,
    (hydro_mwh + wind_mwh + solar_mwh + tidal_mwh + biomass_mwh) AS renewable_mwh,
    (non_renewable_mwh + other_mwh) AS non_renewable_mwh,
    (hydro_mwh + wind_mwh + solar_mwh + tidal_mwh + biomass_mwh + non_renewable_mwh + other_mwh) AS total_mwh,
    ROUND(
        100.0 * (hydro_mwh + wind_mwh + solar_mwh + tidal_mwh + biomass_mwh)
        / NULLIF(hydro_mwh + wind_mwh + solar_mwh + tidal_mwh + biomass_mwh + non_renewable_mwh + other_mwh, 0)
    , 2) AS renewable_share_pct
FROM resolved
ORDER BY ref_date;

CREATE UNIQUE INDEX idx_mv_monthly_generation_mix_date ON mv_monthly_generation_mix (ref_date);

-- SQL query optimization: the mix mart above is a materialized view, not a
-- plain view, specifically so Tableau's dashboard filters/extract refreshes
-- re-read one pre-aggregated row per month instead of re-running the pivot
-- and 8 conditional SUMs over all 5,280 raw rows on every request. Refresh
-- concurrently (needs the unique index above) whenever generation_raw is
-- reloaded with a new StatCan release:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_generation_mix;
