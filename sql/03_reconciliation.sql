-- Report reconciliation: StatCan publishes a "Total all classes of electricity
-- producer" figure for each month/generation-type, which should equal the sum
-- of its two components ("Electricity producers, electric utilities" +
-- "Electricity producers, industries"). This view recomputes that sum
-- independently and flags any month/type where the reported total doesn't
-- reconcile against the components, and any suppressed ('..') source cells.

DROP VIEW IF EXISTS v_reconciliation_check;

CREATE VIEW v_reconciliation_check AS
WITH reported_total AS (
    SELECT ref_date, generation_type, value_mwh AS reported_total_mwh
    FROM generation_raw
    WHERE producer_class = 'Total all classes of electricity producer'
),
component_sum AS (
    SELECT
        ref_date,
        generation_type,
        SUM(value_mwh) AS computed_total_mwh,
        COUNT(*) FILTER (WHERE value_mwh IS NULL) AS suppressed_component_count,
        COUNT(*) AS component_count
    FROM generation_raw
    WHERE producer_class IN ('Electricity producers, electric utilities', 'Electricity producers, industries')
    GROUP BY ref_date, generation_type
)
SELECT
    rt.ref_date,
    rt.generation_type,
    rt.reported_total_mwh,
    cs.computed_total_mwh,
    cs.suppressed_component_count,
    cs.component_count,
    (rt.reported_total_mwh - cs.computed_total_mwh) AS variance_mwh,
    CASE
        WHEN cs.computed_total_mwh IS NULL OR cs.computed_total_mwh = 0 THEN NULL
        ELSE ROUND(100.0 * (rt.reported_total_mwh - cs.computed_total_mwh) / cs.computed_total_mwh, 4)
    END AS variance_pct,
    CASE
        WHEN cs.suppressed_component_count > 0 THEN 'SUPPRESSED_SOURCE'
        WHEN rt.reported_total_mwh IS DISTINCT FROM cs.computed_total_mwh THEN 'MISMATCH'
        ELSE 'OK'
    END AS reconciliation_flag
FROM reported_total rt
LEFT JOIN component_sum cs
    ON cs.ref_date = rt.ref_date AND cs.generation_type = rt.generation_type
ORDER BY rt.ref_date, rt.generation_type;

-- Summary used in the dashboard's data-quality tile.
DROP VIEW IF EXISTS v_reconciliation_summary;

CREATE VIEW v_reconciliation_summary AS
SELECT
    reconciliation_flag,
    COUNT(*) AS row_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_rows
FROM v_reconciliation_check
GROUP BY reconciliation_flag;
