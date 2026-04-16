#!/usr/bin/env bash
# ec2-setup.sh — One-time EC2 setup: install tools + extract GeoJSONL from Overture.
# Run inside tmux so it survives disconnection.
#
# After this completes (~2 hrs), use build-tiles.sh for fast iteration.
#
# Usage:
#   tmux new -s setup
#   bash ~/ec2-setup.sh 2>&1 | tee ~/setup.log

set -euo pipefail
log() { echo "[$(date '+%H:%M:%S')] $*"; }

RELEASE="2026-03-18.0"
GEOJSONL=~/us_buildings.geojsonl

# ── Install tools ─────────────────────────────────────────────────────────────

log "=== Installing tools ==="
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential libsqlite3-dev zlib1g-dev git curl unzip jq

# DuckDB
if ! command -v duckdb >/dev/null 2>&1; then
  log "Installing DuckDB..."
  curl -sLO https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
  unzip -o duckdb_cli-linux-amd64.zip && sudo mv duckdb /usr/local/bin/ && rm duckdb_cli-linux-amd64.zip
fi

# Tippecanoe (felt fork)
if ! command -v tippecanoe >/dev/null 2>&1; then
  log "Building Tippecanoe..."
  git clone --depth 1 https://github.com/felt/tippecanoe.git /tmp/tippecanoe
  (cd /tmp/tippecanoe && make -j"$(nproc)" && sudo make install)
fi

# pmtiles CLI
if ! command -v pmtiles >/dev/null 2>&1; then
  log "Installing pmtiles CLI..."
  PMTILES_URL=$(curl -s https://api.github.com/repos/protomaps/go-pmtiles/releases/latest \
    | grep -o 'https://[^"]*Linux_x86_64.tar.gz' | head -1)
  curl -sLO "$PMTILES_URL" && tar xzf "$(basename "$PMTILES_URL")"
  sudo mv pmtiles /usr/local/bin/ && rm -f "$(basename "$PMTILES_URL")"
fi

# rclone
if ! command -v rclone >/dev/null 2>&1; then
  log "Installing rclone..."
  curl -s https://rclone.org/install.sh | sudo bash
fi

log "Tools ready: duckdb=$(duckdb --version 2>&1 | head -1), tippecanoe=$(tippecanoe --version 2>&1 | head -1)"

# ── Extract US buildings from Overture ────────────────────────────────────────

if [ -f "$GEOJSONL" ]; then
  log "GeoJSONL already exists: $(du -h "$GEOJSONL" | cut -f1). Skipping extraction."
else
  log "=== Extracting US buildings from Overture $RELEASE ==="
  log "Reading from S3 with bbox pushdown. Expect ~180M features, 1-2 hrs."

  duckdb <<SQL
INSTALL spatial; INSTALL httpfs;
LOAD spatial;   LOAD httpfs;
SET s3_region = 'us-west-2';
SET s3_url_style = 'path';

-- Filter out complex-outline polygons: buildings with has_parts=true but no
-- height are parent envelopes (Penn Station, Grand Central, etc.) whose
-- individual building parts carry the actual height data.
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
  WHERE (
    (bbox.xmin > -125 AND bbox.xmax < -66 AND bbox.ymin > 24 AND bbox.ymax < 50)
    OR (bbox.xmin > -180 AND bbox.xmax < -129 AND bbox.ymin > 51 AND bbox.ymax < 72)
    OR (bbox.xmin > -161 AND bbox.xmax < -154 AND bbox.ymin > 18 AND bbox.ymax < 23)
  )
  AND NOT (has_parts = true AND (height IS NULL OR height = 0))
) TO '$GEOJSONL'
WITH (FORMAT CSV, HEADER false, QUOTE '', DELIMITER E'\x01');
SQL

  log "Extraction complete: $(du -h "$GEOJSONL" | cut -f1), $(wc -l < "$GEOJSONL") features"
fi

# ── Build z8-z13 (full features, never changes) ──────────────────────────────

if [ -f ~/z8_z13.pmtiles ]; then
  log "z8_z13.pmtiles already exists. Skipping."
else
  log "=== Building z8-z13 (all features, no thinning) ==="
  tippecanoe \
    -Z8 -z13 \
    -l building \
    --no-feature-limit --no-tile-size-limit \
    --extend-zooms-if-still-dropping \
    -o ~/z8_z13.pmtiles \
    -P \
    "$GEOJSONL"

  log "z8_z13.pmtiles: $(du -h ~/z8_z13.pmtiles | cut -f1)"
fi

log "=== SETUP COMPLETE ==="
log "Now iterate with: bash ~/build-tiles.sh"
