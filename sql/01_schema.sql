-- Nova Scotia Grid Analytics
-- Source: Statistics Canada Table 25-10-0015-01, "Electric power generation,
-- monthly generation by type of electricity" (Open Government Licence - Canada)
-- https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=2510001501

DROP TABLE IF EXISTS generation_raw;

CREATE TABLE generation_raw (
    ref_date            date        NOT NULL,
    geo                 text        NOT NULL,
    dguid               text,
    producer_class      text        NOT NULL,
    generation_type     text        NOT NULL,
    uom                 text,
    vector              text,
    coordinate          text,
    value_mwh           numeric,
    status              text
);

CREATE INDEX idx_generation_raw_date ON generation_raw (ref_date);
CREATE INDEX idx_generation_raw_class_type ON generation_raw (producer_class, generation_type);
