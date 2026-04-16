#!/usr/bin/env bash
# build-phases.sh — Two-phase PMTiles build on EC2
#
# Phase 1: H3-aggregated hexagon tiles (z3-z9)  → ~/us_buildings_agg.pmtiles
# Phase 2: Raw building polygon tiles (z10-z13) → ~/us_buildings_raw.pmtiles
#
# Logs: ~/agg.log (phase 1), ~/raw.log (phase 2)
# Run inside tmux so it survives disconnection.

set -euo pipefail
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────

log "Checking prerequisites..."

# H3 extension
if ! duckdb -c "INSTALL h3 FROM community; LOAD h3; SELECT h3_latlng_to_cell(42.36, -71.06, 3);" \
        > /dev/null 2>&1; then
    log "ERROR: DuckDB H3 extension unavailable. Aborting."
    exit 1
fi
log "H3 OK"

# tile-join
if ! command -v tile-join > /dev/null 2>&1; then
    log "ERROR: tile-join not found. Aborting."
    exit 1
fi
log "tile-join OK"

# Input geojsonl for phase 2
if [ ! -f ~/us_buildings.geojsonl ]; then
    log "ERROR: ~/us_buildings.geojsonl missing (needed for phase 2). Aborting."
    exit 1
fi
log "us_buildings.geojsonl present ($(du -h ~/us_buildings.geojsonl | cut -f1))"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1 — H3 aggregation → us_buildings_agg.pmtiles
# ══════════════════════════════════════════════════════════════════════════════
{

log "=== PHASE 1 START: H3 aggregation ==="

log "Running DuckDB aggregation (reads Overture parquet from S3, expect 1-2 hrs)..."
duckdb < ~/aggregate-h3.sql

log "Row counts:"
for res in 3 4 5 6; do
    f=~/agg_res${res}.geojsonl
    if [ -f "$f" ]; then
        log "  agg_res${res}.geojsonl: $(wc -l < "$f") cells, $(du -h "$f" | cut -f1)"
    else
        log "  agg_res${res}.geojsonl: MISSING — aborting"
        exit 1
    fi
done

log "tippecanoe: res3 -> z3-z4..."
tippecanoe -Z3 -z4 -l buildings_agg \
    --no-feature-limit --no-tile-size-limit \
    -o ~/agg_res3.pmtiles -P ~/agg_res3.geojsonl

log "tippecanoe: res4 -> z5-z6..."
tippecanoe -Z5 -z6 -l buildings_agg \
    --no-feature-limit --no-tile-size-limit \
    -o ~/agg_res4.pmtiles -P ~/agg_res4.geojsonl

log "tippecanoe: res5 -> z7-z8..."
tippecanoe -Z7 -z8 -l buildings_agg \
    --no-feature-limit --no-tile-size-limit \
    -o ~/agg_res5.pmtiles -P ~/agg_res5.geojsonl

log "tippecanoe: res6 -> z9..."
tippecanoe -Z9 -z9 -l buildings_agg \
    --no-feature-limit --no-tile-size-limit \
    -o ~/agg_res6.pmtiles -P ~/agg_res6.geojsonl

log "tile-join -> us_buildings_agg.pmtiles..."
tile-join -f -o ~/us_buildings_agg.pmtiles \
    ~/agg_res3.pmtiles ~/agg_res4.pmtiles \
    ~/agg_res5.pmtiles ~/agg_res6.pmtiles

log "Phase 1 complete: $(ls -lh ~/us_buildings_agg.pmtiles | awk '{print $5}')"

} 2>&1 | tee ~/agg.log

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Raw building polygons z10-z13 → us_buildings_raw.pmtiles
# ══════════════════════════════════════════════════════════════════════════════
{

log "=== PHASE 2 START: raw polygon tiles z10-z13 ==="

tippecanoe \
    -Z10 -z13 \
    -l building \
    -o ~/us_buildings_raw.pmtiles \
    --no-feature-limit \
    --no-tile-size-limit \
    --extend-zooms-if-still-dropping \
    -P \
    ~/us_buildings.geojsonl

log "Phase 2 complete: $(ls -lh ~/us_buildings_raw.pmtiles | awk '{print $5}')"
log "=== ALL DONE ==="

} 2>&1 | tee ~/raw.log
