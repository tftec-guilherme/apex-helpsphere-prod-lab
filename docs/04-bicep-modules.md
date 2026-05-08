# Capítulo 04 — Bicep modules

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## Outline

### 1. Estrutura

```
infra/
├── main.bicep          # Entry point (subscription scope)
├── bicepconfig.json    # Lint rules
├── modules/
│   ├── apim.bicep
│   ├── content-safety.bicep
│   ├── app-insights.bicep
│   └── policy.bicep
└── envs/
    ├── dev.parameters.json
    ├── staging.parameters.json
    └── prod.parameters.json
```

### 2. Filosofia "Bicep IS canonical"

- Tudo declarativo
- Portal só pra visualizar
- Mudanças manuais = drift = sobrescrito no próximo deploy

### 3. Walkthrough cada module

#### `main.bicep`
- targetScope subscription
- Cria RG + chama 4 modules
- Outputs: rgName, apimGatewayUrl, contentSafetyEndpoint, appInsightsConnectionString

#### `modules/apim.bicep`
- Developer SKU (R$ 250/mês — R4 disclaimer)
- 1 product `helpsphere-prod`
- 1 API `agent-api` com policies inbound (rate-limit + JWT + CORS)

#### `modules/content-safety.bicep`
- F0 free tier
- Managed Identity para Function App acessar

#### `modules/app-insights.bicep`
- Workspace-based (Log Analytics)
- Daily cap 1GB (controle custo)
- Custom metrics dimensions documentadas

#### `modules/policy.bicep`
- 3 assignments: locations + tags + Cosmos public-access denied

### 4. Comandos locais

```bash
az bicep lint --file infra/main.bicep
az bicep build --file infra/main.bicep --outfile infra/main.json
az deployment sub what-if \
  --location eastus2 \
  --template-file infra/main.bicep \
  --parameters @infra/envs/dev.parameters.json
```

---

## Checklist

```
[ ] az bicep lint passa em main.bicep + 4 modules
[ ] az bicep build gera main.json sem erros
[ ] az deployment sub what-if mostra recursos corretos
[ ] Parâmetros dev/staging/prod revisados
```

---

## Próximo capítulo

[05 — GitHub Actions pipelines](./05-github-actions-pipelines.md)
