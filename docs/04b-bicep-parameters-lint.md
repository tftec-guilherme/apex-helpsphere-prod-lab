# Capítulo 04b — Bicep parameters & lint local

> **Objetivo:** criar parameter files por env (`dev`, `staging`, `prod`), validar todos os 5 templates Bicep do Capítulo 04a com `az bicep build`, executar lint local com `--diagnostics-level error`, rodar `az deployment what-if` para preview do deploy, e fazer o primeiro commit consolidado de toda a infra.
>
> **Tempo:** 30-45 min (depende da velocidade de iteração com erros de lint)
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` outline) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Parte 2 (Passos 2.6-2.8)

---

## Pré-requisitos

- ✅ Capítulo 04a concluído — 5 arquivos `.bicep` criados em `infra/main.bicep` + `infra/modules/{apim,content-safety,app-insights,policy}.bicep`
- ✅ Azure CLI logado (`az login`) — usado em `az bicep build` e `az deployment what-if`
- ✅ `az bicep version` retorna ≥ 0.20.x (versão atual em maio/2026: 0.36.x). Se desatualizado, rode `az bicep upgrade`
- ✅ Repo `helpsphere-ia` com branch local sincronizada com `main` (`git pull origin main`)
- ✅ RG `rg-lab-avancado` existe (do Capítulo 02) — necessário para `what-if` rodar

> **Atenção gotcha:** `az bicep build` valida sintaxe + lint, mas **NÃO valida** se o `workspaceId` do App Insights aponta pra Log Analytics que existe. `what-if` (Passo 2.7) **detecta**. Por isso essa etapa é obrigatória antes de deploy real (Capítulo 05).

---

## Resumo dos 4 passos que vamos cravar

| Passo | Ação | Comando-chave | Output esperado |
|---|---|---|---|
| 2.6 | Parameter files por env | `infra/envs/{dev,staging,prod}.parameters.json` | 3 arquivos JSON, schema válido |
| 2.7a | Bicep build (lint) | `az bicep build --file infra/main.bicep` | `infra/main.json` gerado, zero erros |
| 2.7b | What-if (preview) | `az deployment group what-if --resource-group rg-lab-avancado` | Lista de recursos `+ Create` |
| 2.8 | Commit | `git add infra/ && git commit -m ...` | Commit local pronto pra push (push fica para Capítulo 05) |

> **Nota pedagógica — por que parameter files JSON e não Bicep parameters (`.bicepparam`)?** `.bicepparam` é mais novo (preview até GA em 2024), mais ergonômico, mas **não suporta `securestring` em todos os providers ainda**. Usamos JSON neste lab porque é o formato canônico que GitHub Actions Bicep extension entende sem flags adicionais. Em prod real (2026+), considere migrar para `.bicepparam` quando seu pipeline já estabilizou.

---

## Passo 2.6 — Criar parameter files por env

**No VS Code:**

Crie 3 arquivos dentro de `infra/envs/`:

### `infra/envs/dev.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "env": { "value": "dev" },
    "apimSku": { "value": "Developer" },
    "contentSafetySku": { "value": "F0" }
  }
}
```

### `infra/envs/staging.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "env": { "value": "staging" },
    "apimSku": { "value": "Developer" },
    "contentSafetySku": { "value": "F0" }
  }
}
```

### `infra/envs/prod.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "env": { "value": "prod" },
    "apimSku": { "value": "Developer" },
    "contentSafetySku": { "value": "S0" }
  }
}
```

<!-- screenshot: cap04b-passo2.6-vscode-parameter-files-3-envs.png -->

> **Em produção real:** APIM Standard ou Premium (R$ 1.500/mês a R$ 11.000+/mês), Content Safety S0 (R$ 0,75/1.000 req). Para o lab, mantemos Developer/F0 em todos exceto `prod.contentSafetySku=S0` para você ver a diferença em policy/cost report depois.

> **Custo:** parameter files são apenas JSON local — custo zero. Eles definem os valores que o template usa quando deploy roda (Capítulo 05).

> **Nota pedagógica — por que `apimSku: Developer` em prod neste lab?** Porque APIM Premium custa R$ 11.000+/mês — proibitivo para gravação. Em prod real, você usa Standard (R$ 1.500/mês) ou Premium. O lab demonstra o **pattern de parametrização** (env determina SKU), não o tier definitivo. O `main.bicep` tem default `(env == 'prod') ? 'Standard' : 'Developer'` — sobrescrevemos aqui via parameter file para custo controlado durante demo.

> **Nota pedagógica — `$schema` correto importa?** Sim. Se você usar URL inválida, VS Code não dá highlight/autocomplete e algumas validações de Azure CLI falham. Use sempre `https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#` (versão `2019-04-01` ainda é a vigente para parameter files em 2026).

---

## Passo 2.7a — Validar Bicep com `az bicep build` (lint)

**No terminal local (PowerShell, Bash ou WSL):**

`az bicep build` faz duas coisas:
1. **Compila** o `.bicep` em ARM JSON (fonte real que o ARM aceita)
2. **Lint local** que detecta erros de sintaxe + warnings de best practice

```bash
# Build do main.bicep (entry point) → gera infra/main.json
az bicep build --file infra/main.bicep

# Build dos 4 modules (cada um gera seu .json)
az bicep build --file infra/modules/apim.bicep
az bicep build --file infra/modules/content-safety.bicep
az bicep build --file infra/modules/app-insights.bicep
az bicep build --file infra/modules/policy.bicep
```

**Saída esperada (sucesso):**
- Sem mensagens em stdout/stderr → tudo OK
- Arquivos `.json` gerados ao lado dos `.bicep` (mesmo nome, extensão diferente)

**Saída se erro (exemplo):**
```text
infra/modules/policy.bicep(45,7) : Error BCP118: Expected the "@" character at this location.
```

<!-- screenshot: cap04b-passo2.7a-terminal-az-bicep-build-success.png -->

> **Alternativa — só lint sem gerar JSON (mais rápido):**
>
> ```bash
> # Roda só o lint, sem produzir arquivos .json (~3x mais rápido)
> az bicep build --file infra/main.bicep --stdout > /dev/null
> ```

> **Custo:** zero — `az bicep build` roda 100% localmente, não chama Azure ARM API.

> **Nota pedagógica — `--diagnostics-level error` filtra só erros (ignora warnings):**
>
> ```bash
> # Filtrar só erros (suprimir warnings) — útil em CI quando warnings ainda não foram corrigidos
> az bicep build --file infra/main.bicep --diagnostics-level error
> ```
>
> Em CI (Capítulo 05), você quer **failar só em erros**, não em warnings (que podem ser secure-by-default mas não bloqueantes). O flag `--diagnostics-level error` é o que usamos no `lint-bicep` job do `ci.yml`.

> **Nota pedagógica — por que builda os modules separadamente se main.bicep já compila tudo?** Porque module reference em Bicep é **transparente** durante build — `az bicep build infra/main.bicep` compila tudo recursivamente. Mas se um module falha isoladamente (ex.: typo só em `policy.bicep`), você quer descobrir antes de tentar o main. Pattern em CI: 5 jobs paralelos, um por arquivo (vide `ci.yml` cap 05 — exatamente esse pattern).

---

## Passo 2.7b — What-if (preview do deploy)

What-if mostra **o que o deployment criaria/modificaria** sem realmente provisionar. Ferramenta canônica para revisão pré-deploy.

```bash
# What-if no escopo do RG (main.bicep) — ambiente DEV
az deployment group what-if \
  --resource-group rg-lab-avancado \
  --template-file infra/main.bicep \
  --parameters infra/envs/dev.parameters.json
```

**Saída esperada (formato resumido):**

```text
Resource and property changes are indicated with these symbols:
  + Create
  ~ Modify

The deployment will update the following scope:

Scope: /subscriptions/.../resourceGroups/rg-lab-avancado

  + Microsoft.ApiManagement/service/apim-helpsphere-dev [2023-09-01-preview]

      apiVersion: "2023-09-01-preview"
      identity.type: "SystemAssigned"
      location: "eastus2"
      name: "apim-helpsphere-dev"
      sku.capacity: 1
      sku.name: "Developer"
      tags.application: "helpsphere-ia"
      tags.cost-center: "apex-helpsphere-ia"
      tags.environment: "dev"

  + Microsoft.CognitiveServices/accounts/cs-helpsphere-dev [2024-04-01-preview]
  + Microsoft.Insights/components/ai-helpsphere-dev [2020-02-02]

Resource changes: 3 to create.
```

<!-- screenshot: cap04b-passo2.7b-terminal-what-if-3-create.png -->

> **Alternativa — what-if do `policy.bicep` (subscription scope):**
>
> ```bash
> # Capture o object ID do SP do GitHub Actions
> SP_OBJECT_ID=$(az ad sp show \
>   --id $(az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv) \
>   --query id -o tsv)
>
> # What-if no scope = subscription (note: deployment SUB, não deployment GROUP)
> az deployment sub what-if \
>   --location eastus2 \
>   --template-file infra/modules/policy.bicep \
>   --parameters githubActionsSpObjectId=$SP_OBJECT_ID targetRgName=rg-lab-avancado
> ```
>
> Saída esperada: 5 recursos `+ Create` (2 role assignments + 3 policy definitions + 3 policy assignments = 8 totais; mas roleAssignments dedupados via `guid()` podem ser idempotentes).

> **Custo:** what-if = **zero**. ARM API call read-only, não provisiona nada.

> **Nota pedagógica — por que what-if antes de deploy?** Porque deploy real falha em **runtime** (depois de 5-10 minutos provisionando) se você tiver typo no template. What-if falha em **~10 segundos** com o mesmo erro detectado. Pattern: **what-if é seu CI local antes do CI remoto**.

> **Nota pedagógica — what-if pode mostrar `~ Modify` em deploy idempotente:** se você rodou what-if depois de já ter deploy ado uma vez, recursos existentes aparecem como `~ Modify` (mesmo sem mudança real) ou `= No change`. Isso é normal — ARM compara estado declarado vs estado atual e reporta diff. Use `--result-format ResourceIdOnly` para output mais limpo em CI.

---

## Passo 2.8 — Commit consolidado da infra

Agora que tudo passa lint + what-if, é hora de commitar **todos** os 8 arquivos de uma vez (5 .bicep + 3 .json). Atomic commit: `infra/` chega no repo já validado.

```bash
# Confirmar diff
git status
git diff --stat

# Esperado:
# infra/main.bicep                    | XX +
# infra/modules/apim.bicep            | XX +
# infra/modules/content-safety.bicep  | XX +
# infra/modules/app-insights.bicep    | XX +
# infra/modules/policy.bicep          | XX +
# infra/envs/dev.parameters.json      | XX +
# infra/envs/staging.parameters.json  | XX +
# infra/envs/prod.parameters.json     | XX +

# Stage tudo de infra/ (mas NÃO os .json compilados pelo bicep build)
git add infra/main.bicep infra/modules/ infra/envs/

# OU se quiser também os .json compilados (não obrigatório — gerados em CI):
# git add infra/

# Commit atômico com mensagem descritiva
git commit -m "feat: Bicep templates parametrizados para 3 envs (dev/staging/prod)"
```

<!-- screenshot: cap04b-passo2.8-terminal-git-commit-infra.png -->

> **Atenção `.gitignore`:** se você deixou os `.json` compilados (`infra/*.json`, `infra/modules/*.json`) sem adicionar a `.gitignore`, eles vão pro repo. **Pattern recomendado:** crie `.gitignore` com:
>
> ```text
> # Bicep compiled artifacts (regenerated em CI)
> infra/main.json
> infra/modules/*.json
> ```
>
> Em prod real, alguns squads versionam os JSON compilados (ARM template auditável), outros não. **Sem regra única** — escolha uma policy e mantenha consistência.

> **Custo:** zero — git commit local, nada vai pra Azure ainda.

> **Nota pedagógica — por que commit local sem push agora?** Porque **`git push` é exclusivo do `@devops` agent** na nossa disciplina (vide `agent-authority.md`). Mas além disso: o push automático dispararia o workflow `cd-staging.yml` (Capítulo 05), que ainda **não foi criado** — então push agora seria no-op, mas commit é seguro porque está pronto pra subir junto com os workflows na próxima Parte. Pattern: **commits atomicos + push consolidado** quando você tem múltiplos artefatos relacionados.

> **Nota pedagógica — mensagem de commit descritiva (Conventional Commits):** `feat:` indica nova funcionalidade (vs `fix:`, `chore:`, `docs:`). O escopo (`Bicep templates parametrizados...`) é específico o suficiente pra alguém entender em 6 meses. **Anti-pattern:** `fix bug` ou `update files` (sem contexto). Use `git log --oneline` regularmente — ele te força a escrever mensagens que façam sentido isolado.

---

## Validação end-to-end

```bash
# 1. Confirmar 5 arquivos .bicep válidos
for f in infra/main.bicep infra/modules/*.bicep; do
  echo "=== Validating: $f ==="
  az bicep build --file "$f" --diagnostics-level error
done
# Esperado: zero erros, retorno code 0 em todos

# 2. Confirmar 3 parameter files válidos JSON
for f in infra/envs/*.parameters.json; do
  echo "=== Validating: $f ==="
  python -m json.tool "$f" > /dev/null && echo "OK"
done
# Esperado: "OK" 3 vezes

# 3. What-if final (DEV) — deve listar 3 recursos a criar
az deployment group what-if \
  --resource-group rg-lab-avancado \
  --template-file infra/main.bicep \
  --parameters infra/envs/dev.parameters.json \
  --result-format ResourceIdOnly
# Esperado: 3 IDs novos (APIM, Content Safety, App Insights)

# 4. Confirmar git commit local pronto
git log --oneline -1
# Esperado: <hash> feat: Bicep templates parametrizados para 3 envs (dev/staging/prod)

git status
# Esperado: nothing to commit, working tree clean
```

---

## Checklist final

```text
[ ] infra/envs/dev.parameters.json criado com env=dev, apimSku=Developer, csSku=F0
[ ] infra/envs/staging.parameters.json criado com env=staging, apimSku=Developer, csSku=F0
[ ] infra/envs/prod.parameters.json criado com env=prod, apimSku=Developer, csSku=S0
[ ] az bicep build infra/main.bicep retorna sem erros (apenas warnings opcionais)
[ ] az bicep build em cada um dos 4 modules retorna sem erros
[ ] az deployment group what-if mostra recursos `+ Create` esperados
[ ] az deployment sub what-if no policy.bicep mostra role assignments + policy defs/assigns
[ ] .gitignore atualizado se você decidiu NÃO versionar .json compilados
[ ] git commit local feito com mensagem Conventional Commits
[ ] git status retorna "working tree clean"
```

> **Próximo:** Capítulo 05 cria os 3 workflows GitHub Actions (CI + CD Staging + CD Prod) que vão **deployar** esses Bicep templates. Push consolidado acontece lá.

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`Error BCP037: The property "ConnectionString" is read-only`** — você tentou setar `ConnectionString` como parameter em `app-insights.bicep`. Connection String é **output** (gerado pelo Azure após criar o resource), não input. Workaround: declare como `output`, não como `param`.
- ⚠️ **What-if mostra `+ Create` em recurso que você jura que já existe** — você está apontando pra outro RG por engano. `--resource-group` no what-if precisa ser **exatamente** o `rg-lab-avancado`. Workaround: `az group show -n rg-lab-avancado` confirma RG existe; `az resource list -g rg-lab-avancado -o table` lista o que está lá.
- ⚠️ **`az bicep build` falha com `BCP054: Module path was not found`** — você esqueceu de criar `infra/modules/` ou typo no path do módulo (`'modules/apim.bicep'` vs `'./modules/apim.bicep'`). Workaround: paths em Bicep são **relativos ao arquivo que importa**, não ao CWD. Use `'modules/apim.bicep'` em `main.bicep` (sem `./`).
- ⚠️ **What-if retorna `Forbidden 403` em conta `live.com` VSE** — ABAC condition negando read no RG. Workaround: rode `az role assignment list --assignee <seu-user> -g rg-lab-avancado` para confirmar que você tem `Reader` ou `Contributor`. Se não tem, ABAC bloqueou. Veja Capítulo 03 R6 disclaimer.
- ⚠️ **JSON parameter file com BOM (UTF-8 BOM byte order mark)** — VS Code no Windows às vezes salva com BOM, e Bicep parser falha com `JsonParseError: BOM detected`. Workaround: VS Code → menu inferior direito → `UTF-8 with BOM` → mude pra `UTF-8` (sem BOM) → salve.
- ⚠️ **`apimSku: 'Developer'` no prod.parameters mas template tem default `Standard`** — o parameter file **sobrescreve** o default do template. Não é bug, é design — mas confunde no primeiro contato. Workaround: leia `main.bicep` linha do default + parameter file lado-a-lado para entender o valor final que ARM vai usar.

---

## Próximo capítulo

[05 — GitHub Actions pipelines](./05-github-actions-pipelines.md)
