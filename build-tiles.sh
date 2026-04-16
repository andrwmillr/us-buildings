#!/usr/bin/env bash
# build-tiles.sh — Fast iteration on low-zoom tile density.
#
# Prereqs: run ec2-setup.sh first (installs tools, extracts GeoJSONL, builds z8-z13).
#
# Tweak the TILE_BYTES_* variables below, then re-run. Each cycle takes ~15-25 min.
#
# Usage:
#   bash ~/build-tiles.sh 2>&1 | tee ~/build.log

set -euo pipefail
log() { echo "[$(date '+%H:%M:%S')] $*"; }

GEOJSONL=~/us_buildings.geojsonl
OUTDIR=~
FINAL=~/us_buildings_raw.pmtiles

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  KNOBS — tweak these and re-run                                            ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  Higher = denser tiles = smoother zoom transitions = bigger network loads   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

TILE_BYTES_Z3_Z4=500000       # 500KB  — very sparse, continental overview
TILE_BYTES_Z5_Z6=2000000      # 2MB    — moderate density
TILE_BYTES_Z7=10000000         # 10MB   — nearly full density

# ── Preflight ─────────────────────────────────────────────────────────────────

[ -f "$GEOJSONL" ]       || { log "ERROR: $GEOJSONL missing. Run ec2-setup.sh first."; exit 1; }
[ -f ~/z8_z13.pmtiles ]  || { log "ERROR: z8_z13.pmtiles missing. Run ec2-setup.sh first."; exit 1; }

log "=== Building low-zoom tiles ==="
log "  z3-z4: ${TILE_BYTES_Z3_Z4} bytes/tile"
log "  z5-z6: ${TILE_BYTES_Z5_Z6} bytes/tile"
log "  z7:    ${TILE_BYTES_Z7} bytes/tile"
log "  z8-z13: full (pre-built)"

# ── z3-z4 ─────────────────────────────────────────────────────────────────────

log "--- z3-z4 (expect ~2-5 min) ---"
tippecanoe \
  -Z3 -z4 \
  -l building \
  --drop-densest-as-needed \
  --maximum-tile-bytes="$TILE_BYTES_Z3_Z4" \
  -f -o "$OUTDIR/z3_z4.pmtiles" \
  -P \
  "$GEOJSONL"
log "  z3_z4.pmtiles: $(du -h "$OUTDIR/z3_z4.pmtiles" | cut -f1)"

# ── z5-z6 ─────────────────────────────────────────────────────────────────────

log "--- z5-z6 (expect ~5-10 min) ---"
tippecanoe \
  -Z5 -z6 \
  -l building \
  --drop-densest-as-needed \
  --maximum-tile-bytes="$TILE_BYTES_Z5_Z6" \
  -f -o "$OUTDIR/z5_z6.pmtiles" \
  -P \
  "$GEOJSONL"
log "  z5_z6.pmtiles: $(du -h "$OUTDIR/z5_z6.pmtiles" | cut -f1)"

# ── z7 ────────────────────────────────────────────────────────────────────────

log "--- z7 (expect ~10-15 min) ---"
tippecanoe \
  -Z7 -z7 \
  -l building \
  --drop-densest-as-needed \
  --maximum-tile-bytes="$TILE_BYTES_Z7" \
  -f -o "$OUTDIR/z7.pmtiles" \
  -P \
  "$GEOJSONL"
log "  z7.pmtiles: $(du -h "$OUTDIR/z7.pmtiles" | cut -f1)"

# ── Merge ─────────────────────────────────────────────────────────────────────

log "--- Merging all zoom ranges ---"
tile-join \
  -f -o "$FINAL" \
  --no-tile-size-limit \
  "$OUTDIR/z3_z4.pmtiles" \
  "$OUTDIR/z5_z6.pmtiles" \
  "$OUTDIR/z7.pmtiles" \
  ~/z8_z13.pmtiles

log "=== DONE ==="
log "Final: $(du -h "$FINAL" | cut -f1)"
pmtiles show "$FINAL" 2>/dev/null || true

log ""
log "To preview without uploading:"
log "  pmtiles serve ~/us_buildings_raw.pmtiles --port 8081 --cors='*'"
log "  # Then point us-buildings.html at http://<ec2-ip>:8081/us_buildings_raw"
log ""
log "To upload to R2:"
log "  rclone copyto $FINAL r2:buildings-pmtiles/us_buildings_raw.pmtiles --progress"
