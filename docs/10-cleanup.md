# Capítulo 10 — Cleanup

> **Objetivo:** desligar **TUDO** que custa dinheiro neste lab — APIM Developer (~R$ 250/mês), Application Insights, Action Group, Budget, Service Principal + 3 Federated Credentials, GitHub Secrets/Variables, e (gated) o repositório `helpsphere-ia` — em **ordem correta** (App Reg → Resources → RG → GitHub artifacts) e validar que o billing **zera** em 24-48h via Cost Analysis. Sair daqui com `az group exists --name rg-lab-avancado` retornando `false` e o gráfico de custo descrescendo a R$ 0/dia.
>
> **Tempo:** 25-40 min ativos (+ ~30 min de wait para APIM deletar em background + ~24-48h para Cost Analysis refletir)
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` semi-expandido) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Passos 7.4-7.5 (linhas 2110-2189) + agregação de recursos provisionados nos Capítulos 01-09

---

## DISCLAIMER R4 (HIGH — bloqueante para o bolso) — Cleanup é OBRIGATÓRIO

**APIM SKU Developer custa ~R$ 250/mês ligado**, mesmo se você não fizer uma única request:

| Esquecido por | Custo APIM acumulado | + outros recursos | Total estimado |
|---|---:|---:|---:|
| 1 dia | R$ 8 | R$ 1-2 | **R$ 9-10** |
| 7 dias | R$ 56 | R$ 8-12 | **R$ 65-70** |
| 30 dias | R$ 250 | R$ 30-50 | **R$ 280-300** |
| 6 meses | R$ 1.500 | R$ 200-300 | **R$ 1.700-1.800** |
| 12 meses | R$ 3.000 | R$ 400-600 | **R$ 3.400-3.600** |

> **Comportamento de billing:** APIM Developer cobra **prorated por hora** desde o `provisioningState=Succeeded` — não há "free idle". Application Insights e Content Safety têm free tier generoso (até 5 GB/mês e 5k transações/dia), mas APIM **não tem free tier algum**. Faça cleanup **no mesmo dia** da gravação/lab.

> **Atenção billing-em-trânsito:** Cost Management mostra dados com **6-24h de atraso**. Você delete o RG agora, mas o gráfico de custo só zera em ~24-48h. Não entre em pânico se ver R$ 5-10 ainda no dia seguinte — é runtime cobrado **antes** do delete.

---

## DISCLAIMER R6 (recap — apenas se conta `live.com`) — ABAC pode bloquear delete RG

Se você ignorou o R6 do Capítulo 01/03 e rodou parte do lab numa sub VSE pessoal `live.com` com ABAC ativo, pode ter problema **inverso** no cleanup:

- **CI/CD não funcionou** (esperado — R6 documentado)
- **Delete RG via Portal pode falhar** com `AuthorizationFailed: ConditionRequiresAuthorization` se a condition cobre `Microsoft.Resources/subscriptions/resourceGroups/delete`

**Workaround:** delete recurso-a-recurso (Passo 10.2), não no nível de RG. App Registrations vivem em Entra (não na sub) e deletam normalmente. Restos órfãos podem precisar do admin do tenant.

---

## Pré-requisitos

- ✅ Lab rodado até onde foi possível — você está fechando para evitar billing
- ✅ `az` CLI logado na **mesma subscription** onde provisionou (`az account show` confirma)
- ✅ `gh` CLI autenticado com scope **`delete_repo`** se quiser deletar o repo (`gh auth refresh -s delete_repo` ANTES)
- ✅ Acesso à conta do **email cadastrado no Action Group** para confirmar parada de alerts
- ✅ Resultado do eval (`eval/results.json`) e RUNBOOK exportados localmente se você quer manter histórico (Passo 10.1)

> **Atenção gotcha — escopo do `gh` token:** `gh auth status` mostra "Logged in" mas pode estar **sem** scope `delete_repo`. Tentar deletar repo retorna `HTTP 403: Must have admin rights to Repository`. Workaround: rodar `gh auth refresh -s delete_repo,repo,workflow` ANTES — abre browser, re-autentica com novo escopo.

---

## Inventário consolidado dos recursos a deletar (Capítulos 01-09)

| # | Recurso | Onde vive | Cap origem | Cobra parado? | Custo/mês ligado |
|---|---|---|---|---|---:|
| 1 | RG `rg-lab-avancado` | Subscription Azure | Cap 02 | Não (container) | R$ 0 |
| 2 | APIM `apim-helpsphere-staging` (+ `apim-helpsphere-prod` se subiu) | RG → Microsoft.ApiManagement | Cap 04a, 05, 06 | **SIM (Developer SKU)** | **~R$ 250-500** |
| 3 | Content Safety `cs-helpsphere-staging` | RG → CognitiveServices | Cap 04a, 07 | Não (F0 free) | R$ 0 |
| 4 | Application Insights `ai-helpsphere-staging` | RG → Microsoft.Insights | Cap 04a, 07 | Quase não (≤ 5 GB free) | R$ 0-15 |
| 5 | Log Analytics workspace `log-helpsphere-ia` | RG → Microsoft.OperationalInsights | Cap 04a, 07 | Por GB ingerido | R$ 0-25 |
| 6 | 3 Policy Assignments (allowed-locations + cost-center-tag + cosmos-deny-public) | RG → Microsoft.Authorization | Cap 04a, 08 | Não | R$ 0 |
| 7 | Budget `budget-helpsphere-ia` | Cost Management → escopo RG | Cap 08 | Não | R$ 0 |
| 8 | Action Group `ag-helpsphere-ia-alerts` | Monitor → Alerts (Global) | Cap 08 | Não | R$ 0 |
| 9 | App Registration `sp-github-actions-helpsphere` | **Microsoft Entra ID** (NÃO no RG) | Cap 03 | Não | R$ 0 |
| 10 | 3 Federated Credentials (main + pull_request + production) | Vivem dentro do App Reg | Cap 03 | Não | R$ 0 |
| 11 | 4 GitHub Secrets (`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AOAI_API_KEY`) | Repo → Settings → Secrets | Cap 03 | — | — |
| 12 | 4 GitHub Environment Variables (`AOAI_ENDPOINT`, `AGENT_FUNCTION_URL_STAGING`, `AGENT_FUNCTION_URL_PROD`) | Repo → Settings → Environments | Cap 05 | — | — |
| 13 | 2 GitHub Environments (`staging` + `production`) | Repo → Settings → Environments | Cap 05 | — | — |
| 14 | Repo `helpsphere-ia` (gated) | GitHub | Cap 02 | — | — |
| 15 | Foundry Hub `aifhub-apex-prod` | RG **diferente** (compartilhado D06) | Cap 01 (referência) | Sim (varia) | **NÃO DELETE** |

> **Crítico — itens fora do RG:** App Registration (#9-10) vive em **Entra ID**, **não** no RG. Deletar `rg-lab-avancado` **NÃO remove** o SP — fica órfão até você ir em Entra → App registrations → Delete. Mesmo aplicável a Foundry Hub (#15) que vive em outro RG (compartilhado entre Lab Inter, Final, Avançado) e **NÃO deve ser deletado**.

> **Por que ordem App Reg → Resources → RG → GitHub?** App Registration deletado primeiro **invalida tokens em uso** — se algum CI workflow estiver rodando, falha imediatamente em vez de criar recurso novo durante o cleanup. Em seguida APIM (delete demorado, ~30 min em background), aí RG (deleta o resto cascade), por último GitHub (limpeza local sem dependências cloud).

---

## Passo 10.1 — Exportar artifacts que valem manter (5 min — opcional mas recomendado)

Antes de detonar tudo, baixe localmente o que tem valor pedagógico/portfolio:

**No GitHub Actions UI + Portal Azure:**

1. **eval/results.json:** Actions → último run de `cd-staging.yml` → job `eval-offline` → seção **Artifacts** → download `eval-results-staging` (ZIP)
2. **App Insights queries (KQL salvas):** Portal → `ai-helpsphere-staging` → Logs → query salva `Tokens por minuto (custom metric)` → botão **Export** → **CSV**. Repita para as 4 queries do Capítulo 07
3. **Cost Analysis snapshot:** Portal → `rg-lab-avancado` → Cost analysis → **Daily costs (last 7 days)** → exportar CSV
4. **APIM policy XML:** APIM → APIs → HelpSphere Agent API → Policy editor → copiar todo o XML para `docs/portfolio/apim-policy.xml` no clone local

```powershell
# PowerShell — backup local antes do cleanup
New-Item -ItemType Directory -Path "$HOME/portfolio/helpsphere-ia-cleanup-snapshot" -Force | Out-Null
Set-Location "$HOME/portfolio/helpsphere-ia-cleanup-snapshot"

# Exportar resultado do último run
gh run download --repo <seu-username>/helpsphere-ia --name eval-results-staging

# Exportar últimos custos como CSV
$StartDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere')].{date:usageStart, resource:instanceName, cost:pretaxCost}" `
  -o tsv | Out-File -FilePath usage-pre-cleanup.tsv -Encoding utf8
```

> **Linux/Mac/WSL:** troque `New-Item` por `mkdir -p`, `Set-Location` por `cd`, `$HOME` por `~`, `(Get-Date).AddDays(-30).ToString("yyyy-MM-dd")` por `$(date -d "30 days ago" +%Y-%m-%d)`, `` ` `` por `\`, e `| Out-File` por `> file`.

> **Custo:** R$ 0 — exports são read-only.

> **Nota pedagógica — por que portfolio matters?** Em entrevista de cargo cloud-architect/SRE, mostrar `eval/results.json` real + KQL custom + APIM policy XML produz mais sinal que qualquer cert. Lab terminou — artefato fica.

---

## Passo 10.2 — Deletar App Registration `sp-github-actions-helpsphere` (Entra ID — primeiro!)

Por que primeiro? Token federated em uso para de funcionar instantaneamente. CI workflow disparado por engano durante o cleanup falha em `azure/login@v2` em vez de provisionar coisa nova.

**No Portal Azure (Microsoft Entra ID):**

1. Barra superior → buscar **"Microsoft Entra ID"** → menu lateral → **App registrations**
2. Aba **All applications** → filtre por `sp-github-actions-helpsphere` → clique no nome
3. Tab **Overview** → topo → **Delete**
4. Modal de confirmação → ☑ **"I understand the implications of deleting this app registration"** → **Delete**
5. (Opcional, mas recomendado) Aba lateral → **App registrations** → **Deleted applications** → `sp-github-actions-helpsphere` → **Permanently delete**

<!-- screenshot: cap10-passo10.2-delete-app-registration.png -->

> **Alternativa via Azure CLI (limpa as 2 entidades — App + SP — e federated credentials cascade):**
>
> ```powershell
> $AppId = az ad app list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv
>
> # 1. Deletar SP (instância no tenant)
> az ad sp delete --id $AppId 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(SP já removido — OK)" }
>
> # 2. Deletar App Registration (definição) — federated credentials morrem junto
> az ad app delete --id $AppId
>
> # 3. Confirmar que sumiu
> az ad app list --display-name "sp-github-actions-helpsphere" --query "length(@)"
> # Esperado: 0
> ```
>
> **Linux/Mac/WSL:** troque `$AppId =` por `APP_ID=$(...)`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, e `Write-Host` por `echo`.

> **Custo:** R$ 0 — App Registrations e Federated Credentials são gratuitos no Entra. Deletar não tem fee.

> **Nota pedagógica — soft-delete em Entra é 30 dias:** após `Delete`, o App fica em **Deleted applications** por 30 dias e pode ser restaurado. Em prod isso é feature (recovery de delete acidental). Em lab que terminou, **Permanently delete** garante que não fica resíduo no Entra. Importante se a sub é compartilhada com outros alunos.

---

## Passo 10.3 — Deletar APIM individualmente em background (estratégia "delete cedo, espera depois")

APIM Developer demora **~30 min** para deletar mesmo via `--no-wait`. Iniciar agora libera o cleanup do resto em paralelo.

**No Portal Azure:**

1. Buscar **"API Management services"** → localizar `apim-helpsphere-staging` (e `apim-helpsphere-prod` se subiu)
2. Clicar no nome → tab **Overview** → topo → **Delete**
3. Confirmação → digitar nome do APIM → ☑ **Apply force delete** (necessário se algum subscription/product ficou em estado inconsistente) → **Delete**
4. Notificação no sino: "Deleting api management service apim-helpsphere-staging" (~30 min para concluir, roda async)

<!-- screenshot: cap10-passo10.3-apim-delete.png -->

> **Alternativa via Azure CLI (paralelo + async):**
>
> ```powershell
> # Dispara delete em background — você segue para Passo 10.4 imediatamente
> az apim delete `
>   --name apim-helpsphere-staging `
>   --resource-group rg-lab-avancado `
>   --no-wait `
>   --yes
>
> # Se subiu apim-helpsphere-prod também:
> az apim delete `
>   --name apim-helpsphere-prod `
>   --resource-group rg-lab-avancado `
>   --no-wait `
>   --yes 2>$null
>
> # Status da operação async
> $State = az apim show `
>   --name apim-helpsphere-staging `
>   --resource-group rg-lab-avancado `
>   --query "provisioningState" -o tsv 2>&1
> if ($LASTEXITCODE -ne 0) { Write-Host "✅ APIM deletado ou em deletion final" } else { Write-Host $State }
> # Durante delete: "Deleting" · após: erro ResourceNotFound (esperado)
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, e `Write-Host` por `echo`.

> **Custo:** zero adicional — delete é gratuito · billing **para de cobrar** quando `provisioningState=Deleting` (não no `Deleted` final).

> **Nota pedagógica — por que `--apply-force-delete` (Portal) / `--yes`?** APIM tem dependências em Diagnostic Settings, Custom Domain certs, Backups e Subscriptions internos. Em estados inconsistentes (provisão falhada, custom domain pendente), delete normal trava em loop. Force delete pula validações pré-flight. Em prod real você investigaria o estado antes — em lab é seguro forçar.

---

## Passo 10.4 — Deletar Budget + Action Group + Policy Assignments (não cobram, mas limpam)

Esses recursos **não cobram parados** — limpá-los é higiene de inventário, não economia.

**No Portal Azure (Cost Management → Budgets):**

1. Buscar **"Cost Management + Billing"** → menu lateral → **Cost Management** → **Budgets**
2. Escopo `rg-lab-avancado` → localize `budget-helpsphere-ia` → clicar
3. Topo → **Delete budget** → confirmar

**No Portal Azure (Monitor → Action groups):**

4. Buscar **"Monitor"** → menu lateral → **Alerts** → **Action groups**
5. Localize `ag-helpsphere-ia-alerts` → ☑ checkbox → topo → **Delete**

**No Portal Azure (Policy → Authoring → Assignments):**

6. Buscar **"Policy"** → **Authoring** → **Assignments**
7. Filtre por scope `rg-lab-avancado` → 3 assignments aparecem (`allowed-locations-<hash>`, `helpsphere-cost-center-tag-required-<hash>`, `cosmos-deny-public-<hash>`)
8. Selecione cada uma → menu **...** → **Delete assignment**

> **Alternativa via Azure CLI (1 bloco):**
>
> ```powershell
> # 1. Budget
> az consumption budget delete --budget-name budget-helpsphere-ia 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(budget já removido ou ainda processando)" }
>
> # 2. Action Group
> az monitor action-group delete `
>   --name ag-helpsphere-ia-alerts `
>   --resource-group rg-lab-avancado 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(action group já removido)" }
>
> # 3. Policy assignments scoped no RG
> $SubId = az account show --query id -o tsv
> $Scope = "/subscriptions/$SubId/resourceGroups/rg-lab-avancado"
> $Names = az policy assignment list --scope $Scope --query "[].name" -o tsv
> foreach ($Name in $Names -split "`n") {
>   if ($Name) {
>     az policy assignment delete --name $Name --scope $Scope
>     Write-Host "Deleted: $Name"
>   }
> }
>
> # 4. Confirmar
> az policy assignment list --scope $Scope --query "length(@)"
> # Esperado: 0
> ```
>
> **Linux/Mac/WSL:** troque `$Var =` por `VAR=$(...)`, `` ` `` por `\`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, `Write-Host` por `echo`, e o `foreach`/`-split` por `for NAME in $(...); do ... done`.

> **Custo:** R$ 0 — todos os 3 (Budget, Action Group, Policy Assignment) são gratuitos. Cleanup é organizacional.

> **Nota pedagógica — Policy Assignments cascadam com RG delete?** Sim, **se o assignment scope é o próprio RG**. Mas se você criou alguma assignment no scope `subscription` (ex.: o Bicep `policy.bicep` com `targetScope='subscription'`), elas **NÃO** somem com `az group delete`. Sempre verifique `az policy assignment list --scope /subscriptions/<ID>` no Passo 10.7 final.

---

## Passo 10.5 — Deletar Resource Group `rg-lab-avancado` (cascade dos demais recursos)

Com APIM já em deletion (Passo 10.3) e satellites limpos (Passo 10.4), agora o RG vai cascatear o resto: Content Safety, App Insights, Log Analytics, Function App restos.

**No Portal Azure:**

1. Buscar **"Resource groups"** → localizar `rg-lab-avancado` → clicar no nome
2. Tab **Overview** → topo → **Delete resource group**
3. Painel à direita pede confirmação:
   - **Type the resource group name to confirm:** digitar `rg-lab-avancado`
   - ☑ **Apply force delete** (recomendado — alguns recursos podem estar em estado inconsistente após 30+ min de APIM)
4. **Delete**
5. Notificação no sino: "Deleting resource group rg-lab-avancado" (~30-45 min se APIM ainda não terminou; ~5 min se já estava deletado)

<!-- screenshot: cap10-passo10.5-delete-rg.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> az group delete --name rg-lab-avancado --yes --no-wait
>
> # Polling
> while ((az group exists --name rg-lab-avancado) -eq "true") {
>   Write-Host "$(Get-Date -Format HH:mm:ss) — RG ainda existe, aguardando..."
>   Start-Sleep -Seconds 60
> }
> Write-Host "✅ rg-lab-avancado deletado"
> ```
>
> **Linux/Mac/WSL:** troque o `while` por `while az group exists --name rg-lab-avancado | grep -q true; do`, `Write-Host` por `echo`, `Get-Date -Format HH:mm:ss` por `$(date +%H:%M:%S)`, e `Start-Sleep -Seconds 60` por `sleep 60`.

> **Custo:** zero adicional — delete é gratuito.

> **Nota pedagógica — `Apply force delete` perigoso em prod?** Em prod sim — alguns recursos têm **lock** ou **soft-delete** que force ignora (ex.: Storage com soft-delete blob de 30 dias **fica em backup pago** mesmo após RG delete). Em lab é seguro porque você não criou Storage com soft-delete, nem Key Vault com purge protection. **Stop-loss prod:** sempre `az resource list -g <RG>` antes de force delete, valida que não há nada com retention pago.

> **R6 reminder:** se o delete falha com `ConditionRequiresAuthorization` numa sub `live.com`, vá recurso-a-recurso (Portal → cada recurso → Delete). Workaround sub-ótimo, mas não há outro caminho com ABAC ativo.

---

## Passo 10.6 — Cleanup GitHub Secrets, Environment Variables e Environments

Mesmo com SP deletado, os 4 secrets + 4 vars + 2 environments ficam no repo. Limpar reduz superfície (alguém forka, adiciona um workflow malicioso e vê os secrets — improvável mas possível).

**No GitHub (Repository → Settings → Secrets and variables → Actions):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/secrets/actions`
2. Aba **Secrets** → para cada um: **AZURE_TENANT_ID**, **AZURE_SUBSCRIPTION_ID**, **AZURE_CLIENT_ID**, **AOAI_API_KEY** → ☒ ícone de lixeira → **Delete secret**

**No GitHub (Repository → Settings → Environments):**

3. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/environments`
4. Em `staging` → **Environment variables** → delete `AOAI_ENDPOINT` + `AGENT_FUNCTION_URL_STAGING`
5. Em `production` → delete `AOAI_ENDPOINT` + `AGENT_FUNCTION_URL_PROD`
6. Volte para a lista → ☒ ícone de lixeira nas environments `staging` e `production` → confirmar

<!-- screenshot: cap10-passo10.6-github-secrets-deleted.png -->

> **Alternativa via gh CLI (mais rápido):**
>
> ```powershell
> $Repo = "<seu-username>/helpsphere-ia"
>
> # 1. Deletar 4 repository secrets
> foreach ($S in @("AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_CLIENT_ID", "AOAI_API_KEY")) {
>   gh secret delete $S --repo $Repo 2>$null
>   if ($LASTEXITCODE -ne 0) { Write-Host "(secret $S já removido)" }
> }
>
> # 2. Deletar environment variables (staging)
> gh variable delete AOAI_ENDPOINT --repo $Repo --env staging 2>$null
> gh variable delete AGENT_FUNCTION_URL_STAGING --repo $Repo --env staging 2>$null
>
> # 3. Deletar environment variables (production)
> gh variable delete AOAI_ENDPOINT --repo $Repo --env production 2>$null
> gh variable delete AGENT_FUNCTION_URL_PROD --repo $Repo --env production 2>$null
>
> # 4. Deletar os 2 environments inteiros
> gh api -X DELETE "repos/$Repo/environments/staging" 2>$null
> gh api -X DELETE "repos/$Repo/environments/production" 2>$null
>
> # 5. Confirmar
> gh secret list --repo $Repo
> # Esperado: vazio
> ```
>
> **Linux/Mac/WSL:** troque `$Var =` por `VAR=`, `foreach`/`@(...)` por `for S in ...; do ... done`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, `Write-Host` por `echo`, e referências `$Var` por `"$VAR"`.

> **Custo:** R$ 0 — GitHub.

> **Nota pedagógica — por que limpar secrets se SP já está deletado?** Defesa em profundidade. Se o SP foi deletado mas o `AOAI_API_KEY` ficou (chave do AOAI provisionado no Lab Inter, **ainda válida**), qualquer fork ou collaborator tem acesso. Sempre limpe **ambos os lados** (Azure + GitHub) — não confie só em um.

---

## Passo 10.7 — Deletar repositório GitHub `helpsphere-ia` (gated — opcional)

> **Decisão pedagógica — manter como portfolio?** Repos com IaC + workflows OIDC + eval Python + RUNBOOK valem como amostra de trabalho em entrevista. Recomendo **manter**, removendo só os secrets (já feito no Passo 10.6). Se mantém: arquivar o repo via Settings → General → Danger Zone → **Archive this repository** — fica read-only e não dispara Actions acidentalmente.

Se mesmo assim quer deletar:

**Pré-requisito:** `gh auth status` deve mostrar scope `delete_repo`. Se não tem:

```powershell
gh auth refresh -s delete_repo,repo,workflow
# Abre browser, confirme novo escopo
```

> **Atenção pendência:** caso esteja num ambiente onde `gh auth refresh -s delete_repo` esteja **gated por permissão admin** (Federated SP gov, MFA pendente, browser bloqueado), **anote como pendência** e prefira **archive** via Settings UI (não exige scope adicional).

**No GitHub (Repository → Settings → General → Danger Zone):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings`
2. Scroll até o final → **Danger Zone**
3. **Delete this repository** → digitar `<seu-username>/helpsphere-ia` para confirmar → **I understand the consequences, delete this repository**

> **Alternativa via gh CLI (com scope `delete_repo`):**
>
> ```powershell
> gh repo delete <seu-username>/helpsphere-ia --yes
> ```

> **Custo:** R$ 0 — GitHub não cobra delete.

---

## Passo 10.8 — Verificação final + economia validada

**No Portal Azure (Cost Management):**

1. Buscar **"Cost Management"** → escopo **subscription** → **Cost analysis**
2. Filtro **Time range:** Last 7 days · **Group by:** Resource group
3. Confirme que `rg-lab-avancado` **não aparece mais** OU aparece com custo decrescente nos últimos 1-2 dias
4. Aguarde **24-48h** após cleanup → re-abra → custo deve ser R$ 0/dia
5. Salve screenshot do gráfico zerado como evidência (boa prática FinOps interna)

<!-- screenshot: cap10-passo10.8-cost-analysis-zeroed.png -->

```powershell
# 1. Confirmar RG sumiu
az group exists --name rg-lab-avancado
# Esperado: false

# 2. Confirmar SP sumiu
az ad app list --display-name "sp-github-actions-helpsphere" --query "length(@)"
# Esperado: 0

# 3. Confirmar nenhum resource órfão tag application=helpsphere-ia
az resource list --tag application=helpsphere-ia -o table
# Esperado: vazio (ou só recursos do Lab Inter que NÃO devem ser deletados)

# 4. Confirmar nenhum policy assignment scoped no RG órfão (em scope subscription)
$SubId = az account show --query id -o tsv
az policy assignment list `
  --scope "/subscriptions/$SubId" `
  --query "[?contains(scope, 'rg-lab-avancado')].name" -o tsv
# Esperado: vazio

# 5. Confirmar GitHub repo (se mantido) sem secrets
gh secret list --repo <seu-username>/helpsphere-ia
# Esperado: vazio (ou erro se repo deletado — ambos OK)

# 6. Custo último 7 dias
$StartDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere-ia')].{day:usageStart, resource:instanceName, cost:pretaxCost}" `
  -o table
# Esperado: lista decrescente, próximos R$ 0 nos últimos 1-2 dias
```

> **Linux/Mac/WSL:** troque `$SubId =` por inline `$(az account show --query id -o tsv)`, `(Get-Date).AddDays(-7).ToString("yyyy-MM-dd")` por `$(date -d "7 days ago" +%Y-%m-%d)`, e `` ` `` por `\`.

> **Economia validada — exemplo real medido na gravação:**
>
> | Estado | Custo APIM | Custo total/dia | Anualizado se esquecido |
> |---|---:|---:|---:|
> | **Lab ligado (ato 1 do dia)** | R$ 8/dia | ~R$ 10-12/dia | ~R$ 3.600-4.300 |
> | **Pós-cleanup (24h depois)** | R$ 0/dia | R$ 0/dia | R$ 0 |

> **Custo:** R$ 0 — verificações são read-only.

---

## Cleanup Foundry Hub `aifhub-apex-prod` — **NÃO DELETE** (callout crítico)

> **NÃO delete** `aifhub-apex-prod` no cleanup deste lab. Esse Hub é **compartilhado** entre **3 Labs D06**:
>
> - **Lab Intermediário (RAG):** AOAI deployments + Search index ficam embaixo dele
> - **Lab Final (Agente):** Foundry Project + agent registry ficam embaixo dele
> - **Lab Avançado (este):** referência opcional via `eval/run_eval.py` em modo Hub (não-stub)
>
> Se você deletar `aifhub-apex-prod`, quem rodar Lab Inter ou Final em seguida (mesmo aluno reciclando, ou outro aluno na mesma sub) **quebra**. O Hub vive em RG **diferente** (não em `rg-lab-avancado`) — `az group delete --name rg-lab-avancado` **não toca** o Hub.
>
> **Cleanup do Hub é decisão de fim-de-disciplina**, não fim-de-lab. Quando concluir todos os labs D06, aí sim delete o Hub (ou mantenha como portfolio).

---

## Validação end-to-end

```powershell
# 1. RG, SP, Policy, Budget, AG todos limpos
az group exists --name rg-lab-avancado                                   # false
az ad app list --display-name "sp-github-actions-helpsphere" -o tsv      # vazio
az consumption budget list --query "[?name=='budget-helpsphere-ia']"     # []
az monitor action-group list -g rg-lab-avancado 2>&1                     # ResourceGroupNotFound (OK)

# 2. GitHub limpo
gh secret list --repo <seu-username>/helpsphere-ia 2>&1                  # vazio ou erro 404

# 3. Custo zerado (após 24-48h)
$StartDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere-ia')]" -o table
# Esperado: vazio
```

> **Linux/Mac/WSL:** troque `$StartDate =` por inline `$(date -d "1 day ago" +%Y-%m-%d)`, `$EndDate =` por `$(date +%Y-%m-%d)`, e `` ` `` por `\`.

---

## Checklist final

```text
[ ] Artifacts portfolio exportados (eval/results.json + KQL CSV + APIM policy XML)
[ ] App Registration sp-github-actions-helpsphere DELETADO em Entra (incluindo soft-delete purgado)
[ ] APIM apim-helpsphere-staging (e prod se subiu) com delete iniciado em background
[ ] Budget budget-helpsphere-ia deletado
[ ] Action Group ag-helpsphere-ia-alerts deletado
[ ] 3 Policy Assignments deletadas (allowed-locations + cost-center-tag + cosmos-deny-public)
[ ] Resource Group rg-lab-avancado deletado (cascade limpou Content Safety + App Insights + Log Analytics)
[ ] az group exists retorna false
[ ] 4 GitHub Secrets deletados (TENANT, SUB, CLIENT, AOAI_KEY)
[ ] 4 GitHub Environment Variables deletadas
[ ] 2 GitHub Environments (staging + production) deletados
[ ] Repo helpsphere-ia (decisão consciente: arquivado | deletado | mantido com secrets limpos)
[ ] Cost Analysis confirma custo decrescente até R$ 0/dia (24-48h após cleanup)
[ ] Foundry Hub aifhub-apex-prod NÃO deletado (compartilhado outros labs D06)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **Cost Analysis mostra custo R$ 8 NO DIA SEGUINTE ao cleanup** — causa: Cost Management tem latência de **6-24h** + APIM cobrou prorated até o `Deleting` final (não o `Delete iniciado`) · workaround: aguarde 48h antes de declarar vazamento. Se ainda houver custo após 72h, abra ticket Azure investigando soft-delete recovery vault ou Storage com retention pago.
- ⚠️ **`az group delete` retorna sucesso mas Portal ainda mostra RG por ~10 min** — causa: cache do Portal (Resource Manager async + UI cache em camadas distintas) · workaround: hard refresh `Ctrl+F5` no Portal · `az group exists --name rg-lab-avancado` é fonte da verdade (responde imediato).
- ⚠️ **App Registration deletado mas `gh workflow run` ainda dispara CI workflow** — causa: workflow YAML continua no repo (cleanup não tocou nele); ele dispara mas falha no `azure/login@v2` com `AADSTS700016` · workaround: ou desabilite o workflow em Actions UI (ícone •••  → Disable workflow) ou delete o `.github/workflows/*.yml` em commit local + push.
- ⚠️ **`gh repo delete` falha com `Must have admin rights`** — causa: scope `delete_repo` ausente no token (default vem só com `repo`+`workflow`) · workaround: `gh auth refresh -s delete_repo,repo,workflow` (abre browser) · **anote como pendência** se o admin do tenant bloqueia auth refresh — neste caso **archive** em vez de delete (não exige scope adicional).
- ⚠️ **APIM em estado `Deleting` por mais de 1h sem completar** — causa: dependências internas (Custom Domain pendente, Diagnostic Setting com Storage Key Vault reference) · workaround: aguarde mais 30min; se passar de 2h, abra ticket Azure (raro mas acontece) · força bruta: `az apim delete --apply-force-delete` (Portal) ou aceitar custo prorated do dia se ticket Azure demorar.
- ⚠️ **Policy Assignments scoped em subscription (não RG) ficam órfãs após `az group delete`** — causa: o módulo `policy.bicep` tem `targetScope='subscription'` (do Cap 04a) → assignment vive em `/subscriptions/<ID>`, **não** em `/subscriptions/<ID>/resourceGroups/rg-lab-avancado` · workaround: explicitar no Passo 10.4 a deleção pelo nome (CLI bloco com `for NAME` cobre — siga literalmente) e validar com `az policy assignment list --scope /subscriptions/<ID> --query "[?contains(name, 'helpsphere')]"`.
- ⚠️ **Budget `budget-helpsphere-ia` "deletado" volta a aparecer no Portal após 5 min** — causa: o Budget foi deletado num scope (RG) mas estava também referenciando outro scope (sub) ou cache · workaround: confirme com `az consumption budget list --query "[?name=='budget-helpsphere-ia']"`. Se aparecer em scope sub, repita delete com `--scope "/subscriptions/<ID>"`.
- ⚠️ **Foundry Hub deletado por engano "limpando tudo"** — causa: aluno seleciona todos os RGs com prefixo `rg-` no Portal e dá Delete em massa · workaround pós-incidente: re-provisionar Hub leva ~1h + perde Search indexes do Lab Inter · prevenção: **leia o callout NÃO DELETE** acima. Hub vive em RG separado, não em `rg-lab-avancado`.

---

## Pos-cleanup — pendências mapeadas (ações fora deste lab)

- ⏸ **Aguarde 24-48h** para Cost Analysis mostrar custo zero (não é bug, é latência do Cost Management)
- ⏸ **`gh auth refresh -s delete_repo`** se você quer deletar repo (gated por browser auth do prof) — alternativa: archive
- ⏸ **Foundry Hub cleanup** quando você terminar **todos** os labs D06 (Inter + Final + Avançado)
- ⏸ **Email do Action Group** pode receber 1-2 alerts atrasados após delete (latência do Monitor) — ignore, são "fantasmas" que param em ~24h

---

## Recap do Lab Avançado

Você implementou em ~8h e cleaned em ~30 min:

✅ Repositório GitHub estruturado (Bicep + Python + workflows + eval + docs)
✅ Service Principal `sp-github-actions-helpsphere` com OIDC trust (3 federated credentials, sem secrets persistidos)
✅ Bicep parametrizado para 3 envs (dev/staging/prod) num único RG `rg-lab-avancado`
✅ GitHub Actions: CI + CD Staging + CD Prod com approval gate (3 mecanismos de proteção)
✅ APIM como gateway (JWT + rate limit + quota + audit + CORS)
✅ Content Safety pré-LLM e pós-LLM (fail-open pattern)
✅ Custom metrics LLM no Application Insights (5 metrics OpenTelemetry)
✅ 3 Azure Policies + Budget R$ 200/mês + Action Group + Cost Analysis dashboard
✅ RUNBOOK.md operacional + eval offline com stubs (v0.1.0) prontos pra Bloco C
✅ **Cleanup completo R$ 250/mês → R$ 0/mês validado**

---

**Parabéns!** Você completou o Lab Avançado D06. 🎓

**Próximos passos sugeridos:**

- Aplicar conceitos production-grade em projeto real (CI/CD OIDC + APIM + Cost Management)
- Estudar APIM Premium tier (multi-region, VNET integration, self-hosted gateway)
- Estudar Foundry Agents avançados (multi-agent collaboration, A2A protocol)
- Substituir os stubs de eval por embeddings + judge LLM (Bloco C, próxima onda)
- Implementar Logic App circuit-breaker (adiado para `v0.3.0`, ver Capítulo 08 callout)
