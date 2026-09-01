# Day 3 Troubleshooting — Give It Hands (MCP Tools + Tool Calling)

This guide covers the two problems most likely to block **Lab 4 – Configure the AI Agent** and
**Step 4 – Test Tool Calling**. Both were hit during a live run and confirmed fixed.

Throughout this doc, replace **`YOURNAME`** with your participant alias (e.g. `priyanka`) and use
**your own** Gateway ID, region, and Connect instance ID. Set these once:

```bash
# ---- edit these for your environment ----
export NAME=YOURNAME                                  # e.g. priyanka
export REGION=us-east-1                                # your workshop region
export PROFILE=default                                 # your AWS CLI profile
export GATEWAY_ID=nmc-$NAME-gateway-xxxxxxxxxx          # from AgentCore Gateway page
export CONNECT_INSTANCE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # aws connect list-instances
```

> These symptoms are **not** caused by browser cache, IAM execution-role mismatch, a trailing
> slash in the discovery URL, or the outbound API key. A hard refresh (Ctrl+F5) will not fix them.
> Don't waste time re-creating the Gateway or the Connect integration.

---

## Issue 1 — "No Tools available" / MCP namespace missing in the AI Agent

### Symptoms
- **Users → Security Profiles → `nmc-YOURNAME-Agent-Profile` → Tools** shows **"No Tools available"**.
- **AI Agent Designer → Edit in Agent Builder → Add AI Tool → Namespace** dropdown only shows
  **Amazon Connect**, not `nmc-YOURNAME-mcp-integration`.
- Everything looks correctly configured: Gateway is `READY`, target is `READY`, the 8 tools are in
  the OpenAPI schema, the Connect integration exists and is associated.

### Root cause
The AgentCore **Gateway's MCP `supportedVersions` list is too narrow**. When Amazon Connect's AI
Agent Builder performs the MCP handshake (`tools/list`) to populate the namespace, it negotiates an
**older MCP protocol version**. If the Gateway only advertises the two newest versions, version
negotiation fails, the MCP session never establishes, **zero tools are discovered**, and the
namespace never appears.

A **working** gateway advertises four versions:
```
2026-07-28, 2025-11-25, 2025-06-18, 2025-03-26
```
A **broken** gateway advertises only:
```
2026-07-28, 2025-11-25
```

### How to check
```bash
aws bedrock-agentcore-control get-gateway \
  --gateway-identifier "$GATEWAY_ID" \
  --region "$REGION" --profile "$PROFILE" \
  --query 'protocolConfiguration.mcp.supportedVersions'
```
If the older versions (`2025-06-18`, `2025-03-26`) are missing, apply the fix.

### Fix — widen the Gateway's supported MCP versions
`update-gateway` is a full replace, so you must re-supply `--name`, `--role-arn`,
`--authorizer-type`, and `--authorizer-configuration`. Grab your current values first:

```bash
aws bedrock-agentcore-control get-gateway \
  --gateway-identifier "$GATEWAY_ID" --region "$REGION" --profile "$PROFILE" \
  --query '{name:name, role:roleArn, authType:authorizerType, auth:authorizerConfiguration}'
```

Then update (substitute ROLE_ARN, DISCOVERY_URL, and AUDIENCE from the output above — AUDIENCE is
normally your Gateway ID):

```bash
aws bedrock-agentcore-control update-gateway \
  --gateway-identifier "$GATEWAY_ID" \
  --name "nmc-$NAME-gateway" \
  --role-arn "ROLE_ARN" \
  --protocol-type MCP \
  --protocol-configuration '{"mcp":{"supportedVersions":["2026-07-28","2025-11-25","2025-06-18","2025-03-26"],"streamingConfiguration":{"enableResponseStreaming":false}}}' \
  --authorizer-type CUSTOM_JWT \
  --authorizer-configuration '{"customJWTAuthorizer":{"discoveryUrl":"DISCOVERY_URL","allowedAudience":["AUDIENCE"]}}' \
  --region "$REGION" --profile "$PROFILE"
```

Wait for the Gateway to return to `READY`:
```bash
aws bedrock-agentcore-control get-gateway \
  --gateway-identifier "$GATEWAY_ID" --region "$REGION" --profile "$PROFILE" \
  --query 'status'
```

### Then, in the Connect console (order matters)
1. **Security profiles → `nmc-YOURNAME-Agent-Profile`** → enable the checkbox for
   `nmc-YOURNAME-mcp-integration` under **Agent Applications** → **Save**.
2. **Fully sign out** of the Connect workspace and **sign back in** (a browser refresh is not
   enough — the session token must be reissued to carry the new permission).
3. **AI Agent Designer → `NMC-AI-Agent` → Edit in Agent Builder → Add AI Tool** → the namespace
   `nmc-YOURNAME-mcp-integration` now appears → select it → add the 8 tools → **Save** → **Publish**.
4. Re-check **Security profiles → Tools** — the tools should now be listed.

### How to verify the 8 tools are actually attached
```bash
# find your assistant + orchestration agent
aws qconnect list-assistants --region "$REGION" --profile "$PROFILE" \
  --query "assistantSummaries[?contains(name,'$NAME')].[name,assistantId]" --output table

aws qconnect list-ai-agents --assistant-id ASSISTANT_ID \
  --region "$REGION" --profile "$PROFILE" \
  --query "aiAgentSummaries[?type=='ORCHESTRATION'].[name,aiAgentId,visibilityStatus]" --output table

# list attached tool names — expect 3 built-ins + 8 gateway tools = 11
aws qconnect get-ai-agent --assistant-id ASSISTANT_ID --ai-agent-id AGENT_ID \
  --region "$REGION" --profile "$PROFILE" \
  --query 'aiAgent.configuration.orchestrationAIAgentConfiguration.toolConfigurations[].toolName' \
  --output table
```
A correctly configured agent shows `Complete`, `Escalate`, `Retrieve` **plus** 8 gateway tools whose
IDs look like:
```
gateway_<GATEWAY-ID>__<TARGET-NAME>___verify_identity
gateway_<GATEWAY-ID>__<TARGET-NAME>___check_available_slots
... (book_appointment, reschedule_appointment, cancel_appointment,
     lookup_appointment, request_prescription_refill, log_call_result)
```

> **Note on CLI version:** the AI Agent orchestration config and the newer AgentCore/Q Connect
> shapes require **AWS CLI v2**. On AWS CLI v1 you may see `SDK_UNKNOWN_MEMBER` and cannot read the
> tool list. Install/upgrade to CLI v2 before running the `get-ai-agent` verification.

---

## Issue 2 — Test chat says "Chat has ended" immediately (no tool call happens)

### Symptoms
- You start a Test chat, the bot greets you, you type a request (e.g. *"Book the first available
  slot for patient P-1001"*), and the chat immediately ends.
- No records appear in the Lambda logs or API Gateway access logs — **the request never reached the
  tools**. The failure is upstream, in the contact flow.

### Root cause
The `NMC-Main-Flow` **Get customer input** block routes the caller's message to a **Lex V2 bot**,
which feeds the AI Agent. Connect can only invoke a Lex bot alias that has a **resource-based policy**
granting your Connect instance permission. That policy is created when you **associate** the bot
alias with the Connect instance.

If the contact flow points at one alias (e.g. **`Prod`**) but only a *different* alias (e.g.
**`TestBotAlias` / `TSTALIASID`**) was associated, Connect gets a **403 AccessDeniedException** on
`lex:RecognizeMessageAsync`, the input block errors, and the flow jumps to **Disconnect**.

### How to confirm (read the Connect flow logs)
```bash
START=$(($(date +%s000) - 900000))   # last 15 minutes
aws logs filter-log-events \
  --log-group-name "/aws/connect/nmc-$NAME" \
  --start-time $START --region "$REGION" --profile "$PROFILE" \
  --query 'events[].message' --output text | grep -i -A2 error
```
A matching failure looks like:
```
"ErrorCode":"AccessDeniedException",
"Message":"User: [AmazonConnect] is not authorized to perform: lex:RecognizeMessageAsync
 on resource: arn:aws:lex:REGION:ACCT:bot-alias/BOTID/ALIASID
 because no resource-based policy allows the lex:RecognizeMessageAsync action ... (Status Code: 403)"
```
Note the **ALIASID** in that message — that's the alias the flow is calling.

### Check which aliases are associated vs which the flow calls
```bash
# aliases associated with your Connect instance:
aws connect list-bots --instance-id "$CONNECT_INSTANCE_ID" \
  --lex-version V2 --region "$REGION" --profile "$PROFILE"

# all aliases of the bot (match the BOTID from the error):
aws lexv2-models list-bot-aliases --bot-id BOTID \
  --region "$REGION" --profile "$PROFILE" \
  --query 'botAliasSummaries[].{alias:botAliasName,id:botAliasId,status:botAliasStatus}'
```
If the flow's alias (from the error message) is **not** in the `list-bots` output, that's the gap.

### Fix (choose one)

**Option A — associate the alias the flow calls (recommended, one command).**
This creates the resource policy so Connect may invoke that alias:
```bash
aws connect associate-bot \
  --instance-id "$CONNECT_INSTANCE_ID" \
  --lex-v2-bot AliasArn=arn:aws:lex:$REGION:ACCOUNT_ID:bot-alias/BOTID/ALIASID \
  --region "$REGION" --profile "$PROFILE"
```
Verify the policy was created:
```bash
aws lexv2-models describe-resource-policy \
  --resource-arn arn:aws:lex:$REGION:ACCOUNT_ID:bot-alias/BOTID/ALIASID \
  --region "$REGION" --profile "$PROFILE"
```
You should see a statement allowing `connect.amazonaws.com` to perform `lex:RecognizeMessageAsync`
(and `lex:StartConversation`, `lex:RecognizeText`) on that alias.

**Option B — point the flow at the already-associated alias.**
In the Connect console, edit `NMC-Main-Flow` → the **Get customer input** block → change the Lex bot
alias to the one already associated (commonly `TestBotAlias`). Save & publish the flow.

> To reverse Option A: `aws connect disassociate-bot ...` with the same `--lex-v2-bot` argument.

---

## Prerequisite for Step 4 — sample data must be seeded

Step 4 (Test Tool Calling) needs the **Day 5 sample data stack** deployed, which seeds six DynamoDB
tables. If the tables are empty, tool calls "succeed" but return no slots and the test looks broken.

### Verify your data exists
```bash
for t in patients available-slots providers appointments; do
  printf "nmc-$NAME-%s : " "$t"
  aws dynamodb scan --table-name "nmc-$NAME-$t" --select COUNT \
    --region "$REGION" --profile "$PROFILE" --query 'Count' --output text
done

# confirm the test patient exists
aws dynamodb get-item --table-name "nmc-$NAME-patients" \
  --key '{"patientId":{"S":"P-1001"}}' \
  --region "$REGION" --profile "$PROFILE" \
  --query 'Item.{id:patientId.S,first:firstName.S,phone:phoneNumber.S,dob:dateOfBirth.S}'
```
Expected (approximate): patients ≥ 5, available-slots ≥ 10, providers ≥ 5, and `P-1001` present
(Aarav Sharma, `+16505551001`, DOB `1985-03-15`). If tables are empty, deploy/run the Day 5 sample
data stack (or its seeder Lambda) before testing.

---

## End-to-end test (Step 4) and verification

In the AI Agent **Test** chat:
1. `Check available appointment slots for this week` → should call **check_available_slots** and
   return real slot data.
2. `Book the first available slot for patient P-1001` → should call **book_appointment** and confirm.

Confirm a booking row was written:
```bash
aws dynamodb scan --table-name "nmc-$NAME-appointments" --select COUNT \
  --region "$REGION" --profile "$PROFILE" --query 'Count'
```
The count should increase by 1 after a successful booking.

### If a tool call now returns an error at execution time
If discovery works and the chat reaches the tools but a call fails, check the per-tool Lambda log:
```bash
START=$(($(date +%s000) - 900000))
aws logs filter-log-events \
  --log-group-name "/aws/lambda/nmc-$NAME-check-available-slots" \
  --start-time $START --region "$REGION" --profile "$PROFILE" \
  --query 'events[].message' --output text | tail -40
```
And the API Gateway access log:
```bash
aws logs filter-log-events \
  --log-group-name "/aws/apigateway/nmc-$NAME/access" \
  --start-time $START --region "$REGION" --profile "$PROFILE" \
  --query 'events[].message' --output text | tail -20
```
A **403 at the API Gateway** points to the outbound **`x-api-key`** credential provider on the
Gateway target (wrong/missing key value or header) — the tool *executes* using that key, which is a
different layer from tool discovery.

---

## Quick reference — layer map

| Symptom | Failing layer | Fix |
|---|---|---|
| No tools / namespace missing in Agent Builder | Gateway MCP version negotiation | Add older `supportedVersions` (Issue 1) |
| Chat ends immediately, no tool/Lambda logs | Connect → Lex bot permission | Associate the correct Lex alias (Issue 2) |
| Tools return empty slots | DynamoDB not seeded | Deploy Day 5 sample data |
| Tool call returns 403 at API Gateway | Outbound `x-api-key` on Gateway target | Fix the API key credential provider |
