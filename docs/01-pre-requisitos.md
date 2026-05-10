# Capítulo 01 — Pré-requisitos

> **Objetivo:** validar — antes de provisionar 1 byte — que sua subscription, tooling e contas Git estão prontas para o pipeline production-grade. Sair daqui com a tela de "Subscription OK · ABAC OK · gh logado · Bicep instalado · Foundry decidido" antes de tocar o Capítulo 02.
>
> **Tempo:** 30-45 min (mais ~10 min se precisar instalar tooling do zero · pode dobrar se cair em ABAC e tiver que pivotar de subscription)
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` outline) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Pré-requisitos (linhas 45-77) + R6 disclaimer recap

---

## ⚙️ Sintaxe de comandos shell

> **Os blocos shell deste guia usam PowerShell** (Windows-first, alinhado ao público da disciplina). Continuação de linha é `` ` `` (backtick), variáveis de ambiente via `$env:VAR = "..."`, substituição de comando via `(cmd)` ou `$(cmd)`.
>
> **Linux / Mac / WSL:** troque `$env:VAR = "..."` por `export VAR="..."`, `$env:VAR = (cmd)` por `export VAR=$(cmd)`, e `` ` `` por `\` no fim das linhas.

---

## DISCLAIMER R6 (recap obrigatório) — checagem ABAC antes de tudo

Este lab é o **único dos 3 Labs D06 que sobe CI/CD via Service Principal federado**. Isso significa que sua subscription **não pode ter ABAC condition ativa** — caso contrário o workflow `ci.yml` falha no primeiro `az role assignment create` e o demo CI/CD perde o valor pedagógico.

> **TL;DR (detalhes completos no Capítulo 03 — `docs/03-service-principal-federated.md`):**
>
> - **Visual Studio Enterprise (`live.com`):** ABAC default ATIVO → **CI/CD falha** (use sub TFTEC, PAYG ou corporate)
> - **Free Trial USD 200:** sem ABAC, mas sem PAYG → Azure OpenAI bloqueia
> - **PAYG sem ABAC / TFTEC / Corporate sem CA restritiva:** funciona ✅

Você ainda consegue rodar `az deployment group create` localmente com sua user identity em qualquer sub, mas o foco do lab é o pipeline — então **resolva ABAC antes**, não depois.

---

## Pré-requisitos

- ✅ Labs Intermediário (RAG) e Final (Agente) **concluídos** ou pelo menos **lidos** — este lab assume entendimento de Foundry Hub, RAG, MCP e Agente Workflow
- ✅ **Subscription Azure** PAYG (preferido) ou TFTEC ou corporate — **sem ABAC condition restritiva** (validação concreta no Passo 1.4)
- ✅ Conta GitHub com permissão para criar repositório privado (free OK)
- ✅ Acesso a um **e-mail real** que esteja vinculado à mesma identidade Entra que assina sua sub (federated credentials usam o login GitHub, mas o reviewer aprova via Entra/GitHub combo)
- ✅ ~30 minutos contínuos sem reuniões (algumas ações disparam provisões longas — APIM ~30-45 min — então prepare paralelismo)
- ✅ Espaço em disco **mínimo 2 GB** livre (clone repo + Bicep build cache + venv Python)

> **Atenção breaking — versão Bicep antiga:** Bicep CLI < 0.30 não suporta `userDefinedTypes` e `compile-time imports` que aparecem em `infra/modules/*.bicep`. Se você não atualiza desde 2024, o Capítulo 04 vai estourar com `BCP236: Expected new line character`. Atualize ANTES (`az bicep upgrade`).

---

## Resumo dos 5 itens que vamos validar

| Item | Como validar | Falha bloqueante? | Tempo |
|---|---|---|---|
| 1. Subscription Azure ativa | `az account show` retorna state `Enabled` | SIM | 1 min |
| 2. ABAC condition INATIVA na sub | `az role assignment create` com SP de teste não retorna `ConditionRequiresAuthorization` | SIM (R6) | 5-10 min |
| 3. Tooling local (Az CLI · Bicep · Python · gh CLI · VS Code + extensions) | `az --version`, `bicep --version`, `python --version`, `gh auth status` | SIM | 5-15 min |
| 4. Conta GitHub + repo privado **vazio** `helpsphere-ia` criável | `gh repo create --private --confirm=false` (dry) | SIM | 2-3 min |
| 5. Foundry Hub `aifhub-apex-prod` (decisão prof) — provisionado OU plano B | `az ml workspace show --name aifhub-apex-prod` OU plano B textual | NÃO (gated) | 2 min |

> **Nota pedagógica — por que validar ABAC ANTES de provisionar?** Stop-loss puro: ABAC bloqueia role assignments via SP federado **silenciosamente** até o primeiro `az role assignment create` do CI workflow. Se você descobre isso só depois de provisionar APIM (R$ 250/mês prorated) e clonar repo + criar SP + 2 federated creds, você queimou ~1h e ~R$ 30 antes do erro aparecer. **Validar a custo zero agora salva a sessão de gravação.**

---

## Passo 1.1 — Validar subscription Azure ativa

**No Portal Azure:**

1. Abra `https://portal.azure.com` → barra superior → buscar **"Subscriptions"** → clicar
2. Localize sua subscription na lista (PAYG / TFTEC / Corporate)
3. Coluna **State** deve aparecer **`Enabled`** (verde) — se aparecer `Warned` ou `PastDue`, resolva billing antes
4. Clique no nome da sub → painel **Overview**
5. Anote (vamos usar várias vezes):
   - **Subscription ID** (formato GUID `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   - **Tenant ID** (em **Properties** → **Parent Management Group** ou no canto superior direito do portal)
   - **Tipo** (Pay-As-You-Go / Visual Studio Enterprise / Microsoft Azure Sponsorship)

<!-- screenshot: cap01-passo1.1-subscription-overview-state-enabled.png -->

> **Alternativa via Azure CLI:**
> ```powershell
> # Login (abre browser; aceita device code com --use-device-code)
> az login
>
> # Listar subs e marcar a default
> az account list --query "[].{name:name, id:id, state:state, isDefault:isDefault, type:user.type}" -o table
>
> # Setar a sub que vamos usar no lab
> az account set --subscription "<SUBSCRIPTION_ID>"
>
> # Confirmar default
> az account show --query "{name:name, id:id, state:state, tenantId:tenantId}" -o json
> # Esperado: state=Enabled
> ```
>
> **Linux/Mac/WSL:** comandos `az` são idênticos — só a sintaxe shell de variáveis muda (não usadas neste bloco).

> **Custo:** R$ 0 — validação read-only.

> **Nota pedagógica — por que tenant ID e sub ID separados?** Em orgs reais um tenant Entra hospeda **N subscriptions** (dev/staging/prod/sandbox). O federated credential do Capítulo 03 valida `tenant + subscription + client (SP)` em conjunto — se você confunde IDs entre subs, o GitHub Actions retorna `AADSTS700016` no primeiro `azure/login@v2`. Anote os 2 com nomes claros num bloco de notas (`tenant_lab`, `sub_lab`).

---

## Passo 1.2 — Instalar / atualizar tooling local

**No terminal local (Windows PowerShell 7):**

```powershell
# 1. Azure CLI >= 2.60 (validamos em 2.65 na gravação)
az --version
# Se < 2.60: https://learn.microsoft.com/cli/azure/install-azure-cli
#   Windows: winget install Microsoft.AzureCLI
#   macOS:   brew install azure-cli
#   Ubuntu:  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 2. Bicep CLI >= 0.30 (vem dentro do az)
az bicep upgrade
az bicep version
# Esperado: Bicep CLI version 0.30.x ou superior

# 3. Python 3.11+ (necessário para eval/run_eval.py do Capítulo 09)
python --version
# Se < 3.11: https://www.python.org/downloads/
#   Windows: winget install Python.Python.3.12
#   macOS:   brew install python@3.12

# 4. GitHub CLI autenticado
gh --version
gh auth status
# Se não logado: gh auth login → escolha GitHub.com → HTTPS → Login with a web browser

# 5. Git
git --version
```

> **Linux/Mac/WSL:** comandos são idênticos — só a sintaxe shell de variáveis muda (não usadas neste bloco).

> **Alternativa via VS Code (recomendado):** instale as 3 extensões abaixo no VS Code — vamos usá-las no Capítulo 04 (Bicep) e 05 (Actions).
>
> ```powershell
> code --install-extension ms-azuretools.vscode-bicep
> code --install-extension github.vscode-github-actions
> code --install-extension ms-python.python
> ```

> **Custo:** R$ 0 — todas as ferramentas são free/open-source.

> **Nota pedagógica — por que `az bicep upgrade` e não `npm install bicep`?** Bicep CLI vive **dentro** do Azure CLI desde 2022. Versões standalone (download manual) ficam stale e divergem do `az` — manter via `az bicep upgrade` garante alinhamento. Em Bicep < 0.30, `userDefinedTypes` (que o Cap 04 usa) explode em erro de parse. **Stop-loss:** pin a versão no `dev-container.json` se for trabalhar em squad.

---

## Passo 1.3 — Criar repositório GitHub vazio `helpsphere-ia`

Este lab é IaC end-to-end — o código Bicep + workflows YAML + Python eval vivem num repo GitHub que dispara GitHub Actions ao push. Vamos criar o repo **vazio** agora; o conteúdo é commitado nos Capítulos 02-09.

**No GitHub (`https://github.com`):**

1. Logado no GitHub → canto superior direito → **+** → **New repository**
2. Preencher:
   - **Owner:** seu user (anote — vamos referenciar no Capítulo 03 federated credential `subject`)
   - **Repository name:** `helpsphere-ia` (case-sensitive — combina com `subject` do federated credential)
   - **Description:** `Lab Avançado D06 — IA Production-grade (Apex HelpSphere)`
   - **Visibility:** ☑ **Private** (recomendado — não vamos commitar segredos, mas Bicep mostra arquitetura)
   - ☐ **Add a README file** (NÃO marcar — queremos repo vazio para `git push` inicial)
   - ☐ Add `.gitignore` (NÃO marcar)
   - ☐ Choose a license (NÃO marcar)
3. **Create repository**
4. Anote a URL: `https://github.com/<seu-username>/helpsphere-ia`

<!-- screenshot: cap01-passo1.3-github-new-repo-helpsphere-ia.png -->

> **Alternativa via gh CLI:**
> ```powershell
> gh repo create helpsphere-ia `
>   --private `
>   --description "Lab Avançado D06 — IA Production-grade (Apex HelpSphere)" `
>   --confirm
>
> # Confirmar criação
> gh repo view <seu-username>/helpsphere-ia --json url,visibility,isPrivate
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\` no fim das linhas.

> **Custo:** R$ 0 — repo privado é free para 1 colaborador. GitHub Actions tem 2.000 min/mês free em repos privados (este lab consome ~50 min total).

> **Nota pedagógica — por que NÃO marcar `Add README`?** Marcar README inicializa o repo com 1 commit em `main`. Quando você der `git push` do clone local (Capítulo 02), `main` já tem histórico → conflito. Repo vazio aceita `git push -u origin main` direto. Microsoft / GitHub docs recomendam essa rota para IaC automation.

---

## Passo 1.4 — Validar ABAC condition INATIVA (R6 stop-loss)

Esta é a validação **mais importante** do Capítulo. Custo R$ 0. Tempo 5-10 min. Salva ~1h se ABAC estiver ativo.

**No Portal Azure:**

1. Buscar **"Subscriptions"** → sua sub → painel lateral **Access control (IAM)**
2. Aba **Role assignments** → filtro **Type:** `User, group, or service principal`
3. Inspecione coluna **Condition** — se algum role assignment seu lista condition (ícone de cadeado azul/cinza), abra e leia
4. Padrões de ABAC bloqueante:
   - "Allow user to assign a role only if it's `Storage Blob Data Reader`..."
   - "Allow user to read storage blob containers only with tag X..."
   - Qualquer condition citando `@Resource[Microsoft.Authorization/roleAssignments]` em **DENY**

<!-- screenshot: cap01-passo1.4-iam-conditions-inspection.png -->

5. Se sua sub **Visual Studio Enterprise** vinculada ao `live.com`, ABAC default está ativo (ainda que não apareça na UI) → CI/CD vai falhar → **pivote agora**

> **Alternativa via Azure CLI (validação direta com SP de teste · destrutiva-leve):**
>
> ```powershell
> # 1. Crie SP de teste (descartável — vamos deletar no fim)
> $Timestamp = [int][double]::Parse((Get-Date -UFormat %s))
> $Sp = az ad sp create-for-rbac `
>   --name "sp-test-abac-$Timestamp" `
>   --role contributor `
>   --scopes "/subscriptions/<SUB_ID>" `
>   --query "{id:id, appId:appId}" -o json | ConvertFrom-Json
> Write-Host $Sp
>
> $SpObjectId = $Sp.id
> $SpAppId = $Sp.appId
>
> # 2. Tente role assignment via esse SP (em RG fictício, mesmo se não existir é OK pra teste de auth)
> az role assignment create `
>   --assignee $SpObjectId `
>   --role "Storage Blob Data Reader" `
>   --scope "/subscriptions/<SUB_ID>"
>
> # SE retornar:
> #   "AuthorizationFailed: The client does not have authorization to perform action..."
> #   COM "ConditionRequiresAuthorization" no detalhe
> #   → ABAC ATIVO → STOP, pivote sub
> #
> # SE retornar sucesso ou erro genérico (RG não existe), ABAC OK → siga
>
> # 3. Cleanup do SP de teste
> az ad sp delete --id $SpAppId
> ```
>
> **Linux/Mac/WSL:** troque `$Var = ...` por `VAR=...`, `$Var` por `"$VAR"`, `` ` `` por `\` no fim das linhas, e use `$(date +%s)` + `jq -r .id` no lugar das equivalências PowerShell.

> **Custo:** R$ 0 — SPs e role assignments são gratuitos · cleanup do SP é obrigatório (cravado no comando acima).

> **Nota pedagógica — por que esse teste é o canário do lab inteiro?** O CI workflow do Capítulo 05 faz **exatamente** essa operação (`role assignment create` via SP federado) toda vez que provisiona APIM/Content Safety. Se a operação falha agora com seu SP de teste, falha em produção. Inversamente, se passa agora, você tem confiança alta de que o CI/CD vai funcionar end-to-end. **Pattern Microsoft:** `az role assignment create --dry-run` (em preview) faz o mesmo sem criar nada — quando GA chegar, este Passo simplifica.

> **⚠️ Plano B se ABAC estiver ativo:** você tem 4 opções, em ordem de preferência:
> 1. **Pedir ao admin do tenant para remover a condition** (corporate) — 10 min, melhor cenário
> 2. **Pivotar para sub TFTEC** (alunos da disciplina recebem acesso) — 5 min, simples
> 3. **Criar nova PAYG (cartão de crédito)** — 10 min, ~R$ 35-45 no lab
> 4. **Rodar local sem CI/CD** (apenas `az deployment group create` no terminal) — perde o valor pedagógico do pipeline mas conclui Capítulos 04, 06, 07, 08

---

## Passo 1.5 — Decidir Foundry Hub: existente vs provisionar ao vivo

O lab Avançado **opcionalmente** integra com o Foundry Hub `aifhub-apex-prod` para custom metrics LLM (Capítulo 07) e eval offline (Capítulo 09). Como o Hub não foi provisionado em todos os tenants, há 2 caminhos.

**No Portal Azure:**

1. Buscar **"AI Foundry"** (ou **"Azure Machine Learning"**) → aba **Hubs**
2. Procure `aifhub-apex-prod` na lista
3. Se existe → **Status: Succeeded** → anote o **Resource Group** que hospeda → você está pronto
4. Se não existe (esperado em sub nova) → vamos seguir o **plano B** (provisionar ao vivo na gravação ou usar mocks)

<!-- screenshot: cap01-passo1.5-foundry-hub-aifhub-apex-prod.png -->

> **Alternativa via Azure CLI:**
> ```powershell
> az ml workspace show `
>   --name aifhub-apex-prod `
>   --resource-group <RG_DO_HUB> `
>   --query "{name:name, kind:kind, provisioningState:provisioningState}" -o table
>
> # Se retorna "ResourceNotFound" → Hub não existe nesta sub → plano B
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\` no fim das linhas.

> **Custo:** Hub vazio R$ 0/mês · Hub com deployments PAYG (gpt-4.1-mini + text-embedding-3-small) cobra por token consumido (~R$ 5-10 no lab inteiro de eval).

> **Nota pedagógica — por que Hub é "gated" e não bloqueante?** O eval offline do Capítulo 09 pode rodar com 2 modos: (a) **com Foundry Hub real** → calcula metrics como `groundedness`, `relevance`, `coherence` via SDK Azure AI Eval; (b) **com stubs** → retorna metrics fake mas valida o pipeline (CI integrado, threshold-regression, upload artifact). Para a primeira execução do lab, **modo stub é suficiente** — você troca para Hub real quando provisionar. **Decisão pedagógica:** não bloquear lab inteiro por causa de 1 dependência opcional.

> **Decisão arquitetural:** se Hub não existe na sub usada, o Capítulo 09 detalha o stub mode (`eval/run_eval.py --stub`). Se existe, o flag default sem `--stub` puxa o Hub.

---

## Passo 1.6 — Validar tudo via smoke command único

Antes de fechar o Capítulo, rode o bloco abaixo que valida os 5 itens em série:

```powershell
Write-Host "=== Capítulo 01 — Smoke validation ==="
Write-Host "1. az account show:"
az account show --query "{name:name, state:state, tenantId:tenantId, id:id}" -o table
Write-Host ""
Write-Host "2. Bicep version:"
az bicep version
Write-Host ""
Write-Host "3. Python version:"
python --version
Write-Host ""
Write-Host "4. gh auth status:"
gh auth status
Write-Host ""
Write-Host "5. Repo helpsphere-ia visível:"
try { gh repo view <seu-username>/helpsphere-ia --json name,visibility,isPrivate,url } catch { Write-Host "(crie no Passo 1.3)" }
Write-Host ""
Write-Host "=== FIM smoke ==="
```

> **Linux/Mac/WSL:** versão bash equivalente com `echo ... && \` em série e `|| echo "(crie...)"` no fallback.

**Esperado (saída completa, abreviada):**

```
1. az account show:
Name                  State    TenantId                              Id
--------------------  -------  ------------------------------------  ------------------------------------
PAYG do Guilherme     Enabled  72f988bf-86f1-41af-91ab-2d7cd011db47  3075a5eb-...

2. Bicep version: Bicep CLI version 0.30.23
3. Python version: Python 3.12.4
4. gh auth status: ✓ Logged in to github.com account <seu-username>
5. Repo helpsphere-ia visível: { "name": "helpsphere-ia", "isPrivate": true, ... }
```

---

## Validação end-to-end

```powershell
# 1. Subscription state Enabled
az account show --query state -o tsv
# Esperado: Enabled

# 2. ABAC test (com SP descartável criado no Passo 1.4) passou (não retornou ConditionRequiresAuthorization)

# 3. Toolchain version mínima
az version --query '"azure-cli"' -o tsv                                       # >= 2.60
az bicep version | Select-String -Pattern '[0-9]+\.[0-9]+'                    # >= 0.30
python --version | Select-String -Pattern '3\.[0-9]+'                         # >= 3.11
gh --version | Select-Object -First 1                                         # >= 2.40

# 4. Repo privado existe
gh repo view <seu-username>/helpsphere-ia --json isPrivate -q .isPrivate
# Esperado: true

# 5. (Opcional) Foundry Hub
az ml workspace list --query "[?name=='aifhub-apex-prod'].name" -o tsv
# Esperado: aifhub-apex-prod (se modo Hub) OU vazio (se modo stub)
```

> **Linux/Mac/WSL:** troque `Select-String -Pattern X` por `grep -oE X` e `Select-Object -First 1` por `head -1`.

---

## Checklist final

```text
[ ] Subscription state=Enabled validado no Portal e via az account show
[ ] Subscription ID e Tenant ID anotados em local seguro
[ ] ABAC condition INATIVA (Passo 1.4 SP de teste passou) — R6 OK
[ ] Az CLI >= 2.60 instalado e logado
[ ] Bicep CLI >= 0.30 instalado (via az bicep upgrade)
[ ] Python 3.11+ instalado e no PATH
[ ] gh CLI >= 2.40 instalado e gh auth status verde
[ ] VS Code com extensões Bicep + GitHub Actions + Python instaladas
[ ] Repo privado helpsphere-ia criado (vazio, sem README)
[ ] Foundry Hub aifhub-apex-prod localizado OU plano B stub aceito
[ ] SP de teste do Passo 1.4 deletado (cleanup)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`az bicep version` retorna 0.20 mesmo após `az bicep upgrade`** — causa: cache do CLI corrupto · workaround: `az bicep uninstall && az bicep install` (recria do zero) · em casos extremos, reinstale az CLI via winget/brew.
- ⚠️ **`gh auth status` mostra "Logged in" mas `gh repo create` retorna `HTTP 403`** — causa: scopes ausentes (token criado antes de `repo` ser scope necessário) · workaround: `gh auth refresh -s repo,workflow,delete_repo`. **Atenção:** scope `delete_repo` é necessário para o Capítulo 10 cleanup.
- ⚠️ **Repo `helpsphere-ia` criado com README** — você marcou `Add README` no Passo 1.3 e agora `git push` do Capítulo 02 falha com `non-fast-forward` · workaround: (a) deletar e recriar, OU (b) `git pull --rebase origin main` antes do primeiro push, OU (c) `git push --force` (perigoso, só em repo recém-criado).
- ⚠️ **Visual Studio Enterprise sub mostra "Enabled" mas ABAC bloqueia silenciosamente** — Portal não exibe condition ABAC default em VSE pessoais · só descobre via Passo 1.4 SP de teste · **stop-loss:** sempre rode o teste, nunca confie só no Portal.
- ⚠️ **Tenant ID confuso em conta multi-tenant (Microsoft 365 + dev tenant)** — `az account show --query tenantId` mostra o tenant da sub atual, mas seu login GitHub pode estar vinculado a outro tenant Entra · valide com `az account list --query "[].tenantId" -o tsv | Sort-Object -Unique` (PowerShell) ou `az account list --query "[].tenantId" -o tsv | sort -u` (Linux/Mac/WSL) — deve listar 1 só, antes de cravar federated credential no Capítulo 03.

---

## Próximo capítulo

[02 — RG + GitHub setup](./02-rg-github-setup.md)
