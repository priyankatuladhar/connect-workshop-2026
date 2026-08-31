#!/bin/bash
# Uploads real handler code to all 12 participant Lambda functions.
# Run this AFTER the Day 3 CloudFormation stack is CREATE_COMPLETE.
#
# Usage: bash upload-lambdas.sh <participant-name>
# Example: bash upload-lambdas.sh alice

set -e

PARTICIPANT="${1}"
REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIPS_DIR="${SCRIPT_DIR}/zips"

if [ -z "$PARTICIPANT" ]; then
  echo "ERROR: participant name required"
  echo "Usage: bash upload-lambdas.sh <participant-name>"
  exit 1
fi

echo "Uploading Lambda code for participant: ${PARTICIPANT} (region: ${REGION})"
echo ""

FUNCTIONS=(
  "verify-identity"
  "check-available-slots"
  "book-appointment"
  "reschedule-appointment"
  "cancel-appointment"
  "lookup-appointment"
  "request-prescription-refill"
  "log-call-result"
  "customer-lookup"
  "update-q-session"
  "sample-data-seeder"
  "api-key-retrieval"
)

SUCCESS=0
FAIL=0

for fn in "${FUNCTIONS[@]}"; do
  FNAME="ivr-ws-${PARTICIPANT}-${fn}"
  ZIP="${ZIPS_DIR}/${fn}.zip"

  if [ ! -f "$ZIP" ]; then
    echo "  ✗ $fn — zip not found at $ZIP"
    FAIL=$((FAIL + 1))
    continue
  fi

  echo -n "  Uploading ${FNAME}... "
  aws lambda update-function-code \
    --function-name "$FNAME" \
    --zip-file "fileb://${ZIP}" \
    --region "$REGION" \
    --query 'FunctionName' \
    --output text 2>&1

  SUCCESS=$((SUCCESS + 1))
done

echo ""
echo "Done: ${SUCCESS} uploaded, ${FAIL} skipped"
echo ""
echo "Next: wire up update-q-session with your Connect instance and Q assistant IDs:"
echo "  aws lambda update-function-configuration \\"
echo "    --function-name ivr-ws-${PARTICIPANT}-update-q-session \\"
echo "    --environment \"Variables={CONNECT_INSTANCE_ID=YOUR_ID,AI_ASSISTANT_ID=YOUR_ID}\" \\"
echo "    --region ${REGION}"
