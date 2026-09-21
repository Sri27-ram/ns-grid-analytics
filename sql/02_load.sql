-- Stage the raw StatCan CSV exactly as downloaded, then normalize into generation_raw.
-- REF_DATE arrives as 'YYYY-MM' (first-of-month), VALUE as text with blanks for suppressed cells.

DROP TABLE IF EXISTS _stage_statcan;

CREATE TABLE _stage_statcan (
    ref_date_txt        text,
    geo                 text,
    dguid               text,
    producer_class      text,
    generation_type     text,
    uom                 text,
    uom_id              text,
    scalar_factor        text,
    scalar_id           text,
    vector              text,
    coordinate          text,
    value_txt           text,
    status              text,
    symbol              text,
    terminated          text,
    decimals            text
);

\copy _stage_statcan FROM 'C:/Users/Sriram/ns-grid-analytics/data/raw/nova_scotia_generation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

INSERT INTO generation_raw (ref_date, geo, dguid, producer_class, generation_type, uom, vector, coordinate, value_mwh, status)
SELECT
    to_date(ref_date_txt, 'YYYY-MM'),
    geo,
    dguid,
    producer_class,
    generation_type,
    uom,
    vector,
    coordinate,
    NULLIF(value_txt, '')::numeric,
    NULLIF(status, '')
FROM _stage_statcan;

DROP TABLE _stage_statcan;
