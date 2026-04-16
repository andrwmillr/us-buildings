#!/usr/bin/env bash
# Upload the PMTiles and (gzipped) GeoJSON-L checkpoint to Cloudflare R2.
# Expects env vars: R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT.

set -euo pipefail

: "${R2_BUCKET:?missing}"
: "${R2_ACCESS_KEY_ID:?missing}"
: "${R2_SECRET_ACCESS_KEY:?missing}"
: "${R2_ENDPOINT:?missing}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- 1. Configure rclone for R2 (non-interactive) ---
log "Configuring rclone for R2..."
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf <<EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT
region = auto
acl = private
EOF
chmod 600 ~/.config/rclone/rclone.conf

# --- 2. Verify PMTiles exists ---
if [ ! -f ~/us_buildings.pmtiles ]; then
  log "ERROR: us_buildings.pmtiles not found"
  exit 1
fi
log "PMTiles size: $(du -h ~/us_buildings.pmtiles | cut -f1)"

# --- 3. Gzip the GeoJSON-L checkpoint (if not already gzipped) ---
if [ -f ~/us_buildings.geojsonl ] && [ ! -f ~/us_buildings.geojsonl.gz ]; then
  log "Gzipping us_buildings.geojsonl (this takes ~20-30 min)..."
  # pigz uses all cores; fall back to gzip if not installed
  if command -v pigz >/dev/null 2>&1; then
    pigz -p "$(nproc)" ~/us_buildings.geojsonl
  else
    sudo apt-get install -y -qq pigz
    pigz -p "$(nproc)" ~/us_buildings.geojsonl
  fi
fi
if [ -f ~/us_buildings.geojsonl.gz ]; then
  log "Gzipped checkpoint size: $(du -h ~/us_buildings.geojsonl.gz | cut -f1)"
fi

# --- 4. Upload ---
log "Uploading us_buildings.pmtiles to r2:$R2_BUCKET/ ..."
rclone copy ~/us_buildings.pmtiles "r2:$R2_BUCKET/" --progress

if [ -f ~/us_buildings.geojsonl.gz ]; then
  log "Uploading us_buildings.geojsonl.gz to r2:$R2_BUCKET/ (checkpoint) ..."
  rclone copy ~/us_buildings.geojsonl.gz "r2:$R2_BUCKET/" --progress
fi

# --- 5. Verify ---
log "Files in R2 bucket:"
rclone ls "r2:$R2_BUCKET/"

log "Done."
