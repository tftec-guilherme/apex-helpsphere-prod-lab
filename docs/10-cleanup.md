# Capítulo 10 — Cleanup

> **Objetivo:** desligar **TUDO** que custa dinheiro neste lab — APIM Developer (~R$ 240/mês), Content Safety, Application Insights, Log Analytics, Action Group, Budget, Service Principal + Federated Credentials, e (gated) o repositório `helpsphere-ia` — em **ordem correta** (App Reg → APIM async → satellites → RG → GitHub artifacts) e validar que o billing **zera** em 24-48h via Cost Analysis. Sair daqui com `az group exists --name rg-lab-avancado` retornando `false` e o gráfico de custo decrescendo a R$ 0/dia.
>
> **Tempo:** 25-40 min ativos (+ ~30-45 min de wait para APIM deletar em background + ~24-48h para Cost Analysis refletir)
>
> **Escopo de cleanup:** apenas o RG **`rg-lab-avancado`** (este lab). Os RGs abaixo **NÃO DEVEM** ser tocados — pertencem a outros labs/stacks paralelas e quebram se forem deletados aqui:
>
> | RG | Stack | Por que não tocar |
> |---|---|---|
> | `rg-helpsphere-saas` | Template SaaS base (HelpSphere produção) | Compartilhado · vive em outra região (`westus3`) |
> | `rg-lab-intermediario` | Lab Intermediário (RAG fork funcional) | Reusado por outros alunos · Foundry Hub + AOAI vivem lá |
> | `rg-lab-final` | Lab Final (Agente SDK) | Stack paralela · `AGENT_URL` consumido cross-stack |
>
> Delete **somente** `rg-lab-avancado`. App Registration vive em **Entra ID** (não em RG nenhum) — limpeza separada.

---

## Cleanup é OBRIGATÓRIO — risco real ao bolso

**APIM SKU Developer custa ~R$ 240/mês ligado**, mesmo se você não fizer uma única request. É o único recurso deste lab **sem free tier**:

| Esquecido por | Custo APIM acumulado | + outros recursos | Total estimado |
|---|---:|---:|---:|
| 1 dia | R$ 8 | R$ 1-2 | **R$ 9-10** |
| 7 dias | R$ 56 | R$ 8-12 | **R$ 65-70** |
| 30 dias | **R$ 240** | R$ 30-50 | **R$ 270-290** |
| 6 meses | R$ 1.440 | R$ 200-300 | **R$ 1.640-1.740** |
| 12 meses | R$ 2.880 | R$ 400-600 | **R$ 3.280-3.480** |

> **Comportamento de billing APIM Developer:** cobra **prorated por hora** desde `provisioningState=Succeeded` — não há "free idle", não há "auto-pause". Pausar a instância **não para** o billing (única forma de parar é deletar). Content Safety e Application Insights têm free tier generoso (5 GB/mês logs · F0 5K transações/mês safety), mas APIM **não tem free tier algum**. Faça cleanup **no mesmo dia** da gravação/lab.

> **Atenção billing-em-trânsito:** Cost Management mostra dados com **6-24h de atraso**. Você delete o RG agora, mas o gráfico de custo só zera em ~24-48h. Não entre em pânico se ver R$ 5-10 ainda no dia seguinte — é runtime cobrado **antes** do delete chegar ao billing pipeline.

> **Recomendação FinOps — Cost Anomaly Alert antes do delete:** crie um Cost Anomaly Alert no escopo da subscription **antes** de rodar este capítulo. Se sobrar qualquer recurso órfão (Policy em scope subscription, Budget órfão, soft-delete de Storage, App Reg residual), o alert dispara em ~48h e você reage antes do mês fechar.

---

## ABAC pode bloquear delete RG (apenas contas `live.com` VSE pessoais)

Se você rodou parte do lab numa subscription VSE pessoal `live.com` com **ABAC condition** ativa, pode ter problema no cleanup:

- **Delete RG via Portal pode falhar** com `AuthorizationFailed: ConditionRequiresAuthorization` se a condition cobre `Microsoft.Resources/subscriptions/resourceGroups/delete`

**Workaround:** delete recurso-a-recurso (Passo 10.4 + 10.5 via Portal selecionando individual), não no nível de RG. App Registrations vivem em Entra (não na sub) e deletam normalmente. Resíduos órfãos podem precisar do admin do tenant.

---

## Pré-requisitos

- ✅ Lab rodado até onde foi possível — você está fechando para evitar billing
- ✅ `az` CLI logado na **mesma subscription** onde provisionou (`az account show` confirma)
- ✅ Acesso à conta do **email cadastrado no Action Group** (Cap 08) para confirmar parada de alerts
- ✅ (Opcional) `gh` CLI autenticado com scope **`delete_repo`** se quiser deletar o repo `helpsphere-ia` (`gh auth refresh -s delete_repo` ANTES)
- ✅ (Opcional) Resultado do eval e exports (KQL, APIM policy XML) baixados localmente se você quer manter histórico (Passo 10.1)

> **Atenção gotcha — escopo do `gh` token:** `gh auth status` mostra "Logged in" mas pode estar **sem** scope `delete_repo`. Tentar deletar repo retorna `HTTP 403: Must have admin rights to Repository`. Workaround: rodar `gh auth refresh -s delete_repo,repo,workflow` ANTES — abre browser, re-autentica com novo escopo. Se o admin do tenant bloqueia auth refresh, **archive** o repo em vez de deletar (Settings → Danger Zone → Archive).

---

## Inventário consolidado dos recursos a deletar (Capítulos 01-09)

| # | Recurso | Onde vive | Cap origem | Cobra parado? | Custo/mês ligado |
|---|---|---|---|---|---:|
| 1 | RG `rg-lab-avancado` | Subscription Azure | Cap 02 | Não (container) | R$ 0 |
| 2 | APIM `apim-helpsphere-<env>` (1 a 3 instâncias dev/staging/prod) | RG → Microsoft.ApiManagement | Cap 04a, 05, 06 | **SIM (Developer SKU)** | **~R$ 240/instância** |
| 3 | Content Safety `cs-helpsphere-<env>` | RG → CognitiveServices | Cap 04a, 07 | F0 não · **S0 sim (~R$ 5-30/mês)** | R$ 0 (F0) / R$ 5-30 (S0) |
| 4 | Application Insights `ai-helpsphere-<env>` | RG → Microsoft.Insights | Cap 04a, 07 | Quase não (≤ 5 GB free) | R$ 0-15 |
| 5 | Log Analytics workspace `log-helpsphere-<env>` | RG → Microsoft.OperationalInsights | Cap 04a, 07 | Por GB ingerido | R$ 0-25 |
| 6 | 3 Policy Assignments (allowed-locations + cost-center-tag + cosmos-deny-public) | RG → Microsoft.Authorization · **ou scope subscription** | Cap 04a, 08 | Não | R$ 0 |
| 7 | Budget `budget-helpsphere-ia` | Cost Management → escopo RG **ou subscription** | Cap 08 | Não | R$ 0 |
| 8 | Action Group `ag-helpsphere-ia-alerts` | Monitor → Alerts (Global) | Cap 08 | Não | R$ 0 |
| 9 | App Registration `sp-helpsphere-lab-<rand>` (federated) | **Microsoft Entra ID** (NÃO no RG) | Cap 03 (opcional) | Não | R$ 0 |
| 10 | Federated Credentials (main / pull_request / production) | Dentro do App Reg #9 | Cap 03 (opcional) | Não | R$ 0 |
| 11 | (Se Cap 03 rodado) GitHub Secrets/Variables/Environments | Repo `helpsphere-ia` | Cap 03 (opcional) | — | — |
| 12 | (Opcional) Repo `helpsphere-ia` | GitHub (fora do Azure) | Cap 02 | — | — |
| 13 | Foundry Hub `aifhub-apex-prod` (referência narrativa em Cap 09) | RG **diferente** (compartilhado outros labs) | Cap 09 (referência) | Sim (varia) | **NÃO DELETE — fora do escopo** |

> **Crítico — itens fora do RG:** App Registration (#9-10) vive em **Entra ID**, **não** no RG. Deletar `rg-lab-avancado` **NÃO remove** o SP — fica órfão até você ir em Entra → App registrations → Delete. Mesmo aplicável a Policy Assignments/Budgets em scope subscription (não RG) — `az group delete` **não toca** eles. Validação final no Passo 10.8.

> **Sobre Cap 03 + GitHub Actions (linhas 9-12 da tabela):** o Cap 05 deste lab é Portal+CLI manual, sem CI/CD automatizado. Se você seguiu o **Cap 03 opcional** (Service Principal federated para CI/CD futuro), os recursos das linhas 9-12 existem e precisam ser limpos no Passo 10.2 + 10.6 + 10.7. Se você pulou o Cap 03, todos esses recursos **não existem** — pule esses passos.

> **Por que ordem App Reg → APIM async → satellites → RG → GitHub?** (1) App Registration deletado primeiro **invalida tokens em uso** — qualquer automação remanescente falha em vez de criar recurso novo durante cleanup. (2) APIM em paralelo (delete demorado, ~30-45 min async). (3) Satellites (Budget, Action Group, Policies) são leves e gratuitos — limpam rápido. (4) RG cascateia o resto. (5) GitHub é limpeza local sem dependências cloud.

---

## Passo 10.1 — Exportar artifacts que valem manter (5 min — opcional mas recomendado)

Antes de detonar tudo, baixe localmente o que tem valor pedagógico/portfolio:

**No Portal Azure + clone local:**

1. **eval/results.json:** se você rodou `eval/run_eval.py` (Cap 09), o arquivo está em `eval/results.json` no clone local — copie para sua pasta de portfolio antes de deletar o clone
2. **App Insights queries (KQL salvas):** Portal → `ai-helpsphere-<env>` → Logs → query salva `Tokens por minuto (custom metric)` → botão **Export** → **CSV**. Repita para as 4 queries do Capítulo 07
3. **Cost Analysis snapshot:** Portal → `rg-lab-avancado` → Cost analysis → **Daily costs (last 7 days)** → exportar CSV
4. **APIM policy XML:** APIM → APIs → HelpSphere Agent API → Policy editor → copiar todo o XML para `docs/portfolio/apim-policy.xml` no clone local
5. **Bicep templates + parameters:** clone local `infra/main.bicep` + `infra/envs/*.parameters.json` já são portfolio — copie a pasta `infra/` inteira para `$HOME/portfolio/helpsphere-ia-snapshot/`

```powershell
# PowerShell — backup local antes do cleanup
New-Item -ItemType Directory -Path "$HOME/portfolio/helpsphere-ia-cleanup-snapshot" -Force | Out-Null
Set-Location "$HOME/portfolio/helpsphere-ia-cleanup-snapshot"

# Copiar artifacts locais do clone (ajuste o path)
Copy-Item -Recurse -Force <caminho-clone>/infra ./infra
Copy-Item -Force <caminho-clone>/eval/results.json ./results.json 2>$null

# Exportar últimos custos como TSV
$StartDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere')].{date:usageStart, resource:instanceName, cost:pretaxCost}" `
  -o tsv | Out-File -FilePath usage-pre-cleanup.tsv -Encoding utf8
```

> **Alternativa Linux/Mac/WSL (bash):** troque `New-Item` por `mkdir -p`, `Set-Location` por `cd`, `Copy-Item -Recurse` por `cp -r`, `$HOME` por `~`, `(Get-Date).AddDays(-30).ToString("yyyy-MM-dd")` por `$(date -d "30 days ago" +%Y-%m-%d)`, `` ` `` por `\`, e `| Out-File` por `> file`.

> **Custo:** R$ 0 — exports são read-only.

> **Nota pedagógica — por que portfolio matters?** Em entrevista de cargo cloud-architect/SRE, mostrar Bicep templates parametrizados + KQL custom + APIM policy XML produz mais sinal que qualquer cert. Lab terminou — artefato fica.

---

## Passo 10.2 — Deletar App Registration federated (Entra ID — primeiro!)

> **Pule este passo se você não seguiu o Cap 03 opcional** (Service Principal Federated). Sem Cap 03 não há App Registration nem Federated Credentials para limpar — siga direto para Passo 10.3.

Por que primeiro (quando Cap 03 foi seguido)? Token federated em uso para de funcionar instantaneamente. Qualquer automação remanescente falha em `azure/login@v2` com `AADSTS700016` em vez de criar recurso novo durante o cleanup. Federated Credentials não vivem em RG nenhum — `az group delete` **não toca** elas.

**No Portal Azure (Microsoft Entra ID):**

1. Barra superior → buscar **"Microsoft Entra ID"** → menu lateral → **App registrations**
2. Aba **All applications** → filtre por `sp-helpsphere-lab-` → clique no nome (terá um `<rand>` no final, ex.: `sp-helpsphere-lab-a1b2c3`)
3. Tab **Overview** → topo → **Delete**
4. Modal de confirmação → marque **"I understand the implications of deleting this app registration"** → **Delete**
5. (Opcional, mas recomendado) Aba lateral → **App registrations** → **Deleted applications** → mesmo app → **Permanently delete**

<!-- screenshot: cap10-passo10.2-delete-app-registration.png -->

> **Alternativa via Azure CLI (limpa as 2 entidades — App + SP — e federated credentials cascade):**
>
> ```powershell
> # Ajuste o prefixo se você usou outro display-name no Cap 03
> $AppId = az ad app list --display-name "sp-helpsphere-lab-*" --query "[0].appId" -o tsv
> if (-not $AppId) { Write-Host "(nenhum App Reg encontrado — Cap 03 não rodado, OK)"; return }
>
> # 1. Deletar SP (instância no tenant)
> az ad sp delete --id $AppId 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(SP já removido — OK)" }
>
> # 2. Deletar App Registration (definição) — federated credentials morrem junto
> az ad app delete --id $AppId
>
> # 3. Confirmar que sumiu
> az ad app list --display-name "sp-helpsphere-lab-*" --query "length(@)"
> # Esperado: 0
> ```
>
> **Alternativa Linux/Mac/WSL (bash):** troque `$AppId =` por `APP_ID=$(...)`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, e `Write-Host` por `echo`.

> **Custo:** R$ 0 — App Registrations e Federated Credentials são gratuitos no Entra. Deletar não tem fee.

> **Nota pedagógica — soft-delete em Entra é 30 dias:** após `Delete`, o App fica em **Deleted applications** por 30 dias e pode ser restaurado. Em prod isso é feature (recovery de delete acidental). Em lab que terminou, **Permanently delete** garante que não fica resíduo no Entra. Importante se a sub é compartilhada.

---

## Passo 10.3 — Deletar APIM (PRIORIDADE ALTA — R$ 240/mês cada instância)

APIM Developer demora **~30-45 min** para deletar mesmo via `--no-wait` (o provisioning de criar é similar — assim como leva ~30-45 min para criar, leva similar para deletar). **Não cancele mid-flight** — você arrisca recurso ficar em estado inconsistente. Inicie agora e libere o cleanup do resto em paralelo.

> **Por que prioridade alta:** APIM é o **único recurso pago sem free tier** deste lab — R$ 240/mês cada instância ligada. Se você deployou `dev` + `staging` + `prod` (3 instâncias), são **R$ 720/mês** se esquecido. Esse passo sozinho representa >95% da economia do cleanup.

**No Portal Azure:**

1. Buscar **"API Management services"** → localizar instâncias com prefixo `apim-helpsphere-` (pode haver 1, 2 ou 3 conforme envs deployados)
2. Para CADA instância: clicar no nome → tab **Overview** → topo → **Delete**
3. Confirmação → digitar nome do APIM → marque **Apply force delete** (necessário se algum subscription/product ficou em estado inconsistente) → **Delete**
4. Notificação no sino: "Deleting api management service..." (~30-45 min para concluir, roda async)

<!-- screenshot: cap10-passo10.3-apim-delete.png -->

> **Alternativa via Azure CLI (paralelo + async — todas as instâncias de uma vez):**
>
> ```powershell
> # 1. Lista todas as instâncias APIM no RG
> $Apims = az apim list --resource-group rg-lab-avancado --query "[].name" -o tsv
>
> if (-not $Apims) { Write-Host "(nenhum APIM encontrado — OK)" }
>
> # 2. Dispara delete async para cada — você segue para Passo 10.4 imediatamente
> foreach ($Name in $Apims -split "`n") {
>   if ($Name) {
>     Write-Host "Disparando delete async: $Name"
>     az apim delete `
>       --name $Name `
>       --resource-group rg-lab-avancado `
>       --no-wait `
>       --yes
>   }
> }
>
> # 3. Status (opcional — checa periodicamente)
> az apim list --resource-group rg-lab-avancado --query "[].{name:name, state:provisioningState}" -o table
> # Durante delete: state=Deleting · após: lista vazia
> ```
>
> **Alternativa Linux/Mac/WSL (bash):** troque `$Apims =` por `APIMS=$(...)`, `foreach`/`-split` por `for NAME in $APIMS; do ... done`, `` ` `` por `\`, e `Write-Host` por `echo`.

> **Custo:** zero adicional — delete é gratuito. Billing **para de cobrar** quando `provisioningState=Deleting` (não espera pelo `Deleted` final). Você economiza desde o minuto que dispara o delete.

> **Nota pedagógica — por que `Apply force delete` / `--yes`?** APIM tem dependências em Diagnostic Settings, Custom Domain certs, Backups e Subscriptions internos. Em estados inconsistentes (provisão falhada, custom domain pendente, certificate expirado), delete normal trava em loop esperando dependency cleanup. Force delete pula validações pré-flight. Em prod real você investigaria o estado antes — em lab é seguro forçar.

---

## Passo 10.4 — Deletar Budget + Action Group + Policy Assignments + Cost Anomaly Alerts (não cobram, mas limpam)

Esses recursos **não cobram parados** — limpá-los é higiene de inventário, não economia. **Atenção especial:** Budget e Policy Assignment podem ter sido criados em scope **subscription** (não RG). Se foram, **sobrevivem** ao `az group delete` no Passo 10.5 e ficam órfãos para sempre.

**No Portal Azure (Cost Management → Budgets):**

1. Buscar **"Cost Management + Billing"** → menu lateral → **Cost Management** → **Budgets**
2. Filtre por **escopo `rg-lab-avancado` E escopo `subscription`** (verifique os DOIS) → localize `budget-helpsphere-ia` → clicar
3. Topo → **Delete budget** → confirmar
4. (Se você criou Cost Anomaly Alert no início do Passo 10) → mesmo menu → **Cost alerts** → delete o alert manualmente

**No Portal Azure (Monitor → Action groups):**

5. Buscar **"Monitor"** → menu lateral → **Alerts** → **Action groups**
6. Localize `ag-helpsphere-ia-alerts` → marque checkbox → topo → **Delete**

**No Portal Azure (Policy → Authoring → Assignments):**

7. Buscar **"Policy"** → **Authoring** → **Assignments**
8. Filtre por scope `rg-lab-avancado` **E por scope subscription** (3 assignments podem estar em qualquer um dos dois): `allowed-locations-<hash>`, `helpsphere-cost-center-tag-required-<hash>`, `cosmos-deny-public-<hash>`
9. Selecione cada uma → menu **...** → **Delete assignment**

> **Alternativa via Azure CLI (cobre RG E subscription scope):**
>
> ```powershell
> $SubId = az account show --query id -o tsv
>
> # 1. Budget — tenta deletar no scope RG E no scope subscription
> az consumption budget delete --budget-name budget-helpsphere-ia 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(budget no scope subscription já removido ou inexistente)" }
> az consumption budget delete `
>   --budget-name budget-helpsphere-ia `
>   --resource-group rg-lab-avancado 2>$null
>
> # 2. Action Group
> az monitor action-group delete `
>   --name ag-helpsphere-ia-alerts `
>   --resource-group rg-lab-avancado 2>$null
> if ($LASTEXITCODE -ne 0) { Write-Host "(action group já removido)" }
>
> # 3. Policy assignments — RG scope
> $ScopeRg = "/subscriptions/$SubId/resourceGroups/rg-lab-avancado"
> $NamesRg = az policy assignment list --scope $ScopeRg --query "[].name" -o tsv
> foreach ($Name in $NamesRg -split "`n") {
>   if ($Name) {
>     az policy assignment delete --name $Name --scope $ScopeRg
>     Write-Host "Deleted (RG scope): $Name"
>   }
> }
>
> # 4. Policy assignments — SUBSCRIPTION scope (críticos! sobrevivem ao az group delete)
> $ScopeSub = "/subscriptions/$SubId"
> $NamesSub = az policy assignment list --scope $ScopeSub --query "[?contains(name, 'helpsphere') || contains(displayName, 'helpsphere')].name" -o tsv
> foreach ($Name in $NamesSub -split "`n") {
>   if ($Name) {
>     az policy assignment delete --name $Name --scope $ScopeSub
>     Write-Host "Deleted (SUB scope — crítico!): $Name"
>   }
> }
>
> # 5. Confirmar ambos scopes vazios
> az policy assignment list --scope $ScopeRg --query "length(@)"  # esperado: 0
> az policy assignment list --scope $ScopeSub --query "length([?contains(name, 'helpsphere')])"  # esperado: 0
> ```
>
> **Alternativa Linux/Mac/WSL (bash):** troque `$Var =` por `VAR=$(...)`, `` ` `` por `\`, `2>$null` por `2>/dev/null`, `$LASTEXITCODE` por `$?`, `Write-Host` por `echo`, e o `foreach`/`-split` por `for NAME in $(...); do ... done`.

> **Custo:** R$ 0 — todos os 4 (Budget, Action Group, Policy Assignment, Cost Anomaly Alert) são gratuitos. Cleanup é organizacional **mas crítico** para Policy/Budget em scope subscription — eles **não cascadam** com RG delete.

> **Nota pedagógica — Policy Assignments cascadam com RG delete?** **Apenas se o assignment scope é o próprio RG.** Se foi criado no scope `subscription` (ex.: módulo Bicep com `targetScope='subscription'`), **NÃO** some com `az group delete`. Sempre verifique `az policy assignment list --scope /subscriptions/<ID>` no Passo 10.8 final. Mesma lógica para Budget — pode estar em scope subscription e ficar órfão.

---

## Passo 10.5 — Deletar Resource Group `rg-lab-avancado` (cascade dos demais recursos)

Com APIM já em deletion (Passo 10.3) e satellites limpos (Passo 10.4), agora o RG vai cascatear o resto: Content Safety, App Insights, Log Analytics, restos de deployment metadata.

> ⚠️ **NÃO TOQUE OUTROS RGs.** Confirme **antes de clicar Delete** que você está em `rg-lab-avancado` — não em `rg-helpsphere-saas` (template SaaS), `rg-lab-intermediario` (Lab Inter compartilhado) ou `rg-lab-final` (Lab Final paralelo). Aluno selecionando "todos os RGs com prefixo rg-" no Portal e dando Delete em massa é gotcha clássico — recuperação leva horas.

**No Portal Azure:**

1. Buscar **"Resource groups"** → localizar **exatamente** `rg-lab-avancado` (sem typos) → clicar no nome
2. Tab **Overview** → topo → **Delete resource group**
3. Painel à direita pede confirmação:
   - **Type the resource group name to confirm:** digitar `rg-lab-avancado`
   - Marque **Apply force delete** (recomendado — alguns recursos podem estar em estado inconsistente após 30+ min de APIM)
4. **Delete**
5. Notificação no sino: "Deleting resource group rg-lab-avancado" (~30-45 min se APIM ainda não terminou; ~5 min se já estava deletado)

<!-- screenshot: cap10-passo10.5-delete-rg.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> # SEGURANÇA: confirmação dupla antes do delete
> $RgName = "rg-lab-avancado"
> Write-Host "Você está prestes a DELETAR $RgName. Outros RGs deste tenant:"
> az group list --query "[].name" -o tsv
> Read-Host "Digite '$RgName' para confirmar"
>
> az group delete --name $RgName --yes --no-wait
>
> # Polling
> while ((az group exists --name $RgName) -eq "true") {
>   Write-Host "$(Get-Date -Format HH:mm:ss) — RG ainda existe, aguardando..."
>   Start-Sleep -Seconds 60
> }
> Write-Host "rg-lab-avancado deletado"
> ```
>
> **Alternativa Linux/Mac/WSL (bash):** troque o `while` por `while az group exists --name rg-lab-avancado | grep -q true; do`, `Read-Host` por `read -p`, `Write-Host` por `echo`, `Get-Date -Format HH:mm:ss` por `$(date +%H:%M:%S)`, e `Start-Sleep -Seconds 60` por `sleep 60`.

> **Custo:** zero adicional — delete é gratuito. Billing de RG é **assíncrono em até 24h** — o gráfico de Cost Management pode mostrar custo residual mesmo após o `az group exists` retornar `false`. Aguarde 24-48h.

> **Atenção Log Analytics linked workspace:** se o Log Analytics `log-helpsphere-<env>` foi configurado como **workspace compartilhado** entre múltiplos labs (Inter/Final/Avançado), deletar o RG **NÃO** deleta o workspace se ele vive em outro RG. Confirme com `az monitor log-analytics workspace list -g rg-lab-avancado` ANTES do delete. Se o workspace está em RG diferente, ele sobrevive (correto — outros labs ainda usam).

> **Atenção connection strings órfãs:** apps externos (Lab Final, Lab Inter) que apontavam para `AGENT_FUNCTION_URL` ou `AOAI_ENDPOINT` provisionados aqui ficam **quebrados** após o delete. Se você reusa esses URLs em outros labs ativos, **atualize-os primeiro** ou aceite o break temporário.

> **Nota pedagógica — `Apply force delete` perigoso em prod?** Em prod sim — alguns recursos têm **lock** ou **soft-delete** que force ignora (ex.: Storage com soft-delete blob de 30 dias **fica em backup pago** mesmo após RG delete). Em lab é seguro porque você não criou Storage com soft-delete, nem Key Vault com purge protection. **Stop-loss prod:** sempre `az resource list -g <RG>` antes de force delete, valida que não há nada com retention pago.

> **Reminder ABAC:** se o delete falha com `ConditionRequiresAuthorization` numa sub `live.com`, vá recurso-a-recurso (Portal → cada recurso → Delete). Workaround sub-ótimo, mas não há outro caminho com ABAC ativo.

---

## Passo 10.6 — Cleanup GitHub Secrets, Environment Variables e Environments (apenas se Cap 03 foi seguido)

> **Pule este passo se você não seguiu o Cap 03 opcional.** Sem CI/CD via GitHub Actions, não há secrets/variables/environments para limpar — siga direto para Passo 10.7.

Mesmo com SP deletado (Passo 10.2), os 4 secrets + 4 vars + 2 environments ficam no repo. Limpar reduz superfície (alguém forka, adiciona um workflow malicioso e vê os secrets — improvável mas possível). Especialmente crítico para `AOAI_API_KEY` — essa chave continua válida mesmo após delete do SP (foi provisionada em outro lab/RG).

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

## Passo 10.8 — Verificação final + economia validada (validação visual obrigatória)

**No Portal Azure (Cost Management) — validação VISUAL obrigatória:**

1. Buscar **"Cost Management"** → escopo **subscription** → **Cost analysis**
2. Filtro **Time range:** Last 7 days · **Group by:** Resource group
3. Confirme **visualmente** que `rg-lab-avancado` **não aparece mais** OU aparece com gráfico **decrescente** nos últimos 1-2 dias
4. Aguarde **24-48h** após cleanup → re-abra → gráfico deve mostrar **R$ 0,00 nos últimos 2 dias consecutivos**
5. Salve screenshot do gráfico zerado como evidência (boa prática FinOps — comprova ao financeiro que cleanup funcionou)

<!-- screenshot: cap10-passo10.8-cost-analysis-zeroed.png -->

```powershell
# 1. Confirmar RG sumiu
az group exists --name rg-lab-avancado
# Esperado: false

# 2. Confirmar SP sumiu (se Cap 03 rodado)
az ad app list --display-name "sp-helpsphere-lab-*" --query "length(@)"
# Esperado: 0

# 3. Confirmar OUTROS RGs intactos (defesa em profundidade — não deletou por engano)
az group exists --name rg-helpsphere-saas       # Esperado: true (se existia antes)
az group exists --name rg-lab-intermediario     # Esperado: true (se existia antes)
az group exists --name rg-lab-final             # Esperado: true (se existia antes)

# 4. Confirmar nenhum resource órfão com tag application=helpsphere-ia
az resource list --tag application=helpsphere-ia -o table
# Esperado: vazio (ou só recursos de outros labs que NÃO devem ser deletados)

# 5. Confirmar nenhum policy assignment órfão em scope subscription
$SubId = az account show --query id -o tsv
az policy assignment list `
  --scope "/subscriptions/$SubId" `
  --query "[?contains(name, 'helpsphere') || contains(scope, 'rg-lab-avancado')].name" -o tsv
# Esperado: vazio

# 6. Confirmar nenhum budget órfão
az consumption budget list --query "[?contains(name, 'helpsphere')].name" -o tsv
# Esperado: vazio

# 7. Confirmar GitHub repo (se mantido e Cap 03 rodado) sem secrets
gh secret list --repo <seu-username>/helpsphere-ia 2>$null
# Esperado: vazio (ou erro 404 se repo deletado — ambos OK)

# 8. Custo último 7 dias
$StartDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere')].{day:usageStart, resource:instanceName, cost:pretaxCost}" `
  -o table
# Esperado: lista decrescente, próximos R$ 0 nos últimos 1-2 dias
```

> **Alternativa Linux/Mac/WSL (bash):** troque `$SubId =` por inline `$(az account show --query id -o tsv)`, `(Get-Date).AddDays(-7).ToString("yyyy-MM-dd")` por `$(date -d "7 days ago" +%Y-%m-%d)`, e `` ` `` por `\`.

> **Economia validada — exemplo real medido em smoke run:**
>
> | Estado | Custo APIM/dia | Custo total/dia | Custo anualizado se esquecido |
> |---|---:|---:|---:|
> | **Lab ligado (1 instância APIM Developer)** | R$ 8/dia | ~R$ 10-12/dia | ~R$ 3.600-4.300 |
> | **Lab ligado (3 instâncias dev+staging+prod)** | R$ 24/dia | ~R$ 30-35/dia | ~R$ 10.800-12.600 |
> | **Pós-cleanup (após 24-48h)** | R$ 0/dia | R$ 0/dia | **R$ 0** |
>
> Cleanup em 25-40 min ativos = economia anual potencial de R$ 3.600-12.600.

> **Custo:** R$ 0 — verificações são read-only.

---

## Foundry Hub e Lab Final — **NÃO DELETE** (callout crítico)

> **NÃO delete recursos fora de `rg-lab-avancado`** no cleanup deste lab:
>
> - **Foundry Hub `aifhub-apex-prod`** vive em RG diferente (`rg-lab-intermediario`) — é **compartilhado** entre Lab Intermediário (RAG), Lab Final (Agente) e este lab (referência narrativa em Cap 09). Se você deletar, quem rodar Lab Inter ou Final em seguida **quebra**.
> - **Endpoint do Lab Final (`AGENT_URL`)** é stack paralela em `rg-lab-final` (East US 2) — Cap 09 deste lab apenas **consome** esse endpoint via HTTP. NÃO toque `rg-lab-final`.
> - **RG `rg-helpsphere-saas` (template SaaS base, West US 3)** é a stack do app HelpSphere fora-de-lab. Pode estar provisionado por outro motivo. NÃO toque.
>
> `az group delete --name rg-lab-avancado` **não toca** nenhum desses — é seguro. Mas se você deletar manualmente por engano, recuperação leva 1-2h (re-provisionar Hub + re-indexar Search + re-deploy Agent).
>
> **Cleanup do Hub é decisão de fim-de-trilha**, não fim-de-lab. Quando concluir **todos** os labs que usam o Hub, aí sim delete o Hub (ou mantenha como portfolio).

---

## Validação end-to-end

```powershell
# 1. RG, SP, Policy, Budget, AG todos limpos
az group exists --name rg-lab-avancado                                  # false
az ad app list --display-name "sp-helpsphere-lab-*" -o tsv              # vazio (se Cap 03 rodado)
az consumption budget list --query "[?name=='budget-helpsphere-ia']"    # []
az monitor action-group list -g rg-lab-avancado 2>&1                    # ResourceGroupNotFound (OK)

# 2. Outros RGs intactos
az group exists --name rg-helpsphere-saas                               # true (se existia)
az group exists --name rg-lab-intermediario                             # true (se existia)
az group exists --name rg-lab-final                                     # true (se existia)

# 3. GitHub limpo (se Cap 03 rodado e repo mantido)
gh secret list --repo <seu-username>/helpsphere-ia 2>&1                 # vazio ou erro 404

# 4. Custo zerado (após 24-48h)
$StartDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")
az consumption usage list `
  --start-date $StartDate `
  --end-date $EndDate `
  --query "[?contains(instanceName, 'helpsphere')]" -o table
# Esperado: vazio
```

> **Alternativa Linux/Mac/WSL (bash):** troque `$StartDate =` por inline `$(date -d "1 day ago" +%Y-%m-%d)`, `$EndDate =` por `$(date +%Y-%m-%d)`, e `` ` `` por `\`.

---

## Checklist final

```text
[ ] Artifacts portfolio exportados (Bicep infra/ + KQL CSV + APIM policy XML + eval results se existir)
[ ] (Se Cap 03 rodado) App Registration sp-helpsphere-lab-<rand> DELETADO em Entra (incluindo soft-delete purgado)
[ ] Todas as instâncias APIM apim-helpsphere-* com delete iniciado em background (R$ 240/mês cada)
[ ] Budget budget-helpsphere-ia deletado (scope RG E scope subscription verificados)
[ ] Action Group ag-helpsphere-ia-alerts deletado
[ ] 3 Policy Assignments deletadas (allowed-locations + cost-center-tag + cosmos-deny-public) — RG E subscription scope verificados
[ ] Resource Group rg-lab-avancado deletado (cascade limpou Content Safety + App Insights + Log Analytics)
[ ] az group exists --name rg-lab-avancado retorna false
[ ] rg-helpsphere-saas / rg-lab-intermediario / rg-lab-final INTACTOS (defesa em profundidade)
[ ] (Se Cap 03 rodado) GitHub Secrets/Variables/Environments deletados
[ ] (Opcional) Repo helpsphere-ia (decisão consciente: arquivado | deletado | mantido sem secrets)
[ ] Cost Analysis confirma gráfico decrescente até R$ 0/dia nos últimos 2 dias (24-48h após cleanup)
[ ] Cost Anomaly Alert configurado para capturar resíduos pós-cleanup
[ ] Foundry Hub aifhub-apex-prod NÃO deletado (compartilhado outros labs / stacks paralelas)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **APIM Developer cobra R$ 240/mês mesmo parado** — causa: SKU Developer não tem free tier nem pause; cobra prorated por hora desde `provisioningState=Succeeded` · workaround: deletar é a **única** forma de parar o billing — pausa/stop não existe para Developer.
- ⚠️ **APIM leva 30-45 min para deletar (similar ao tempo de criar)** — causa: APIM é multi-tenant cluster com setup/teardown async; força bruta `--apply-force-delete` reduz para ~20 min em alguns casos · workaround: dispare delete em background com `--no-wait` e siga limpando o resto em paralelo · **não cancele mid-flight** com Ctrl+C — recurso fica em estado inconsistente.
- ⚠️ **Content Safety S0 cobra parado (~R$ 5-30/mês)** — causa: tier Standard tem custo fixo por instância mesmo sem requests; F0 free é 5K transações/mês mas **esgota rápido** em testing iterativo (cada PII check + each safety check = transação separada) · workaround: prefira F0 em lab; se forçou para S0 (testes de capacidade) confirme delete no Cap 07/Passo 10.5 · sempre deletar S0 mesmo se não usou.
- ⚠️ **Cost Analysis mostra custo R$ 5-10 NO DIA SEGUINTE ao cleanup** — causa: Cost Management tem latência de **6-24h** + APIM cobrou prorated até o `Deleting` final (não o "Delete iniciado") + billing pipeline é async em até 24h · workaround: aguarde 48h antes de declarar vazamento; se ainda houver custo após 72h, abra ticket Azure investigando soft-delete recovery vault ou Storage com retention pago.
- ⚠️ **Policy Assignments scoped em subscription (não RG) ficam órfãs após `az group delete`** — causa: se módulo Bicep tem `targetScope='subscription'`, assignment vive em `/subscriptions/<ID>`, **não** em `/subscriptions/<ID>/resourceGroups/rg-lab-avancado` · workaround: o Passo 10.4 cobre AMBOS os scopes — siga o bloco CLI literalmente (loops `$NamesRg` E `$NamesSub`) e valide com `az policy assignment list --scope /subscriptions/<ID> --query "[?contains(name, 'helpsphere')]"` no Passo 10.8.
- ⚠️ **Budget `budget-helpsphere-ia` "deletado" volta a aparecer no Portal após 5 min** — causa: Budget pode ser criado em scope RG **ou** subscription; deletar num scope não toca o outro · workaround: confirme com `az consumption budget list --query "[?name=='budget-helpsphere-ia']"` e re-rode delete em ambos os scopes (Passo 10.4 cobre).
- ⚠️ **Service Principal federated NÃO é deletado via `az group delete`** — causa: App Registrations vivem em Entra ID (tenant), não em Resource Group · workaround: Passo 10.2 deleta explicitamente · skipping isso = SP fica órfão para sempre (gratuito, mas insiders security audit reclama).
- ⚠️ **`az group delete` retorna sucesso mas Portal ainda mostra RG por ~10 min** — causa: cache do Portal (Resource Manager async + UI cache em camadas distintas) · workaround: hard refresh `Ctrl+F5` no Portal · `az group exists --name rg-lab-avancado` é fonte da verdade (responde imediato).
- ⚠️ **Connection strings órfãs em apps externos quebram após delete** — causa: Function App de outro lab apontando para `AGENT_FUNCTION_URL` ou `AOAI_ENDPOINT` provisionados aqui ficam com 500 errors · workaround: antes do delete, identifique apps que consumiam esses endpoints (`grep` no código local) e atualize-os para outros endpoints OU aceite o break temporário se eles não estão em uso.
- ⚠️ **Log Analytics linked workspace deletado por engano quebra outros labs** — causa: se você apontou o `log-helpsphere-<env>` para um workspace shared (em outro RG), `az group delete` deste lab tenta deletar a referência mas o workspace original (compartilhado) sobrevive · workaround: confirme com `az monitor log-analytics workspace list -g rg-lab-avancado` ANTES; se a lista é vazia, o workspace vive em outro RG e o cleanup é seguro.
- ⚠️ **Foundry Hub deletado por engano "limpando tudo"** — causa: aluno seleciona todos os RGs com prefixo `rg-` no Portal e dá Delete em massa · workaround pós-incidente: re-provisionar Hub leva ~1h + perde Search indexes de outros labs · **prevenção:** leia o callout NÃO DELETE acima; Hub vive em `rg-lab-intermediario`, não em `rg-lab-avancado`; o Passo 10.5 inclui confirmação dupla por nome no bloco CLI.
- ⚠️ **`gh repo delete` falha com `Must have admin rights`** — causa: scope `delete_repo` ausente no token (default vem só com `repo`+`workflow`) · workaround: `gh auth refresh -s delete_repo,repo,workflow` (abre browser) · se admin do tenant bloqueia auth refresh, **archive** em vez de delete (Settings → Danger Zone → Archive, não exige scope adicional).
- ⚠️ **APIM em estado `Deleting` por mais de 1h sem completar** — causa: dependências internas (Custom Domain pendente, Diagnostic Setting com Storage/Key Vault reference, certificate expirado) · workaround: aguarde mais 30min; se passar de 2h, abra ticket Azure (raro mas acontece); última opção: `--apply-force-delete` no Portal pula validações pré-flight.

---

## Pos-cleanup — pendências mapeadas (ações fora deste lab)

- ⏸ **Aguarde 24-48h** para Cost Analysis mostrar gráfico zerado (não é bug, é latência do Cost Management)
- ⏸ **Configure Cost Anomaly Alert** para subscription se ainda não fez — captura resíduos órfãos automaticamente
- ⏸ **`gh auth refresh -s delete_repo`** se você quer deletar repo (gated por browser auth) — alternativa: archive
- ⏸ **Foundry Hub cleanup** quando você terminar **todos** os labs que usam o Hub (decisão de fim-de-trilha, não fim-de-lab)
- ⏸ **Email do Action Group** pode receber 1-2 alerts atrasados após delete (latência do Monitor) — ignore, são "fantasmas" que param em ~24h
- ⏸ **Connection strings órfãs em apps externos** — se algum Function App de outro lab apontava para endpoints provisionados aqui, atualize a configuração lá

---

## Recap do Lab Avançado

Você implementou em ~8h e fez cleanup em ~30 min:

- Repositório GitHub estruturado (Bicep + Python + eval + docs)
- (Opcional Cap 03) Service Principal federated com OIDC trust (sem secrets persistidos)
- Bicep parametrizado para 3 envs (dev/staging/prod) num único RG `rg-lab-avancado`
- Deploy via Portal+CLI manual (`az deployment group create`) sem CI/CD automatizado
- APIM como gateway (JWT + rate limit + quota + audit + CORS)
- Content Safety pré-LLM e pós-LLM (fail-open pattern)
- Custom metrics LLM no Application Insights (5 metrics OpenTelemetry)
- 3 Azure Policies + Budget + Action Group + Cost Analysis dashboard
- RUNBOOK.md operacional + eval offline com stubs
- **Cleanup completo: R$ 240-720/mês → R$ 0/mês validado** (1-3 instâncias APIM)

---

**Parabéns!** Você completou o Lab Avançado.

**Próximos passos sugeridos:**

- Aplicar conceitos production-grade em projeto real (CI/CD OIDC + APIM + Cost Management)
- Estudar APIM Premium tier (multi-region, VNET integration, self-hosted gateway)
- Estudar Foundry Agents avançados (multi-agent collaboration, A2A protocol)
- Substituir os stubs de eval por embeddings + judge LLM
- Implementar Logic App circuit-breaker (ver Capítulo 08 callout)
