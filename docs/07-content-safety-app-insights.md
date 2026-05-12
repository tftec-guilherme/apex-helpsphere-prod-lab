# Capítulo 07 — Content Safety + Application Insights

> **Objetivo:** validar Content Safety (F0 free) provisionado pelo Bicep, conectar a Function App `func-helpsphere-agent` via env vars (`CS_ENDPOINT` + `CS_KEY`), instrumentar custom metrics OpenTelemetry para tokens/custo/groundedness/safety/escalação no `agent_runner.py`, escrever 4 queries KQL canônicas em Log Analytics e montar 1 dashboard custom no Portal com 4 tiles cravados em métricas reais.
>
> **Tempo:** 75-90 min (não inclui ~3-30 min de latência ingest do App Insights antes dos primeiros pontos aparecerem)

---

## Pré-requisitos

- ✅ Capítulo 05 concluído — `az deployment group create` rodou pelo menos uma vez, criando `cs-helpsphere-<env>` (kind `ContentSafety`) + `ai-helpsphere-<env>` (Application Insights workspace-based) no RG `rg-lab-avancado`
- ✅ Capítulo 06 concluído — APIM `apim-helpsphere-<env>` provisionado e Product `helpsphere-prod` publicado (a Function `func-helpsphere-agent` está exposta atrás dele)
- ✅ Function App `func-helpsphere-agent` deployada (mesmo que com handler stub) — você precisa ter acesso a **Configuration → Environment variables** dela
- ✅ `az` CLI logado, `func` (Azure Functions Core Tools v4) instalado para `func azure functionapp publish`
- ✅ Python 3.11 local com `azure-monitor-opentelemetry` ≥ 1.6.0 (`pip install azure-monitor-opentelemetry requests`)
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first

> **Atenção custo escondido:** Content Safety **F0 (free)** suporta 1.000 req/min e 5.000 req/dia — suficiente para o lab inteiro com folga. Se você fizer load test (`> 5k requests no mesmo dia`), o tier F0 começa a retornar HTTP `429 Too Many Requests` e o `agent_runner.py` cai no **fail-open** (libera o request). Se for fazer load > 5k/dia, troque para **S0** (~R$ 1,00/1.000 transações texto + ~R$ 1,50/1.000 imagens) editando `infra/modules/content-safety.bicep` (`sku.name: 'S0'`) — para o lab pedagógico, F0 é suficiente.

---

## Resumo do que vamos cravar nesta etapa

| Camada | Item | Onde fica | Custo absoluto |
|---|---|---|---|
| **Safety** | Content Safety F0 já provisionado pelo Bicep | RG `rg-lab-avancado` → `cs-helpsphere-<env>` | R$ 0 (free tier 1k/min · 5k/dia) |
| **Safety** | Wrapper `content_safety_check()` pré e pós LLM | `src/functions/agent/function_app.py` | — |
| **Safety** | Threshold `4` (medium) input + output | `SAFETY_BLOCK_THRESHOLD=4` em App Settings | — |
| **Telemetria** | App Insights workspace-based + daily cap 1 GB | `ai-helpsphere-<env>` | R$ 0 (≤ 5 GB/mês free, ~R$ 13/GB acima) |
| **Telemetria** | 6 custom metrics OpenTelemetry | `agent_runner.py` via `azure-monitor-opentelemetry` | R$ 0 (within free tier) |
| **Observabilidade** | 4 queries KQL canônicas | Log Analytics `Logs` blade | R$ 0 (≤ 5 GB/mês free) |
| **Observabilidade** | Dashboard `helpsphere-ia-dashboard` 4 tiles | Portal Azure → Dashboards | R$ 0 |

> **Nota pedagógica — por que threshold `4` e não `2` ou `6`?** Threshold `4` (medium) = bloqueia hostilidade direcionada e linguagem severa, mas deixa passar reclamação informal ("esse produto é uma porcaria"). HelpSphere Apex é B2B Tier 1, clientes corporativos pagantes — esperamos profissionalismo, mas falso-positivo em reclamação legítima destrói NPS. Threshold `2` é certo para **moderação UGC pública**; threshold `6` é razoável para **chat interno de funcionários adultos**. A regra: ajuste o threshold à audiência, não copie do tutorial.

> **Nota pedagógica — por que defense-in-depth (input + output filter)?** Azure OpenAI já tem safety filters integrados no próprio modelo. Por que filtrar de novo? **Defense in depth.** O safety filter do modelo cobre o que o LLM pode **gerar**; nosso input filter cobre o que o **prompt injection adversário** pode tentar forçar via system message override. O output filter é o segundo guard-rail caso jailbreak vaze. Pattern OWASP LLM Top 10 (LLM01 — Prompt Injection): **nunca confiar em uma única camada**.

---

## Passo 7.1 — Verificar Content Safety provisionado e capturar endpoint + key

O recurso `cs-helpsphere-<env>` (ex.: `cs-helpsphere-dev`) foi criado pelo módulo `content-safety.bicep` durante o `az deployment group create` do Capítulo 05. Vamos confirmar no Portal e anotar as credenciais que vão para o Function App.

> **Placeholder `<env>`:** substitua por `dev`, `staging` ou `prod` conforme o ambiente que você deployou no Capítulo 05. Os exemplos abaixo usam `dev` — se você só deployou `dev` (recomendação custo-mínimo do Cap 05), está coberto.

**No Portal Azure:**

1. Topo → barra de busca → digite `Azure AI services` (também aparece como "Cognitive Services") → clique
2. Filtre por Resource Group → selecione `rg-lab-avancado` → localize `cs-helpsphere-dev` (`Kind: ContentSafety`)
3. Clique no recurso → tab **Overview** → anote:
   - **Endpoint:** `https://cs-helpsphere-dev.cognitiveservices.azure.com/`
   - **Location:** `eastus2` (deve bater com a região do RG)
   - **Pricing tier:** `F0` (Free)
4. Menu lateral → **Resource Management** → **Keys and Endpoint**
5. Clique no botão **Show Keys** → copie **KEY 1** — esse é o seu **`CONTENT_SAFETY_KEY`** (será cravado como `CS_KEY` no Function App no Passo 7.2)

<!-- screenshot: cap07-passo7.1-content-safety-keys-endpoint.png -->

> **Placeholder — `CONTENT_SAFETY_KEY`:** trata-se de um secret que NUNCA deve ser commitado em git. Anote em gerenciador de senhas pessoal (1Password, Bitwarden, KeePass) durante o lab. Em produção, esse valor vive em Key Vault e o Function App pega via reference (`@Microsoft.KeyVault(SecretUri=...)`) — pattern flagado pela Azure Policy `audit-managed-identity-on-functions` no Capítulo 08.

> **Alternativa via Azure CLI:**
>
> ```powershell
> # Endpoint
> $CsEndpoint = az cognitiveservices account show `
>   --name cs-helpsphere-dev `
>   --resource-group rg-lab-avancado `
>   --query "properties.endpoint" -o tsv
> Write-Host "CS_ENDPOINT=$CsEndpoint"
>
> # Key 1
> $CsKey = az cognitiveservices account keys list `
>   --name cs-helpsphere-dev `
>   --resource-group rg-lab-avancado `
>   --query "key1" -o tsv
> Write-Host "CS_KEY=$($CsKey.Substring(0, 8))…"  # primeiros 8 chars só pra confirmar
> ```
>
> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`, `Write-Host` por `echo`.

> **Custo:** R$ 0 — Content Safety **F0** é 100% gratuito até **1.000 transações/minuto** e **5.000 transações/dia**. Cobra **zero parado** (sem custo idle). Se F0 estourar, retorna HTTP 429 — não vira S0 sozinho.

> **Nota pedagógica — Managed Identity > API key (futuro):** Em produção real, **NÃO** colocamos `CS_KEY` em App Settings. Dá-se ao Function App uma **System-assigned Managed Identity** com role `Cognitive Services User` no recurso de Content Safety, e o SDK pega o token via `DefaultAzureCredential()`. Para o lab mantemos key (mais simples + visível para troubleshooting), mas o Capítulo 08 crava a policy `audit-managed-identity-on-functions` justamente para flagar este débito técnico.

---

## Passo 7.2 — Configurar env vars no Function App e cravar wrapper Content Safety

A Function precisa de 3 vars: `CS_ENDPOINT`, `CS_KEY` e `SAFETY_BLOCK_THRESHOLD`. Em produção via IaC viriam do Bicep + Key Vault reference; para o lab cravamos direto no Portal.

**No Portal Azure:**

1. Buscar `Function App` → clicar em `func-helpsphere-agent`
2. Menu lateral → **Settings** → **Environment variables** → tab **App settings**
3. Botão **+ Add** → criar 3 settings (uma por vez):
   - **Name:** `CS_ENDPOINT` · **Value:** `https://cs-helpsphere-dev.cognitiveservices.azure.com/` (ajuste `dev` para o env que você deployou)
   - **Name:** `CS_KEY` · **Value:** valor do `CONTENT_SAFETY_KEY` capturado no Passo 7.1
   - **Name:** `SAFETY_BLOCK_THRESHOLD` · **Value:** `4`
4. Botão **Apply** (rodapé) → diálogo "Save changes will restart the app" → confirmar (~30s downtime aceitável)

<!-- screenshot: cap07-passo7.2-function-env-vars-cs.png -->

> **Alternativa via Azure CLI (recomendado para reprodutibilidade):**
>
> ```powershell
> $CsEndpoint = az cognitiveservices account show -n cs-helpsphere-dev -g rg-lab-avancado --query "properties.endpoint" -o tsv
> $CsKey = az cognitiveservices account keys list -n cs-helpsphere-dev -g rg-lab-avancado --query "key1" -o tsv
>
> az functionapp config appsettings set `
>   --name func-helpsphere-agent `
>   --resource-group rg-lab-avancado `
>   --settings `
>     "CS_ENDPOINT=$CsEndpoint" `
>     "CS_KEY=$CsKey" `
>     "SAFETY_BLOCK_THRESHOLD=4"
> ```
>
> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`.

5. **No editor local (VS Code):** abra `src/functions/agent/function_app.py` e crave o wrapper:

```python
# src/functions/agent/function_app.py
import json
import logging
import os
import azure.functions as func
import requests

CS_ENDPOINT = os.environ["CS_ENDPOINT"]
CS_KEY = os.environ["CS_KEY"]
SAFETY_THRESHOLD = int(os.environ.get("SAFETY_BLOCK_THRESHOLD", "4"))


def content_safety_check(text: str, mode: str = "input") -> dict:
    """Returns {'safe': bool, 'severity_max': int, 'categories': [...]}.

    Fail-open: se Content Safety falhar (timeout/429/5xx), libera o request
    e emite metric `safety.error` para alarme dedicado (não bloqueia UX).
    """
    try:
        response = requests.post(
            f"{CS_ENDPOINT}contentsafety/text:analyze?api-version=2024-09-01",
            headers={
                "Ocp-Apim-Subscription-Key": CS_KEY,
                "Content-Type": "application/json",
            },
            json={
                "text": text,
                "categories": ["Hate", "Sexual", "Violence", "SelfHarm"],
                "outputType": "FourSeverityLevels",
            },
            timeout=2.0,  # SLA agressivo: safety check NUNCA pode dominar latência
        )
        response.raise_for_status()
        result = response.json()
        severities = [c["severity"] for c in result.get("categoriesAnalysis", [])]
        max_severity = max(severities) if severities else 0
        return {
            "safe": max_severity < SAFETY_THRESHOLD,
            "severity_max": max_severity,
            "categories": result.get("categoriesAnalysis", []),
            "error": None,
        }
    except requests.RequestException as exc:
        logging.error(f"Content Safety call failed (fail-open): {exc}")
        return {"safe": True, "severity_max": 0, "categories": [], "error": str(exc)}


@app.route(route="agent/chat", methods=["POST"])
def chat(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    user_message = body.get("message", "")

    # === Pre-LLM Content Safety ===
    safety_in = content_safety_check(user_message, mode="input")
    if not safety_in["safe"]:
        logging.warning(
            "Content Safety blocked INPUT severity=%s categories=%s",
            safety_in["severity_max"], safety_in["categories"],
        )
        content_safety_hit.add(1, {"mode": "input", "severity": safety_in["severity_max"]})
        return func.HttpResponse(
            json.dumps({
                "response": "Não posso processar essa mensagem por questões de segurança.",
                "blocked": True,
                "reason": "input_safety",
            }),
            status_code=200,
            mimetype="application/json",
        )

    # === Agent processing ===
    response_text, usage = run_agent(body.get("thread_id"), user_message)

    # === Post-LLM Content Safety ===
    safety_out = content_safety_check(response_text, mode="output")
    if not safety_out["safe"]:
        logging.warning(
            "Content Safety blocked OUTPUT severity=%s categories=%s",
            safety_out["severity_max"], safety_out["categories"],
        )
        content_safety_hit.add(1, {"mode": "output", "severity": safety_out["severity_max"]})
        return func.HttpResponse(
            json.dumps({
                "response": "Resposta filtrada por segurança. Tente reformular sua pergunta.",
                "blocked": True,
                "reason": "output_safety",
            }),
            status_code=200,
            mimetype="application/json",
        )

    # === Custom metrics emit (Passo 7.3) ===
    emit_llm_metrics(usage, model="gpt-4.1-mini", feature="chat")

    return func.HttpResponse(
        json.dumps({"response": response_text}),
        status_code=200,
        mimetype="application/json",
    )
```

> **Atenção severidade — escala 0/2/4/6 (não 0-7):** Quando `outputType: "FourSeverityLevels"`, a API retorna apenas valores discretos `0` (safe), `2` (low), `4` (medium), `6` (high). A escala formal Azure tem 8 níveis (0-7) via `outputType: "EightSeverityLevels"`, mas é overkill aqui. Trabalhe com 4 níveis para B2B.

> **Nota pedagógica — fail-open vs fail-closed:** O wrapper retorna `safe=True` se Content Safety estiver indisponível (fail-open). Decisão deliberada: HelpSphere é B2B suporte ao cliente, indisponibilidade do safety **não pode derrubar atendimento**. O trade-off: ataque adversário durante incidente Azure passaria. Mitigação: emitimos `safety.error` metric → alerta dispara → SRE investiga. Em casos onde **conteúdo bloqueado é crítico** (ex.: chat público de menores), mude para **fail-closed** (retorne `safe=False` e mensagem genérica).

---

## Passo 7.3 — Instrumentar custom metrics OpenTelemetry no `agent_runner.py`

Custom metrics permitem agregar tokens/custo/latência **por dimensão** (modelo, feature, tenant) — coisa que `requests`/`dependencies` tables nativas não fazem fora do esquema fixo.

> **Placeholder — `APPLICATIONINSIGHTS_CONNECTION_STRING`:** o SDK Azure Monitor OpenTelemetry exige **Connection String completa** (formato `InstrumentationKey=<guid>;IngestionEndpoint=https://<region>...`), não a Instrumentation Key sozinha. A Connection String é o padrão obrigatório desde 2025 — Instrumentation Key isolada é **deprecated**. Capture do recurso `ai-helpsphere-<env>` → tab **Overview** → campo **Connection String** (não confunda com **Instrumentation Key** logo acima). Deve já estar cravada como App Setting `APPLICATIONINSIGHTS_CONNECTION_STRING` pelo `app-insights.bicep` (output `connectionString` → setting Function App). Confirme em **Function App → Configuration → Application settings** antes do deploy do Passo 7.4 — ausência derruba startup (ver Surpresas pedagógicas).

**No editor local — `src/agent_runner.py`:**

```python
# src/agent_runner.py — top-level (executa uma vez no startup do worker)
import os
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import metrics

# OpenTelemetry exporter para App Insights
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"],
    logger_name="helpsphere.ia",
)

meter = metrics.get_meter("helpsphere.ia")

# === Histograms (distribuição) ===
prompt_tokens_metric = meter.create_histogram(
    name="llm.prompt_tokens",
    description="Prompt tokens consumed per request",
    unit="tokens",
)
completion_tokens_metric = meter.create_histogram(
    name="llm.completion_tokens",
    description="Completion tokens generated per request",
    unit="tokens",
)
cost_brl_metric = meter.create_histogram(
    name="llm.cost_brl",
    description="Cost in BRL per request (computed from model pricing table)",
    unit="BRL",
)
groundedness_metric = meter.create_histogram(
    name="llm.groundedness",
    description="Groundedness score 0.0-1.0 (Foundry eval, opcional)",
)
latency_ms_metric = meter.create_histogram(
    name="llm.latency_ms",
    description="End-to-end agent latency in ms (excludes APIM overhead)",
    unit="ms",
)

# === Counters (eventos discretos) ===
content_safety_hit = meter.create_counter(
    name="safety.hit",
    description="Content Safety blocks (input or output)",
)
escalation_decision = meter.create_counter(
    name="agent.escalation",
    description="Agent escalation decisions to human (Tier 2)",
)
safety_error = meter.create_counter(
    name="safety.error",
    description="Content Safety call failures (fail-open trigger)",
)

# Tabela de preços (mantida em código pra rastreabilidade — em prod, ler de Bicep param)
PRICING_BRL_PER_1M = {
    "gpt-4.1-mini": {"input": 0.20, "output": 0.80},
    "gpt-4.1":      {"input": 2.50, "output": 10.00},
    "gpt-4o-mini":  {"input": 0.18, "output": 0.72},
}


def emit_llm_metrics(usage, model: str, feature: str, tenant_id: str = "default") -> None:
    """Emite os 5 metrics canônicos do agent run (por feature + tenant)."""
    dims = {"model": model, "feature": feature, "tenant_id": tenant_id}

    prompt_tokens_metric.record(usage.prompt_tokens, dims)
    completion_tokens_metric.record(usage.completion_tokens, dims)

    pricing = PRICING_BRL_PER_1M.get(model, {"input": 0, "output": 0})
    cost_brl = (
        usage.prompt_tokens  * pricing["input"]  +
        usage.completion_tokens * pricing["output"]
    ) / 1_000_000
    cost_brl_metric.record(cost_brl, dims)

    if hasattr(usage, "latency_ms"):
        latency_ms_metric.record(usage.latency_ms, dims)
    if hasattr(usage, "groundedness"):
        groundedness_metric.record(usage.groundedness, dims)
```

> **Nota pedagógica — Histogram vs Counter (escolha errada custa caro):** **Histograms** capturam distribuição (p50/p95/p99) — use para tokens, custo, latência (queremos ver a cauda). **Counters** são monotonicamente crescentes — use para eventos discretos (block, escalation, error). Trocar histogram por counter em `cost_brl` daria só `sum()` no Portal — você perderia a habilidade de plotar p95 (custo do request mais caro do P95 dos clientes), que é a métrica que vira **alerta** ("R$ X passou do orçamento").

> **Nota pedagógica — `tenant_id` dimension é multi-tenant cost attribution:** Sem `tenant_id`, você sabe que gastou R$ 42 no dia, mas não sabe quem pagar. Com a dimension, KQL no Passo 7.4 quebra custo por cliente (`summarize sum(value) by tenant`), permitindo charge-back direto na fatura. Pattern obrigatório em SaaS B2B.

> **Custo:** R$ 0 — `azure-monitor-opentelemetry` exporter usa o **connection string** do App Insights (que é workspace-based + daily cap 1 GB do `app-insights.bicep`). 5 GB/mês são gratuitos. Custom metrics são **dimensions**, contam como `customMetrics` rows — bem dentro do free tier para tráfego de lab.

---

## Passo 7.4 — Deploy nova versão da Function e validar metrics chegando

**No terminal local:**

```powershell
Set-Location src/functions/agent/

# Confirme que o requirements.txt tem azure-monitor-opentelemetry
if (-not (Select-String -Path requirements.txt -Pattern "azure-monitor-opentelemetry" -Quiet)) {
    Add-Content -Path requirements.txt -Value "azure-monitor-opentelemetry>=1.6.0"
}

# Capture nome dinâmico do Function App (sufixo de hash do Bicep)
$FuncName = az functionapp list -g rg-lab-avancado `
  --query "[?starts_with(name, 'func-helpsphere-agent')].name | [0]" -o tsv
Write-Host "Publishing to: $FuncName"

# Publish com runtime Python
func azure functionapp publish $FuncName --python
```

> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `Set-Location` por `cd`, `` ` `` por `\`, `Select-String` por `grep`.

Aguarde build + deploy (~3-5 min). Output esperado termina com `Functions in <name>: chat - [httpTrigger]`.

**Gerar tráfego para popular as métricas:**

```powershell
# Capture URL APIM + subscription key (do Capítulo 06)
$ApimUrl = az apim show -n apim-helpsphere-dev -g rg-lab-avancado --query gatewayUrl -o tsv
$SubKey = az apim subscription show `
  --service-name apim-helpsphere-dev `
  --resource-group rg-lab-avancado `
  --sid master `
  --query primaryKey -o tsv

# 10 requests neutras (devem passar)
1..10 | ForEach-Object {
  $status = curl.exe -s -X POST "$ApimUrl/agent/chat" `
    -H "Content-Type: application/json" `
    -H "Ocp-Apim-Subscription-Key: $SubKey" `
    -d '{\"message\": \"Como abro um chamado de suporte?\"}' `
    -o $null -w "%{http_code}"
  Write-Host "Request $_`: $status"
  Start-Sleep -Seconds 1
}

# 1 request adversária (deve ser bloqueada — severity 6 esperado)
curl.exe -s -X POST "$ApimUrl/agent/chat" `
  -H "Content-Type: application/json" `
  -H "Ocp-Apim-Subscription-Key: $SubKey" `
  -d '{\"message\": \"I want to physically harm everyone in this office immediately\"}' `
  -w "`nAdversarial: %{http_code}`n"
```

> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `curl.exe` por `curl`, `` ` `` por `\`, `Start-Sleep -Seconds 1` por `sleep 1`, `$null` por `/dev/null`. Use `for i in {1..10}; do ...; done` em vez do `ForEach-Object`.

**No Portal Azure (verificar metrics chegando — Application Insights):**

1. Buscar `Application Insights` → clicar em `ai-helpsphere-dev` (ou o env que você deployou)
2. Menu lateral → **Monitoring** → **Logs** → fechar prompt "Welcome"
3. Cole no editor KQL:

```kusto
customMetrics
| where timestamp > ago(15m)
| where name startswith "llm." or name startswith "safety." or name startswith "agent."
| summarize count() by name, bin(timestamp, 1m)
| order by timestamp desc
```

4. Clique **Run** → você deve ver linhas como `llm.prompt_tokens`, `llm.completion_tokens`, `llm.cost_brl`, `safety.hit`

<!-- screenshot: cap07-passo7.4-app-insights-metrics-arrived.png -->

> **Atenção latência ingest — 3 a 30 minutos:** App Insights tem **dois caminhos** de visualização. **`Logs` (KQL)** retorna em **2-3 min** após a métrica ser emitida. **`Metrics` blade** (chart canvas) leva **15-30 min** para popular custom metrics no namespace dropdown. **Sempre confirme com KQL primeiro**, depois migra para Metrics blade quando precisar dashboard visual. Se 5 min depois o KQL não retorna nada → veja Surpresas pedagógicas #2 e #3 abaixo.

> **Custo:** R$ 0 — App Insights workspace-based com **daily cap 1 GB** (cravado em `app-insights.bicep` no Capítulo 04a). Free tier Log Analytics = **5 GB/mês** + 31 dias retenção. Lab inteiro fica abaixo de 50 MB.

---

## Passo 7.5 — 4 queries KQL canônicas (cost · latency · safety · errors)

**No Portal Azure (App Insights → Logs):**

Salve cada query usando **Save → Save as query** com nome canônico (ficam disponíveis em `Queries → Saved queries → Workspace`).

### Query A — Custo BRL por tenant (últimas 24h)

```kusto
// Saved as: helpsphere/cost-by-tenant-24h
customMetrics
| where timestamp > ago(24h)
| where name == "llm.cost_brl"
| extend tenant = tostring(customDimensions["tenant_id"])
| extend model  = tostring(customDimensions["model"])
| summarize total_brl = sum(valueSum), avg_brl_per_req = avg(valueSum / valueCount)
    by tenant, model
| order by total_brl desc
```

### Query B — Latency p50/p95/p99 por modelo (1h sliding)

```kusto
// Saved as: helpsphere/latency-percentiles-1h
customMetrics
| where timestamp > ago(1h)
| where name == "llm.latency_ms"
| extend model = tostring(customDimensions["model"])
| summarize
    p50 = percentile(valueSum / valueCount, 50),
    p95 = percentile(valueSum / valueCount, 95),
    p99 = percentile(valueSum / valueCount, 99),
    n = sum(valueCount)
    by model, bin(timestamp, 5m)
| order by timestamp desc
```

### Query C — Safety blocks por categoria/severity (24h)

```kusto
// Saved as: helpsphere/safety-blocks-by-category-24h
customMetrics
| where timestamp > ago(24h)
| where name == "safety.hit"
| extend
    mode     = tostring(customDimensions["mode"]),
    severity = toint(customDimensions["severity"])
| summarize blocks = sum(valueCount) by mode, severity, bin(timestamp, 1h)
| order by timestamp desc
```

### Query D — Error rate por status code (1h)

```kusto
// Saved as: helpsphere/error-rate-1h
requests
| where timestamp > ago(1h)
| where name contains "agent/chat"
| summarize
    total = count(),
    errors = countif(success == false)
    by resultCode, bin(timestamp, 5m)
| extend error_rate_pct = round(100.0 * errors / total, 2)
| order by timestamp desc
```

> **Nota pedagógica — `valueSum / valueCount` em histograms:** OpenTelemetry exporta histograms para App Insights com 3 colunas internas: `valueSum`, `valueCount`, `valueMin/Max`. Para média use `valueSum / valueCount`. Para percentil use `percentile()` na expressão. Erro comum: usar `avg(valueSum)` direto — isso te dá média de **somas por bucket**, não média **por request**.

> **Nota pedagógica — KQL save vs ad-hoc:** `Save as query` salva a query **no workspace** (visível por toda equipe), não na sua conta. Em squads reais, você commita queries em `runbook/kql/*.kusto` (versionado em git) como artefato auditável. Para o lab, salvar no workspace já cumpre o objetivo pedagógico.

> **Custo:** R$ 0 (queries KQL contam contra free tier 5 GB/mês ingest, não contra retention nem query execution).

---

## Passo 7.6 — Dashboard custom `helpsphere-ia-dashboard` (4 tiles)

**No Portal Azure:**

1. Topo do Portal → ícone **Dashboard** (canto superior esquerdo, ao lado do logo Microsoft Azure) → você verá lista de dashboards do user
2. **+ New dashboard** → **Blank dashboard**
3. Topo da página → editar nome → digite `helpsphere-ia-dashboard` → tab **Save** (disquete)

**Tile 1 — Custo BRL (últimas 24h):**

4. **+ Add tile** (canto superior direito) → painel Tile Gallery → escolher **Metrics chart** → **Add**
5. Tile vazio aparece → clique **Edit** (ícone lápis) → painel direito:
   - **Resource:** clicar **Select a resource** → `ai-helpsphere-dev` (ou o env deployado)
   - **Metric Namespace:** `azure.applicationinsights` (custom metrics aparecem no namespace padrão do SDK OTEL)
   - **Metric:** `llm.cost_brl`
   - **Aggregation:** `Sum`
   - **Time granularity:** `1 hour`
6. Topo do tile → **Save** (checkmark)

<!-- screenshot: cap07-passo7.6-dashboard-tile-1-cost.png -->

**Tile 2 — Tokens p95 (sliding 1h):**

7. **+ Add tile** → **Metrics chart** → Edit:
   - Metric: `llm.prompt_tokens` · Aggregation: `Avg` · Chart type: `Line`
   - **Apply splitting** → `model` → mostra uma linha por modelo
   - **+ Add metric** → `llm.completion_tokens` (mesma agregação) na sobreposição

**Tile 3 — Safety blocks (bar 24h):**

8. **+ Add tile** → **Metrics chart** → Edit:
   - Metric: `safety.hit` · Aggregation: `Count` · Chart type: `Bar`
   - **Apply splitting** → `mode` (input vs output)
   - Time range: `Last 24 hours`

**Tile 4 — Escalation rate (Bar 24h):**

9. **+ Add tile** → **Metrics chart** → Edit:
   - Metric: `agent.escalation` · Aggregation: `Count` · Chart type: `Bar`
   - **Apply splitting** → `feature`

10. Topo da página → **Save** (disquete) — dashboard fica disponível em todos os browsers do usuário Azure

**Validação visual (último checkpoint do capítulo):**

11. Volte para **Application Insights** → recurso `ai-helpsphere-dev` → menu lateral **Monitoring → Logs**
12. Cole a Query A (Custo BRL por tenant) que você salvou no Passo 7.5
13. Clique **Run** — confirme que o resultado mostra pelo menos 1 linha com `total_brl > 0` (smoke test do Passo 7.4 gerou tráfego)
14. Tire screenshot do **Logs blade** rodando a query — esse é o artefato visual de prova que o pipeline Content Safety + App Insights + KQL está end-to-end funcional

<!-- screenshot: cap07-passo7.6-dashboard-4-tiles-overview.png -->
<!-- screenshot: cap07-passo7.6-logs-blade-cost-query-result.png -->

> **Alternativa Workbooks (recomendado em produção real):** Workbooks são templates JSON versionáveis, exportáveis, multi-resource. Use **App Insights → Workbooks → + New** para padrão production-grade — você commita o JSON em `infra/workbooks/helpsphere-ia.workbook.json` e provisiona via Bicep `Microsoft.Insights/workbooks`. Para o lab, dashboards diretos são suficientes (1 tile = 1 click); Workbooks ficam como evolução opcional.

> **Nota pedagógica — dashboard pessoal vs shared:** Por default, dashboards são **escopados ao seu user**. Para compartilhar com SRE/dev team: **Share** (topo direito) → escolher subscription + RG `rg-shared-dashboards` → publicar. Em prod multi-time, sempre publish em RG dedicado de dashboards (vira recurso ARM como qualquer outro, governável por RBAC).

---

## Validação end-to-end

```powershell
# 1. Confirma Content Safety provisionado e tier F0
az cognitiveservices account show `
  -n cs-helpsphere-dev -g rg-lab-avancado `
  --query "{name:name, kind:kind, sku:sku.name, state:properties.provisioningState}" -o table
# Esperado: cs-helpsphere-dev | ContentSafety | F0 | Succeeded

# 2. Confirma App Insights workspace-based + daily cap 1 GB
az monitor app-insights component show `
  --app ai-helpsphere-dev --resource-group rg-lab-avancado `
  --query "{kind:kind, retentionInDays:retentionInDays, dailyCap:properties.dailyCap}" -o table
# Esperado: web | 90 | 1.0 (GB)

# 3. Confirma Function App tem env vars CS_* e APPLICATIONINSIGHTS_CONNECTION_STRING
az functionapp config appsettings list `
  --name $FuncName --resource-group rg-lab-avancado `
  --query "[?starts_with(name, 'CS_') || name == 'SAFETY_BLOCK_THRESHOLD' || name == 'APPLICATIONINSIGHTS_CONNECTION_STRING'].{name:name}" -o table
# Esperado: CS_ENDPOINT, CS_KEY, SAFETY_BLOCK_THRESHOLD, APPLICATIONINSIGHTS_CONNECTION_STRING

# 4. KQL last 15min — custom metrics chegando
az monitor app-insights query `
  --app ai-helpsphere-dev `
  --analytics-query "customMetrics | where timestamp > ago(15m) | where name startswith 'llm.' | summarize n=sum(valueCount) by name | order by n desc"
# Esperado: linhas para llm.prompt_tokens, llm.completion_tokens, llm.cost_brl
```

> **Linux/Mac/WSL:** troque `` ` `` por `\` e `$FuncName` por `$FUNC_NAME`.

---

## Checklist final

```text
[ ] Content Safety F0 provisionado e visível no Portal (state=Succeeded)
[ ] CS_ENDPOINT, CS_KEY, SAFETY_BLOCK_THRESHOLD=4 cravados em Function App
[ ] function_app.py tem content_safety_check() pré e pós LLM
[ ] Wrapper implementa fail-open + emite safety.error metric
[ ] agent_runner.py instrumentado com 6 custom metrics OpenTelemetry
[ ] Tabela PRICING_BRL_PER_1M cravada com 3+ modelos
[ ] func azure functionapp publish concluiu com sucesso
[ ] Smoke test 10 requests neutras retornou 200
[ ] Smoke test 1 request adversária retornou blocked=true reason=input_safety
[ ] KQL helpsphere/cost-by-tenant-24h salva no workspace
[ ] KQL helpsphere/latency-percentiles-1h salva no workspace
[ ] KQL helpsphere/safety-blocks-by-category-24h salva no workspace
[ ] KQL helpsphere/error-rate-1h salva no workspace
[ ] Dashboard helpsphere-ia-dashboard com 4 tiles cravados
[ ] Logs blade rodou Query A (cost-by-tenant) com resultado total_brl > 0 (validação visual)
[ ] APPLICATIONINSIGHTS_CONNECTION_STRING confirmado em App Settings (não Instrumentation Key sozinha)
[ ] App Insights daily cap 1GB confirmado em Bicep
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **Custom metrics namespace aparece como `azure.applicationinsights` (não `helpsphere.ia`)** — `meter = metrics.get_meter("helpsphere.ia")` parece que vai criar namespace `helpsphere.ia`, mas o exporter Azure Monitor coloca tudo no namespace padrão `azure.applicationinsights` e a string `helpsphere.ia` vira `meter_name` em customDimensions. **Workaround:** filtrar por `name == "llm.cost_brl"` (não pelo namespace). Custou ~20min em smoke run inicial.

- ⚠️ **`Metrics` blade demora 15-30 min para popular dropdown — `Logs` (KQL) retorna em 2-3 min** — se você abrir Metrics blade logo após o primeiro request e não ver `llm.cost_brl`, **não é bug, é latência ingest**. **Workaround:** sempre validar primeiro com KQL `customMetrics | where timestamp > ago(5m) | summarize count() by name`. Quando KQL retornar, espera mais 10-25min e Metrics blade puxa.

- ⚠️ **Connection String `APPLICATIONINSIGHTS_CONNECTION_STRING` ausente derruba startup do Function App** — `configure_azure_monitor()` lança `KeyError: 'APPLICATIONINSIGHTS_CONNECTION_STRING'` se a env var não estiver definida e o worker entra em **CrashLoopBackOff** silencioso (Function aparece como `Running` no Portal, mas todos os requests retornam 503). **Workaround:** confirme em **Function App → Configuration → Application settings** que `APPLICATIONINSIGHTS_CONNECTION_STRING` existe (deve ter sido cravado pelo Bicep `app-insights.bicep` via `application_insights.connectionString` output). Se não existe → re-rode `az deployment group create` do Capítulo 05.

- ⚠️ **Connection String é obrigatória — Instrumentation Key sozinha é deprecated** — alguns tutoriais Microsoft antigos mostram só `APPINSIGHTS_INSTRUMENTATIONKEY=<guid>`. O SDK OpenTelemetry **ignora** essa var e exige `APPLICATIONINSIGHTS_CONNECTION_STRING` no formato completo (`InstrumentationKey=<guid>;IngestionEndpoint=https://<region>.in.applicationinsights.azure.com/;LiveEndpoint=...`). **Workaround:** sempre copiar a string completa do campo **Connection String** no Overview do recurso — nunca tentar reconstruir manualmente.

- ⚠️ **Content Safety F0 retorna HTTP 429 após 5.000 req/dia (UTC reset)** — em load test com >5k requests, F0 começa a 429 e o wrapper cai no **fail-open** (libera). Você vê uma onda de `safety.error` no dashboard mas **zero `safety.hit`**. **Workaround:** ou troque para S0 em `content-safety.bicep` (`sku.name: 'S0'` — ~R$ 1,00/1.000 trans texto), ou paginate o load test em janelas de 24h. Custou ~30min em smoke run combinado de eval+chaos.

- ⚠️ **`outputType: "FourSeverityLevels"` retorna 0/2/4/6 (não 0-3)** — engenheiros novos em Content Safety assumem que "Four levels" = 0/1/2/3 e setam `SAFETY_BLOCK_THRESHOLD=2` esperando bloquear nível "medium". Na verdade level 2 é "low" e bloqueia tudo (incluindo "olá, bom dia") — false positive de 90%. **Workaround:** thresholds canônicos são **0/2/4/6**; threshold `4` = bloqueia medium+high. Cravar comentário inline no código com a tabela de severities.

- ⚠️ **`customDimensions` é coluna dynamic — sem `tostring()` cast a `where` clause quebra silenciosa** — KQL trata `customDimensions["tenant_id"]` como `dynamic`. Sem `extend tenant = tostring(customDimensions["tenant_id"])`, comparações tipo `where tenant == "acme-corp"` retornam **zero rows** sem mensagem de erro — você acha que não tem dados. **Workaround:** sempre `extend X = tostring(customDimensions["X"])` antes de filtrar/agrupar. Vale para qualquer dimension (model, feature, mode, severity — esse último usa `toint()`).

- ⚠️ **`TrackMetric()` legacy vs OpenTelemetry SDK — não misture** — alguns code samples antigos da Microsoft usam `TelemetryClient.TrackMetric()` (SDK legacy `applicationinsights`). Esses metrics aparecem em **`customMetrics`** table mas com **schema diferente** (valueSum/valueCount não calculados igual). Se você mistura `TrackMetric()` e OpenTelemetry no mesmo app, queries KQL agregadas dão números errados. **Workaround:** padronize 100% em OpenTelemetry (`meter.create_histogram()`/`create_counter()`) e remova qualquer import `applicationinsights` legado do `requirements.txt`.

- ⚠️ **Token counting precisa de `tiktoken` truncation a 8000 tokens — `usage.prompt_tokens` reportado pode estourar `max_context_length`** — Azure OpenAI retorna `usage.prompt_tokens` exato no response, mas se você **emite a métrica ANTES** da call (pré-flight estimation) ou se concatena `system_message + user_message + RAG context` sem contar tokens, pode passar do contexto e a call falha com HTTP 400 `BadRequest: context_length_exceeded`. **Workaround:** instale `tiktoken` no `requirements.txt`, use `encoding = tiktoken.encoding_for_model("gpt-4o-mini")` e trunque o RAG context a `8000 tokens` antes do append (mesma técnica usada em indexação RAG). A métrica `llm.prompt_tokens` deve sempre vir do `usage.prompt_tokens` pós-call, não de estimativa local.

- ⚠️ **Daily cap 1 GB no App Insights é "soft cap" — billable continua até reset** — quando atinge 1 GB no dia, App Insights **stops ingesting** (não derruba app). Mas Azure Monitor ainda **bilha o que já entrou**. Se você esquecer cap em produção em modo debug verbose, gasta R$ 50+/mês fácil (ingest ~R$ 13/GB acima do free tier). **Workaround:** o `app-insights.bicep` já crava `dailyCap: 1` + Capítulo 08 crava Azure Policy `audit-app-insights-daily-cap` para flagar workspaces sem cap.

- ⚠️ **Workspace-based vs Classic App Insights — alguns guides Microsoft ainda mostram Classic (deprecated)** — Classic é o modelo pré-2021 onde App Insights tinha storage próprio. Workspace-based (atual) escreve em Log Analytics Workspace dedicado. Alguns tutoriais Microsoft ainda mostram `Microsoft.Insights/components` sem `workspaceResourceId` (resulta em Classic) — isso vai deprecation EOL fevereiro 2027. **Workaround:** o `app-insights.bicep` deste lab já força workspace-based via property `workspaceResourceId: logAnalyticsWorkspace.id`. Confirme em validação end-to-end (`kind=web` + `workspaceId` não-vazio).

- ⚠️ **`requests.post()` com timeout=2.0s ainda passa de 200ms p95** — Content Safety latência típica 50-150ms p50 e 300-500ms p95. Timeout 2s parece generoso, mas em incidente Cognitive Services regional, pode passar p99 de 1.5s. **Workaround:** monitorar `safety.error` rate e correlacionar com Service Health `Cognitive Services` regional. Se `safety.error rate > 1%` por 5min → degradar para fail-closed temporariamente via App Setting `SAFETY_FAIL_MODE=closed`.

---

## Decisões arquiteturais cravadas neste capítulo

- **D-7.1:** Content Safety **F0** (free) é suficiente para o lab — troca para S0 só quando load > 5k req/dia (cravado em `content-safety.bicep` parameter `sku`)
- **D-7.2:** Threshold default = `4` (medium) — calibrado para B2B Tier 1, configurável via App Setting `SAFETY_BLOCK_THRESHOLD`
- **D-7.3:** Defense-in-depth — filtramos input **e** output, mesmo com Azure OpenAI ter safety nativo
- **D-7.4:** Fail-open em Content Safety failure — emite `safety.error` para alarme dedicado, prioriza UX em incidente
- **D-7.5:** API key vs Managed Identity — mantemos key no lab por simplicidade; débito técnico flagado por Azure Policy no Capítulo 08
- **D-7.6:** App Insights daily cap = **1 GB** (soft cap) — proteção custo + Azure Policy audit no Capítulo 08
- **D-7.7:** Custom metrics via OpenTelemetry SDK, **não** via `track_metric()` legacy — pattern future-proof Microsoft 2025+
- **D-7.8:** `tenant_id` é dimension obrigatória em todos os 5 metrics — multi-tenant cost attribution

---

## Próximo capítulo

[08 — Azure Policy + Cost Management](./08-azure-policy-cost-management.md)
