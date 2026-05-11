# Apex HelpSphere — Lab Avançado D06 (IA Production-grade)

> Companion repo do **Lab Avançado** da Disciplina 06 (IA e Automação no Azure — Ferramentas Integradas) da Pós-Graduação em Arquitetura Cloud Azure (TFTEC + Anhanguera).

Este repo é o **espelho production-grade** do tema apex-helpsphere para o Lab Avançado. Diferente do `apex-rag-lab` (Lab Intermediário, Portal-first puro), aqui o aluno aplica **Bicep production-ready + Azure CLI manual** numa STACK PARALELA à fundação SaaS — mesmos padrões técnicos (APIM Developer, Content Safety, App Insights workspace-based, Azure Policy), recursos isolados em `rg-lab-avancado` para fins pedagógicos.

> **CI/CD via GitHub Actions é capítulo futuro** — esta versão (v0.3.0) é 100% Portal+CLI manual para reduzir superfície de falha (ABAC, OIDC trust, federated SP). Aluno domina Bicep + `az deployment group create` primeiro; CI/CD vira release dedicada.

**Status:** v0.3.0-cli-manual

---

## Stack production-grade

| Componente | Tier | Função |
|------------|------|--------|
| **APIM (API Management)** | Developer | Gateway com policies inbound (rate-limit + JWT + CORS) — visibilidade canônica |
| **Content Safety** | F0 (free) | Filtro input + output do agente Foundry |
| **Application Insights** | Workspace-based | Custom metrics LLM (model, tokens, latency, blocked) |
| **Azure Policy** | Free | 3 policies: allowed locations + required tags + Cosmos public-access denied |
| **Cost Management Budget** | Free | Alertas de custo por RG |
| **Logic App (Circuit Breaker)** | Consumption | Disjuntor automático em caso de spike de custo / errors |

**Region:** East US 2 (alinhada com `aifhub-apex-prod` Foundry Hub)

---

## Quick start

```powershell
# 1. (Opcional) Fork ESTE repo no seu GitHub para portfolio
gh repo fork tftec-guilherme/apex-helpsphere-prod-lab --clone
Set-Location apex-helpsphere-prod-lab

# 2. Logar no Azure CLI e confirmar subscription
az login
az account show --query "{name:name, id:id}" -o table

# 3. Criar o RG manualmente (docs/02)
az group create `
  --name rg-lab-avancado `
  --location eastus2 `
  --tags cost-center=apex-helpsphere-ia environment=lab application=helpsphere-ia owner="<seu-email>"

# 4. Editar infra/envs/dev.parameters.json — substituir apimPublisherEmail

# 5. Validar com what-if (read-only, gratuito)
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/dev.parameters.json'

# 6. Deploy dev (real — APIM Developer ~R$ 8/dia ligado)
az deployment group create `
  --name "deploy-dev-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/dev.parameters.json'

# 7. Cleanup obrigatório no fim do lab — ver Cap 10
az group delete --name rg-lab-avancado --yes --no-wait
```

**Linux/Mac/WSL:** troque `` ` `` (backtick) por `\` no fim das linhas, `Set-Location` por `cd`, `Get-Date -Format 'yyyyMMddHHmmss'` por `date +%Y%m%d%H%M%S`, e remova as aspas simples ao redor de `@infra/envs/...`.

---

## Pré-requisitos

| # | Item | Crítico? |
|---|------|----------|
| 1 | **Subscription PAYG** (Free Trial NÃO funciona — Azure OpenAI exige PAYG) | YES |
| 2 | **Foundry Hub `aifhub-apex-prod`** já provisionado | YES |
| 3 | Az CLI `>=2.60` + Bicep CLI `>=0.30` | YES |
| 4 | RG `rg-lab-avancado` criado em East US 2 com 4 tags FinOps (docs/02) | YES |
| 5 | Python `3.11+` (eval scripts) | NO (offline opcional) |
| 6 | GitHub repo (fork opcional para portfolio) | NO |
| 7 | gh CLI autenticado | NO (só se quiser fork via CLI) |
| 8 | Service Principal com Federated Credentials | NO (CI/CD futuro — fora do escopo) |

---

## Custos esperados (PAYG East US 2)

| Recurso | Tier | Custo aprox/mês |
|---------|------|-----------------|
| **APIM Developer** ligado 24/7 | Developer | **~R$ 250/mês** |
| Content Safety | F0 | Free |
| App Insights | Pay-per-GB | ~R$ 10/mês (volume baixo lab) |
| Azure Policy | Free | R$ 0 |
| Logic App Circuit Breaker | Consumption | ~R$ 5/mês |
| Foundry Agent calls | gpt-4.1-mini PAYG | ~R$ 15/mês (lab uso) |
| **TOTAL aprox** | | **~R$ 280/mês se APIM ligado** |

> **DISCLAIMER R4:** APIM Developer **não tem auto-pause**. Se você esquecer ligado, R$ 250/mês recorrente. **Cleanup obrigatório** ao fim do lab (capítulo 10) OU use SKU `Consumption` (alternativa documentada em `docs/06-apim-gateway-policies.md`).

---

## Filosofia

- **Bicep IS canonical** — `infra/main.bicep` é a fonte de verdade. Portal só pra visualizar.
- **CLI manual nesta versão** — Portal+CLI manual (Azure CLI via PowerShell). CI/CD via GitHub Actions é capítulo futuro (fora do escopo).
- **Production-grade canônico** — não simplificamos para "didático". Aluno vê o real (APIM Developer, Content Safety, App Insights workspace-based, Azure Policy).

---

## Estrutura

```
apex-helpsphere-prod-lab/
├── infra/              # Bicep modules + envs parameters
│   ├── main.bicep      # Entry point (resourceGroup scope)
│   ├── modules/        # apim + content-safety + app-insights + policy
│   └── envs/           # dev / staging / prod parameters
├── src/
│   ├── agent/          # Function App agent runner (Content Safety + custom metrics)
│   ├── mcp-server/     # Placeholder — consumido via APIM, não reimplementado
│   └── functions/      # Reservado para HTTP triggers auxiliares
├── eval/               # Offline evaluation harness (groundedness/relevance/latency)
├── docs/               # 10 capítulos Lab Avançado (Portal+CLI manual)
├── README.md           # ESTE arquivo
├── PARA-O-ALUNO.md     # Boas-vindas + 7 pré-requisitos + 2 disclaimers HIGH
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE             # MIT
```

> **Nota:** `.github/workflows/` removido nesta versão (v0.3.0). CI/CD via GitHub Actions sai do escopo — capítulo futuro.

---

## Cleanup obrigatório

```powershell
az group delete --name rg-lab-avancado --yes --no-wait
```

Veja `docs/10-cleanup.md` para checklist completo.

---

## Suporte

- Issues: https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/issues
- Discussão Lab Avançado: usar canal oficial da disciplina

---

**Disciplina:** D06 — IA e Automação no Azure (Ferramentas Integradas)
**Pós-Graduação:** Arquitetura Cloud Azure | TFTEC + Anhanguera
**Professor:** Guilherme Campos
