Below is the **updated, complete `README.md`**, with your **expanded prerequisites section integrated cleanly** and aligned with the rest of the document.
You can replace your existing README with this version directly.

---

# Azure APIM Automated Deployment with LLM Prompt & Response Firewall

This repository provides a **fully automated Azure API Management (APIM) deployment** that provisions an API and operation on an **existing APIM instance**, applies an **operation-level security policy**, and integrates **AccuKnox LLM Defence** to inspect and block unsafe prompts and model responses **at runtime**.

The solution acts as a **secure proxy** in front of Azure AI Foundry / OpenAI-compatible models with **minimal onboarding effort** and **no manual APIM configuration**.

---

## 📁 Repository Structure

```
├── bicep/
│   └── apim-api.bicep          # Creates API + operation in existing APIM
├── named-values/
│   └── named-values.sh         # Creates APIM Named Values (secure runtime input)
├── policies/
│   └── policy.xml              # Operation-level APIM policy
├── .env                        # Deployment configuration
└── deploy.sh                   # End-to-end deployment orchestrator
```

---

## 🎯 What This Deployment Does

* Deploys an **API and operation** using Bicep
* Applies **operation-level APIM policies**
* Validates client bearer tokens
* Extracts user prompts from request payloads
* Scans prompts using **AccuKnox LLM Defence**
* Blocks unsafe prompts before model execution
* Forwards safe requests to **Azure AI Foundry**
* Scans model responses before returning to client
* Blocks unsafe model outputs

---

## 🔐 Runtime Security Flow

```
Client
  |
  | POST /models/chat/completions
  | Authorization: Bearer <Foundry API Key>
  |
Azure API Management (APIM)
  |
  |-- Extract Prompt
  |-- AccuKnox LLM Defence (Prompt Scan)
  |-- BLOCK if unsafe
  |
  |-- Forward to Azure AI Foundry
  |
  |-- AccuKnox LLM Defence (Response Scan)
  |-- BLOCK if unsafe
  |
Client Response
```

---

## 🧩 Prerequisites

Before running this project, ensure the following prerequisites are met:

1. **Azure Subscription**

   * Active Azure subscription with billing enabled

2. **Azure API Management Instance**

   * APIM instance must already exist
   * Recommended SKU: **Developer** (non-production) or **Premium** (production)
   * The APIM instance must be reachable from Azure AI Foundry endpoints

3. **Azure AI Foundry Model Deployed**

   * A model must be deployed and accessible via an OpenAI-compatible endpoint
   * The endpoint must support **Bearer token authentication**

4. **AccuKnox LLM Defence Access Token**

   * Valid API token obtained from onboarding an application on accuknox platform(AI/ML Security -> Applications -> Prompt Firewall -> Add Application):

   * Token must be stored as an APIM Named Value (not in code)

5. **Azure CLI Installed**

   * Azure CLI version `2.50+` recommended
   * Logged in using:

     ```bash
     az login
     ```

---

## ⚙️ Configuration (`.env`)

Create a `.env` file in the repository root.
Each variable must be filled by the user. **Do not commit real values to source control.**

### 📄 `.env` (Single-Line, Commented)

```env
SUBSCRIPTION_ID=        # Azure subscription ID (example: 69e37648-d32f-46a0-a45e-e983eb816225)
RESOURCE_GROUP=         # Existing resource group name (example: ai-runtime-firewall-test)
LOCATION=               # Azure region, wrap in quotes if needed (example: "East US")

APIM_SERVICE_NAME=      # Existing API Management service name (example: prompt-firewall-apim)

API_ID=                 # Unique API identifier, no spaces (example: foundry-proxy-api)
API_DISPLAY_NAME=       # Display name shown in APIM, use quotes (example: "Foundry Proxy API")
API_PATH=               # Public base path for the API (example: foundry)


OPERATION_ID=           # Unique operation identifier (example: chat-completions)
OPERATION_DISPLAY_NAME= # Operation display name, use quotes (example: "Chat Completions")
OPERATION_METHOD=       # HTTP method for the operation (example: POST)
OPERATION_URL_TEMPLATE= # Operation URL template (example: /models/chat/completions)
```
---
Perfect — below is the **updated README section** with **exact line numbers called out**, so users know **precisely where to edit** in `policy.xml`.
This is written in a **copy-paste ready, customer-safe format**.

You can drop this section directly into your existing `README.md`.

---

## ⚠️ Mandatory Policy Changes (User Action Required)

Before running the deployment, you **must update two values** in the following file:

```
policies/policy.xml
```

These values are **environment- and deployment-specific** and **must be updated manually**.

---

## 🔁 Change 1: AccuKnox LLM Defence Endpoint

### 📍 Lines to Update

* **Line ~45** – Prompt scan (Inbound)
* **Line ~135** – Response scan (Outbound)

> ⚠️ You must update **both occurrences**

---

### 🔴 Default Value (As Shipped)

```xml
<set-url>https://cwpp.dev.accuknox.com/llm-defence/application-query</set-url>
```

---

### ✅ Required Change

Replace the URL with your **AccuKnox environment-specific endpoint**:

```text
https://cwpp.<your-environment>.accuknox.com/llm-defence/application-query
```

---

### 📌 Environment Examples

| Environment | URL                                                            |
| ----------- | -------------------------------------------------------------- |
| Development | `https://cwpp.dev.accuknox.com/llm-defence/application-query`   |
| Staging     | `https://cwpp.stage.accuknox.com/llm-defence/application-query` |
| Production  | `https://cwpp.prod.accuknox.com/llm-defence/application-query`  |

---

## 🔁 Change 2: Azure AI Foundry Backend URL

### 📍 Line to Update

* **Line ~100** – Backend forwarding configuration

---

### 🔴 Default Value (As Shipped)

```xml
<set-backend-service base-url="https://ai-prompt-firewall-openai.services.ai.azure.com" />
```

---

### ✅ Required Change

Replace the `base-url` with **your Azure AI Foundry / OpenAI deployment endpoint**:

```xml
<set-backend-service base-url="https://<your-foundry-resource>.services.ai.azure.com" />
```

---

### 📌 Example

```xml
<set-backend-service base-url="https://my-foundry-openai.services.ai.azure.com" />
```

> ⚠️ This URL **must exactly match** the endpoint of your deployed model and must support **Bearer token authentication**.

---

## ✅ Summary of Required Policy Edits

| Change              | File         | Line(s)   | Description                        |
| ------------------- | ------------ | --------- | ---------------------------------- |
| AccuKnox endpoint   | `policy.xml` | ~45, ~135 | Set correct AccuKnox environment   |
| Foundry backend URL | `policy.xml` | ~100      | Set your model deployment endpoint |

---

## 🚨 Important Notes

* Line numbers may vary slightly if comments are added or removed
* Always verify both **prompt** and **response** scan URLs
* Deployment will **fail or block traffic** if these values are incorrect



---

## 🔐 Secrets Handling (Mandatory)

Secrets **must not** be placed in `.env`.

This deployment requires the following **APIM Named Value**:

| Name                | Purpose                        |
| ------------------- | ------------------------------ |
| `LLM_DEFENCE_TOKEN` | AccuKnox LLM Defence API token |

Create it securely using:

```bash
bash named-values/named-values.sh <RESOURCE_GROUP> <APIM_SERVICE_NAME>
```

The script prompts for the token securely (input hidden).

---

## 🚀 Deployment

Make the deployment script executable:

```bash
chmod +x deploy.sh
```

Run the deployment:

```bash
./deploy.sh
```

This will:

* Set the Azure subscription
* Deploy the API and operation via Bicep
* Apply the operation-level policy
* Bind the backend service
* Enable prompt and response scanning

---

## 🧠 Policy Behavior Summary

### Inbound Processing

* Extracts and validates `Authorization: Bearer` token
* Extracts `messages[0].content` from request body
* Calls AccuKnox LLM Defence (prompt scan)
* Blocks unsafe prompts (`403 Forbidden`)
* Forwards safe requests to Azure AI Foundry

### Outbound Processing

* Extracts model response content
* Calls AccuKnox LLM Defence (response scan)
* Blocks unsafe responses before returning to client

---

## ❌ Failure Scenarios

| Scenario                        | HTTP Response               |
| ------------------------------- | --------------------------- |
| Missing or invalid bearer token | `401 Unauthorized`          |
| Prompt blocked by defence       | `403 Forbidden`             |
| Response blocked by defence     | `403 Forbidden`             |
| Defence API failure             | Request fails (fail-closed) |

---

## 🛠 Troubleshooting

**Policy deployment fails**

* Verify API ID and Operation ID
* Ensure policy is applied at **operation level**
* Confirm content type:

  ```
  application/vnd.ms-azure-apim.policy+xml
  ```

**Named Value not resolving**

* Ensure `LLM_DEFENCE_TOKEN` exists in APIM
* Confirm it is marked as **secret**

**Backend authorization errors**

* Ensure client passes valid Foundry API key
* Ensure backend supports bearer token passthrough

---

## 🧩 Extensibility

This solution can be extended to:

* Add request/response logging
* Apply policies at API or global scope
* Support multiple models
* Add rate limiting or quotas
* Integrate additional security engines

---

## ✅ Design Principles

* No manual APIM UI configuration
* Secure-by-default (fail closed)
* Customer-friendly onboarding
* CI/CD ready
* Secrets isolated from source code


