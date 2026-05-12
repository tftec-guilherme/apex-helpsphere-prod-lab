# Capítulo 04b — Bicep parameters & lint local

> **Objetivo:** criar parameter files por env (`dev`, `staging`, `prod`) **no mesmo RG `rg-lab-avancado`** (parâmetro `envName` diferencia nomes dos recursos), validar todos os 5 templates Bicep do capítulo anterior com `az bicep build`, executar lint local com `--diagnostics-level error`, rodar `az deployment group what-if` para preview do deploy, e fazer o primeiro commit consolidado de toda a infra.
>
> **Tempo:** 30-45 min (depende da velocidade de iteração com erros de lint)

---

## Pré-requisitos

- ✅ Capítulo anterior concluído — 5 arquivos `.bicep` criados em `infra/main.bicep` + `infra/modules/{apim,content-safety,app-insights,policy}.bicep`
- ✅ Azure CLI logado (`az login`) — usado em `az bicep build` e `az deployment group what-if`
- ✅ `az bicep version` retorna ≥ 0.20.x. Se desatualizado, rode `az bicep upgrade`
- ✅ Repo local com branch sincronizada com `main` (`git pull origin main`)
- ✅ RG `rg-lab-avancado` existe — necessário para `what-if` rodar (mesmo RG para os 3 envs dev/staging/prod)
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first

> **Atenção gotcha:** `az bicep build` valida sintaxe + lint, mas **NÃO valida** se o `workspaceId` do App Insights aponta pra Log Analytics que existe. `what-if` (Passo 2.7) **detecta**. Por isso essa etapa é obrigatória antes do deploy real.

> **Estratégia "3 envs no MESMO RG":** os 3 parameter files (`dev`, `staging`, `prod`) apontam para o mesmo `rg-lab-avancado`. O parâmetro `envName` diferencia os **nomes dos recursos** (ex.: `apim-helpsphere-dev` vs `apim-helpsphere-staging`), não o RG. Isso simplifica cleanup (1 `az group delete`). Em prod real você usaria 3 RGs separados — para o lab, isolar por nome é suficiente.

---

## Resumo dos 4 passos que vamos cravar

| Passo | Ação | Comando-chave | Output esperado |
|---|---|---|---|
| 2.6 | Parameter files por env | `infra/envs/{dev,staging,prod}.parameters.json` | 3 arquivos JSON, schema válido |
| 2.7a | Bicep build (lint) | `az bicep build --file infra/main.bicep` | `infra/main.json` gerado, zero erros |
| 2.7b | What-if (preview) | `az deployment group what-if --resource-group rg-lab-avancado` | Lista de recursos `+ Create` |
| 2.8 | Commit | `git add infra/ && git commit -m ...` | Commit local pronto, push fica para o próximo capítulo |

> **Nota pedagógica — por que parameter files JSON e não Bicep parameters (`.bicepparam`)?** `.bicepparam` é mais novo, mais ergonômico, mas **não suporta `securestring` em todos os providers ainda**. Usamos JSON neste lab porque é o formato canônico que pipelines Bicep entendem sem flags adicionais. Em prod real, considere migrar para `.bicepparam` quando seu pipeline já estabilizou.

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

> **Custo:** parameter files são apenas JSON local — **R$ 0**. Eles definem os valores que o template usa quando deploy roda no próximo capítulo.

> **Nota pedagógica — por que `apimSku: Developer` em prod neste lab?** Porque APIM Premium custa R$ 11.000+/mês — proibitivo para gravação. Em prod real, você usa Standard (R$ 1.500/mês) ou Premium. O lab demonstra o **pattern de parametrização** (env determina SKU), não o tier definitivo. O `main.bicep` pode ter default `(env == 'prod') ? 'Standard' : 'Developer'` — sobrescrevemos aqui via parameter file para custo controlado durante demo.

> **Atenção schema URL exato:** o `$schema` precisa ser **exatamente** `https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#` (com o `#` no final). URL errada ou versão divergente quebra `az deployment group what-if` com erro críptico do tipo `InvalidTemplate: The provided value for the template parameter is not valid`. Use a versão `2019-04-01` (canônica para parameter files).

> **Atenção placeholders e segredos:** se algum parameter file precisar de valor sensível (ex.: connection string, API key), **NUNCA** cole o segredo literal no JSON — você comita em git. Use referência a Key Vault: `"value": { "reference": { "keyVault": { "id": "/subscriptions/.../vaults/<kv>" }, "secretName": "<nome>" } }`. Os parameter files deste lab **não têm segredos** (só `env`/`sku` literais), mas vale o pattern para produção.

---

## Passo 2.7a — Validar Bicep com `az bicep build` (lint)

**No terminal local (PowerShell, Bash ou WSL):**

`az bicep build` faz duas coisas:
1. **Compila** o `.bicep` em ARM JSON (fonte real que o ARM aceita)
2. **Lint local** que detecta erros de sintaxe + warnings de best practice

```powershell
# Build do main.bicep (entry point) → gera infra/main.json
az bicep build --file infra/main.bicep

# Build dos 4 modules (cada um gera seu .json)
az bicep build --file infra/modules/apim.bicep
az bicep build --file infra/modules/content-safety.bicep
az bicep build --file infra/modules/app-insights.bicep
az bicep build --file infra/modules/policy.bicep
```

> **Linux/Mac/WSL:** comandos `az` são idênticos — apenas o shell muda quando há variáveis/pipes/redirects.

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
> ```powershell
> # Roda só o lint, sem produzir arquivos .json (~3x mais rápido)
> az bicep build --file infra/main.bicep --stdout | Out-Null
> ```
>
> > **Linux/Mac/WSL:** troque `| Out-Null` por `> /dev/null`.

> **Custo:** **R$ 0** — `az bicep build` roda 100% localmente, não chama Azure ARM API.

> **Nota pedagógica — `--diagnostics-level error` filtra só erros (ignora warnings):**
>
> ```powershell
> # Filtrar só erros (suprimir warnings) — útil quando warnings ainda não foram corrigidos
> az bicep build --file infra/main.bicep --diagnostics-level error
> ```
>
> > **Linux/Mac/WSL:** comando idêntico — sem variáveis nem redirects.
>
> Quando você roda em pipeline, quer **failar só em erros**, não em warnings (que podem ser secure-by-default mas não bloqueantes). O flag `--diagnostics-level error` é o pattern canônico de lint-bicep.

> **Nota pedagógica — `az bicep build` vs `az deployment group validate`:** ambos checam sintaxe + parâmetros, mas há diferença:
>
> - **`az bicep build`** roda 100% local, gera o ARM JSON e detecta erros de Bicep DSL — não precisa de Azure conectado.
> - **`az deployment group validate`** envia o template para o ARM API e checa se os parâmetros batem com schemas dos resource providers (ex.: SKU realmente existe?). Mas **não simula** se o deploy daria conflito com o estado atual do RG.
> - **`az deployment group what-if`** (próximo passo) faz tudo do `validate` + **simula o resultado contra o estado real do RG** (compara template declarado vs recursos existentes).
>
> Pattern recomendado: `build` (offline) → `what-if` (com estado). Pule `validate` — `what-if` é estritamente superior.

> **Nota pedagógica — por que builda os modules separadamente se main.bicep já compila tudo?** Porque module reference em Bicep é **transparente** durante build — `az bicep build infra/main.bicep` compila tudo recursivamente. Mas se um module falha isoladamente (ex.: typo só em `policy.bicep`), você quer descobrir antes de tentar o main. Pattern em pipeline: 5 jobs paralelos, um por arquivo.

---

## Passo 2.7b — What-if (preview do deploy) nos 3 envs

What-if mostra **o que o deployment criaria/modificaria** sem realmente provisionar. Ferramenta canônica para revisão pré-deploy. Rode para os 3 envs no mesmo RG `rg-lab-avancado` — cada parameter file vai gerar nomes diferentes via `envName`.

```powershell
# What-if no escopo do RG (main.bicep) — ambiente DEV
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/dev.parameters.json'

# What-if STAGING (mesmo RG, recursos com sufixo -staging)
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/staging.parameters.json'

# What-if PROD (mesmo RG, recursos com sufixo -prod)
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/prod.parameters.json'
```

> **Linux/Mac/WSL (bash):** troque `` ` `` por `\` e remova as aspas simples do `@infra/envs/...json`.

> **Atenção PowerShell — aspas simples no `@`:** sem as aspas, PS interpreta `@` como splatting operator. SEMPRE use `'@infra/envs/<env>.parameters.json'` (aspas simples) em PowerShell. Bash não precisa.

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
> ```powershell
> # What-if no scope = subscription (note: deployment SUB, não deployment GROUP)
> az deployment sub what-if `
>   --location eastus2 `
>   --template-file infra/modules/policy.bicep `
>   --parameters targetRgName=rg-lab-avancado
> ```
>
> > **Linux/Mac/WSL:** troque `` ` `` por `\`.
>
> Saída esperada: recursos `+ Create` para policy definitions + policy assignments (roleAssignments dedupados via `guid()` podem ser idempotentes).

> **Custo:** `what-if` = **R$ 0**. ARM API call read-only, não provisiona nada.

> **Nota pedagógica — por que what-if antes de deploy?** Porque deploy real falha em **runtime** (depois de 5-10 minutos provisionando) se você tiver typo no template. What-if falha em **~10 segundos** com o mesmo erro detectado. Pattern: **what-if é seu lint final antes do deploy**.

> **Nota pedagógica — símbolos do what-if (`+ Create`, `~ Modify`, `= No change`, `- Delete`, `~ Ignore`):** o `what-if` usa 5 símbolos. Atenção especial ao `~ Ignore` — significa que o recurso **existe no RG mas o template não declara** (foi criado externamente, ex.: Portal). Isso é **drift silencioso** — o template não vai apagar, mas você nunca mais consegue versionar esse recurso. Workaround: ou importa pro Bicep, ou deleta no Portal. Use `--result-format ResourceIdOnly` para output mais limpo em pipeline.

---

## Passo 2.8 — Commit consolidado da infra

Agora que tudo passa lint + what-if, é hora de commitar **todos** os 8 arquivos de uma vez (5 .bicep + 3 .json). Atomic commit: `infra/` chega no repo já validado.

```powershell
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

> **Linux/Mac/WSL:** comandos `git` são idênticos — funciona igual em qualquer shell.

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

> **Custo:** **R$ 0** — git commit local, nada vai pra Azure ainda.

> **Nota pedagógica — por que commit local sem push agora?** Porque o push consolidado vai junto com os próximos artefatos da infra (deploy real no próximo capítulo). Pattern: **commits atômicos + push consolidado** quando você tem múltiplos artefatos relacionados. Mantém o histórico limpo e te dá chance de rebase local antes do push.

> **Nota pedagógica — mensagem de commit descritiva (Conventional Commits):** `feat:` indica nova funcionalidade (vs `fix:`, `chore:`, `docs:`). O escopo (`Bicep templates parametrizados...`) é específico o suficiente pra alguém entender em 6 meses. **Anti-pattern:** `fix bug` ou `update files` (sem contexto). Use `git log --oneline` regularmente — ele te força a escrever mensagens que façam sentido isolado.

---

## Validação end-to-end (visual)

```powershell
# 1. Confirmar 5 arquivos .bicep válidos (zero erros em todos)
$BicepFiles = @('infra/main.bicep') + (Get-ChildItem infra/modules/*.bicep | ForEach-Object { $_.FullName })
foreach ($f in $BicepFiles) {
  Write-Host "=== Validating: $f ==="
  az bicep build --file $f --diagnostics-level error
}
# Esperado: zero saída de erro em todos os 5; retorno code 0

# 2. Confirmar 3 parameter files válidos JSON
foreach ($f in Get-ChildItem infra/envs/*.parameters.json) {
  Write-Host "=== Validating: $($f.Name) ==="
  try { Get-Content $f.FullName -Raw | ConvertFrom-Json | Out-Null; Write-Host "OK" }
  catch { Write-Host "FALHOU: $_" }
}
# Esperado: "OK" 3 vezes (dev, staging, prod)

# 3. What-if listando os 3 envs no mesmo RG — confirma envName diferenciando nomes
foreach ($env in @('dev','staging','prod')) {
  Write-Host "=== what-if env=$env ==="
  az deployment group what-if `
    --resource-group rg-lab-avancado `
    --template-file infra/main.bicep `
    --parameters "@infra/envs/$env.parameters.json" `
    --result-format ResourceIdOnly
}
# Esperado para CADA env: 3 IDs novos com sufixo do env
#   .../apim-helpsphere-<env>
#   .../cs-helpsphere-<env>
#   .../ai-helpsphere-<env>
# Nenhum "- Delete" e nenhum "! Error" em nenhum dos 3.

# 4. Confirmar git commit local pronto
git log --oneline -1
# Esperado: <hash> feat: Bicep templates parametrizados para 3 envs (dev/staging/prod)

git status
# Esperado: nothing to commit, working tree clean
```

<!-- screenshot: cap04b-validacao-end-to-end-3-envs-resource-ids.png -->

**O que você confirma visualmente:**

- ✅ `az bicep build` rodou em 5 arquivos `.bicep` com **zero erros** no stdout
- ✅ 3 parameter files retornam `OK` no parse JSON
- ✅ `what-if` para os 3 envs lista resources com sufixo correto (`-dev`, `-staging`, `-prod`) — confirma que `envName` está diferenciando nomes no MESMO RG
- ✅ `git log` mostra o commit `feat: Bicep templates parametrizados...` no HEAD local

> **Linux/Mac/WSL:** troque `foreach ($f in ...)` por `for f in ...; do ... done`, `Write-Host` por `echo`, `ConvertFrom-Json` por `python -m json.tool "$f" > /dev/null`, `` ` `` por `\`, e remova aspas simples do `@infra/envs/...json`.

> **Custo total da validação:** **R$ 0** — `bicep build` é offline, `what-if` é read-only no Resource Manager, `git` é local.

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

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`$schema` errado quebra `what-if` com erro críptico** — se você copiar `$schema` de outro template (ex.: `2015-01-01`) ou esquecer o `#` no final da URL, `az deployment group what-if` falha com `InvalidTemplate: The provided value for the template parameter is not valid` sem dizer **qual** parâmetro. Workaround: a URL canônica para parameter files (vigente em 2026) é `https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#` — copie literalmente.
- ⚠️ **Typo silencioso em parameter file: `paramaters` vira default value** — se você escrever `"paramaters": { ... }` (typo) em vez de `"parameters": { ... }`, o ARM **ignora silenciosamente** e usa os defaults do `main.bicep`. Não dá erro. Workaround: declare params como `param <nome> string` (sem default) no main.bicep para forçar erro de parameter faltante, ou abra o JSON em VS Code com schema URL correto — autocomplete pega o typo.
- ⚠️ **Segredo literal em parameter file vaza no git** — quem coloca `"apiKey": { "value": "sk-abc123..." }` no JSON e dá commit, o segredo vai pro histórico **para sempre**, mesmo após `git rm`. Workaround: use Key Vault reference: `"value": { "reference": { "keyVault": { "id": "/subscriptions/.../vaults/<kv>" }, "secretName": "<nome>" } }`. Os parameter files deste lab não têm segredos, mas grave o pattern.
- ⚠️ **`what-if` mostra `~ Ignore` em recurso que você criou no Portal** — drift silencioso: o recurso existe no RG mas o template não declara, então `what-if` marca `~ Ignore` (não vai deletar mas nunca mais consegue versionar). Workaround: ou importa pro Bicep com `az bicep decompile`, ou deleta no Portal antes de continuar.
- ⚠️ **`az deployment group validate` passou mas `what-if` falhou** — `validate` checa só sintaxe + schema dos providers. `what-if` simula contra o **estado atual do RG** (policy, conflitos de nome, recursos existentes). Workaround: sempre rode `what-if`, nunca confie só em `validate`.
- ⚠️ **`Error BCP037: The property "ConnectionString" is read-only`** — você tentou setar `ConnectionString` como parameter em `app-insights.bicep`. Connection String é **output** (gerado pelo Azure após criar o resource), não input. Workaround: declare como `output`, não como `param`.
- ⚠️ **What-if mostra `+ Create` em recurso que você jura que já existe** — você está apontando pra outro RG por engano. `--resource-group` no what-if precisa ser **exatamente** o `rg-lab-avancado`. Workaround: `az group show -n rg-lab-avancado` confirma RG existe; `az resource list -g rg-lab-avancado -o table` lista o que está lá.
- ⚠️ **`az bicep build` falha com `BCP054: Module path was not found`** — você esqueceu de criar `infra/modules/` ou typo no path do módulo (`'modules/apim.bicep'` vs `'./modules/apim.bicep'`). Workaround: paths em Bicep são **relativos ao arquivo que importa**, não ao CWD. Use `'modules/apim.bicep'` em `main.bicep` (sem `./`).
- ⚠️ **What-if retorna `Forbidden 403` em conta `live.com` VSE** — ABAC condition negando read no RG. Workaround: rode `az role assignment list --assignee <seu-user> -g rg-lab-avancado` para confirmar que você tem `Reader` ou `Contributor`. Se não tem, ABAC bloqueou — peça ao admin da sub.
- ⚠️ **JSON parameter file com BOM (UTF-8 BOM byte order mark)** — VS Code no Windows às vezes salva com BOM, e Bicep parser falha com `JsonParseError: BOM detected`. Workaround: VS Code → menu inferior direito → `UTF-8 with BOM` → mude pra `UTF-8` (sem BOM) → salve.
- ⚠️ **`apimSku: 'Developer'` no prod.parameters mas template tem default `Standard`** — o parameter file **sobrescreve** o default do template. Não é bug, é design — mas confunde no primeiro contato. Workaround: leia `main.bicep` linha do default + parameter file lado-a-lado para entender o valor final que ARM vai usar.

---

## Próximo capítulo

[05 — Aplicar infra com Azure CLI](./05-github-actions-pipelines.md)
