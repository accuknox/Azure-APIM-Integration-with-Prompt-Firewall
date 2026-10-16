# AccuKnox LLM Defence – Azure API Management Policy Templates

These Azure API Management policy templates send LLM prompts and model responses to AccuKnox LLM Defence for scanning. They are added to an existing LLM gateway policy without changing how clients call the API.

## Templates

| File | Mode | Behaviour |
|---|---|---|
| `apim_accuknox_prompt_response_scan_fire_and_forget.xml` | Fire-and-forget | Prompt and response are sent with `send-one-way-request`. The policy adds no latency and never blocks. Verdicts are recorded in AccuKnox only. |
| `apim_accuknox_prompt_response_scan_blocking.xml` | Blocking | Prompt and response are sent with `send-request`, with a 4 s timeout on each call. A `BLOCK` verdict returns `403 PROMPT_BLOCKED` or `403 RESPONSE_BLOCKED`. A timeout or AccuKnox error is bypassed (fail-open). |

The two templates are identical apart from how they call AccuKnox. Use fire-and-forget for the initial rollout and monitoring. Change to blocking when enforcement is required.

## Policy structure

All AccuKnox logic is in two self-contained blocks, marked `ACCUKNOX LLM DEFENCE` / `END ACCUKNOX`:

```
<inbound>
    <base />
    [existing gateway logic: authentication, routing, backend selection]
    ACCUKNOX LLM DEFENCE - PROMPT SCAN      ← last element in <inbound>; holds all configuration
</inbound>
<backend>
    <base />
</backend>
<outbound>
    <base />
    [existing outbound logic]
    ACCUKNOX LLM DEFENCE - RESPONSE SCAN    ← last element in <outbound>
</outbound>
<on-error>
    <base />
</on-error>
```

- All variables are prefixed `accuknox-`. The blocks don't read or modify any other policy variables.
- The prompt block is placed last in `<inbound>`. It therefore scans only requests that passed the existing gateway checks, and it reads the final routed request body.
- The response block is placed last in `<outbound>` and processes 2xx backend responses only.

## Prerequisites

- An APIM instance and API that already route traffic to the LLM backend.
- An AccuKnox LLM Defence API token and the tenant endpoint URL.
- Outbound HTTPS (443) connectivity from the APIM gateway to the AccuKnox endpoint. For VNet-integrated instances, the NSG, firewall or UDR rules must allow it.
- Application Insights connected to the API, with verbosity set to **Information** so that the scan traces are emitted. This is recommended.

## Configuration

### Named Values

| Name | Type | Value |
|---|---|---|
| `accuknox-token` | Secret or Key Vault | AccuKnox API token |
| `accuknox-enabled` | Plain | `true` / `false` |

Both Named Values must exist before the policy is saved. For a Key Vault-backed secret, grant the APIM managed identity the **Key Vault Secrets User** role on the vault.

### Policy settings

All other settings are at the top of the prompt-scan block:

```xml
<set-variable name="accuknox-endpoint" value="https://cwpp.TENANT.accuknox.com/llm-defence/application-query" />
<set-variable name="accuknox-app-name" value="auto" />
<set-variable name="accuknox-scan-prompt" value="@(true)" />
<set-variable name="accuknox-scan-response" value="@(true)" />
```

| Variable | Description |
|---|---|
| `accuknox-endpoint` | The AccuKnox application-query endpoint. Replace `TENANT` with your tenant. |
| `accuknox-app-name` | The value sent in the `client-Info` header. With `auto`, it is derived from the model family (`gpt`, `claude`, `gemini`, `llama`, `mistral`, `cohere`, `amazon`, `deepseek`, `phi`, `grok`, `embedding`). If the family is unknown, the header is omitted. |
| `accuknox-scan-prompt` | Enables or disables the prompt scan. |
| `accuknox-scan-response` | Enables or disables the response scan. |

**Blocking timeout:** set by `timeout="4"` on the two `send-request` elements (`accuknox-prompt-reply` and `accuknox-response-reply`).

## Installation

### New or empty policy

If the API policy contains only `<base />` elements:

1. Replace the policy with the full template.
2. Add backend routing at the `LLM ROUTING` placeholder if it is not inherited from product or global scope.

### Existing policy

To add AccuKnox to an existing policy:

1. Copy the prompt-scan block from the template, from the opening comment of `ACCUKNOX LLM DEFENCE - PROMPT SCAN` through `END ACCUKNOX PROMPT SCAN`. Insert it as the **last element of `<inbound>`**.
2. Copy the response-scan block from the template, from the opening comment of `ACCUKNOX LLM DEFENCE - RESPONSE SCAN` through `END ACCUKNOX RESPONSE SCAN`. Insert it as the **last element of `<outbound>`**.
3. Save the policy.

**Requirements:**
- The prompt block must come after any policy that rewrites the request body (`set-body`) or rejects the request (`validate-jwt`, `rate-limit-by-key`, and so on).
- `buffer-response` must remain `true` (the default) on `forward-request`. With `buffer-response="false"`, set `accuknox-scan-response` to `@(false)`.

Apply the policy at **All operations** scope, or at the operation scope that serves the LLM endpoint.

## Processing logic

### Prompt scan (inbound)

1. The block is skipped unless `{{accuknox-enabled}}` is `true`.
2. The request body is read with `preserveContent: true`. Bodies that are neither JSON nor text (multipart, binary) are skipped.
3. The model name is resolved from these sources, in order:
   1. the `model` field in the body
   2. the `x-model` header
   3. the URL path: `/deployments/{name}/`, `/models/{name}:…` or `/model/{id}/`
4. The prompt text is extracted from the request (see [Payload support](#payload-support)).
5. The policy posts `{ "query_type": "prompt", "content": "<prompt>" }` to `accuknox-endpoint`, with `Authorization: Bearer {{accuknox-token}}` and the `client-Info` header.
   - **Fire-and-forget:** `send-one-way-request`. Processing continues immediately.
   - **Blocking:** `send-request`, with `timeout="4"` and `ignore-error="true"`:
     1. The policy parses `query_status` and `session_id` from a 2xx JSON reply.
     2. If `query_status` is `BLOCK` (case-insensitive), it returns `403 PROMPT_BLOCKED`. The backend is not called.
     3. With any other result, processing continues. If no valid verdict was received, a `bypass_reason` is recorded.
6. The policy emits the `accuknox-prompt-scan` trace and sets `accuknox-scan`, which tells the response block to run.

### Response scan (outbound)

1. The block runs only when `accuknox-scan` is set and the backend status is 2xx.
2. The response body is read with `preserveContent: true`, and the assistant text is extracted.
3. The policy posts `{ "query_type": "response", "content": "<text>", "session_id": "<id>" }`.
   - **Fire-and-forget:** `send-one-way-request`. `session_id` is empty, because the prompt call returns no verdict.
   - **Blocking:** `send-request`, sending the `session_id` from the prompt scan so that AccuKnox can link the response to its prompt. A `BLOCK` verdict returns `403 RESPONSE_BLOCKED` in place of the model output. Any other result passes the response through unchanged.
4. The policy emits the `accuknox-response-scan` trace.

### Decision matrix (blocking)

| AccuKnox result | Prompt scan | Response scan | `bypass_reason` |
|---|---|---|---|
| 2xx, `query_status = BLOCK` | `403 PROMPT_BLOCKED` | `403 RESPONSE_BLOCKED` | *(empty)* |
| 2xx, any other status | Forwarded to backend | Returned to client | *(empty)* |
| No reply within 4 s / connection failure | Bypassed | Bypassed | `timeout-or-unreachable` |
| Non-2xx reply | Bypassed | Bypassed | `accuknox-status-<code>` |
| 2xx with a non-JSON body | Bypassed | Bypassed | `unreadable-reply` |

A bypassed request is processed normally, without a scan. Each bypass also emits an `accuknox-scan-bypassed` trace at warning severity. The maximum added latency is 4 s for the prompt scan plus 4 s for the response scan.

### Error responses (blocking)

The templates add only two error responses. All other status codes come from the existing gateway policy or from the backend.

```json
{
  "error_code": "PROMPT_BLOCKED",
  "message": "Prompt blocked by LLM Defence.",
  "severity": "HIGH",
  "reason": "<AccuKnox description>",
  "violated_policies": ["Prompt injection check"],
  "session_id": "<AccuKnox session id>",
  "correlation_id": "<x-correlation-id or request id>"
}
```

| Status | `error_code` | Condition |
|---|---|---|
| 403 | `PROMPT_BLOCKED` | AccuKnox returned `BLOCK` for the prompt |
| 403 | `RESPONSE_BLOCKED` | AccuKnox returned `BLOCK` for the response |

**How the body fields are filled:**
- `severity` and `reason` come from `overall_severity` and `description` in the AccuKnox reply.
- `violated_policies` lists the entries in `risk_score.prompt` (or `risk_score.response`) whose value is `1`.
- `correlation_id` uses the `correlation-id` variable if the gateway policy sets one. Otherwise it uses `context.RequestId`.

### Fault tolerance

The policy fails open:
- Every AccuKnox expression is wrapped in `try/catch` and falls back to an empty value.
- The `send-request` calls use `ignore-error="true"`.
- `send-one-way-request` never waits for a reply.
- All trace metadata values are null-guarded.

As a result, no AccuKnox failure can raise into `on-error`. The client is affected only by an explicit `BLOCK` verdict in the blocking template.

## Payload support

### Prompt extraction

The policy sends the **latest user turn**. System and developer turns, assistant turns, tool results and image or audio blocks are excluded. If no recognised field holds the prompt, the policy sends the raw request body.

| API | Source |
|---|---|
| OpenAI / Azure OpenAI Chat Completions, Anthropic Messages, Mistral, Llama, Cohere v2, Ollama chat | `messages[]` (string content or `text` blocks) |
| Amazon Bedrock Converse | `messages[].content[].text` |
| Google Gemini / Vertex AI | `contents[].parts[].text` |
| OpenAI Responses API | `input` (string, or array with `input_text` blocks) |
| Embeddings | `input` (string or string array) |
| Legacy Completions, Bedrock InvokeModel, Ollama generate | `prompt` |
| Amazon Titan / Hugging Face TGI / Cohere v1 | `inputText` / `inputs` / `message` |
| Vertex AI predict | `instances[].prompt` / `instances[].content` |

### Response extraction

The policy handles JSON objects, JSON arrays, Server-Sent Events (`data:` lines) and NDJSON streams. Text from all chunks is joined in order.

| API | Source |
|---|---|
| OpenAI / Azure OpenAI | `choices[].message.content` / `refusal`, `choices[].delta.content`, `choices[].text` |
| Anthropic Messages | `content[].text`; stream `content_block_delta.delta.text` |
| OpenAI Responses API | `output[].content[]` (`output_text`, `refusal`); stream `response.output_text.delta` |
| Google Gemini / Vertex AI | `candidates[].content.parts[].text`, `predictions[]` |
| Amazon Bedrock | `output.message.content[].text`, `generation`, `completion`, `outputs[].text`, `results[].outputText` |
| Cohere / Ollama / Hugging Face | `text`, `message.content`, `response`, `generated_text` |

Embedding responses are not scanned. A response in any other format is sent raw.

## Observability

| Trace | Severity | Emitted when | Fields |
|---|---|---|---|
| `accuknox-prompt-scan` | Information | `accuknox-enabled` is `true` | `correlation_id`, `mode`, `dispatched`, `prompt_chars`, `model`, `app_name` |
| `accuknox-response-scan` | Information | A 2xx response is in scope | `correlation_id`, `mode`, `dispatched`, `response_chars`, `model`, `app_name` |
| `accuknox-scan-bypassed` | Warning | Blocking template only: no valid verdict | `correlation_id`, `scan`, `bypass_reason`, `model` |

In the blocking template, the scan traces also include `accuknox_status`, `query_status`, `session_id` and `bypass_reason`.

```kusto
traces
| where timestamp > ago(1h)
| where message has "accuknox"
| project timestamp, message, severityLevel, customDimensions
| order by timestamp desc
```

An alert on `accuknox-scan-bypassed` is recommended for the blocking template, so that you are notified when AccuKnox is degraded or unreachable.

## Verification

1. Send a standard chat request through the gateway, and confirm the response is unchanged.
2. Confirm that `accuknox-prompt-scan` and `accuknox-response-scan` show `dispatched = true`. In the blocking template, also confirm `accuknox_status = 200` and an empty `bypass_reason`.
3. Confirm that both scans appear in the AccuKnox console.
4. **Blocking template:** send a prompt that violates an active AccuKnox policy, and confirm `403 PROMPT_BLOCKED`.

## Operations

| Action | Method |
|---|---|
| Disable all scanning | Set the Named Value `accuknox-enabled` to `false`. No policy change is needed. |
| Disable one direction | Set `accuknox-scan-prompt` or `accuknox-scan-response` to `@(false)`. |
| Change mode | Replace both AccuKnox blocks with the blocks from the other template, then set `accuknox-endpoint` again. |
| Remove AccuKnox | Delete both AccuKnox blocks. The rest of the policy is unaffected. |

## Limitations

- **Fire-and-forget:** there is no enforcement. The response scan carries no `session_id`. APIM cannot see whether a call to AccuKnox succeeded.
- **Blocking:** latency increases by up to two AccuKnox round trips per request. Streamed responses are buffered in full before they are scanned, so they reach the client in one piece.
- **Both templates:**
  - Non-2xx backend responses are not scanned.
  - The response scan requires a buffered response.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| Policy save fails: named value not found | `accuknox-token` or `accuknox-enabled` is missing | Create the Named Values. |
| No `accuknox-*` traces | `accuknox-enabled` is not `true`, or App Insights verbosity is below Information | Check the Named Value and the API diagnostics settings. |
| `dispatched = false` | Empty or non-text body, or the scan is disabled | Expected for non-text payloads. Otherwise check `accuknox-scan-*`. |
| `dispatched = true`, but no events in AccuKnox | Endpoint, token or network | Check `accuknox-endpoint`, `accuknox-token` and egress to AccuKnox. |
| `bypass_reason = accuknox-status-401` / `403` | Invalid or expired token | Rotate `accuknox-token`. |
| `bypass_reason = accuknox-status-404` | Incorrect endpoint path | Confirm the endpoint ends in `/llm-defence/application-query`. |
| `bypass_reason = timeout-or-unreachable` | AccuKnox latency is above 4 s, or there is no connectivity | Check egress and the endpoint. Raise `timeout` if required. |
| `bypass_reason = unreadable-reply` | The endpoint returned a non-JSON body | Check that the endpoint URL points to the AccuKnox API. |
| No blocking in blocking mode | Verdict is not `BLOCK`, or the scan was bypassed | Check `query_status` and `bypass_reason` in the trace, and the policy configuration in AccuKnox. |
