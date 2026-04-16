#!/usr/bin/env bash
# Pipeline to generate US building PMTiles from Overture Maps with height preserved at all zoom levels.
# Run this on an EC2 r6i.4xlarge (or similar) with 500GB gp3 EBS, Ubuntu 22.04.
# Expected total runtime: 3-6 hours.

set -euo pipefail

RELEASE="2026-03-18.0"
OUTPUT_PMTILES="us_buildings.pmtiles"
INTERMEDIATE_GEOJSONL="us_buildings.geojsonl"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Step 1: Install tools ---
log "=== Step 1: Installing tools ==="
sudo apt-get update
sudo apt-get install -y \
  build-essential libsqlite3-dev zlib1g-dev \
  git python3-pip curl unzip jq

# DuckDB CLI
if ! command -v duckdb >/dev/null 2>&1; then
  log "Installing DuckDB..."
  curl -LO https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
  unzip -o duckdb_cli-linux-amd64.zip
  sudo mv duckdb /usr/local/bin/
  rm duckdb_cli-linux-amd64.zip
fi

# Tippecanoe (felt fork)
if ! command -v tippecanoe >/dev/null 2>&1; then
  log "Building Tippecanoe (felt fork)..."
  git clone https://github.com/felt/tippecanoe.git /tmp/tippecanoe
  (cd /tmp/tippecanoe && make -j"$(nproc)" && sudo make install)
fi

# pmtiles CLI
if ! command -v pmtiles >/dev/null 2>&1; then
  log "Installing pmtiles CLI..."
  # Resolve latest version number via GitHub API (release assets are named with version)
  PMTILES_URL=$(curl -s https://api.github.com/repos/protomaps/go-pmtiles/releases/latest \
    | grep -o 'https://[^"]*Linux_x86_64.tar.gz' | head -1)
  curl -LO "$PMTILES_URL"
  tar xzf "$(basename "$PMTILES_URL")"
  sudo mv pmtiles /usr/local/bin/
  rm -f "$(basename "$PMTILES_URL")"
fi

# rclone (for R2 upload)
if ! command -v rclone >/dev/null 2>&1; then
  log "Installing rclone..."
  curl https://rclone.org/install.sh | sudo bash
fi

log "All tools installed."

# --- Step 2: Extract US buildings from Overture parquet via DuckDB ---
if [ ! -f "$INTERMEDIATE_GEOJSONL" ]; then
  log "=== Step 2: Extracting US buildings from Overture $RELEASE ==="
  log "This will read from Overture's public S3 bucket with bbox predicate pushdown."
  log "Expected: ~130M features, 80-120GB output, 1-2 hours."

  duckdb <<SQL
INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;
SET s3_region = 'us-west-2';
SET s3_url_style = 'path';

-- Three tight US bboxes (CONUS + Alaska + Hawaii). Pure bbox filter uses parquet
-- zone maps — no spatial join, no OOM risk. Accepts ~1-3% border bleed (Tijuana,
-- Vancouver BC, Windsor ON) as an acceptable tradeoff vs. a 128 GB ST_Intersects.
COPY (
  SELECT
    '{"type":"Feature","properties":' ||
      CASE
        WHEN height IS NOT NULL AND height > 0
        THEN '{"height":' || ROUND(height::DOUBLE, 1) || '}'
        ELSE '{}'
      END ||
      ',"geometry":' || ST_AsGeoJSON(geometry) || '}' AS feature
  FROM read_parquet(
    's3://overturemaps-us-west-2/release/$RELEASE/theme=buildings/type=building/*.parquet',
    hive_partitioning = true
  )
  WHERE
    -- CONUS
    (bbox.xmin > -125 AND bbox.xmax < -66 AND bbox.ymin > 24 AND bbox.ymax < 50)
    -- Alaska
    OR (bbox.xmin > -180 AND bbox.xmax < -129 AND bbox.ymin > 51 AND bbox.ymax < 72)
    -- Hawaii
    OR (bbox.xmin > -161 AND bbox.xmax < -154 AND bbox.ymin > 18 AND bbox.ymax < 23)
) TO '$INTERMEDIATE_GEOJSONL'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');
SQL

  log "Extraction complete."
  log "File size: $(du -h "$INTERMEDIATE_GEOJSONL" | cut -f1)"
  log "Line count: $(wc -l < "$INTERMEDIATE_GEOJSONL")"
else
  log "GeoJSON-L file already exists, skipping extraction."
fi

# --- Step 3: Run Tippecanoe ---
if [ ! -f "$OUTPUT_PMTILES" ]; then
  log "=== Step 3: Running Tippecanoe ==="
  log "Expected: 1-3 hours, 500MB-2GB output."

  tippecanoe \
    -zg \
    --coalesce-densest-as-needed \
    --extend-zooms-if-still-dropping \
    --accumulate-attribute=height:mean \
    -y height \
    -l building \
    -o "$OUTPUT_PMTILES" \
    -P \
    "$INTERMEDIATE_GEOJSONL"

  log "Tippecanoe complete."
  log "Output file size: $(du -h "$OUTPUT_PMTILES" | cut -f1)"
else
  log "PMTiles file already exists, skipping Tippecanoe."
fi

# --- Step 4: Verify ---
log "=== Step 4: Verifying PMTiles ==="
pmtiles show "$OUTPUT_PMTILES"

log ""
log "=== Done ==="
log "Next: configure rclone for Cloudflare R2 with 'rclone config',"
log "then upload with:"
log "  rclone copy $OUTPUT_PMTILES r2:<your-bucket>/ --progress"
