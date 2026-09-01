# Nepal Medical Care IVR Workshop
## Day 3: Give It Hands

This repo contains everything participants need to set up and run the Day 3 workshop infrastructure.

---

## What's in this repo

```
cloudformation/
  day1-foundation.yaml     — DynamoDB, S3, SNS, IAM (deploy on Day 1)
  day3-lambda.yaml         — 12 Lambda functions
  day4-apigateway.yaml     — REST API + 8 endpoints
  day5-data.yaml           — Sample patient data + API key

src/                       — Lambda function source code (one folder per function)
zips/                      — Pre-built Lambda deployment packages (12 .zip files)

setup_day3.sh              — One-command setup: clones repo, deploys all stacks, uploads Lambda code
upload-lambdas.sh          — Upload Lambda zips only (if stacks already exist)
run_smoke_tests.sh         — Test all 8 API endpoints
openapi.yaml               — OpenAPI schema for the AgentCore Gateway
ai_agent_prompt.yaml       — System prompt for the Q in Connect AI Agent
```

---

## Quick Start — Day 3 Setup

You need these four things:

| Thing | Example |
|-------|---------|
| Your participant name | `alice` — same name you used on Day 1 |
| Your AWS region | `us-east-1`, `ap-south-1`, `eu-west-1`, etc. |
| KMS key ARN for your region | `arn:aws:kms:REGION:ACCOUNT:key/KEY-ID` — get from your instructor |
| Your email address | `alice@example.com` — used for SNS notifications from Day 1 stack |

> ⚠️ The KMS key ARN is region-specific. Your instructor will give you the correct one.

### Step 1 — Open CloudShell

Open AWS CloudShell (terminal icon in the top nav bar). **Set your region in the top-right dropdown first** — it must match what you used on Day 1.

### Step 2 — Set your variables

Paste this block and fill in your three values. **This is the only place you need to type your details.**

```bash
PARTICIPANT="yourname"       # your participant name — same as Day 1 (e.g. alice)
REGION="us-east-1"           # your AWS region (e.g. us-east-1, ap-south-1, eu-west-1)
KEY_ARN="your-kms-key-arn"   # get this from your instructor — it is region-specific
ADMIN_EMAIL="your@email.com" # your email — needed to deploy the Day 1 foundation stack
```

Verify they look right:
```bash
echo "Name:   $PARTICIPANT"
echo "Region: $REGION"
echo "KMS:    $KEY_ARN"
echo "Email:  $ADMIN_EMAIL"
```

### Step 3 — Run the script

Paste this exactly as-is — no substitutions needed:

```bash
curl -sO https://raw.githubusercontent.com/priyankatuladhar/connect-workshop-2026/main/setup_day3.sh \
  && bash setup_day3.sh "$PARTICIPANT" "$REGION" "$KEY_ARN" "$ADMIN_EMAIL"
```

The script runs for ~10–15 minutes and handles everything automatically:
- Clones this repo into CloudShell
- Deploys Day 3, Day 4, and Day 5 CloudFormation stacks
- Uploads all 12 Lambda functions
- Runs a smoke test to confirm the backend is live
- Prints the API endpoint and API key you need for the labs

### Step 3 — Save the output

When the script finishes, copy the `export` block it prints:

```
export PARTICIPANT="alice"
export REGION="us-east-1"
export KEY_ARN="arn:aws:kms:..."
export API_ENDPOINT="https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod"
export API_KEY="AbCdEfGhIj1234567890"
```

Paste this into a text file. If CloudShell times out during the labs, re-paste these lines to restore your variables.

### Step 4 — Proceed to the labs

Once all four stacks show `CREATE_COMPLETE` and the smoke test returns `200 OK`, open **Day 3 Lab Commands** and start Lab 1.

---

## Run all smoke tests

After setup, you can test all 8 endpoints at once:

```bash
bash connect-workshop-2026/run_smoke_tests.sh
```

(Requires `$API_ENDPOINT` and `$API_KEY` to be set in your shell.)

---

## Re-upload Lambda code only

If the stacks already exist but you need to re-push the Lambda zips:

```bash
bash connect-workshop-2026/upload-lambdas.sh alice us-east-1
```

---

## Sample patient data

These patients are seeded into your DynamoDB tables by the Day 5 stack:

| Patient ID | Name | Phone | Date of Birth |
|------------|------|-------|---------------|
| P-1001 | Aarav Sharma | +16505551001 | 1985-03-15 |
| P-1002 | Priya Thapa | +16505551002 | 1990-07-22 |
| P-1003 | Bikram Rai | +16505551003 | 1978-11-05 |
| P-1004 | Sunita Gurung | +16505551004 | 1995-02-14 |
| P-1005 | Rajesh Karki | +16505551005 | 1967-09-30 |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Day 1 stack not found` | The script will print the deploy command — set `ADMIN_EMAIL="your@email.com"` and run it, then re-run the setup script |
| `501 Not Implemented` on smoke test | Lambda zips not uploaded — re-run `setup_day3.sh` |
| `403 Forbidden` on smoke test | API key wrong — re-export `$API_KEY` from the setup output |
| KMS error during deploy | `KEY_ARN` is for the wrong region — get the correct ARN from your instructor |
| Script fails mid-way | Fix the error, re-run — already-deployed stacks are skipped automatically |
| CloudShell session expired | Re-paste the `export` block from your notes |
| `Function not found` when uploading | Wrong participant name or region — check `$PARTICIPANT` and `$REGION` |
