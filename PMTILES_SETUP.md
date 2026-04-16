# Building Custom US PMTiles — Setup Guide

This is the manual setup you'll need to do alongside the automated pipeline in `build-pmtiles.sh`. The script handles data extraction and tile generation — but launching the VM, uploading the result, and updating the HTML need your credentials.

**Total cost**: ~$1.50 (one-time) + ~$0.03/month hosting.

---

## Prerequisites

1. **AWS account** with EC2 permissions
2. **Cloudflare account** (free) for R2 hosting
3. **AWS CLI** installed locally: `brew install awscli` then `aws configure`

---

## Part 1: Launch the EC2 VM

### 1a. Create a key pair (if you don't have one)

```bash
aws ec2 create-key-pair --key-name pmtiles-key --query 'KeyMaterial' --output text > ~/.ssh/pmtiles-key.pem
chmod 400 ~/.ssh/pmtiles-key.pem
```

### 1b. Create a security group that allows SSH

```bash
aws ec2 create-security-group --group-name pmtiles-sg --description "SSH for PMTiles build"
aws ec2 authorize-security-group-ingress --group-name pmtiles-sg --protocol tcp --port 22 --cidr $(curl -s ifconfig.me)/32
```

### 1c. Launch the spot instance

Pick an AMI ID for Ubuntu 22.04 in your region (the one below is for us-east-1, but pick us-west-2 to be in the same region as the Overture bucket for zero data transfer cost):

```bash
# Ubuntu 22.04 LTS in us-west-2 (example — check for latest)
# aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query 'sort_by(Images, &CreationDate)[-1].ImageId'

aws ec2 run-instances \
  --region us-west-2 \
  --image-id <ubuntu-22.04-ami-id> \
  --instance-type r6i.4xlarge \
  --key-name pmtiles-key \
  --security-groups pmtiles-sg \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=pmtiles-build}]'
```

Copy the `InstanceId` from the output.

### 1d. Get the public IP and SSH in

```bash
INSTANCE_ID=<paste-instance-id>
aws ec2 wait instance-running --region us-west-2 --instance-ids $INSTANCE_ID
IP=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ssh -i ~/.ssh/pmtiles-key.pem ubuntu@$IP
```

---

## Part 2: Run the pipeline on the VM

### 2a. Upload the script

From your local machine (new terminal):

```bash
scp -i ~/.ssh/pmtiles-key.pem \
  /Users/andrwmllr/coding/Cambridge-building-map/build-pmtiles.sh \
  ubuntu@$IP:~/
```

### 2b. Run it on the VM

Back in the SSH session:

```bash
# Run in tmux/screen so it survives disconnection
sudo apt-get install -y tmux
tmux new -s pmtiles

# Inside tmux:
./build-pmtiles.sh 2>&1 | tee build.log
```

Detach from tmux with `Ctrl+B, D`. Reattach later with `tmux attach -t pmtiles`.

Total runtime: ~3-6 hours. Check in occasionally with `tmux attach`.

---

## Part 3: Set up Cloudflare R2

### 3a. Create the R2 bucket

1. Go to https://dash.cloudflare.com/ → R2 → Create bucket
2. Name it `buildings-pmtiles` (or whatever you want)
3. Under Settings → Public access → Allow Access (via "R2.dev subdomain" is simplest for testing)
4. Note the public URL, something like `https://pub-<hash>.r2.dev`

### 3b. Get R2 API credentials

1. R2 → Manage R2 API Tokens → Create API Token
2. Permission: "Object Read & Write", scope to your bucket
3. Save the Access Key ID, Secret Access Key, and Account ID

### 3c. Set up CORS

R2 → your bucket → Settings → CORS Policy, paste:

```json
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET"],
    "AllowedHeaders": ["Range"],
    "ExposeHeaders": ["ETag", "Content-Length", "Content-Range"]
  }
]
```

---

## Part 4: Upload PMTiles from the VM

Back in your SSH session:

```bash
rclone config
# n (new remote)
# name: r2
# storage: 5 (Amazon S3 Compliant)
# provider: Cloudflare
# access_key_id: <from step 3b>
# secret_access_key: <from step 3b>
# region: auto
# endpoint: https://<account-id>.r2.cloudflarestorage.com
# Leave rest default

rclone copy us_buildings.pmtiles r2:buildings-pmtiles/ --progress
```

---

## Part 5: Update the HTML

Edit `us-buildings.html` line 58 (marked with `TODO`):

```javascript
const BUILDINGS_URL = 'pmtiles://https://pub-<your-hash>.r2.dev/us_buildings.pmtiles';
```

Open the HTML in a browser and verify:

- **Zoom 3 (whole US)**: Warm glow over east coast, bright spots for NYC/LA/Chicago
- **Zoom 6**: Metro areas as colored blobs, heatmap fading
- **Zoom 10**: Neighborhoods as merged fill polygons, colored by avg height
- **Zoom 14**: Individual buildings, colored by their own height
- Hover at zoom 13+ — height values visible

---

## Part 6: Clean up

**Terminate the VM** (so you stop being charged):

```bash
aws ec2 terminate-instances --region us-west-2 --instance-ids $INSTANCE_ID
```

The PMTiles file stays on R2 (~$0.03/month for 2GB).

---

## Tweaking after the fact

If you want to re-run Tippecanoe with different settings (e.g., switch `mean` → `max`, adjust zoom range):

1. Launch a new VM (same commands as Part 1)
2. Upload `build-pmtiles.sh`
3. If you want to skip re-extraction, also upload the previous `us_buildings.geojsonl` (big — 80-120GB)
4. Or just re-run from scratch (~3-6 hours, ~$1.50)

The script is idempotent — it skips Step 2 if `us_buildings.geojsonl` exists and skips Step 3 if `us_buildings.pmtiles` exists.
