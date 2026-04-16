-- aggregate-h3.sql
-- Reads US buildings from Overture Maps parquet (S3, same region as EC2 = no egress cost).
-- Produces 4 H3-aggregated GeoJSON-L files, one per resolution band.
-- Output: agg_res3.geojsonl, agg_res4.geojsonl, agg_res5.geojsonl, agg_res6.geojsonl

INSTALL spatial;
INSTALL httpfs;
INSTALL h3 FROM community;
LOAD spatial;
LOAD httpfs;
LOAD h3;

SET threads = 16;
SET memory_limit = '110GB';
SET s3_region = 'us-west-2';
SET s3_url_style = 'path';

SELECT 'Step 1: loading buildings from Overture parquet (centroid + height + footprint)...' AS status;

-- Materialize centroid lat/lon, height, and approx footprint for all US buildings.
-- ~130M rows × 32B ≈ 4 GB in memory — fine for r7i.4xlarge.
-- Reading parquet columnar is much faster than re-parsing the 46 GB geojsonl.
CREATE OR REPLACE TABLE _bld AS
SELECT
    TRY_CAST(height AS DOUBLE)                               AS height,
    ST_Y(ST_Centroid(geometry))                              AS lat,
    ST_X(ST_Centroid(geometry))                              AS lon,
    -- Approximate m² from geographic degrees² at ~38°N (good enough for a heatmap)
    ST_Area(geometry) * 12392029030.0                        AS footprint_m2
FROM read_parquet(
    's3://overturemaps-us-west-2/release/2026-03-18.0/theme=buildings/type=building/*.parquet',
    hive_partitioning = true
)
WHERE
    -- CONUS
    (bbox.xmin > -125 AND bbox.xmax < -66  AND bbox.ymin > 24 AND bbox.ymax < 50)
    -- Alaska
    OR (bbox.xmin > -180 AND bbox.xmax < -129 AND bbox.ymin > 51 AND bbox.ymax < 72)
    -- Hawaii
    OR (bbox.xmin > -161 AND bbox.xmax < -154 AND bbox.ymin > 18 AND bbox.ymax < 23);

SELECT COUNT(*) AS buildings_loaded FROM _bld;

-- ── RES 3 → z3-z4 ─────────────────────────────────────────────────────────────
SELECT 'Step 2a: aggregating res3 (z3-z4)...' AS status;

COPY (
    SELECT
        '{"type":"Feature","properties":{"median_height":'  ||
        COALESCE(ROUND(approx_quantile(height, 0.5),  1)::VARCHAR, 'null') ||
        ',"mean_height":'                                                   ||
        COALESCE(ROUND(AVG(height),                   1)::VARCHAR, 'null') ||
        ',"p90_height":'                                                    ||
        COALESCE(ROUND(approx_quantile(height, 0.9),  1)::VARCHAR, 'null') ||
        ',"count":'         || COUNT(*)::VARCHAR                            ||
        ',"total_footprint_m2":' || ROUND(SUM(footprint_m2), 0)::VARCHAR   ||
        '},"geometry":'     ||
        ST_AsGeoJSON(ST_GeomFromText(
            h3_cell_to_boundary_wkt(h3_latlng_to_cell(lat, lon, 3))
        )) || '}'
    FROM _bld
    WHERE lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY h3_latlng_to_cell(lat, lon, 3)
) TO '/home/ubuntu/agg_res3.geojsonl'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');

SELECT 'res3 done' AS status;

-- ── RES 4 → z5-z6 ─────────────────────────────────────────────────────────────
SELECT 'Step 2b: aggregating res4 (z5-z6)...' AS status;

COPY (
    SELECT
        '{"type":"Feature","properties":{"median_height":'  ||
        COALESCE(ROUND(approx_quantile(height, 0.5),  1)::VARCHAR, 'null') ||
        ',"mean_height":'                                                   ||
        COALESCE(ROUND(AVG(height),                   1)::VARCHAR, 'null') ||
        ',"p90_height":'                                                    ||
        COALESCE(ROUND(approx_quantile(height, 0.9),  1)::VARCHAR, 'null') ||
        ',"count":'         || COUNT(*)::VARCHAR                            ||
        ',"total_footprint_m2":' || ROUND(SUM(footprint_m2), 0)::VARCHAR   ||
        '},"geometry":'     ||
        ST_AsGeoJSON(ST_GeomFromText(
            h3_cell_to_boundary_wkt(h3_latlng_to_cell(lat, lon, 4))
        )) || '}'
    FROM _bld
    WHERE lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY h3_latlng_to_cell(lat, lon, 4)
) TO '/home/ubuntu/agg_res4.geojsonl'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');

SELECT 'res4 done' AS status;

-- ── RES 5 → z7-z8 ─────────────────────────────────────────────────────────────
SELECT 'Step 2c: aggregating res5 (z7-z8)...' AS status;

COPY (
    SELECT
        '{"type":"Feature","properties":{"median_height":'  ||
        COALESCE(ROUND(approx_quantile(height, 0.5),  1)::VARCHAR, 'null') ||
        ',"mean_height":'                                                   ||
        COALESCE(ROUND(AVG(height),                   1)::VARCHAR, 'null') ||
        ',"p90_height":'                                                    ||
        COALESCE(ROUND(approx_quantile(height, 0.9),  1)::VARCHAR, 'null') ||
        ',"count":'         || COUNT(*)::VARCHAR                            ||
        ',"total_footprint_m2":' || ROUND(SUM(footprint_m2), 0)::VARCHAR   ||
        '},"geometry":'     ||
        ST_AsGeoJSON(ST_GeomFromText(
            h3_cell_to_boundary_wkt(h3_latlng_to_cell(lat, lon, 5))
        )) || '}'
    FROM _bld
    WHERE lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY h3_latlng_to_cell(lat, lon, 5)
) TO '/home/ubuntu/agg_res5.geojsonl'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');

SELECT 'res5 done' AS status;

-- ── RES 6 → z9 ────────────────────────────────────────────────────────────────
SELECT 'Step 2d: aggregating res6 (z9)...' AS status;

COPY (
    SELECT
        '{"type":"Feature","properties":{"median_height":'  ||
        COALESCE(ROUND(approx_quantile(height, 0.5),  1)::VARCHAR, 'null') ||
        ',"mean_height":'                                                   ||
        COALESCE(ROUND(AVG(height),                   1)::VARCHAR, 'null') ||
        ',"p90_height":'                                                    ||
        COALESCE(ROUND(approx_quantile(height, 0.9),  1)::VARCHAR, 'null') ||
        ',"count":'         || COUNT(*)::VARCHAR                            ||
        ',"total_footprint_m2":' || ROUND(SUM(footprint_m2), 0)::VARCHAR   ||
        '},"geometry":'     ||
        ST_AsGeoJSON(ST_GeomFromText(
            h3_cell_to_boundary_wkt(h3_latlng_to_cell(lat, lon, 6))
        )) || '}'
    FROM _bld
    WHERE lat IS NOT NULL AND lon IS NOT NULL
    GROUP BY h3_latlng_to_cell(lat, lon, 6)
) TO '/home/ubuntu/agg_res6.geojsonl'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');

SELECT 'res6 done' AS status;

DROP TABLE _bld;
SELECT 'All H3 aggregations complete.' AS status;
