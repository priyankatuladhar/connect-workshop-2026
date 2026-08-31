#!/bin/bash
# Downloads all workshop Lambda function code from the nepal-medical-care-prod- prefix
# Run this from CloudShell (already authenticated) or locally if you have AWS creds
#
# Usage: bash download-lambdas.sh
# Output: one .zip per function, then extracted into src/<function-name>/

set -e

REGION="us-east-1"
PREFIX="nepal-medical-care-prod"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}"

FUNCTIONS=(
  "verify-identity"
  "customer-lookup"
  "update-q-session"
  "book-appointment"
  "check-available-slots"
  "lookup-appointment"
  "reschedule-appointment"
  "cancel-appointment"
  "request-prescription-refill"
  "log-call-result"
  "sample-data-seeder"
  "api-key-retrieval"
)

echo "Downloading Lambda code from us-east-1 (prefix: ${PREFIX}-)"
echo ""

mkdir -p "${OUT_DIR}/zips"
mkdir -p "${OUT_DIR}/src"

SUCCESS=0
FAIL=0

for fn in "${FUNCTIONS[@]}"; do
  FNAME="${PREFIX}-${fn}"
  echo -n "  Fetching ${FNAME}... "

  URL=$(aws lambda get-function \
    --function-name "$FNAME" \
    --region "$REGION" \
    --query 'Code.Location' \
    --output text 2>/dev/null)

  if [ -z "$URL" ] || [ "$URL" = "None" ]; then
    echo "NOT FOUND"
    FAIL=$((FAIL + 1))
    continue
  fi

  wget -q -O "${OUT_DIR}/zips/${fn}.zip" "$URL"

  # Extract into src/<function-name>/
  mkdir -p "${OUT_DIR}/src/${fn}"
  unzip -q -o "${OUT_DIR}/zips/${fn}.zip" -d "${OUT_DIR}/src/${fn}"

  echo "OK"
  SUCCESS=$((SUCCESS + 1))
done

echo ""
echo "Done: ${SUCCESS} downloaded, ${FAIL} not found"
echo "Zips:    ${OUT_DIR}/zips/"
echo "Source:  ${OUT_DIR}/src/"
