#!/usr/bin/env bash
# Upload the new aggregated + raw PMTiles to Cloudflare R2.
# Keeps old us_buildings.pmtiles intact for rollback.
#
# Usage (set env vars first):
#   export R2_BUCKET=buildings-pmtiles
#   export R2_ACCESS_KEY_ID=<key>
#   export R2_SECRET_ACCESS_KEY=<secret>
#   export R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
#   bash ~/upload-agg-raw.sh

set -euo pipefail

: "${R2_BUCKET:?missing — set R2_BUCKET}"
: "${R2_ACCESS_KEY_ID:?missing — set R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?missing — set R2_SECRET_ACCESS_KEY}"
: "${R2_ENDPOINT:?missing — set R2_ENDPOINT}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- 1. Configure rclone ---
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
no_check_bucket = true
EOF
chmod 600 ~/.config/rclone/rclone.conf

# --- 2. Verify files exist ---
for f in ~/us_buildings_agg.pmtiles ~/us_buildings_raw.pmtiles; do
  if [ ! -f "$f" ]; then
    log "ERROR: $f not found"
    exit 1
  fi
  log "$(basename $f): $(du -h "$f" | cut -f1)"
done

# --- 3. Upload (new names only — does NOT touch us_buildings.pmtiles) ---
log "Uploading us_buildings_agg.pmtiles..."
rclone copy ~/us_buildings_agg.pmtiles "r2:$R2_BUCKET/" --progress

log "Uploading us_buildings_raw.pmtiles (6.7 GB — expect ~10-20 min)..."
rclone copy ~/us_buildings_raw.pmtiles "r2:$R2_BUCKET/" --progress

# --- 4. Verify ---
log "Files now in R2 bucket:"
rclone ls "r2:$R2_BUCKET/"

log "Done. Public URLs (if bucket has R2.dev public access enabled):"
log "  Agg:  https://pub-<hash>.r2.dev/us_buildings_agg.pmtiles"
log "  Raw:  https://pub-<hash>.r2.dev/us_buildings_raw.pmtiles"
log "Replace <hash> with your bucket's R2.dev subdomain (Cloudflare dashboard → R2 → your bucket → Settings → Public access)."
