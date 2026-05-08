# Capítulo 05 — GitHub Actions pipelines

> **HIGH disclaimer R6 cravado neste capítulo.**

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## DISCLAIMER R6 (recap) — CI/CD requer sub sem ABAC

Ver `docs/03-service-principal-federated.md` para detalhes completos.

**TL;DR:** este lab assume sub TFTEC sem ABAC OU sub PAYG sem ABAC OU sub corporate. Em VSE pessoal `live.com` com ABAC, **CI workflow falha** ao fazer role assignments. Você ainda consegue rodar `az deployment sub create` localmente, mas perde o valor pedagógico do CI/CD demo.

---

## Outline

### 1. 3 Workflows

#### `ci.yml` — Pull Request validation
- Triggers: PR para main + push em feature branches
- Jobs:
  - `bicep-lint`: az bicep lint em main.bicep + modules
  - `bicep-build`: compila para ARM JSON, upload artifact
  - `bicep-what-if`: preview diff contra dev env
  - `python-lint`: ruff check src/ eval/

#### `cd-staging.yml` — Auto deploy
- Trigger: push to main
- Job: deploy staging + smoke (APIM gateway reachable)
- Environment GitHub: `staging`

#### `cd-prod.yml` — Manual approval gate
- Trigger: workflow_dispatch (manual)
- Pre-flight: confirma input "sim" sobre custo APIM R$ 250/mês
- Approval gate: GitHub Environment `production` requer approver
- Smoke estendido: APIM provisioning state + agent-api operations listadas

### 2. Walkthrough manual approval

- Abrir Actions → "3. CD Prod"
- Clicar "Run workflow"
- Escolher branch main + input confirm_apim_cost = sim
- Aguardar approval gate em GitHub Environments
- Reviewer aprova → deploy roda

### 3. Validação end-to-end

```bash
# 1. Trigger CI manual
gh workflow run ci.yml

# 2. Watch
gh run watch

# 3. Após PR merged, cd-staging roda automaticamente

# 4. Para prod, manual:
gh workflow run cd-prod.yml -f confirm_apim_cost=sim
```

---

## Checklist

```
[ ] CI workflow passou em PR
[ ] CD Staging deployou sem erro
[ ] CD Prod requer approval (testado)
[ ] APIM provisioned em rg-helpsphere-ia-prod-staging
[ ] Smoke test reportou HTTP code (200/202/404 esperado pra APIM em init)
```

---

## Próximo capítulo

[06 — APIM gateway + policies](./06-apim-gateway-policies.md)
