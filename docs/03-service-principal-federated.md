# Capítulo 03 — Service Principal com Federated Credentials

> **HIGH disclaimer R6 cravado neste capítulo.**

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## DISCLAIMER R6 — ABAC Condition bloqueia fork-by-student

CI/CD via Federated Service Principal **NÃO funciona** em subscriptions com **ABAC condition** ativa por default.

### Quando isso acontece

- **Visual Studio Enterprise (live.com)**: vem com ABAC default que bloqueia role assignments via SP federado
- **Subscriptions corporate com Conditional Access policy** restritiva
- **Free Trial**: sem ABAC mas sem PAYG → ainda bloqueia Azure OpenAI

### Como validar ABAC ANTES de tentar deploy

```bash
# 1. Crie SP de teste
az ad sp create-for-rbac --name sp-test-abac --role contributor --scopes /subscriptions/<sub>

# 2. Tente role assignment via SP
az role assignment create \
  --assignee <SP_OBJECT_ID> \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/<sub>/resourceGroups/<rg>

# Se erro "ConditionRequiresAuthorization" ou "AuthorizationFailed conditional":
# → ABAC ATIVO → CI/CD vai falhar
# → Pivote para sub TFTEC OU PAYG sem ABAC OU corporate
```

### Subs que funcionam vs que falham

| Tipo | CI/CD funciona? |
|------|-----------------|
| **TFTEC subscription** (cenário ideal) | YES |
| **PAYG sem ABAC** | YES |
| **Subscription corporate** sem CA restritiva | YES |
| Visual Studio Enterprise (live.com) | NO (ABAC) |
| Free Trial | NO (sem PAYG) |

---

## Outline

### 1. Criar SP

```bash
az ad sp create-for-rbac \
  --name "sp-helpsphere-prod-lab" \
  --role contributor \
  --scopes /subscriptions/<SUB_ID>
```

Anotar:
- `appId` → `AZURE_CLIENT_ID`
- `tenant` → `AZURE_TENANT_ID`

### 2. Configurar Federated Credentials

Via Portal Azure → App Registrations → seu SP → Certificates & secrets → Federated credentials → Add credential

- Issuer: `https://token.actions.githubusercontent.com`
- Subject identifier: `repo:<seu-user>/apex-helpsphere-prod-lab:ref:refs/heads/main` (e adicionalmente um pra `environment:staging` e `environment:production`)
- Audience: `api://AzureADTokenExchange`

### 3. Adicionar ao GitHub Variables

```bash
gh variable set AZURE_TENANT_ID --body "<tenant>"
gh variable set AZURE_SUBSCRIPTION_ID --body "<sub>"
gh variable set AZURE_CLIENT_ID --body "<appId>"
```

### 4. Validar com workflow CI

```bash
gh workflow run ci.yml
gh run watch
```

Se falhar com "AuthorizationFailed" → R6 disclaimer aplica → pivote sub.

---

## Checklist

```
[ ] ABAC validado (sub funciona)
[ ] SP criado com nome sp-helpsphere-prod-lab
[ ] Federated Credentials configurados (3 subjects: main, staging, production)
[ ] GitHub Variables configuradas
[ ] Workflow CI roda sem erro de auth
```

---

## Próximo capítulo

[04 — Bicep modules](./04-bicep-modules.md)
