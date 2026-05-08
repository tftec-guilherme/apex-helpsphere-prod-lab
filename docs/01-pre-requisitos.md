# Capítulo 01 — Pré-requisitos

> **Lab Avançado D06 (companion):** este capítulo lista o que você precisa **antes** de começar. Se algum item falhar, pare e resolva — não pule.

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior quando @ux-design-expert refatorar Lab Avançado guide (Story 06.12 Bloco A). Este é o esqueleto inicial.

---

## Outline

### 1. Subscription Azure (PAYG, sem ABAC)

- Validar tipo de subscription
- Validar ABAC condition (CRÍTICO — R6 disclaimer)
- Comando: `az account show --query "[id, name, state]" -o tsv`
- Como verificar ABAC: tentar `az role assignment create` em SP federado

### 2. Foundry Hub `aifhub-apex-prod` provisionado

- Validar Hub existe e está em "Succeeded"
- Validar deployments gpt-4.1-mini + text-embedding-3-small em PAYG
- Comando: `az ml workspace show --name aifhub-apex-prod --resource-group <RG>`

### 3. Tooling local

- Az CLI >= 2.60
- Bicep CLI >= 0.30
- Python 3.11+
- gh CLI autenticado

### 4. GitHub repo (este, forked)

- Fork via gh CLI
- Configurar secrets (próximo capítulo)

### 5. Service Principal com Federated Credentials

- Criar SP com escopo Subscription Contributor
- Configurar Federated Credentials apontando para GitHub repo
- Validar com workflow_dispatch trigger CI

---

## Checklist

```
[ ] Subscription PAYG ativa
[ ] Subscription sem ABAC condition (CRITICO)
[ ] Foundry Hub aifhub-apex-prod com deployments PAYG
[ ] Az CLI + Bicep CLI atualizados
[ ] Python 3.11+ instalado
[ ] gh CLI autenticado
[ ] GitHub repo forked
[ ] SP com Federated Credentials
[ ] Workflow CI rodou com sucesso (manual dispatch)
```

---

## Próximo capítulo

[02 — RG + GitHub setup](./02-rg-github-setup.md)
