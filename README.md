<div align="center">

# 🏭 Apex HelpSphere — Lab Avançado D06

**IA Production-grade — Bicep canonical + Azure CLI manual em STACK PARALELA**

[![Status](https://img.shields.io/badge/status-v0.3.1--guia--portal--consolidado-success)](./CHANGELOG.md)
[![Cost](https://img.shields.io/badge/custo-~R%24%20280%2Fm%C3%AAs%20se%20APIM%20ligado-red)](./PARA-O-ALUNO.md#disclaimer-r4--apim-developer-r-250m%C3%AAs-ligado)
[![Region](https://img.shields.io/badge/region-East%20US%202-orange)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Disciplina D06](https://img.shields.io/badge/Pós--Graduação-TFTEC%20+%20Anhanguera-purple)](https://github.com/tftec-guilherme/azure-retail)

📘 [**Guia Portal completo (94KB · 2212L · entry-point único)**](./docs/00-Lab_Avancado_IA_Producao_Guia_Portal.md)

</div>

---

> Companion repo do **Lab Avançado D06** (IA e Automação no Azure — Ferramentas Integradas) da Pós-Graduação Arquitetura Cloud Azure (TFTEC + Anhanguera). Espelho **production-grade** do tema `apex-helpsphere` em **STACK PARALELA** à fundação SaaS — mesmos padrões técnicos (APIM Developer + Content Safety + App Insights workspace-based + Azure Policy), recursos isolados em `rg-lab-avancado`.

> **CI/CD via GitHub Actions é capítulo futuro** — esta versão (v0.3.1) é 100% Portal+CLI manual para reduzir superfície de falha (ABAC, OIDC trust, federated SP). Aluno domina Bicep + `az deployment group create` primeiro; CI/CD vira release dedicada.

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

## 🚀 Quick start

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

## 📋 Pré-requisitos

> [!IMPORTANT]
> **Stack PARALELA à SaaS** — este lab NÃO consome `apex-helpsphere`. Veja [PARA-O-ALUNO.md "Por que stack paralela?"](./PARA-O-ALUNO.md#por-que-stack-paralela-e-não-integrada).

### 🔴 Críticos (precisa antes)

| # | Item | Por que? |
|---|------|----------|
| 1 | **Subscription PAYG** ativa | Azure OpenAI exige PAYG. Free Trial **não funciona** |
| 2 | **Foundry Hub `aifhub-apex-prod`** | Provisionado no Bloco 6 do recording, em `rg-lab-intermediario` |
| 3 | **Az CLI ≥ 2.60 + Bicep CLI ≥ 0.30** | Necessário para `az deployment group create` |
| 4 | **RG `rg-lab-avancado`** | Criar manualmente em East US 2 com 4 tags FinOps ([docs/02](./docs/02-rg-github-setup.md)) |

### 🟡 Opcionais

| # | Item | Quando? |
|---|------|---------|
| 5 | GitHub repo (fork) | Portfolio/histórico |
| 6 | Service Principal federated | Só se estender com CI/CD (capítulo futuro) |
| 7 | Python 3.11+ | Eval offline opcional |
| 8 | gh CLI autenticado | Só pra fork via CLI |

---

## 💰 Custos esperados (PAYG East US 2)

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

## 🧭 Filosofia

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
├── docs/               # guia consolidado (entry-point) + 11 capítulos Lab Avançado (Portal+CLI manual)
│   ├── 00-Lab_Avancado_IA_Producao_Guia_Portal.md  # ⭐ GUIA COMPLETO entry-point (94KB · 2212L)
│   └── 01-... → 10-...  (11 capítulos detalhados)
├── README.md           # ESTE arquivo
├── PARA-O-ALUNO.md     # Boas-vindas + 7 pré-requisitos + 2 disclaimers HIGH
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE             # MIT
```

> **Nota:** `.github/workflows/` removido nesta versão (v0.3.0). CI/CD via GitHub Actions sai do escopo — capítulo futuro.

---

## 🧹 Cleanup obrigatório

```powershell
az group delete --name rg-lab-avancado --yes --no-wait
```

Veja `docs/10-cleanup.md` para checklist completo.

---

## 🔗 Família D06

Este lab faz parte da **família de 4 repos** da Disciplina 06 (IA e Automação no Azure):

| Repo | Bloco D06 | Estilo | Status |
|---|---|---|---|
| [`apex-helpsphere`](https://github.com/tftec-guilherme/apex-helpsphere) | Bloco 2 — SaaS base | Production-grade, `azd up` | v2.x |
| [`apex-rag-lab`](https://github.com/tftec-guilherme/apex-rag-lab) | Bloco 3 — Lab Intermediário RAG | Portal-first + fork funcional | v1.x |
| [`apex-helpsphere-agente-lab`](https://github.com/tftec-guilherme/apex-helpsphere-agente-lab) | Bloco 4-5 — Lab Final agente | Portal-first companion | v0.3.x |
| **`apex-helpsphere-prod-lab`** (você está aqui) | Bloco 6 — Lab Avançado IA production | Bicep + Azure CLI manual | v0.3.x |

> **Stack paralela à SaaS:** este repo NÃO consome `apex-helpsphere`. Aprende-se o pattern production-grade (APIM Developer, Content Safety, App Insights workspace-based, Azure Policy) em recursos isolados em `rg-lab-avancado`. Ver [`PARA-O-ALUNO.md`](./PARA-O-ALUNO.md#filosofia-bicep-is-canonical) para rationale.

---

## Suporte

- Issues: https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/issues
- Discussão Lab Avançado: usar canal oficial da disciplina

---

**Disciplina:** D06 — IA e Automação no Azure (Ferramentas Integradas)
**Pós-Graduação:** Arquitetura Cloud Azure | TFTEC + Anhanguera
**Professor:** Guilherme Campos
