#!/bin/bash
# Day 3 Prerequisites Setup Script
# Nepal Medical Care IVR Workshop — Day 3: Give It Hands
#
# Usage:
#   bash setup_day3.sh <participant-name> <region> <kms-key-arn> <admin-email>
#
# Example:
#   bash setup_day3.sh alice us-east-1 arn:aws:kms:us-east-1:834283091954:key/8a8dad96-e77e-4b1b-9208-1cc0f30920db alice@example.com
#
# What this script does:
#   1. Clones (or pulls) the workshop repo to get templates and Lambda zips
#   2. Checks Day 1 stack — deploys it automatically if missing
#   3. Deploys day3-lambda.yaml   (12 Lambda functions)
#   4. Uploads real Lambda code from the repo's zips/ folder
#   5. Deploys day4-apigateway.yaml  (REST API + 8 endpoints)
#   6. Deploys day5-data.yaml        (sample patient data + API key)
#   7. Verifies all 4 stacks are CREATE_COMPLETE
#   8. Runs a quick smoke test
#   9. Prints a summary of all variables needed for the labs

set -e

REPO_URL="https://github.com/priyankatuladhar/connect-workshop-2026.git"
REPO_DIR="connect-workshop-2026"

# ─── colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
info() { echo -e "${CYAN}▶ $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail() { echo -e "${RED}✗ ERROR: $1${RESET}"; exit 1; }
hr()   { echo -e "${CYAN}────────────────────────────────────────────────────────${RESET}"; }

# ─── arguments ────────────────────────────────────────────────────────────────
PARTICIPANT="${1}"
REGION="${2}"
KEY_ARN="${3}"
ADMIN_EMAIL="${4:-}"

if [ -z "$PARTICIPANT" ] || [ -z "$REGION" ] || [ -z "$KEY_ARN" ]; then
  echo ""
  echo -e "${BOLD}Usage:${RESET} bash setup_day3.sh <participant-name> <region> <kms-key-arn> <admin-email>"
  echo ""
  echo "  participant-name  your lowercase workshop name, same as Day 1 (e.g. alice)"
  echo "  region            your AWS region (e.g. us-east-1, ap-south-1, eu-west-1)"
  echo "  kms-key-arn       get this from your instructor — it is region-specific"
  echo "  admin-email       your email address (needed if Day 1 stack not yet deployed)"
  echo ""
  echo "Example:"
  echo "  bash setup_day3.sh alice us-east-1 arn:aws:kms:us-east-1:123456789012:key/abc-def alice@example.com"
  echo ""
  exit 1
fi

# ─── banner ───────────────────────────────────────────────────────────────────
echo ""
hr
echo -e "${BOLD}  Nepal Medical Care IVR Workshop — Day 3 Setup${RESET}"
hr
echo "  Participant : ${PARTICIPANT}"
echo "  Region      : ${REGION}"
echo "  KMS Key     : ${KEY_ARN}"
if [ -n "$ADMIN_EMAIL" ]; then
echo "  Email       : ${ADMIN_EMAIL}"
fi
hr
echo ""

# ─── step 0: clone / pull repo ────────────────────────────────────────────────
info "Step 0 — Getting workshop repository..."

if [ -d "$REPO_DIR/.git" ]; then
  echo "  Repository already cloned — fetching latest..."
  git -C "$REPO_DIR" fetch --quiet origin
  git -C "$REPO_DIR" reset --hard origin/main --quiet
  ok "Repository up to date"
else
  git clone --quiet "$REPO_URL" "$REPO_DIR"
  ok "Repository cloned"
fi
echo ""

# ─── step 1: verify day 1 stack ───────────────────────────────────────────────
info "Step 1 — Checking Day 1 stack..."

DAY1_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day1" \
  --region "${REGION}" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DAY1_STATUS" = "REVIEW_IN_PROGRESS" ] || [ "$DAY1_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$DAY1_STATUS" = "CREATE_FAILED" ]; then
  warn "Day 1 stack is stuck (${DAY1_STATUS}) — deleting and redeploying..."
  aws cloudformation delete-stack --stack-name "nmc-${PARTICIPANT}-day1" --region "${REGION}"
  aws cloudformation wait stack-delete-complete --stack-name "nmc-${PARTICIPANT}-day1" --region "${REGION}"
  DAY1_STATUS="NOT_FOUND"
fi

if [ "$DAY1_STATUS" != "CREATE_COMPLETE" ] && [ "$DAY1_STATUS" != "UPDATE_COMPLETE" ]; then
  warn "Day 1 stack not found (status: ${DAY1_STATUS}) — deploying it now..."

  if [ -z "$ADMIN_EMAIL" ]; then
    echo -n "  Enter your email address for SNS notifications: "
    read ADMIN_EMAIL
    if [ -z "$ADMIN_EMAIL" ]; then
      fail "Email address is required to deploy the Day 1 stack. Re-run with: bash setup_day3.sh $PARTICIPANT $REGION $KEY_ARN your@email.com"
    fi
  fi

  aws cloudformation deploy \
    --template-file "${REPO_DIR}/cloudformation/day1-foundation.yaml" \
    --stack-name "nmc-${PARTICIPANT}-day1" \
    --parameter-overrides \
      ParticipantName="${PARTICIPANT}" \
      KmsKeyArn="${KEY_ARN}" \
      AdminEmail="${ADMIN_EMAIL}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}"

  aws cloudformation wait stack-create-complete \
    --stack-name "nmc-${PARTICIPANT}-day1" \
    --region "${REGION}"

  ok "Day 1 stack deployed — check your email and confirm the SNS subscription"
fi

ok "Day 1 stack is ${DAY1_STATUS}"
echo ""

# ─── step 2: deploy day 3 stack ───────────────────────────────────────────────
info "Step 2 — Deploying Day 3 stack (12 Lambda functions)..."

DAY3_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day3" \
  --region "${REGION}" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DAY3_STATUS" = "CREATE_COMPLETE" ] || [ "$DAY3_STATUS" = "UPDATE_COMPLETE" ]; then
  warn "Day 3 stack already exists (${DAY3_STATUS}) — skipping deploy"
else
  aws cloudformation deploy \
    --template-file "${REPO_DIR}/cloudformation/day3-lambda.yaml" \
    --stack-name "nmc-${PARTICIPANT}-day3" \
    --parameter-overrides \
      ParticipantName="${PARTICIPANT}" \
      KmsKeyArn="${KEY_ARN}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}"

  aws cloudformation wait stack-create-complete \
    --stack-name "nmc-${PARTICIPANT}-day3" \
    --region "${REGION}"

  ok "Day 3 stack deployed"
fi
echo ""

# ─── step 3: upload lambda code ───────────────────────────────────────────────
info "Step 3 — Uploading Lambda code..."

FUNCTIONS=(
  verify-identity
  check-available-slots
  book-appointment
  reschedule-appointment
  cancel-appointment
  lookup-appointment
  request-prescription-refill
  log-call-result
  register-new-patient
  customer-lookup
  update-q-session
  sample-data-seeder
  api-key-retrieval
)

UPLOAD_SUCCESS=0
UPLOAD_FAIL=0

for fn in "${FUNCTIONS[@]}"; do
  ZIP="${REPO_DIR}/zips/${fn}.zip"
  if [ ! -f "$ZIP" ]; then
    warn "  Skipping ${fn} — ${fn}.zip not found in repo"
    UPLOAD_FAIL=$((UPLOAD_FAIL + 1))
    continue
  fi
  echo -n "  Uploading ${fn}... "
  aws lambda update-function-code \
    --function-name "nmc-${PARTICIPANT}-${fn}" \
    --zip-file "fileb://${ZIP}" \
    --region "${REGION}" \
    --query 'FunctionName' \
    --output text
  UPLOAD_SUCCESS=$((UPLOAD_SUCCESS + 1))
done

if [ "$UPLOAD_FAIL" -gt 0 ]; then
  warn "${UPLOAD_SUCCESS} uploaded, ${UPLOAD_FAIL} skipped (zips missing from repo)"
else
  ok "All ${UPLOAD_SUCCESS} Lambda functions updated"
fi
echo ""

# ─── step 4: deploy day 4 stack ───────────────────────────────────────────────
info "Step 4 — Deploying Day 4 stack (API Gateway)..."

DAY4_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day4" \
  --region "${REGION}" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DAY4_STATUS" = "CREATE_COMPLETE" ] || [ "$DAY4_STATUS" = "UPDATE_COMPLETE" ]; then
  warn "Day 4 stack already exists (${DAY4_STATUS}) — skipping deploy"
else
  aws cloudformation deploy \
    --template-file "${REPO_DIR}/cloudformation/day4-apigateway.yaml" \
    --stack-name "nmc-${PARTICIPANT}-day4" \
    --parameter-overrides \
      ParticipantName="${PARTICIPANT}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}"

  aws cloudformation wait stack-create-complete \
    --stack-name "nmc-${PARTICIPANT}-day4" \
    --region "${REGION}"

  ok "Day 4 stack deployed"
fi

API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day4" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
  --output text)

echo ""

# ─── step 5: deploy day 5 stack ───────────────────────────────────────────────
info "Step 5 — Deploying Day 5 stack (sample data + API key)..."

DAY5_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day5" \
  --region "${REGION}" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$DAY5_STATUS" = "CREATE_COMPLETE" ] || [ "$DAY5_STATUS" = "UPDATE_COMPLETE" ]; then
  warn "Day 5 stack already exists (${DAY5_STATUS}) — skipping deploy"
else
  aws cloudformation deploy \
    --template-file "${REPO_DIR}/cloudformation/day5-data.yaml" \
    --stack-name "nmc-${PARTICIPANT}-day5" \
    --parameter-overrides \
      ParticipantName="${PARTICIPANT}" \
    --region "${REGION}"

  aws cloudformation wait stack-create-complete \
    --stack-name "nmc-${PARTICIPANT}-day5" \
    --region "${REGION}"

  ok "Day 5 stack deployed"
fi

API_KEY=$(aws cloudformation describe-stacks \
  --stack-name "nmc-${PARTICIPANT}-day5" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiKeyValue'].OutputValue" \
  --output text)

echo ""

# ─── step 6: verify all 4 stacks ─────────────────────────────────────────────
info "Step 6 — Verifying all 4 stacks..."

aws cloudformation list-stacks \
  --region "${REGION}" \
  --query "StackSummaries[?contains(StackName,'nmc-${PARTICIPANT}') && StackStatus!='DELETE_COMPLETE'][StackName,StackStatus]" \
  --output table

echo ""

# ─── step 7: smoke test ───────────────────────────────────────────────────────
info "Step 7 — Smoke test (verify-identity)..."

if [ -z "$API_ENDPOINT" ] || [ -z "$API_KEY" ]; then
  warn "API_ENDPOINT or API_KEY is empty — skipping smoke test"
else
  HTTP_STATUS=$(curl -s -o /tmp/smoke_response.json -w "%{http_code}" \
    -X POST "${API_ENDPOINT}/tools/verify-identity" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -d '{"phoneNumber":"+16505551001","dateOfBirth":"1985-03-15"}')

  if [ "$HTTP_STATUS" = "200" ]; then
    ok "Smoke test passed (200 OK)"
    cat /tmp/smoke_response.json | python3 -m json.tool 2>/dev/null || cat /tmp/smoke_response.json
  elif [ "$HTTP_STATUS" = "501" ]; then
    warn "Got 501 — Lambda code not fully uploaded. Check the warnings above."
  elif [ "$HTTP_STATUS" = "403" ]; then
    warn "Got 403 — API key issue. Re-run this script to retrieve the correct key."
  else
    warn "Got HTTP ${HTTP_STATUS} — check CloudWatch logs for nmc-${PARTICIPANT}-verify-identity"
  fi
fi

echo ""

# ─── summary ──────────────────────────────────────────────────────────────────
hr
echo -e "${BOLD}  Setup Complete — Save These Values${RESET}"
hr
echo ""
echo "  export PARTICIPANT=\"${PARTICIPANT}\""
echo "  export REGION=\"${REGION}\""
echo "  export KEY_ARN=\"${KEY_ARN}\""
echo "  export API_ENDPOINT=\"${API_ENDPOINT}\""
echo "  export API_KEY=\"${API_KEY}\""
echo ""
echo -e "  ${YELLOW}Copy the block above and keep it handy.${RESET}"
echo -e "  ${YELLOW}If CloudShell times out, re-run those exports to restore your variables.${RESET}"
echo ""
hr
echo -e "  ${GREEN}All done — proceed to Day 3 Lab Commands.${RESET}"
hr
echo ""
