#!/bin/bash
# ============================================================================
# Day 4 Knowledge Base — S3 setup + upload
#
# Ensures the KB bucket exists and uploads the 6 FAQ .txt files to faq/.
# The Day 1 stack already creates the bucket (nmc-<name>-kb-<account-id>) with
# KMS default encryption and a policy that denies unencrypted uploads — so
# uploads must be SSE-KMS. This script handles that.
#
# Usage:
#   bash knowledge-base/setup-kb-s3.sh <name> <region> [kms-key-arn]
#
#   <name>        your participant name (same as Day 1)
#   <region>     your AWS region
#   kms-key-arn  optional — only used if the bucket does NOT already exist
#
# After it finishes: Amazon Connect → Knowledge bases → create NMC-Knowledge-Base
# with the S3 location it prints, then Sync.
# ============================================================================
set -euo pipefail

NAME="${1:?usage: setup-kb-s3.sh <name> <region> [kms-key-arn]}"
REGION="${2:?usage: setup-kb-s3.sh <name> <region> [kms-key-arn]}"
KEY_ARN="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAQ_DIR="${SCRIPT_DIR}/faq"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# ---- 1. bucket name: prefer the Day 1 stack output, else the standard name ----
BUCKET="$(aws cloudformation describe-stacks --stack-name "nmc-${NAME}-day1" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseBucketName'].OutputValue" \
  --output text 2>/dev/null || true)"
if [ -z "$BUCKET" ] || [ "$BUCKET" = "None" ]; then
  BUCKET="nmc-${NAME}-kb-${ACCOUNT_ID}"
fi
echo "Bucket: $BUCKET"

# ---- 2. create the bucket if it isn't there ----
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  echo "  exists — skipping create"
else
  echo "  creating..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  if [ -n "$KEY_ARN" ]; then
    aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
      --server-side-encryption-configuration \
      "{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"${KEY_ARN}\"},\"BucketKeyEnabled\":true}]}"
  else
    aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
      --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"},"BucketKeyEnabled":true}]}'
  fi
fi

# ---- 3. upload the 6 FAQ files (SSE-KMS is required by the bucket policy) ----
SSE=(--sse aws:kms)
[ -n "$KEY_ARN" ] && SSE+=(--sse-kms-key-id "$KEY_ARN")

echo "Uploading ${FAQ_DIR}/*.txt -> s3://${BUCKET}/faq/"
aws s3 sync "${FAQ_DIR}/" "s3://${BUCKET}/faq/" --region "$REGION" \
  --exclude "*" --include "*.txt" \
  --content-type "text/plain" --delete "${SSE[@]}"

# ---- 4. verify ----
echo
echo "s3://${BUCKET}/faq/"
aws s3 ls "s3://${BUCKET}/faq/" --region "$REGION"
COUNT="$(aws s3 ls "s3://${BUCKET}/faq/" --region "$REGION" | grep -c '\.txt$' || true)"
echo
if [ "$COUNT" -eq 6 ]; then
  echo "OK — 6 files. Use this S3 location for NMC-Knowledge-Base:"
  echo "    s3://${BUCKET}/faq/"
else
  echo "WARNING — expected 6 .txt files, found ${COUNT}"
  exit 1
fi
