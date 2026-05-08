# Capítulo 05 — GitHub Actions pipelines

> **Objetivo:** criar 3 workflows GitHub Actions production-grade (CI + CD Staging + CD Prod com manual approval gate), configurar 2 GitHub Environments (`staging` + `production`) com protection rules, e disparar o primeiro deploy end-to-end via OIDC federated credential (sem secret armazenado).
>
> **Tempo:** 90-120 min (não inclui ~30-45 min de provisão APIM em background)
>
> **Status:** `v0.2.0-piloto` ⚠️ EXPANDIDO (era `v0.1.0-init` outline) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Parte 3 (Passos 3.1-3.7) + Parte 1 (Passos 1.3-1.5)

---

## DISCLAIMER R6 (recap obrigatório) — CI/CD requer sub sem ABAC

Ver `docs/03-service-principal-federated.md` para detalhes completos. **TL;DR:** este lab assume sub TFTEC sem ABAC OU sub PAYG sem ABAC OU sub corporate. Em VSE pessoal `live.com` com ABAC, **CI workflow falha** ao fazer role assignments. Você ainda consegue rodar `az deployment group create` localmente, mas perde o valor pedagógico do CI/CD demo.

---

## Pré-requisitos

- ✅ Capítulo 02 concluído — RG `rg-lab-avancado` existe e tags `cost-center=apex-helpsphere-ia environment=lab application=helpsphere-ia` aplicadas
- ✅ Capítulo 03 concluído — Service Principal `sp-github-actions-helpsphere` criado com role **Contributor** scoped em `rg-lab-avancado` + 2 federated credentials (main branch + pull_request)
- ✅ Capítulo 04 concluído — Bicep modules em `infra/main.bicep` + `infra/modules/{apim,content-safety,app-insights,policy}.bicep` + parameter files `infra/envs/{staging,prod}.parameters.json` committed
- ✅ GitHub Secrets registrados no repo `helpsphere-ia` (cravados no Capítulo 03):
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
  - `AZURE_CLIENT_ID`
  - `AOAI_API_KEY` (necessário para o job `eval-offline`)
- ✅ `az` CLI logado e `gh` CLI autenticado (usados nas Alternativas CLI)
- ✅ VS Code com extensão **GitHub Actions** instalada (sintaxe highlight + validation)

---

## Resumo dos 3 workflows que vamos cravar

| Workflow | Trigger | Jobs | Environment | Approval gate? |
|---|---|---|---|---|
| `ci.yml` | `pull_request` em `main` + `push` em `main` | `lint-bicep` · `lint-python` · `bicep-what-if` (só em PR) | — | Não |
| `cd-staging.yml` | `push` em `main` (auto após PR merged) | `deploy-staging` · `eval-offline` | `staging` | Não |
| `cd-prod.yml` | `workflow_dispatch` (manual) | `validate` · `deploy-prod` · `rollback` (em failure) | `production` | **SIM** (required reviewer) |

> **Por que 3 workflows e não 1?** Separação de responsabilidades: CI roda em todo PR (rápido, barato, dá feedback), CD Staging roda automático em main (ambiente intermediário pra eval), CD Prod só roda manual com gate humano (custo + risco). Pattern canônico de pipeline production-grade.

---

## Passo 5.1 — Criar workflow `ci.yml`

**No Portal Azure:** este Passo é executado no **GitHub Actions UI** (não no Portal Azure). Workflows são arquivos YAML versionados no repo.

**No GitHub Actions UI:**

1. Abra o navegador em `https://github.com/<seu-username>/helpsphere-ia/actions`
2. Se for primeira vez no repo, GitHub mostra catálogo de starter workflows. Clique no link azul **"set up a workflow yourself"** (canto superior direito do título "Get started with GitHub Actions")
3. GitHub abre editor web com `main.yml` por padrão. **Renomeie para `ci.yml`** no campo do nome do arquivo (topo do editor)
4. Apague o conteúdo placeholder e cole o YAML abaixo:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  id-token: write   # OBRIGATÓRIO para OIDC azure/login
  contents: read

jobs:
  lint-bicep:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bicep lint
        run: |
          az bicep build --file infra/main.bicep
          az bicep build --file infra/modules/apim.bicep
          az bicep build --file infra/modules/content-safety.bicep
          az bicep build --file infra/modules/app-insights.bicep
          az bicep build --file infra/modules/policy.bicep

  lint-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install ruff pytest
      - run: ruff check src/ eval/

  bicep-what-if:
    runs-on: ubuntu-latest
    needs: lint-bicep
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Bicep what-if
        run: |
          az deployment group what-if \
            --resource-group rg-lab-avancado \
            --template-file infra/main.bicep \
            --parameters infra/envs/staging.parameters.json
```

5. Canto superior direito → **Commit changes...** → escolha **"Commit directly to the `main` branch"** → **Commit changes**
6. GitHub redireciona para `https://github.com/<seu-username>/helpsphere-ia/actions` — você verá o workflow **CI** listado e (como o commit foi `push` em `main`) ele dispara automaticamente

<!-- screenshot: cap05-passo5.1-github-actions-new-workflow-ci.png -->

> **Alternativa via VS Code + git push (recomendado se você prefere editor local):**
>
> ```bash
> # Na raiz do clone local de helpsphere-ia
> mkdir -p .github/workflows
> # Cole o YAML acima em .github/workflows/ci.yml usando seu editor preferido
> git add .github/workflows/ci.yml
> git commit -m "feat: GitHub Actions CI workflow"
> git push origin main
> ```

> **Custo:** GitHub Actions é gratuito em repos públicos · em repos privados, conta para 2.000 minutos/mês free tier · provisão Azure aqui é **zero** (apenas `bicep build` + `what-if` que são read-only)

> **Nota pedagógica — por que 3 jobs separados e não 1 monolítico?** Jobs paralelos rodam em runners independentes → feedback ~3x mais rápido. Se `lint-python` falhar, você não precisa esperar `lint-bicep` terminar pra ver o erro. O `needs: lint-bicep` em `bicep-what-if` é a única dependência (porque what-if precisa do template compilado).

> **Nota OIDC vs client secret:** repare que **NÃO há `creds: ${{ secrets.AZURE_CREDENTIALS }}`** em `azure/login@v2`. Em vez disso, `client-id` + `tenant-id` + `subscription-id` apontam para a federated credential criada no Capítulo 03. GitHub apresenta JWT, Entra valida, ninguém troca segredo. Production-grade.

---

## Passo 5.2 — Criar workflow `cd-staging.yml`

**No GitHub Actions UI:**

1. Abra `https://github.com/<seu-username>/helpsphere-ia/actions` → botão **"New workflow"** (canto superior direito)
2. Topo da página → link **"set up a workflow yourself"**
3. Renomeie o arquivo para **`cd-staging.yml`** no campo do nome do arquivo
4. Cole o YAML abaixo:

```yaml
# .github/workflows/cd-staging.yml
name: CD Staging

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy infra (Bicep)
        run: |
          az deployment group create \
            --resource-group rg-lab-avancado \
            --template-file infra/main.bicep \
            --parameters infra/envs/staging.parameters.json \
            --name "staging-${{ github.run_number }}"

      - name: Health check
        run: |
          APIM_URL=$(az apim show -n apim-helpsphere-staging -g rg-lab-avancado --query gatewayUrl -o tsv)
          echo "APIM URL: $APIM_URL"
          curl -f -s --max-time 30 "$APIM_URL/status-0123456789abcdef" \
            || echo "(APIM health endpoint pode não existir ainda — OK em primeiro deploy)"

  eval-offline:
    runs-on: ubuntu-latest
    needs: deploy-staging
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -r eval/requirements.txt

      - name: Run eval offline
        env:
          AOAI_API_KEY: ${{ secrets.AOAI_API_KEY }}
          AOAI_ENDPOINT: ${{ vars.AOAI_ENDPOINT }}
          AGENT_FUNCTION_URL: ${{ vars.AGENT_FUNCTION_URL_STAGING }}
        run: |
          python eval/run_eval.py --threshold-regression 0.05

      - name: Upload eval results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: eval-results-staging
          path: eval/results.json
```

5. **Commit changes...** → branch `main` → **Commit changes**

<!-- screenshot: cap05-passo5.2-cd-staging-yml-editor.png -->

> **Alternativa via VS Code + git push:**
>
> ```bash
> # Na raiz do clone local
> # Cole o YAML acima em .github/workflows/cd-staging.yml
> git add .github/workflows/cd-staging.yml
> git commit -m "feat: GitHub Actions CD Staging workflow"
> git push origin main
> ```

> **Custo:** zero overhead GitHub Actions · custo Azure depende do que o Bicep deploya (APIM Developer = R$ 250/mês se ficar ligado — provisione e delete no mesmo dia, ver Capítulo 10)

> **Nota pedagógica — `environment: staging`:** a chave `environment: staging` no job vincula esse run ao GitHub Environment chamado `staging` (criamos no Passo 5.4). Permite isolar variables (`AOAI_ENDPOINT`, `AGENT_FUNCTION_URL_STAGING`) por env e — em produção real — adicionar approval gates por env.

> **Nota pedagógica — `needs: deploy-staging`:** o job `eval-offline` só roda **depois** que `deploy-staging` termina com sucesso. Se deploy falha, eval nem dispara → economia de tokens AOAI + clareza de causa raiz.

---

## Passo 5.3 — Criar workflow `cd-prod.yml` (manual approval gate)

**No GitHub Actions UI:**

1. `https://github.com/<seu-username>/helpsphere-ia/actions` → **"New workflow"** → **"set up a workflow yourself"**
2. Renomeie o arquivo para **`cd-prod.yml`**
3. Cole o YAML abaixo:

```yaml
# .github/workflows/cd-prod.yml
name: CD Prod (Manual)

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type "deploy-prod" to confirm'
        required: true
        type: string

permissions:
  id-token: write
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate confirmation
        if: github.event.inputs.confirm != 'deploy-prod'
        run: |
          echo "::error::Confirmation incorrect — workflow requires input='deploy-prod'"
          exit 1

  deploy-prod:
    runs-on: ubuntu-latest
    needs: validate
    environment:
      name: production
      url: ${{ steps.deploy.outputs.apimUrl }}
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - id: deploy
        name: Deploy infra (Bicep)
        run: |
          OUTPUT=$(az deployment group create \
            --resource-group rg-lab-avancado \
            --template-file infra/main.bicep \
            --parameters infra/envs/prod.parameters.json \
            --name "prod-${{ github.run_number }}" \
            --query properties.outputs.apimGatewayUrl.value -o tsv)
          echo "apimUrl=$OUTPUT" >> $GITHUB_OUTPUT

      - name: Smoke test prod
        run: |
          curl -f -s --max-time 30 "${{ steps.deploy.outputs.apimUrl }}/status-0123456789abcdef" \
            || (echo "::error::Smoke test failed — initiating rollback consideration" && exit 1)

  rollback:
    runs-on: ubuntu-latest
    needs: deploy-prod
    if: failure()
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Rollback (revert to previous deployment)
        run: |
          PREV=$(az deployment group list -g rg-lab-avancado \
            --query "[?starts_with(name, 'prod-')] | [1].name" -o tsv)
          echo "Reverting to: $PREV"
          # Em produção real isso seria revert efetivo via slot swap, ARM template
          # anterior, ou rollback de deployment. Aqui é placeholder pedagógico.
```

4. **Commit changes...** → branch `main` → **Commit changes**

<!-- screenshot: cap05-passo5.3-cd-prod-yml-editor.png -->

> **3 mecanismos de proteção empilhados** neste workflow:
>
> 1. **`workflow_dispatch` only** — sem trigger automático em push/PR, só roda se humano clicar "Run workflow"
> 2. **`input: confirm` obrigatório** — validador rejeita se texto não for exatamente `deploy-prod` (case-sensitive)
> 3. **`environment: production`** — vincula a Environment com **required reviewer** (Passo 5.4) → bloqueia deploy até alguém aprovar via UI
>
> Pattern: **"3 obstáculos contra deploy acidental"** — você teria que (1) abrir manualmente, (2) digitar string específica, (3) aprovar como reviewer. Provavelmente refletiu antes de cada passo.

> **Custo:** zero overhead pipeline · custo Azure prod depende do Bicep — em prod real, APIM + Content Safety + App Insights podem chegar em R$ 600+/mês ligado · neste lab, provisione e delete no mesmo dia (ver Capítulo 10)

---

## Passo 5.4 — Configurar GitHub Environments (`staging` + `production`)

GitHub Environments isolam variáveis e protegem deploys (required reviewers, wait timers, deployment branch restrictions). O workflow `cd-prod.yml` referencia `environment: production` — sem o environment criado, **deploy bloqueia com erro `environment 'production' not found`**.

**No GitHub (Repository → Settings → Environments):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/environments`
2. **New environment** → name `staging` → **Configure environment**
3. Em `staging`, deixe tudo default (sem protection rules — staging é território de experimentação)

<!-- screenshot: cap05-passo5.4-environment-staging.png -->

4. Volte para `https://github.com/<seu-username>/helpsphere-ia/settings/environments` → **New environment** → name `production` → **Configure environment**
5. Em `production`, configure protection rules:
   - ☑ **Required reviewers** → adicione seu próprio user (em prod real, seria CTO ou líder técnico)
   - **Wait timer:** `0` minutos (ou `5` minutos se quiser pedagogicamente forçar reflexão antes do deploy)
   - **Deployment branches and tags** → `Selected branches and tags` → adicione rule `main` (somente)
6. **Save protection rules**

<!-- screenshot: cap05-passo5.4-environment-production-protections.png -->

> **Por que `Selected branches and tags = main`?** Bloqueia que alguém crie branch experimental e dispare `cd-prod.yml` apontando pra ela. Em prod real você restringe a `main` + tags `v*` (releases assinadas).

> **Nota pedagógica — você como reviewer de você mesmo:** num lab solo, isso é só formalismo. Mas o **pattern** importa: production-grade exige ≥1 par de olhos diferente do autor. Em squads reais, `Required reviewers` aponta para um time GitHub (`@org/sre`) e qualquer membro pode aprovar.

---

## Passo 5.5 — Configurar Environment Variables (não-sensíveis)

**No GitHub (Settings → Environments → staging):**

1. Settings → Environments → clique em `staging`
2. Seção **Environment variables** → **Add variable** — adicione 2 variables:
   - **Name:** `AOAI_ENDPOINT` · **Value:** `https://aifproj-helpsphere-rag.openai.azure.com/` (do Lab Inter; ou seu endpoint de teste se rodando standalone)
   - **Name:** `AGENT_FUNCTION_URL_STAGING` · **Value:** `https://func-helpsphere-agent-staging.azurewebsites.net` (placeholder por enquanto — você atualiza quando a Function existir)

<!-- screenshot: cap05-passo5.5-environment-variables-staging.png -->

3. Volte → clique em `production`
4. **Add variable:**
   - **Name:** `AOAI_ENDPOINT` · **Value:** mesmo endpoint do staging
   - **Name:** `AGENT_FUNCTION_URL_PROD` · **Value:** `https://func-helpsphere-agent-prod.azurewebsites.net` (placeholder)

> **Diferença canônica entre Variables e Secrets:**
>
> | | Variables | Secrets |
> |---|---|---|
> | Visível em logs | ✅ Sim | ❌ Não (mascarado como `***`) |
> | Use para | URLs, IDs, configs não-sensíveis | API keys, tokens, passwords, certs |
> | Acesso no YAML | `${{ vars.NAME }}` | `${{ secrets.NAME }}` |
>
> `AOAI_API_KEY` (Capítulo 03) é **secret**. URLs são **variables**. Erros comuns: usar variable pra key e expor em log público.

---

## Passo 5.6 — Disparar primeiro deploy (CD Staging automático)

Quando você commitou `cd-staging.yml` no Passo 5.2, o workflow já **disparou automaticamente** porque tem trigger `on: push: branches: [main]`. Vamos verificar.

**No GitHub Actions UI:**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/actions`
2. Aba **All workflows** → selecione **CD Staging**
3. Clique no run mais recente para ver detalhes
4. Acompanhe os 2 jobs em sequência:
   - `deploy-staging` (~30-45 min — APIM Developer provisiona lento, paciência) → ✅ Success
   - `eval-offline` (~2-3 min) → roda eval Python contra staging → ✅ Success

<!-- screenshot: cap05-passo5.6-cd-staging-running.png -->

> **Atenção timeout:** APIM Developer SKU provisiona em ~30-45 min. GitHub Actions tem default `timeout-minutes: 360` (6h) por job, então não dá timeout, mas se a sessão de gravação está apertada, **siga Capítulos 06+ em paralelo** enquanto o deploy roda.

> **Se o run falhar com `AuthorizationFailed`:** confirme que a Federated Credential do Capítulo 03 está correta — `subject` deve ser **exatamente** `repo:<seu-username>/helpsphere-ia:ref:refs/heads/main` (verifique typos no username GitHub).

---

## Passo 5.7 — Disparar CD Prod manualmente (workflow_dispatch + approval)

`cd-prod.yml` usa `on: workflow_dispatch` — só roda manualmente via UI ou API.

**No GitHub Actions UI:**

1. `https://github.com/<seu-username>/helpsphere-ia/actions` → aba lateral **CD Prod (Manual)**
2. Canto direito → botão **Run workflow** (com setinha pra baixo)
3. Preencher:
   - **Use workflow from:** `Branch: main`
   - **Type "deploy-prod" to confirm:** `deploy-prod` (exatamente — case-sensitive)
4. **Run workflow**

<!-- screenshot: cap05-passo5.7-run-workflow-cd-prod.png -->

5. O run inicia → job `validate` passa → job `deploy-prod` **PARA** aguardando approval (porque `production` environment tem required reviewer configurado no Passo 5.4)
6. No topo do run, banner amarelo **"Deployment review"** → clique **Review deployments** → marque ☑ `production` → **Approve and deploy**
7. Deploy continua, smoke test executa, ✅ Success

> **Alternativa via gh CLI (trigger workflow):**
>
> ```bash
> # Disparar workflow manualmente
> gh workflow run cd-prod.yml --ref main -f confirm=deploy-prod
>
> # Listar runs e descobrir ID do run pendente
> gh run list --workflow cd-prod.yml --limit 1
>
> # gh CLI não tem comando nativo pra approve — use UI ou API REST:
> # POST /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments
> gh api -X POST repos/<owner>/<repo>/actions/runs/<run_id>/pending_deployments \
>   -f environment_ids='[<env_id>]' \
>   -f state=approved \
>   -f comment='Approved via CLI'
> ```

---

## Validação end-to-end

```bash
# 1. Trigger CI manual via gh CLI
gh workflow run ci.yml --ref main

# 2. Watch progresso
gh run watch

# 3. Após PR merged em main, cd-staging.yml dispara automático
gh run list --workflow cd-staging.yml --limit 1

# 4. Para prod, manual via CLI
gh workflow run cd-prod.yml --ref main -f confirm=deploy-prod

# 5. Verificar APIM provisionado
az apim list -g rg-lab-avancado --query "[].{name:name, state:provisioningState, sku:sku.name}" -o table
# Esperado: name=apim-helpsphere-staging, state=Succeeded, sku=Developer
```

---

## Checklist final

```text
[ ] CI workflow passou em PR (lint-bicep + lint-python + bicep-what-if)
[ ] CD Staging deployou sem erro
[ ] CD Staging eval-offline passou (sem regressão > 5%)
[ ] CD Prod requer approval (testado clicando Approve)
[ ] APIM provisionado em rg-lab-avancado (state=Succeeded após ~30-45min)
[ ] Smoke test reportou HTTP code esperado (200/202/404 aceitáveis em APIM em init)
[ ] GitHub Environments staging + production criados
[ ] production tem required reviewer configurado
[ ] Federated credentials funcionaram (sem client secret no repo)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **APIM Developer provisiona em ~30-45 min** — não é erro, é o SKU. Se aparecer `Status: Activating` por mais de 1h, abra ticket Azure. Workaround: provisione e siga outros Capítulos em paralelo.
- ⚠️ **`AuthorizationFailed` no primeiro CD Staging** — quase sempre é typo no username GitHub na federated credential `subject`. Confira `repo:<EXATO-username-case-sensitive>/helpsphere-ia:ref:refs/heads/main`.
- ⚠️ **`Bicep what-if` em PR sem federated credential `pull_request`** — se você só criou a credential `main` (sem a `pull_request`), o job falha com `AADSTS70021: No matching federated identity record found`. Volte ao Capítulo 03 e crie a 2ª credential.
- ⚠️ **`environment 'production' not found`** — você esqueceu de criar o GitHub Environment no Passo 5.4. Crie e re-run.
- ⚠️ **Variable vs Secret confusão** — `AOAI_API_KEY` definido como variable em vez de secret vaza no log. Sempre que dúvida: dado sensível = secret, sempre.

---

## Próximo capítulo

[06 — APIM gateway + policies](./06-apim-gateway-policies.md)
