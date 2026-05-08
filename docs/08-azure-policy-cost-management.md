# Capítulo 08 — Azure Policy + Cost Management

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## Outline

### Azure Policy

#### 3 Built-in policy assignments aplicadas

##### 1. Allowed locations (East US 2 only)
- ID: `e56962a6-4747-49cd-b67b-bf8b01975c4c`
- Bloqueia deployments fora de East US 2
- Custo: free

##### 2. Require cost-center tag
- ID: `871b6d14-10aa-478d-b590-94f262ecfa99`
- Exige tag `cost-center` em todos os recursos
- Bicep já cria com tag — policy garante drift fica bloqueado

##### 3. Cosmos DB public access denied (defensivo)
- ID: `797b37f7-06b8-444c-b1ad-fc62867f335a`
- Mesmo que esse lab não use Cosmos, é defensivo se aluno adicionar later

#### Como verificar compliance

```bash
az policy state list \
  --resource-group rg-helpsphere-ia-prod-staging \
  --query "[?complianceState=='NonCompliant']" -o table
```

### Cost Management Budget

#### 1. Budget alerts
- Threshold em USD/mês configurado em `infra/envs/*.parameters.json`
- dev: $50, staging: $100, prod: $300
- Alert at 50%, 80%, 100% — email para `apimPublisherEmail`

#### 2. Cost Analysis queries
- Por RG: `rg-helpsphere-ia-prod-staging` últimos 30 dias
- Por tag: `cost-center=apex-helpsphere-ia`
- Por serviço: APIM domina, depois Foundry calls

#### 3. Logic App Circuit Breaker

##### Trigger
- HTTP webhook chamado quando spike custo / errors detectado

##### Action
- Disable APIM API operation `chat-completion` temporariamente
- Email alert
- Reabilitar manual após investigação

> **Nota:** Logic App pré-pronto provisionado em iteração futura — não está em `infra/main.bicep` v0.1.0-init. Será adicionado quando @ux-design-expert refatorar conteúdo.

---

## Checklist

```
[ ] 3 policy assignments aplicados em RG
[ ] Compliance state verificado (Compliant esperado)
[ ] Budget criado em Cost Management
[ ] Cost Analysis mostra breakdown por tag cost-center
[ ] Logic App circuit-breaker (futura iteração)
```

---

## Próximo capítulo

[09 — Runbook eval](./09-runbook-eval.md)
