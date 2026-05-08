# Capítulo 02 — Resource Group + GitHub repo setup

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## Outline

### 1. Fork do repo

```bash
gh repo fork tftec-guilherme/apex-helpsphere-prod-lab --clone
cd apex-helpsphere-prod-lab
```

### 2. GitHub Variables (não-secret)

Configurar via `gh variable set` ou Settings → Variables:

- `AZURE_TENANT_ID` (Variables, não Secrets — pode ser público)
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_CLIENT_ID` (do SP federado)

### 3. GitHub Environments

- Criar environment `staging` (auto deploy push main)
- Criar environment `production` (manual approval gate)

### 4. Resource Groups (criados pelo Bicep, não manualmente)

- `rg-helpsphere-ia-prod-dev` — what-if + lab local
- `rg-helpsphere-ia-prod-staging` — auto deploy
- `rg-helpsphere-ia-prod-prod` — manual approval

> **Importante:** NÃO crie RGs manualmente no Portal. O Bicep `main.bicep` cria via subscription scope.

---

## Checklist

```
[ ] Repo forked e clonado
[ ] GitHub Variables configuradas (TENANT, SUB, CLIENT)
[ ] Environment staging criado
[ ] Environment production criado com approval reviewers
[ ] Branch protection main configurado (PR + CI required)
```

---

## Próximo capítulo

[03 — Service Principal Federated](./03-service-principal-federated.md)
