# Capítulo 07 — Content Safety + Application Insights

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## Outline

### Content Safety

#### 1. F0 free tier limits
- 1000 calls/min
- 5000 calls/day
- Suficiente para lab pedagógico

#### 2. Categorias filtradas
- Hate
- SelfHarm
- Sexual
- Violence

Severidade 0-6. Threshold default no `agent_runner.py`: severity >= 4 → BLOCK.

#### 3. Como funciona no fluxo
```
User query → Content Safety (input filter)
            → Foundry Agent → response → Content Safety (output filter)
            → User
```

Se input ou output filter rejeitar → emit metric `content_safety_blocked=true` + retorna 400/502.

#### 4. Tuning threshold

```bash
# Em prod parameters.json (se quiser custom)
SAFETY_BLOCK_THRESHOLD=2  # mais agressivo (default 4)
SAFETY_BLOCK_THRESHOLD=6  # mais permissivo (basicamente off)
```

### Application Insights

#### 1. Workspace-based vs classic
- Workspace-based: integra com Log Analytics, queries via KQL
- Daily cap 1GB cravado em `app-insights.bicep` (controle custo)

#### 2. Custom metrics emitidas

Dimensions emitidas pelo `agent_runner.py`:
- `model` (gpt-4.1-mini, gpt-4.1, etc)
- `tokens_input` (int)
- `tokens_output` (int)
- `latency_ms` (int)
- `content_safety_blocked` (boolean)
- `blocked_stage` (input | output | null)
- `tenant_id` (multi-tenant tracking)

#### 3. Queries KQL exemplo

```kusto
// Tokens consumidos por tenant último 24h
customMetrics
| where name == "metric_llm_call"
| where timestamp > ago(24h)
| extend tenant = tostring(customDimensions["tenant_id"])
| extend tokens_total = toint(customDimensions["tokens_input"]) + toint(customDimensions["tokens_output"])
| summarize total_tokens=sum(tokens_total) by tenant
| order by total_tokens desc

// Content Safety blocks por categoria
customEvents
| where name contains "content_safety_blocked"
| extend stage = tostring(customDimensions["blocked_stage"])
| summarize count() by stage, bin(timestamp, 1h)
```

#### 4. Dashboards recomendados
- Tokens por tenant (cost attribution)
- Latency p50/p95/p99
- Safety blocks rate
- Errors rate por status code

---

## Checklist

```
[ ] Content Safety F0 provisionado
[ ] App Insights workspace-based provisionado com daily cap 1GB
[ ] Function App configurada com APPLICATIONINSIGHTS_CONNECTION_STRING
[ ] Function App configurada com CONTENT_SAFETY_ENDPOINT + Managed Identity
[ ] Smoke test emitiu metric custom (verificar customMetrics no Log Analytics)
[ ] Query KQL "tokens por tenant" retorna dados
```

---

## Próximo capítulo

[08 — Azure Policy + Cost Management](./08-azure-policy-cost-management.md)
