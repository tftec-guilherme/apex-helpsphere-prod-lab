# Capítulo 03 — Service Principal com Federated Credentials

> **Objetivo:** criar o **App Registration** + **Service Principal** `sp-github-actions-helpsphere`, atribuir role **Contributor** scoped no `rg-lab-avancado`, configurar **3 federated credentials** (main branch + pull_request + environment:production) e cravar os 4 GitHub Secrets (`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AOAI_API_KEY`) — deixando o repo `helpsphere-ia` pronto para autenticar no Azure via OIDC sem nenhum client secret armazenado.
>
> **Tempo:** 35-50 min (dobra se cair em ABAC e tiver que pivotar de subscription — R6)
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` semi-expandido) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Parte 1 (Passos 1.3-1.5) + R6 disclaimer canônico

---

## DISCLAIMER R6 (HIGH — bloqueante) — ABAC Condition bloqueia fork-by-student

CI/CD via Federated Service Principal **NÃO funciona** em subscriptions com **ABAC condition** ativa por default. Este Capítulo é o canário do lab inteiro: se ABAC bloqueia aqui, **bloqueia tudo dali pra frente** (Capítulos 04-09 dependem do SP federado funcionar).

### Quando isso acontece

- **Visual Studio Enterprise (`live.com`):** vem com ABAC default que bloqueia role assignments via SP federado
- **Subscriptions corporate com Conditional Access policy** restritiva
- **Free Trial USD 200:** sem ABAC, mas sem PAYG → Azure OpenAI bloqueia mesmo se SP funcionar

### Subs que funcionam vs que falham

| Tipo | CI/CD funciona? | Observação |
|---|---|---|
| **TFTEC subscription** (cenário ideal) | ✅ SIM | Cenário recomendado pra alunos |
| **PAYG sem ABAC** | ✅ SIM | Cartão de crédito, ~R$ 35-45 no lab inteiro |
| **Subscription corporate** sem CA restritiva | ✅ SIM | Confirme com TI antes |
| Visual Studio Enterprise (`live.com`) | ❌ NÃO | ABAC default ATIVO |
| Free Trial USD 200 | ❌ NÃO | Sem PAYG → AOAI bloqueia |

> **Atenção breaking — você JÁ validou no Capítulo 01.4.** O teste de ABAC com SP descartável foi feito no Passo 1.4. Se passou lá, vai passar aqui. Se não fez, **volte ao Capítulo 01 antes de seguir** — descobrir ABAC ativo só após criar SP + 3 federated credentials + 4 secrets é desperdício de ~30 min.

> **Plano B (recap) se ABAC estiver ativo:** (1) admin remove condition, (2) pivote sub TFTEC, (3) cria PAYG nova, (4) roda local sem CI/CD (perde valor pedagógico). Detalhes no Capítulo 01.

---

## Pré-requisitos

- ✅ Capítulo 01 concluído — ABAC validado INATIVO (Passo 1.4 SP de teste passou)
- ✅ Capítulo 02 concluído — RG `rg-lab-avancado` existe em `East US 2` com 4 tags FinOps
- ✅ Capítulo 02 concluído — Repo GitHub `helpsphere-ia` criado (Private), com scaffold inicial committed em `main`
- ✅ `az` CLI logado na sub correta (`az account show` retornando subscription validada)
- ✅ `gh` CLI autenticado com scopes `repo` + `workflow` (`gh auth status`)
- ✅ Permissão **Application Administrator** OU **Cloud Application Administrator** OU **Owner** na sub (para criar App Registration)

> **Atenção gotcha — username GitHub case-sensitive:** Federated credential `subject` valida `repo:<seu-username>/helpsphere-ia:...` **case-sensitive**. Se seu user GitHub é `Guilherme-Campos` mas você cravar `guilherme-campos`, todo CI workflow falha com `AADSTS70021: No matching federated identity record found`. Anote o username com a capitalização **exata** que aparece no perfil GitHub.

---

## Resumo dos 3 artefatos que vamos cravar

| # | Artefato | Onde vive | Observação |
|---|---|---|---|
| 1 | App Registration + SP `sp-github-actions-helpsphere` | Microsoft Entra ID | Single tenant, role `Contributor` em `rg-lab-avancado` |
| 2 | 3 Federated Credentials (main / pull_request / production) | App Registration → Certificates & secrets | OIDC trust GitHub → Entra, **zero client secret** |
| 3 | 4 GitHub Secrets (Tenant + Sub + Client + AOAI key) | Repo `helpsphere-ia` → Settings → Secrets and variables → Actions | Consumidos pelos workflows do Capítulo 05 |

> **Nota pedagógica — por que SP federado e não client secret?** O pattern legacy era criar SP, gerar client secret de 1-2 anos de validade, copiar pro `secrets.AZURE_CREDENTIALS` JSON e usar `azure/login@v2` com `creds:`. Funciona — mas o segredo vaza se o repo é exfiltrado, expira sem aviso e exige rotação manual. Federated OIDC elimina o segredo: GitHub apresenta JWT assinado pelo `https://token.actions.githubusercontent.com`, Entra valida `subject` + `audience`, ninguém troca senha. **Pattern Microsoft canônico desde 2022.** Se seu time ainda usa client secret, vale evangelizar.

> **Nota pedagógica — por que 3 federated credentials e não 1?** Cada credential autoriza **um cenário GitHub Actions específico**: (a) `main` autoriza push direto/merge em main → CD Staging dispara, (b) `pull_request` autoriza job `bicep-what-if` no CI ao abrir PR, (c) `environment:production` autoriza deploy prod via `workflow_dispatch` com approval gate. **Sem credential `pull_request`, o `bicep-what-if` falha em PR.** Sem credential `environment:production`, o CD Prod do Capítulo 05 trava com `AADSTS70021`. Pattern: 1 credential = 1 trigger.

---

## Passo 3.1 — Criar App Registration `sp-github-actions-helpsphere`

GitHub Actions precisa de identidade Azure para deployar via Bicep. Criamos um **App Registration** (que automaticamente provisiona um **Service Principal** no tenant).

**No Portal Azure (Microsoft Entra ID):**

1. Acesse `https://portal.azure.com` → barra superior → buscar **"Microsoft Entra ID"** → clicar
2. Menu lateral → **App registrations** → topo → **+ New registration**
3. Preencher:
   - **Name:** `sp-github-actions-helpsphere` (exatamente — referenciado em todos os Capítulos seguintes)
   - **Supported account types:** ☑ `Accounts in this organizational directory only (Single tenant)`
   - **Redirect URI:** deixar vazio (não é app web — é identidade de pipeline)
4. **Register**
5. Após criação, painel **Overview** abre. Anote (vamos usar 4x neste Capítulo + nos workflows):
   - **Application (client) ID** — será `AZURE_CLIENT_ID` no GitHub Secret
   - **Directory (tenant) ID** — será `AZURE_TENANT_ID`
   - **Object ID** (do App, não da sub) — usado em scripts CLI

<!-- screenshot: cap03-passo3.1-app-registration-overview.png -->

> **Alternativa via Azure CLI (mais rápido — cria App + SP + role assignment numa só chamada):**
>
> ```powershell
> $SubscriptionId = az account show --query id -o tsv
> $TenantId = az account show --query tenantId -o tsv
>
> $SpJson = az ad sp create-for-rbac `
>   --name "sp-github-actions-helpsphere" `
>   --role Contributor `
>   --scopes "/subscriptions/$SubscriptionId/resourceGroups/rg-lab-avancado" `
>   --json-auth
>
> # NÃO comite este arquivo — já está no .gitignore do Capítulo 02
> $SpJson | Out-File -FilePath sp-credentials.json -Encoding utf8
>
> # Anote os IDs em local seguro (gerenciador de senhas / bloco de notas privado)
> $SpJson | ConvertFrom-Json | ForEach-Object { "clientId: $($_.clientId)"; "tenantId: $($_.tenantId)"; "subscriptionId: $($_.subscriptionId)" }
> ```
>
> > **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`, `Out-File` por `echo "$VAR" > file`.
>
> **`--json-auth`** retorna o JSON formato legacy compatível com `creds:` — mas vamos descartar a parte do `clientSecret` (Passo 3.3 cria federated credential que **substitui** o secret). Mantemos só os 3 IDs.

> **Custo:** R$ 0 — App Registrations e Service Principals são gratuitos no Entra ID. Não há billing por SP em si — o que custa são os recursos que o SP provisiona.

> **Nota pedagógica — App Registration vs Service Principal:** dois objetos relacionados mas distintos no Entra. **App Registration** é a "definição" (multi-tenant possível), **Service Principal** é a "instância" no tenant que você usa. `az ad sp create-for-rbac` cria os dois de uma vez. No Portal, você gerencia federated credentials e role assignments **pelo App Registration** (mesmo que conceitualmente seja o SP que recebe permissões). Confusão clássica de quem migra de AWS IAM.

---

## Passo 3.2 — Atribuir role Contributor no `rg-lab-avancado`

O SP precisa de permissão para criar/atualizar recursos dentro do RG (APIM, Content Safety, App Insights, Azure Policy). Escopo `Contributor` no RG é o **mínimo viável** — `Contributor` no scope `subscription` seria excessivo (princípio de menor privilégio).

**No Portal Azure (Resource Group → IAM):**

1. Barra superior → buscar **"Resource groups"** → clicar em `rg-lab-avancado`
2. Menu lateral → **Access control (IAM)** → **+ Add** → **Add role assignment**
3. Tab **Role:** procurar **`Contributor`** (ícone de chave azul) → selecionar → **Next**
4. Tab **Members:**
   - **Assign access to:** ☑ `User, group, or service principal`
   - **+ Select members** → digitar `sp-github-actions-helpsphere` → clicar no resultado
5. Tab **Conditions:** **deixar default** (sem condition — se você adicionar uma aqui, recria o R6 disclaimer dentro do próprio role assignment)
6. Tab **Review + assign** → confirmar Role = `Contributor` + Members = SP correto → **Review + assign**
7. Aguardar ~5-15s até notificação **"Role assignment added"** no canto superior direito

<!-- screenshot: cap03-passo3.2-rbac-contributor-rg.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> # Usando o mesmo $SubscriptionId do Passo 3.1
> $SpObjectId = az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].id" -o tsv
>
> az role assignment create `
>   --assignee $SpObjectId `
>   --role "Contributor" `
>   --scope "/subscriptions/$SubscriptionId/resourceGroups/rg-lab-avancado"
>
> # Validar role assignment criada
> az role assignment list `
>   --assignee $SpObjectId `
>   --resource-group rg-lab-avancado `
>   --query "[].{role:roleDefinitionName, scope:scope}" -o table
> # Esperado: role=Contributor, scope=/subscriptions/.../resourceGroups/rg-lab-avancado
> ```
>
> > **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`, `$Var` por `"$VAR"`.

> **Custo:** R$ 0 — role assignments são metadata gratuita.

> **Nota pedagógica — por que Contributor e não Owner?** `Contributor` permite criar/atualizar/deletar **recursos**, mas **NÃO permite criar role assignments**. Se você precisar que o pipeline atribua roles (ex: SP → Storage Blob Data Reader em outro recurso), faltará permissão. O Lab Avançado **não exige isso** — todos os role assignments são criados manualmente no Portal ou em pre-deploy script. Em prod real, padrão é `Contributor` + `User Access Administrator` se pipeline precisar atribuir RBAC, ou `Owner` se é cenário greenfield isolado.

> **Nota pedagógica — escopo RG vs subscription:** atribuir `Contributor` no scope da subscription inteira é tentador (1 click) mas viola menor privilégio. Se o SP for comprometido (token vazado, fork malicioso), atacante tem **toda a sub**. Escopo RG limita explosão a 1 RG. Pattern enterprise: 1 SP por aplicação/projeto, escopo RG ou Resource único.

---

## Passo 3.3 — Configurar Federated Credential 1 — main branch

Em vez de armazenar client secret no GitHub, usamos **OIDC federation trust** entre GitHub Actions e Entra ID. GitHub apresenta um token JWT assinado, Entra valida o `subject` (`repo:<user>/<repo>:<entity>`) e o `audience`. **Production-grade.**

**No Portal Azure (Entra ID → App registration → Federated credentials):**

1. **Microsoft Entra ID** → **App registrations** → clicar em `sp-github-actions-helpsphere`
2. Menu lateral → **Manage** → **Certificates & secrets**
3. Tab **Federated credentials** → **+ Add credential**
4. **Federated credential scenario:** dropdown → `GitHub Actions deploying Azure resources`
5. Preencher (credential 1 — main branch):
   - **Organization:** seu username GitHub (`<seu-username>` — case-sensitive, conforme Pré-requisitos)
   - **Repository:** `helpsphere-ia` (case-sensitive)
   - **Entity type:** `Branch`
   - **GitHub branch name:** `main`
   - **Name:** `github-helpsphere-main`
   - **Description:** `Deploy from main branch (CD Staging trigger)`
   - **Audience:** deixar default `api://AzureADTokenExchange`
6. **Add**
7. Confirme que aparece na lista com **Subject identifier:** `repo:<seu-username>/helpsphere-ia:ref:refs/heads/main`

<!-- screenshot: cap03-passo3.3-federated-credential-main.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> $AppId = az ad app list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv
> $GithubUser = "<seu-username>"  # exatamente como aparece no perfil GitHub
>
> $FcMain = @"
> {
>   "name": "github-helpsphere-main",
>   "issuer": "https://token.actions.githubusercontent.com",
>   "subject": "repo:$GithubUser/helpsphere-ia:ref:refs/heads/main",
>   "description": "Deploy from main branch (CD Staging trigger)",
>   "audiences": ["api://AzureADTokenExchange"]
> }
> "@
> $FcMain | Out-File -FilePath fc-main.json -Encoding utf8
> az ad app federated-credential create --id $AppId --parameters fc-main.json
> ```
>
> > **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, here-string `@"..."@` por here-doc `cat > file <<EOF ... EOF`, `$Var` por `"${VAR}"`.

> **Custo:** R$ 0 — federated credentials são gratuitos (sem limite de quantidade até hoje).

> **Nota pedagógica — `subject` é case-sensitive e literal:** o `subject` do JWT que GitHub apresenta inclui **exatamente** `repo:<owner>/<repo>:ref:refs/heads/<branch>`. Qualquer divergência (typo no username, repo renomeado depois, branch diferente) causa `AADSTS70021: No matching federated identity record found` no `azure/login@v2`. Quando workflow falhar com esse erro, primeiro suspeito é typo de username.

---

## Passo 3.4 — Configurar Federated Credential 2 — pull_request

O job `bicep-what-if` do Capítulo 05 roda **apenas em PRs** (`if: github.event_name == 'pull_request'`). PRs não fazem `push` em `main` — eles disparam o evento `pull_request`. **Sem esta segunda credential, o what-if falha** com `AADSTS70021`.

**No Portal Azure (mesma App Registration):**

1. Volte em **Federated credentials** → **+ Add credential**
2. **Federated credential scenario:** `GitHub Actions deploying Azure resources`
3. Preencher (credential 2 — pull_request):
   - **Organization:** seu username GitHub (mesmo do Passo 3.3)
   - **Repository:** `helpsphere-ia`
   - **Entity type:** `Pull request`
   - **Name:** `github-helpsphere-pr`
   - **Description:** `Validate from PRs (CI bicep-what-if)`
4. **Add**
5. Confirme **Subject identifier:** `repo:<seu-username>/helpsphere-ia:pull_request` (sem ref específica — qualquer PR ativa)

<!-- screenshot: cap03-passo3.4-federated-credential-pr.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> $FcPr = @"
> {
>   "name": "github-helpsphere-pr",
>   "issuer": "https://token.actions.githubusercontent.com",
>   "subject": "repo:$GithubUser/helpsphere-ia:pull_request",
>   "description": "Validate from PRs (CI bicep-what-if)",
>   "audiences": ["api://AzureADTokenExchange"]
> }
> "@
> $FcPr | Out-File -FilePath fc-pr.json -Encoding utf8
> az ad app federated-credential create --id $AppId --parameters fc-pr.json
> ```
>
> > **Linux/Mac/WSL:** troque here-string `@"..."@` por here-doc `cat > file <<EOF ... EOF`, `$Var` por `"${VAR}"`.

> **Nota pedagógica — `pull_request` autoriza qualquer PR no repo:** diferente de `ref:refs/heads/main` (que exige branch específico), `pull_request` é abrangente — qualquer PR dispara. Em prod com forks, isso pode ser perigoso (fork malicioso abre PR + roda código com role Contributor no seu RG). Mitigação no Capítulo 05: o what-if é **read-only** (só `az deployment group what-if`, sem `create`) — então mesmo se um fork rodar, ele não muta nada. Pattern: credential `pull_request` SEMPRE com workflow read-only no PR.

---

## Passo 3.5 — Configurar Federated Credential 3 — environment:production

O workflow `cd-prod.yml` (Capítulo 05) usa `environment: production` no job. O JWT que GitHub apresenta inclui `subject = repo:<user>/<repo>:environment:production`. Sem credential matching, deploy prod falha **mesmo com approval clicado**.

**No Portal Azure (mesma App Registration):**

1. **Federated credentials** → **+ Add credential**
2. **Federated credential scenario:** `GitHub Actions deploying Azure resources`
3. Preencher (credential 3 — environment production):
   - **Organization:** seu username GitHub (idem)
   - **Repository:** `helpsphere-ia`
   - **Entity type:** `Environment`
   - **GitHub environment name:** `production` (case-sensitive — combina com `environment: production` do `cd-prod.yml`)
   - **Name:** `github-helpsphere-env-production`
   - **Description:** `Deploy to production environment (manual approval required)`
4. **Add**
5. Confirme **Subject identifier:** `repo:<seu-username>/helpsphere-ia:environment:production`

<!-- screenshot: cap03-passo3.5-federated-credential-env-production.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> $FcEnvProd = @"
> {
>   "name": "github-helpsphere-env-production",
>   "issuer": "https://token.actions.githubusercontent.com",
>   "subject": "repo:$GithubUser/helpsphere-ia:environment:production",
>   "description": "Deploy to production environment (manual approval required)",
>   "audiences": ["api://AzureADTokenExchange"]
> }
> "@
> $FcEnvProd | Out-File -FilePath fc-env-prod.json -Encoding utf8
> az ad app federated-credential create --id $AppId --parameters fc-env-prod.json
>
> # Validar as 3 credentials criadas
> az ad app federated-credential list --id $AppId `
>   --query "[].{name:name, subject:subject}" -o table
> # Esperado: 3 linhas com subjects diferentes (refs/heads/main, pull_request, environment:production)
> ```
>
> > **Linux/Mac/WSL:** troque here-string `@"..."@` por here-doc, `` ` `` por `\`, `$Var` por `"${VAR}"`.

> **Nota pedagógica — por que credential `environment` separada de `branch`?** Mesmo que o `cd-prod.yml` rode em `main`, GitHub envia JWT com `subject = environment:production` (não `ref:refs/heads/main`) quando o job tem `environment: <name>`. **Os dois subjects são mutuamente exclusivos por workflow run.** Se você criasse só credential `main`, o CD Staging funcionaria (não usa environment) mas CD Prod falharia. Se você criasse só `environment:production`, CD Prod funcionaria mas CI/CD Staging falhariam. Os 3 cobrem os 3 cenários do Capítulo 05.

---

## Passo 3.6 — Cravar 4 GitHub Secrets no repo `helpsphere-ia`

Os 3 IDs (Tenant, Subscription, Client) + a key AOAI precisam virar **secrets** do repo `helpsphere-ia` para os workflows usarem em `azure/login@v2` (sem `creds:`, apenas `client-id` + `tenant-id` + `subscription-id`).

**No GitHub (Repository → Settings → Secrets and variables → Actions):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/secrets/actions`
2. **+ New repository secret** — adicione **4 secrets** em sequência:
   - **Name:** `AZURE_TENANT_ID` · **Secret:** Tenant ID anotado no Passo 3.1 → **Add secret**
   - **Name:** `AZURE_SUBSCRIPTION_ID` · **Secret:** rode `az account show --query id -o tsv` localmente e cole → **Add secret**
   - **Name:** `AZURE_CLIENT_ID` · **Secret:** Application (client) ID anotado no Passo 3.1 → **Add secret**
   - **Name:** `AOAI_API_KEY` · **Secret:** key do Azure OpenAI (recurso `aifproj-helpsphere-rag` do Lab Intermediário, ou crie um novo se rodando standalone) → **Add secret**

<!-- screenshot: cap03-passo3.6-github-secrets-list.png -->

> **Alternativa via gh CLI (mais rápido):**
>
> ```powershell
> $TenantId = az account show --query tenantId -o tsv
> $SubscriptionId = az account show --query id -o tsv
> $ClientId = az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv
>
> gh secret set AZURE_TENANT_ID --body $TenantId --repo "<seu-username>/helpsphere-ia"
> gh secret set AZURE_SUBSCRIPTION_ID --body $SubscriptionId --repo "<seu-username>/helpsphere-ia"
> gh secret set AZURE_CLIENT_ID --body $ClientId --repo "<seu-username>/helpsphere-ia"
> gh secret set AOAI_API_KEY --body "<sua-key-aoai-do-Lab-Inter>" --repo "<seu-username>/helpsphere-ia"
>
> # Validar (não mostra valores — apenas nomes)
> gh secret list --repo "<seu-username>/helpsphere-ia"
> # Esperado: 4 linhas (AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_CLIENT_ID, AOAI_API_KEY)
> ```
>
> > **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `$Var` por `"$VAR"`.

> **Custo:** R$ 0 — secrets ilimitados em qualquer tier GitHub.

> **Nota pedagógica — Variables vs Secrets (recap):** as 3 IDs Azure poderiam tecnicamente ser **variables** (não são "sensíveis" no sentido estrito — `subscription_id` aparece em logs do `az` rotineiramente). Mas pela convenção Microsoft + GitHub OIDC docs, sempre usamos **secrets**. Excepcionalmente o `AOAI_API_KEY` é **inegociavelmente secret** (key API que cobra por token consumido). Se vazar, atacante consome até quota acabar. Pattern: na dúvida, secret. Variable só pra URLs e flags públicos (Capítulo 05 Passo 5.5).

---

## Passo 3.7 — Validar setup via Portal + smoke command

**No Portal Azure:**

1. **Microsoft Entra ID** → **App registrations** → `sp-github-actions-helpsphere` → **Overview** — confirme Application (client) ID + Directory (tenant) ID visíveis
2. Menu lateral → **Certificates & secrets** → tab **Federated credentials** — confirme **3 credentials listadas** com subjects distintos:
   - `repo:<user>/helpsphere-ia:ref:refs/heads/main`
   - `repo:<user>/helpsphere-ia:pull_request`
   - `repo:<user>/helpsphere-ia:environment:production`
3. **Resource groups** → `rg-lab-avancado` → **Access control (IAM)** → tab **Role assignments** → confirme `sp-github-actions-helpsphere` aparece com role `Contributor`

<!-- screenshot: cap03-passo3.7-3-federated-credentials-list.png -->
<!-- screenshot: cap03-passo3.7-iam-role-assignment-sp.png -->

**No GitHub UI:**

4. `https://github.com/<seu-username>/helpsphere-ia/settings/secrets/actions` — confirme 4 secrets listados (`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID`, `AOAI_API_KEY`)

**No terminal local — smoke single-command:**

```powershell
Write-Host "=== Capítulo 03 — Smoke validation ==="
Write-Host "1. App Registration existe:"
az ad app list --display-name "sp-github-actions-helpsphere" --query "[0].{name:displayName, appId:appId}" -o table
Write-Host ""
Write-Host "2. Service Principal com Contributor no RG:"
$SpObj = az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].id" -o tsv
az role assignment list --assignee $SpObj --resource-group rg-lab-avancado --query "[].roleDefinitionName" -o tsv
Write-Host ""
Write-Host "3. 3 Federated credentials cravadas:"
$AppId = az ad app list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv
az ad app federated-credential list --id $AppId --query "[].{name:name, subject:subject}" -o table
Write-Host ""
Write-Host "4. 4 GitHub secrets registrados:"
gh secret list --repo "<seu-username>/helpsphere-ia"
Write-Host ""
Write-Host "=== FIM smoke ==="
```

> **Linux/Mac/WSL:** troque `Write-Host` por `echo`, `$Var = cmd` por `VAR=$(cmd)`, `$Var` por `"$VAR"`, e encadeie linhas com `&& \` em vez de quebra de linha simples.

**Esperado:**

```
1. App Registration existe:
Name                              AppId
--------------------------------  ------------------------------------
sp-github-actions-helpsphere      <client-id-guid>

2. Service Principal com Contributor no RG:
Contributor

3. 3 Federated credentials cravadas:
Name                                   Subject
-------------------------------------  ----------------------------------------------------
github-helpsphere-main                 repo:<user>/helpsphere-ia:ref:refs/heads/main
github-helpsphere-pr                   repo:<user>/helpsphere-ia:pull_request
github-helpsphere-env-production       repo:<user>/helpsphere-ia:environment:production

4. 4 GitHub secrets registrados:
AZURE_CLIENT_ID         Updated 2026-...
AZURE_SUBSCRIPTION_ID   Updated 2026-...
AZURE_TENANT_ID         Updated 2026-...
AOAI_API_KEY            Updated 2026-...
```

---

## Validação end-to-end

```powershell
# 1. App Registration + SP existem
az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].{name:displayName, appId:appId, objectId:id}" -o jsonc

# 2. Role Contributor no RG (e SOMENTE no RG — não na sub)
$SpObj = az ad sp list --display-name "sp-github-actions-helpsphere" --query "[0].id" -o tsv
az role assignment list `
  --assignee $SpObj `
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
# Esperado: 1 linha com role=Contributor + scope terminando em /resourceGroups/rg-lab-avancado

# 3. 3 federated credentials presentes
$AppId = az ad app list --display-name "sp-github-actions-helpsphere" --query "[0].appId" -o tsv
az ad app federated-credential list `
  --id $AppId `
  --query "length(@)"
# Esperado: 3

# 4. GitHub secrets presentes (nomes apenas)
(gh secret list --repo "<seu-username>/helpsphere-ia" | Measure-Object -Line).Lines
# Esperado: 4

# 5. Cleanup do sp-credentials.json local (se criou no Passo 3.1 via CLI)
if (Test-Path sp-credentials.json) {
  Write-Host "ATENÇÃO: delete sp-credentials.json antes de commitar (já está no .gitignore mas não vale o risco)"
  Remove-Item -Force sp-credentials.json
}
```

> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`, `Measure-Object -Line` por `wc -l`, e o `if (Test-Path ...)` por `ls ... 2>/dev/null && rm -f ...`.

---

## Checklist final

```text
[ ] App Registration sp-github-actions-helpsphere criado (single tenant)
[ ] Application (client) ID + Tenant ID + Subscription ID anotados em local seguro
[ ] Role Contributor atribuída ao SP no escopo rg-lab-avancado (NÃO na sub)
[ ] Federated Credential 1: github-helpsphere-main (subject ref/heads/main)
[ ] Federated Credential 2: github-helpsphere-pr (subject pull_request)
[ ] Federated Credential 3: github-helpsphere-env-production (subject environment:production)
[ ] GitHub Secret AZURE_TENANT_ID cravado
[ ] GitHub Secret AZURE_SUBSCRIPTION_ID cravado
[ ] GitHub Secret AZURE_CLIENT_ID cravado
[ ] GitHub Secret AOAI_API_KEY cravado (do Lab Intermediário aifproj-helpsphere-rag)
[ ] sp-credentials.json local DELETADO (cleanup de segurança)
[ ] R6 disclaimer revisitado e ABAC confirmado INATIVO (Cap 01.4)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`AADSTS70021: No matching federated identity record found` no primeiro CI run** — quase sempre é **typo no username GitHub** (case-sensitive). Confira se o `subject` da credential corresponde **exatamente** a `repo:<user>/helpsphere-ia:ref:refs/heads/main` com a capitalização do perfil GitHub. Se renomeou o repo depois, **recria a credential** — Entra não atualiza dinamicamente.
- ⚠️ **Esqueceu credential `pull_request` e o job `bicep-what-if` falha em PR** — sintoma: CI passa em push direto em `main` mas falha ao abrir PR. Causa: só credential `main` cravada. Workaround: voltar ao Passo 3.4 e criar a 2ª credential. **Não tente** "ampliar" o subject da credential 1 — `repo:<user>/<repo>:*` não é wildcard suportado.
- ⚠️ **CD Prod aprovado mas ainda falha com `AADSTS70021`** — mesmo após você clicar Approve no environment `production`, falta credential `environment:production` (Passo 3.5). Sintoma desconcertante porque approval gate fica verde mas o job logo depois quebra. Workaround: criar credential 3 e re-run.
- ⚠️ **Role Contributor atribuída no escopo da subscription inteira "por engano"** — você clicou Subscriptions → IAM em vez de Resource Groups → IAM. Sintoma: pipeline funciona, mas SP tem permissão excessiva (cria recursos em qualquer RG). Workaround: deletar role assignment subscription-scoped (`az role assignment delete --assignee $SP_OBJ --scope /subscriptions/$SUB_ID`) e refazer no scope RG. Faça isso **antes** do primeiro run em produção real.
- ⚠️ **`gh secret set` reclamando "could not find any secrets management"** — repo está vazio sem `main` branch. Sintoma: gh CLI confuso porque não há branch default. Workaround: garantir que Capítulo 02 fez `git push origin main` antes deste Capítulo. Pré-requisito explícito no topo.
- ⚠️ **`sp-credentials.json` commitado por engano** — você rodou `az ad sp create-for-rbac` sem `.gitignore` populado, ou estava em outro diretório. Sintoma: GitHub Secret Scanning alerta em segundos + bots tentam usar o segredo. Workaround imediato: (1) `git rm sp-credentials.json && git commit && git push` + (2) `az ad sp credential reset --id $APP_ID` (invalida segredo vazado, mas SP continua válido para federated). Stop-loss: rode `git status` antes de cada commit, sempre.
- ⚠️ **App Registration criada em tenant errado** — conta multi-tenant (M365 + dev) e você criou no tenant pessoal. Sintoma: `azure/login@v2` falha com `AADSTS700016: Application not found in directory`. Workaround: deletar App Reg, validar `az account show --query tenantId` antes, e recriar no tenant correto. Pattern: sempre rode `az account list --query "[].{name:name, tenantId:tenantId}" -o table` antes de criar artefato Entra.

---

## Próximo capítulo

[04a — Bicep modules](./04a-bicep-modules.md)
