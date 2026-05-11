# Capítulo 05 — Aplicar infra com Azure CLI

> **Objetivo:** aplicar o Bicep validado no Capítulo 04 para deployar a stack production-grade nos 3 ambientes (`dev`, `staging`, `prod`) usando `az deployment group create` — Portal+CLI manual, sem CI/CD automatizado.
>
> **Tempo:** 30-45 min (não inclui ~30-45 min de provisão APIM em background — você inicia, abre outro terminal e segue Capítulos 06+ enquanto roda)
>
> **Status:** `v0.3.0-cli-manual` ⚠️ REESCRITO — versão `v0.2.0-piloto` cobria GitHub Actions com 3 workflows + Federated SP, escopo removido nesta versão para reduzir superfície de falha (ABAC, OIDC trust, environments). Esta versão é **100% Portal+CLI manual**.

---

## Nota — CI/CD via GitHub Actions é capítulo futuro

Versões anteriores deste Capítulo cravavam **3 workflows GitHub Actions** (`ci.yml` + `cd-staging.yml` + `cd-prod.yml`) com OIDC Federated Service Principal + 2 GitHub Environments + approval gate manual em prod. Essa abordagem **fica fora do escopo desta versão** por 3 motivos:

1. **Superfície de falha grande** — federated SP exige sub sem ABAC (R6); subs `live.com` VSE pessoais bloqueiam role assignment.
2. **Acoplamento com GitHub** — aluno precisa de scope `workflow` + `delete_repo` no `gh` CLI, branch protection cravada antes, environments configurados.
3. **Foco pedagógico** — esta versão prioriza **dominar Bicep + Azure CLI primeiro**. CI/CD vira capítulo dedicado em release futura (production-grade canônico **assumindo** que aluno já entendeu o Bicep).

Aluno que terminar este Lab Avançado e quiser CI/CD: estude OIDC Federated SP, `azure/login@v2`, GitHub Environments com `required reviewers`. Pattern não muda — só onde o `az deployment group create` é chamado (runner ubuntu em vez de máquina local).

---

## Pré-requisitos

- ✅ Capítulo 02 concluído — RG `rg-lab-avancado` existe em East US 2 com 4 tags FinOps aplicadas
- ✅ Capítulo 04a concluído — Bicep modules em `infra/main.bicep` + `infra/modules/{apim,content-safety,app-insights,policy}.bicep`
- ✅ Capítulo 04b concluído — parameter files `infra/envs/{dev,staging,prod}.parameters.json` validados via `az bicep build` + `what-if`
- ✅ `az` CLI logado na subscription correta (`az account show` confirma)
- ✅ Bicep CLI atualizado (`az bicep version` `>=0.30`)
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first

> **Nota — Capítulo 03 opcional:** o Capítulo 03 (Service Principal Federated) ficou marcado como **OPCIONAL** nesta versão. O SP federado só seria necessário para CI/CD via GitHub Actions (fora do escopo). Se você pulou o Cap 03, segue tudo normal — `az deployment group create` usa o usuário logado em `az login`.

---

## Resumo dos 4 deploys que vamos cravar

| # | Etapa | Comando | Tempo |
|---|---|---|---|
| 1 | Validação local (what-if dev) | `az deployment group what-if` | ~2 min |
| 2 | Deploy `dev` | `az deployment group create` | ~30-45 min (APIM dominante) |
| 3 | Deploy `staging` | `az deployment group create` | ~30-45 min (APIM dominante) |
| 4 | Deploy `prod` | `az deployment group create` | ~30-45 min (APIM dominante) |

> **Estratégia "deploy 3 envs no MESMO RG":** os 3 deploys rodam no MESMO `rg-lab-avancado`. O parâmetro `envName` (dev/staging/prod) diferencia o **nome dos recursos** (ex.: `apim-helpsphere-dev` vs `apim-helpsphere-staging`), não o RG. Isso reduz custo (1 RG limpo) e simplifica cleanup (1 `az group delete`). Em prod real você usaria 3 RGs separados — para o lab, isolar por nome é suficiente.

> **Alternativa pedagógica — deploya só 1 env:** se você quer **minimizar custo**, pode deployar APENAS `dev` (Passo 5.2) e pular staging/prod. APIM Developer cobra ~R$ 8/dia por instância — 3 instâncias = R$ 24/dia. Recomendação: deploya `dev`, valida o pattern end-to-end, faz cleanup, e só roda staging/prod se quiser ver o `envName` diferenciando recursos.

---

## Passo 5.1 — Validar Bicep localmente com `what-if` (read-only, gratuito)

`what-if` simula o deployment **sem aplicar** mudanças. Lista resources que serão criados/modificados/deletados. Sempre rode `what-if` antes do deploy real — pega erros de Bicep, parâmetros inválidos, e violações de policy (Capítulo 08) ANTES de cobrar APIM provisionando.

**No terminal local (Windows PowerShell 7):**

```powershell
# 1. Navegue para a raiz do clone local de helpsphere-ia (ou apex-helpsphere-prod-lab)
Set-Location <caminho-para-o-clone>

# 2. Confirme que está logado na sub correta
az account show --query "{name:name, id:id}" -o table

# 3. Confirme que o RG existe
az group show --name rg-lab-avancado --query "{name:name, location:location, state:properties.provisioningState}" -o table

# 4. Rode what-if para o env dev
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/dev.parameters.json'
```

**Output esperado:** lista de "Resource changes" com símbolos `+ Create` para APIM, Content Safety, App Insights, Log Analytics, Policy Assignments. Nenhum `- Delete` (RG vazio antes do primeiro deploy) e nenhum `! Error`.

<!-- screenshot: cap05-passo5.1-what-if-dev-output.png -->

> **Alternativa Linux/Mac/WSL (bash):** troque `` ` `` (backtick) por `\` no fim das linhas e `Set-Location` por `cd`.

> **Custo:** R$ 0 — `what-if` é read-only no Resource Manager.

> **Nota pedagógica — por que `what-if` e não `validate`?** `az deployment group validate` checa sintaxe + parâmetros. `what-if` faz o mesmo + **simula o resultado final no estado atual do RG** (compara o template com o que já existe). Pega erros que `validate` não pega: nome duplicado, conflict com policy denying location, recurso já existente com sku diferente. Sempre prefira `what-if`.

---

## Passo 5.2 — Deployar env `dev` (primeiro deploy real)

```powershell
az deployment group create `
  --name "deploy-dev-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/dev.parameters.json'
```

**Tempo:** ~30-45 min (APIM Developer SKU é o gargalo — Content Safety, App Insights e Policy ficam prontos em ~1-2 min).

**Output durante o deploy:** terminal mostra `Running...` com spinner. Você pode **abrir outro terminal** e seguir Capítulos 06+ em paralelo enquanto APIM provisiona.

**Output ao final (success):** JSON com `properties.outputs.apimGatewayUrl.value` = URL do APIM Gateway provisionado, `apimName`, `contentSafetyEndpoint`, etc.

<!-- screenshot: cap05-passo5.2-deploy-dev-completed.png -->

> **Alternativa Linux/Mac/WSL (bash):**
>
> ```bash
> az deployment group create \
>   --name "deploy-dev-$(date +%Y%m%d%H%M%S)" \
>   --resource-group rg-lab-avancado \
>   --template-file infra/main.bicep \
>   --parameters @infra/envs/dev.parameters.json
> ```

> **Custo:** APIM Developer começa a cobrar prorated por hora a partir do `provisioningState=Succeeded` (~R$ 8/dia ligado). Content Safety F0 = R$ 0. App Insights = R$ 0-15/mês (volume baixo lab). **Se você esquecer ligado:** ~R$ 250/mês recorrente em APIM.

> **Nota pedagógica — `--name` único por deploy:** o nome do deployment é como você identifica esse run específico em `az deployment group list -g rg-lab-avancado`. Usar timestamp (`$(Get-Date -Format 'yyyyMMddHHmmss')`) garante uniqueness e ordenação cronológica natural. Se você deployar 2x com mesmo nome, o segundo **substitui** o registro do primeiro (mas os recursos já criados continuam — Azure faz `update`, não `delete + recreate`).

> **Atenção timeout PS7:** terminal PowerShell pode "parecer travado" durante os 30+ min. **NÃO** dê Ctrl+C — você cancela o deployment Azure-side. Se precisar fechar o terminal, use `Get-Process powershell | Stop-Process` em outro terminal, mas o deployment **continua no Azure**. Verifique com `az deployment group list -g rg-lab-avancado --query "[?provisioningState=='Running'].name" -o tsv`.

---

## Passo 5.3 — Validar resources criados em `dev`

Após o deploy do Passo 5.2 retornar `Succeeded`, valide que os 5 grupos de recursos estão em pé:

```powershell
# 1. Listar TODOS os recursos no RG
az resource list `
  --resource-group rg-lab-avancado `
  --query "[].{name:name, type:type, location:location}" `
  -o table

# 2. APIM provisionado e em Succeeded
az apim list `
  --resource-group rg-lab-avancado `
  --query "[].{name:name, sku:sku.name, state:provisioningState}" `
  -o table
# Esperado: name=apim-helpsphere-<token>, sku=Developer, state=Succeeded

# 3. Content Safety endpoint disponível
az cognitiveservices account list `
  --resource-group rg-lab-avancado `
  --query "[?kind=='ContentSafety'].{name:name, sku:sku.name, endpoint:properties.endpoint}" `
  -o table

# 4. App Insights workspace-based
az monitor app-insights component show `
  --resource-group rg-lab-avancado `
  --app "ai-helpsphere-dev" `
  --query "{name:name, kind:kind, workspaceId:workspaceResourceId}" `
  -o jsonc 2>$null

# 5. 3 Policy Assignments scoped no RG
$SubId = az account show --query id -o tsv
az policy assignment list `
  --scope "/subscriptions/$SubId/resourceGroups/rg-lab-avancado" `
  --query "[].{name:name, displayName:displayName, enforcementMode:enforcementMode}" `
  -o table
# Esperado: 3 rows (allowed-locations + require-cost-center + cosmos-deny-public)
```

> **Alternativa Linux/Mac/WSL (bash):** troque `$Var =` por `VAR=$(...)`, `` ` `` por `\`, e `2>$null` por `2>/dev/null`.

> **Custo:** R$ 0 — leituras read-only.

> **Nota pedagógica — por que validar imediatamente após deploy?** APIM pode retornar `Succeeded` no Resource Manager mas levar mais 5-10 min até o Gateway URL responder HTTP 200/404 (warm-up do cluster). Validar `provisioningState` confirma que o deploy não falhou silenciosamente. Smoke test real do Gateway vem no Capítulo 06.

---

## Passo 5.4 — Deployar env `staging` (mesmo padrão, nome de recurso diferente)

Mesmo RG, parâmetro `envName=staging` diferencia os nomes dos recursos.

```powershell
# 1. what-if antes (sempre)
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/staging.parameters.json'

# 2. Deploy real
az deployment group create `
  --name "deploy-staging-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/staging.parameters.json'
```

**Tempo:** ~30-45 min novamente (APIM `apim-helpsphere-staging-<token>` é um recurso NOVO, não compartilha com dev).

<!-- screenshot: cap05-passo5.4-deploy-staging-output.png -->

> **Custo:** +R$ 8/dia adicional ligado (2 APIM Developer SKU agora = R$ 16/dia se dev e staging coexistirem).

> **Decisão pedagógica — pular staging?** Se objetivo é minimizar custo, pule Passo 5.4 e Passo 5.5. O pattern Bicep + `--parameters` é o mesmo — alterar 1 parâmetro = ambiente novo. Você já validou em dev (Passo 5.2). **Cleanup em 5.4/5.5 pulados:** a próxima sessão de gravação pode focar em 1 env só.

---

## Passo 5.5 — Deployar env `prod` (mesmo padrão)

```powershell
# 1. what-if antes
az deployment group what-if `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/prod.parameters.json'

# 2. Deploy real
az deployment group create `
  --name "deploy-prod-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/prod.parameters.json'
```

<!-- screenshot: cap05-passo5.5-deploy-prod-output.png -->

> **Custo:** +R$ 8/dia adicional se prod coexistir com dev+staging (3 APIM Developer ligados = R$ 24/dia = R$ 720/mês se esquecido). **Cleanup obrigatório no Capítulo 10.**

> **Nota pedagógica — sem approval gate em CLI manual:** em CI/CD GitHub Actions (versão `v0.2.0` deste capítulo), `cd-prod.yml` usava `environment: production` com `required reviewers` — bloqueio humano antes do deploy prod. Em CLI manual, o **próprio aluno** é o gate. Recomenda-se: (a) só rode `prod` depois de validar `dev` E `staging`, (b) leia `what-if` linha-a-linha antes de digitar `Enter`, (c) use `--confirm-with-what-if` flag se quiser dupla confirmação.

```powershell
# Variante com dupla confirmação (Azure CLI imprime what-if + pede confirmação interativa)
az deployment group create `
  --name "deploy-prod-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --resource-group rg-lab-avancado `
  --template-file infra/main.bicep `
  --parameters '@infra/envs/prod.parameters.json' `
  --confirm-with-what-if
```

---

## Passo 5.6 — Listar deployments e verificar histórico

Toda execução de `az deployment group create` registra o deployment no Resource Manager. Pode consultar histórico:

```powershell
# 1. Listar TODOS os deployments do RG
az deployment group list `
  --resource-group rg-lab-avancado `
  --query "[].{name:name, state:properties.provisioningState, timestamp:properties.timestamp}" `
  -o table

# 2. Ver output completo do último deployment dev (variáveis exportadas pelos modules)
$LastDevDeploy = az deployment group list `
  --resource-group rg-lab-avancado `
  --query "[?starts_with(name, 'deploy-dev-')] | [0].name" -o tsv

az deployment group show `
  --resource-group rg-lab-avancado `
  --name $LastDevDeploy `
  --query "properties.outputs" `
  -o jsonc

# 3. Ver erros de deployments falhados (se houver)
az deployment group list `
  --resource-group rg-lab-avancado `
  --query "[?properties.provisioningState=='Failed'].{name:name, error:properties.error}" `
  -o jsonc
```

> **Alternativa Linux/Mac/WSL (bash):** troque `$LastDevDeploy =` por `LAST_DEV_DEPLOY=$(...)`, `` ` `` por `\`, e remova as aspas simples do `@infra/envs/...json`.

> **Custo:** R$ 0 — leituras read-only.

> **Nota pedagógica — deployment history vs resource state:** o deployment registra **o que você TENTOU fazer**, não **o estado atual do resource**. Se você deletou um APIM no Portal e re-rodou Bicep, o deployment registra "Succeeded" mas você não vê o delete intermediário. Use `az deployment group show` para auditar intenções e `az resource list` para auditar estado.

---

## Validação end-to-end

```powershell
# 1. RG existe com 4 tags
az group show --name rg-lab-avancado --query "{name:name, tags:tags}" -o jsonc

# 2. Pelo menos 1 APIM em Succeeded
$Count = az apim list -g rg-lab-avancado --query "length([?provisioningState=='Succeeded'])" -o tsv
Write-Host "APIM Succeeded: $Count (esperado: 1, 2 ou 3 conforme envs deployados)"

# 3. Deployments registrados (>=1)
az deployment group list -g rg-lab-avancado --query "length([?properties.provisioningState=='Succeeded'])" -o tsv
# Esperado: numero >= 1

# 4. Policy Assignments cravadas
$SubId = az account show --query id -o tsv
az policy assignment list --scope "/subscriptions/$SubId/resourceGroups/rg-lab-avancado" --query "length(@)" -o tsv
# Esperado: 3
```

> **Linux/Mac/WSL:** troque `$Count =` / `$SubId =` por `COUNT=$(...)` / `SUB_ID=$(...)`, `` ` `` por `\`, e `Write-Host` por `echo`.

---

## Checklist final

```text
[ ] what-if rodou sem erros para dev (Passo 5.1)
[ ] Deploy dev concluiu com Succeeded (Passo 5.2)
[ ] az resource list mostra APIM + Content Safety + App Insights + Log Analytics + Policy (Passo 5.3)
[ ] (Opcional) Deploy staging concluiu — Passo 5.4
[ ] (Opcional) Deploy prod concluiu — Passo 5.5
[ ] az deployment group list mostra historico com Succeeded (Passo 5.6)
[ ] Nenhum deployment em estado Failed
[ ] 3 Policy Assignments cravadas (allowed-locations + require-cost-center + cosmos-deny-public)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **APIM Developer provisiona em ~30-45 min** — não é erro, é o SKU. Se aparecer `Status: Activating` por mais de 1h, abra ticket Azure. Workaround: provisione e siga outros Capítulos em paralelo (Cap 06 detalha policies do APIM que você cravará após `Succeeded`).
- ⚠️ **`az deployment group create` retorna sucesso mas APIM Gateway URL não responde HTTP** — APIM pode levar +5-10 min após `Succeeded` para o cluster Gateway aceitar requests. Workaround: aguarde, depois `curl -I https://<gateway-url>/status-0123456789abcdef` retorna `404 NotFound` (esperado em init — você cria policies/APIs no Cap 06).
- ⚠️ **`--parameters '@infra/envs/dev.parameters.json'` com aspas simples em PowerShell** — sem as aspas, PS interpreta `@` como splatting operator. Workaround: SEMPRE use aspas simples ao redor do path com `@` em PowerShell. Linux/Mac/WSL bash não precisa de aspas.
- ⚠️ **Policy `allowed-locations` bloqueia o primeiro deploy se você cravou Policy ANTES da infra** — sequência errada: aplicar policy `allowed-locations=eastus2` num RG vazio, depois tentar deployar APIM em `eastus2`. Funciona. Mas se você mudar o `commonTags.environment` por engano sem `cost-center`, o policy `require-cost-center-tag` bloqueia. Workaround: o Bicep `policy.bicep` aplica policies **depois** dos recursos no MESMO deployment — Azure resolve dependências automaticamente. Se você split em 2 deployments separados, ordem importa.
- ⚠️ **Deployment registra "Succeeded" mas Cost Analysis mostra R$ 0 nas primeiras 6-24h** — Cost Management tem latência. Workaround: aguarde 24h para ver custo do APIM aparecer. Não pânico nas primeiras horas.
- ⚠️ **`az deployment group create` em sub com policy `allowed-locations` global retorna `RequestDisallowedByPolicy`** — algumas subs corporate têm policy assignment no scope `subscription` (não RG) que bloqueia regiões diferentes. Workaround: verifique `az policy assignment list --scope /subscriptions/<ID>` e ajuste seu `commonTags.location` (no Bicep) ou peça ao admin para ajustar policy.

---

## Próximo capítulo

[06 — APIM gateway + policies](./06-apim-gateway-policies.md)
