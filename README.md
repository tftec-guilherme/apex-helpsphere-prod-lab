# Apex HelpSphere — Lab Avançado D06 (IA Production-grade)

> Companion repo do **Lab Avançado** da Disciplina 06 (IA e Automação no Azure — Ferramentas Integradas) da Pós-Graduação em Arquitetura Cloud Azure (TFTEC + Anhanguera).

Este repo é o **espelho production-grade** do tema apex-helpsphere para o Lab Avançado. Diferente do `apex-rag-lab` (Lab Intermediário, Portal-first puro), aqui o aluno aplica **CI/CD via GitHub Actions + Bicep production-ready** em cima da fundação SaaS já validada no `apex-helpsphere`.

**Status:** v0.1.0-init (scaffold inicial)

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
| **GitHub Actions** | Free tier | 3 workflows: ci (PR) + cd-staging (push main) + cd-prod (manual approval) |

**Region:** East US 2 (alinhada com `aifhub-apex-prod` Foundry Hub)

---

## Quick start

```bash
# 1. Fork ESTE repo no seu GitHub
gh repo fork tftec-guilherme/apex-helpsphere-prod-lab --clone

# 2. Cd e configure secrets
cd apex-helpsphere-prod-lab
gh secret set AZURE_TENANT_ID
gh secret set AZURE_SUBSCRIPTION_ID
gh secret set AZURE_CLIENT_ID  # Service Principal com Federated Credentials

# 3. Edite infra/envs/dev.parameters.json com seu publisherEmail

# 4. Trigger CI (PR para main rodando bicep-lint + bicep-build + what-if)
git checkout -b feature/initial-deploy
git commit --allow-empty -m "chore: trigger CI"
gh pr create --title "Initial deploy validation"

# 5. Após PR merge, cd-staging deploya em rg-helpsphere-ia-prod-staging
# 6. Para prod: gh workflow run cd-prod.yml (manual approval gate)
```

---

## Pré-requisitos

| # | Item | Crítico? |
|---|------|----------|
| 1 | **Subscription PAYG** (Free Trial NÃO funciona — Azure OpenAI exige PAYG) | YES |
| 2 | **Foundry Hub `aifhub-apex-prod`** já provisionado | YES |
| 3 | Subscription **TFTEC sem ABAC** OU **PAYG sem ABAC** OU **corporate** (R6 disclaimer) | YES |
| 4 | GitHub repo (este, forked) | YES |
| 5 | Service Principal com Federated Credentials configurado | YES |
| 6 | Az CLI `>=2.60` + Bicep CLI `>=0.30` | YES |
| 7 | Python `3.11+` (eval scripts) | NO (offline opcional) |
| 8 | gh CLI autenticado | YES |

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
- **GitHub Actions IS pipeline** — tudo declarativo, zero clique manual em produção.
- **Production-grade canônico** — não simplificamos para "didático". Aluno vê o real.

---

## Estrutura

```
apex-helpsphere-prod-lab/
├── infra/              # Bicep modules + envs parameters
│   ├── main.bicep      # Entry point (subscription scope)
│   ├── modules/        # apim + content-safety + app-insights + policy
│   └── envs/           # dev / staging / prod parameters
├── .github/workflows/  # ci + cd-staging + cd-prod
├── src/
│   ├── agent/          # Function App agent runner (Content Safety + custom metrics)
│   ├── mcp-server/     # Placeholder — consumido via APIM, não reimplementado
│   └── functions/      # Reservado para HTTP triggers auxiliares
├── eval/               # Offline evaluation harness (groundedness/relevance/latency)
├── docs/               # 10 capítulos Lab Avançado (skeleton inicial)
├── README.md           # ESTE arquivo
├── PARA-O-ALUNO.md     # Boas-vindas + 8 pré-requisitos + 3 disclaimers HIGH
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE             # MIT
```

---

## Cleanup obrigatório

```bash
az group delete --name rg-helpsphere-ia-prod-dev --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-staging --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-prod --yes --no-wait
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
