# Capítulo 06 — APIM gateway + policies

> **HIGH disclaimer R4 cravado neste capítulo.**

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## DISCLAIMER R4 — APIM Developer R$ 250/mês ligado

**APIM SKU Developer não tem auto-pause.** Custo é cobrado **mesmo sem tráfego**.

### Custo real

- **Developer SKU:** ~R$ 250/mês ligado 24/7
- **Consumption SKU (alternativa):** pay-per-call (~R$ 0,50/1000 chamadas) — mas algumas features do Lab (named values, products) podem ter limitações
- **Premium SKU:** ~R$ 13.000/mês — fora de escopo lab pedagógico

### Cleanup obrigatório

```bash
# Ao fim do lab, OBRIGATÓRIO
az group delete --name rg-helpsphere-ia-prod-dev --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-staging --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-prod --yes --no-wait
```

### Alternativa Consumption

Edite `infra/envs/dev.parameters.json`:

```json
{
  "apimSku": { "value": "Consumption" }
}
```

Re-deploy. Limitações conhecidas:
- Sem custom domain (HTTPS apenas via *.azure-api.net)
- Sem named values com Key Vault references diretas
- Cold-start de ~2s na primeira chamada após idle

---

## Outline

### 1. APIM provisioning timeline

- Developer SKU: **30-45 min** primeiro deploy
- Consumption SKU: ~5 min

### 2. Product `helpsphere-prod`

- subscriptionRequired: true (precisa key)
- approvalRequired: false (auto-approve)
- state: published

### 3. API `agent-api`

- Path: `/agent`
- Operation: `POST /chat` (chat-completion)
- serviceUrl: aponta para Function App (placeholder até cravar)

### 4. Inbound policies

```xml
<rate-limit calls="100" renewal-period="60" />
<quota calls="10000" renewal-period="86400" />
<validate-jwt header-name="Authorization">
  <openid-config url="https://login.microsoftonline.com/{tenantId}/.well-known/openid-configuration" />
  <required-claims>
    <claim name="aud" match="any">
      <value>api://helpsphere-prod-agent</value>
    </claim>
  </required-claims>
</validate-jwt>
<cors>...</cors>
```

### 5. Como obter subscription key

Portal Azure → APIM → Subscriptions → Built-in product `helpsphere-prod` → Show keys

OU CLI:
```bash
az apim subscription show --resource-group <RG> --service-name <APIM> --sid master --query primaryKey -o tsv
```

### 6. Como testar

```bash
curl -X POST https://apim-helpsphere-XXXX.azure-api.net/agent/chat \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: <key>" \
  -H "Authorization: Bearer <jwt>" \
  -d '{"query": "Como abro um chamado?"}'
```

---

## Checklist

```
[ ] APIM provisionado (provisioningState = Succeeded)
[ ] Product helpsphere-prod published
[ ] API agent-api registered com path /agent
[ ] Inbound policies rate-limit + JWT + CORS aplicadas
[ ] Subscription key obtida
[ ] Smoke curl retornou HTTP 4XX (esperado sem JWT valido)
```

---

## Próximo capítulo

[07 — Content Safety + App Insights](./07-content-safety-app-insights.md)
