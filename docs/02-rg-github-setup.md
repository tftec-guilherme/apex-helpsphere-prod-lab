# Capítulo 02 — Resource Group + GitHub repo setup

> **Objetivo:** provisionar o **Resource Group** `rg-lab-avancado` com tags de FinOps obrigatórias, criar o repositório GitHub `helpsphere-ia` (privado, com `.gitignore` Python + estrutura de pastas IaC), commitar o scaffold inicial e cravar branch protection em `main` — deixando o terreno pronto para o Service Principal (Capítulo 03) e os Bicep modules (Capítulo 04).
>
> **Tempo:** 25-35 min
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` outline) — derivado de `Lab_Avancado_IA_Producao_Guia_Portal.md` Parte 1 (Passos 1.1-1.2) + best-practices canônicos do PILOTO Capítulo 05

---

## Pré-requisitos

- ✅ Capítulo 01 concluído — subscription Azure validada (PAYG sem ABAC OU TFTEC OU corporate sem CA restritiva)
- ✅ Foundry Hub `aifhub-apex-prod` provisionado (do Lab Intermediário) — apenas referência: este Capítulo não toca AOAI
- ✅ `az` CLI logado (`az login` + `az account show` retornando subscription correta)
- ✅ `gh` CLI autenticado (`gh auth status` mostrando login + scopes `repo`, `workflow`)
- ✅ `git` configurado com `user.name` + `user.email` globais
- ✅ Editor local pronto (VS Code recomendado — usado a partir do Capítulo 04 para Bicep)

> **Atenção breaking — nomenclatura canônica:** este lab usa **`rg-lab-avancado`** como Resource Group e **`helpsphere-ia`** como nome do repo GitHub. Esses dois nomes são referenciados em **todos os Capítulos seguintes** (workflows, Bicep parameters, federated credentials). Se você renomear, terá que substituir em 8+ arquivos depois — não vale.

---

## Resumo dos 4 artefatos que vamos cravar

| # | Artefato | Onde vive | Observação |
|---|---|---|---|
| 1 | Resource Group `rg-lab-avancado` | Azure (East US 2) | Tags FinOps obrigatórias (4 tags) |
| 2 | GitHub repo `helpsphere-ia` | GitHub (Private) | `.gitignore` Python + README customizado |
| 3 | Estrutura de pastas IaC | clone local | `.github/workflows`, `infra/`, `src/`, `eval/`, `docs/` |
| 4 | Branch protection rule em `main` | GitHub Settings | PR obrigatório + ≥1 review (foreshadowing Capítulo 05) |

> **Nota pedagógica — por que criar RG manualmente se Bicep faz isso?** Em Bicep você pode declarar RGs no escopo `subscription`, mas **role assignments do SP federado precisam de um RG existente** para serem aplicados (Capítulo 03). Criamos um RG-base manualmente e os Bicep modules dos Capítulos 04-08 deployam **dentro** dele. Pattern enterprise: RG = unidade de governança/billing, criado fora do pipeline de aplicação.

> **Nota pedagógica — por que repo `Private` e não `Public`?** Repos públicos no GitHub têm Actions ilimitado mas expõem `subscription_id`, nomes de recursos e topologia. Privado tem 2.000 minutos/mês free tier (suficiente pra este lab) + zero risco de leak. Em open-source real (template, biblioteca), pode ser público com `secrets.AZURE_SUBSCRIPTION_ID` mascarado.

---

## Passo 2.1 — Criar Resource Group `rg-lab-avancado` no Portal Azure

**No Portal Azure (https://portal.azure.com):**

1. Barra superior → buscar **"Resource groups"** → clicar no item de mesmo nome
2. Topo da listagem → **+ Create**
3. Tab **Basics**:
   - **Subscription:** selecione a sub validada no Capítulo 01 (PAYG/TFTEC/corporate sem ABAC)
   - **Resource group:** `rg-lab-avancado` (exatamente — minúsculas, com hífens)
   - **Region:** `East US 2`
4. Tab **Tags** (FinOps obrigatórias — Capítulo 08 cria Azure Policy que bloqueia recursos sem `cost-center`):
   - **Name:** `cost-center` · **Value:** `apex-helpsphere-ia`
   - **Name:** `environment` · **Value:** `lab`
   - **Name:** `application` · **Value:** `helpsphere-ia`
   - **Name:** `owner` · **Value:** `<seu-email>` (use o mesmo email da conta Azure)
5. Tab **Review + create** → aguarde validação verde → **Create**
6. Aguardar ~5-10s até notificação **"Resource group successfully created"** no canto superior direito

<!-- screenshot: cap02-passo2.1-rg-create-basics.png -->
<!-- screenshot: cap02-passo2.1-rg-create-tags.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> az group create `
>   --name rg-lab-avancado `
>   --location eastus2 `
>   --tags `
>     cost-center=apex-helpsphere-ia `
>     environment=lab `
>     application=helpsphere-ia `
>     owner="<seu-email>"
>
> # Validar criação + tags aplicadas
> az group show --name rg-lab-avancado --query "{name:name, location:location, tags:tags}" -o jsonc
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\` no fim das linhas.

> **Custo:** Resource Groups são **gratuitos** (são containers lógicos, sem billing próprio). Os recursos **dentro** do RG são cobrados — neste Capítulo, ainda nada custa. APIM Developer (~R$ 250/mês ligado, Capítulo 06) e Content Safety (~R$ 50-100/mês, Capítulo 07) entram depois.

> **Nota pedagógica — por que `East US 2` e não `Brazil South`?** Azure OpenAI (do Lab Intermediário) tem disponibilidade regional limitada — `East US 2` tem todos os modelos gpt-4.1 + embeddings + Content Safety. `Brazil South` ainda não tem todos os SKUs. Latência Brasil → East US 2 é ~120ms (aceitável). Em produção real você usa Azure Front Door + região regional pra reduzir.

> **Nota pedagógica — quatro tags, por que todas obrigatórias?** Em Capítulo 08, a Azure Policy `helpsphere-cost-center-tag-required` bloqueia qualquer recurso sem tag `cost-center`. As outras 3 (`environment`, `application`, `owner`) não são bloqueantes mas são best-practice CAF (Cloud Adoption Framework). Comece certo — corrigir tags em 30+ recursos depois é trabalho manual chato.

---

## Passo 2.2 — Criar repositório GitHub `helpsphere-ia`

Este lab é IaC end-to-end — Bicep + workflows + Python vivem num repo GitHub que dispara GitHub Actions ao push (Capítulo 05). Sem repo, sem pipeline.

**No GitHub (https://github.com):**

1. Logado no GitHub → canto superior direito → **+** → **New repository**
2. Preencher formulário:
   - **Owner:** seu user (ou organization se você tem uma)
   - **Repository name:** `helpsphere-ia` (exatamente — minúsculas, com hífen)
   - **Description:** `Lab Avançado D06 — IA Production-grade (Apex HelpSphere)`
   - **Visibility:** ☑ **Private**
   - **Initialize this repository with:** ☑ **Add a README file**
   - **Add .gitignore:** dropdown → selecione **Python**
   - **Choose a license:** None (lab interno, sem licença pública)
3. Clique **Create repository**

<!-- screenshot: cap02-passo2.2-github-new-repo.png -->

4. Após criação, GitHub redireciona para `https://github.com/<seu-username>/helpsphere-ia`. Anote a URL HTTPS (canto superior direito → botão verde **Code** → copy).

> **Alternativa via gh CLI (criar repo direto da máquina sem abrir browser):**
>
> ```powershell
> # Criar repo já com .gitignore Python + README + clone local em uma só call
> gh repo create helpsphere-ia `
>   --private `
>   --description "Lab Avançado D06 — IA Production-grade (Apex HelpSphere)" `
>   --gitignore Python `
>   --add-readme `
>   --clone
>
> Set-Location helpsphere-ia
> ```
>
> Funciona se você já tem `gh` autenticado (`gh auth status` mostrando scopes `repo` + `workflow`). Se faltar `workflow`, rode `gh auth refresh -s workflow`.
>
> **Linux/Mac/WSL:** troque `` ` `` por `\` no fim das linhas e `Set-Location` por `cd`.

> **Custo:** GitHub Free tier inclui repos privados ilimitados + **2.000 minutos/mês** de GitHub Actions em repos privados (em públicos é ilimitado). Este lab consome ~50-100 min/mês em rodadas de CI — você fica longe do limite.

> **Nota pedagógica — `.gitignore` Python específico:** o template padrão do GitHub para Python ignora `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/` etc. Capítulo 04 vai adicionar entradas IaC-specific (`.azure/`, `sp-credentials.json`, `*.bicepparam.local`). **Nunca** commite `sp-credentials.json` — credencial vazada no GitHub público é exfiltrada em segundos por bots.

---

## Passo 2.3 — Clonar repo + estruturar pastas IaC

**No terminal local (Windows PowerShell 7):**

```powershell
# 1. Clone (substitua <seu-username>)
git clone https://github.com/<seu-username>/helpsphere-ia.git
Set-Location helpsphere-ia

# 2. Criar estrutura canônica de pastas
New-Item -ItemType Directory -Force -Path `
  ".github\workflows", "infra\modules", "infra\envs", `
  "src\agent", "src\mcp-server", "src\functions", `
  "eval", "docs" | Out-Null

# 3. Substituir README default por README customizado
# Here-string @'...'@ — fechamento na coluna 0 obrigatório
Set-Content -Path README.md -Value @'
# HelpSphere IA — Production Stack

Stack production-ready de IA para HelpSphere Apex (Lab Avançado D06).

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `.github/workflows/` | CI + CD Staging + CD Prod (criados no Capítulo 05) |
| `infra/` | Bicep templates parametrizados (Capítulo 04) |
| `infra/modules/` | Módulos reutilizáveis (apim, content-safety, app-insights, policy) |
| `infra/envs/` | Parameter files por ambiente (`staging.parameters.json`, `prod.parameters.json`) |
| `src/agent/` | Foundry Agent SDK (Lab Final companion) |
| `src/mcp-server/` | MCP server containerizado |
| `src/functions/` | Azure Functions Python |
| `eval/` | Dataset + script de eval offline (Capítulo 09) |
| `docs/RUNBOOK.md` | Operação em produção (Capítulo 09) |

## Como rodar

Ver `docs/RUNBOOK.md` (criado no Capítulo 09).

## Deploy

CI/CD via GitHub Actions com OIDC federated (Capítulo 05). Sem secrets de Azure no repo.
'@

# 4. Append IaC-specifics ao .gitignore Python que o GitHub criou
Add-Content -Path .gitignore -Value @'

# Lab Avançado D06 specifics
.azure/
sp-credentials.json
*.bicepparam.local
*.log
node_modules/
.env
.env.local
'@

# 5. Commit + push
git add .
git commit -m "feat: initial scaffold helpsphere-ia"
git push origin main
```

<!-- screenshot: cap02-passo2.3-folder-structure-vscode.png -->

> **Alternativa Linux/Mac/WSL (bash):**
>
> ```bash
> # Mesmo workflow com utilitários POSIX (mkdir -p + cat heredoc)
> git clone https://github.com/<seu-username>/helpsphere-ia.git
> cd helpsphere-ia
>
> mkdir -p .github/workflows infra/modules infra/envs src/agent src/mcp-server src/functions eval docs
>
> cat > README.md << 'EOF'
> # HelpSphere IA — Production Stack
> ...
> EOF
>
> cat >> .gitignore << 'EOF'
>
> # Lab Avançado D06 specifics
> .azure/
> sp-credentials.json
> *.bicepparam.local
> *.log
> node_modules/
> .env
> .env.local
> EOF
>
> git add .
> git commit -m "feat: initial scaffold helpsphere-ia"
> git push origin main
> ```

> **Custo:** zero — push pra GitHub é gratuito em qualquer tier.

> **Nota pedagógica — por que separar `infra/modules/` de `infra/envs/`?** Modules contêm a **lógica** (parâmetros, recursos, outputs), parameter files contêm os **valores por ambiente**. Mesmo Bicep `main.bicep` deploya staging e prod, mudando apenas o `--parameters infra/envs/<env>.parameters.json`. Pattern Microsoft canônico — você não duplica template por ambiente, apenas o values file.

> **Nota pedagógica — por que pasta `eval/` separada de `src/`?** `eval/` roda apenas em CI (Capítulo 09 — workflow `cd-staging.yml` job `eval-offline`), não em runtime de produção. Isolar em pasta própria mantém `src/` enxuto pra container builds (Dockerfile copia só `src/`, não `eval/` que tem datasets pesados de teste).

---

## Passo 2.4 — Cravar branch protection rule em `main`

Branch protection garante que **ninguém commita direto em `main`** — todo push passa por PR + review. Em squad de 1 (você), parece formalismo, mas o CI workflow do Capítulo 05 (`ci.yml` em `pull_request`) **só roda se PRs forem o caminho obrigatório**. Sem branch protection, você commita direto, pula CI, e o lab perde valor pedagógico.

**No GitHub (Repository → Settings → Branches):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/branches`
2. Seção **Branch protection rules** → **Add branch protection rule**
3. **Branch name pattern:** `main`
4. Marque as protections (mínimas para este lab):
   - ☑ **Require a pull request before merging**
     - ☑ **Require approvals** → set `1` (você como reviewer de você mesmo — pattern formal)
     - ☑ **Dismiss stale pull request approvals when new commits are pushed**
   - ☑ **Require status checks to pass before merging** (deixe a lista de checks vazia por enquanto — Capítulo 05 vai cravar `lint-bicep` + `lint-python` + `bicep-what-if` aqui)
   - ☑ **Require conversation resolution before merging**
   - ☐ **Do not allow bypassing the above settings** (deixe **desmarcado** por enquanto — você precisa hotfixar como admin se algo travar antes do Capítulo 05)
5. **Create** (ou **Save changes** se já existia)

<!-- screenshot: cap02-passo2.4-branch-protection-main.png -->

> **Alternativa via gh CLI (API REST):**
>
> ```powershell
> # gh CLI não tem comando nativo `gh branch protect`, mas você pode via gh api.
> # PowerShell: passa JSON via arquivo temporário (mais robusto que pipe + heredoc).
> $ProtectionJson = @'
> {
>   "required_status_checks": null,
>   "enforce_admins": false,
>   "required_pull_request_reviews": {
>     "required_approving_review_count": 1,
>     "dismiss_stale_reviews": true
>   },
>   "restrictions": null,
>   "required_conversation_resolution": true
> }
> '@
> $ProtectionJson | Set-Content -Path protection.json -Encoding utf8
>
> gh api -X PUT repos/<seu-username>/helpsphere-ia/branches/main/protection `
>   --input protection.json
>
> Remove-Item protection.json
>
> # Validar protection ativa
> gh api repos/<seu-username>/helpsphere-ia/branches/main/protection `
>   --jq '{required_pull_request_reviews, required_conversation_resolution}'
> ```
>
> **Linux/Mac/WSL:** versão bash equivalente usa `--input - << 'EOF' ... EOF` heredoc inline e `\` no fim das linhas.

> **Custo:** zero — branch protection é feature do GitHub Free tier.

> **Nota pedagógica — por que `Require approvals = 1` em squad de 1?** O pattern importa, não o número. Em prod real, `Required reviewers` aponta pra time GitHub (`@org/sre`) e qualquer membro aprova. Em lab solo, você se aprova — mas o **fluxo PR → review → merge** força você a olhar o diff antes de mergear. Atrapalha hotfix (precisa abrir PR pra você mesmo), mas é parte do treino.

> **Nota pedagógica — por que NÃO marcar "Do not allow bypassing"?** Como repo owner você é admin. Bloquear bypass agora trava você se o CI quebrar antes do Capítulo 05 estar pronto. Marque depois (Capítulo 05 final, quando os 3 status checks estiverem cravados e estáveis).

---

## Passo 2.5 — Validar setup no Portal + GitHub UI

**No Portal Azure:**

1. Barra superior → buscar **"Resource groups"** → confirmar `rg-lab-avancado` listado
2. Clique em `rg-lab-avancado` → menu lateral → **Tags** → confirmar 4 tags presentes (`cost-center`, `environment`, `application`, `owner`)
3. **Overview** → confirmar **Status: Succeeded** + **Location: East US 2**

<!-- screenshot: cap02-passo2.5-rg-overview-tags.png -->

**No GitHub UI:**

1. `https://github.com/<seu-username>/helpsphere-ia` → confirmar README customizado renderizado
2. Aba **Code** → confirmar pastas `.github/`, `infra/`, `src/`, `eval/`, `docs/` visíveis
3. Settings → Branches → confirmar protection rule em `main` ativa
4. Settings → Actions → General → **Workflow permissions** → confirmar **Read and write permissions** (necessário pro Capítulo 05 — federated credentials precisam disso pra `azure/login@v2` funcionar com `id-token: write`)

<!-- screenshot: cap02-passo2.5-github-repo-overview.png -->
<!-- screenshot: cap02-passo2.5-actions-workflow-permissions.png -->

---

## Validação end-to-end

```powershell
# 1. RG criado + tags aplicadas
az group show --name rg-lab-avancado `
  --query "{name:name, location:location, state:properties.provisioningState, costCenter:tags.\`"cost-center\`"}" `
  -o table
# Esperado:
# Name              Location  State      CostCenter
# ----------------  --------  ---------  -----------------
# rg-lab-avancado   eastus2   Succeeded  apex-helpsphere-ia

# 2. Repo GitHub existe + é privado
gh repo view <seu-username>/helpsphere-ia --json name,visibility,defaultBranchRef `
  --jq '{name, visibility, default_branch: .defaultBranchRef.name}'
# Esperado: { "name": "helpsphere-ia", "visibility": "PRIVATE", "default_branch": "main" }

# 3. Estrutura de pastas committed
gh api repos/<seu-username>/helpsphere-ia/contents `
  --jq '[.[] | select(.type == "dir") | .name]'
# Esperado: [".github", "docs", "eval", "infra", "src"]

# 4. Branch protection ativa
gh api repos/<seu-username>/helpsphere-ia/branches/main/protection `
  --jq '.required_pull_request_reviews.required_approving_review_count'
# Esperado: 1
```

> **Linux/Mac/WSL:** troque `` ` `` por `\` no fim das linhas e remova os escapes `` \` `` ao redor de `"cost-center"`.

---

## Checklist final

```text
[ ] Resource Group rg-lab-avancado criado em East US 2
[ ] 4 tags aplicadas (cost-center, environment, application, owner)
[ ] Repo GitHub helpsphere-ia criado (Private)
[ ] .gitignore Python + customizações IaC committed
[ ] README customizado committed (substituiu o default)
[ ] 5 pastas top-level criadas (.github, infra, src, eval, docs)
[ ] Branch protection em main ativa (require PR + 1 approval)
[ ] Workflow permissions = Read and write (para id-token: write futuro)
[ ] az group show retornou Succeeded
[ ] gh repo view confirmou visibility PRIVATE
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`East US 2` vs `eastus2` no `--location`** — Portal aceita "East US 2" mas Azure CLI é case/space-sensitive: `eastus2` (sem espaços, sem capitalização). Erro típico: `BadRequest: The provided location 'East US 2' is not available`. Workaround: sempre usar slug minúsculo `eastus2` no CLI.
- ⚠️ **`gh repo create` falha sem scope `workflow`** — gh CLI default vem só com `repo` scope. Ao tentar criar repo + push de `.github/workflows/*.yml` no Capítulo 05, falha com `refusing to allow an OAuth App to create or update workflow`. Workaround: rodar `gh auth refresh -s workflow,repo` ANTES de criar o repo (não depois).
- ⚠️ **`.gitignore` Python do GitHub NÃO ignora `.azure/`** — quando você roda `azd up` futuramente (ou Bicep com env state local), aparece `.azure/<env>/.env` com tokens cacheados. Sem append no `.gitignore`, você commita tokens. Workaround: o append do Passo 2.3 cobre — confirme via `git check-ignore -v .azure/test`.
- ⚠️ **Branch protection bloqueia primeiro push para `main` se você marcou "Require approvals" ANTES do scaffold** — sequência errada: criar protection → tentar push inicial → bloqueado. Workaround: sempre estruturar pastas + push **primeiro** (Passo 2.3), branch protection **depois** (Passo 2.4). A ordem deste Capítulo já está correta.
- ⚠️ **Tags com valor contendo espaço quebram `--tags` em Azure CLI** — `owner="João Silva"` no Azure CLI com aspas escapadas funciona, mas `cost-center="apex helpsphere ia"` quebra silenciosamente em alguns shells (PowerShell vs bash diferem). Workaround: sem espaços em values de tag — sempre `kebab-case`. PILOTO confirma: todos os values são hífen-separados.
- ⚠️ **Workflow permissions default é "Read repository contents"** — em repos novos, GitHub define **Read-only** como default em Settings → Actions → General. Sem mudar pra "Read and write", o `id-token: write` no workflow YAML do Capítulo 05 funciona, mas `actions/checkout` em PR de fork falha em escrever artifacts. Workaround: ajustar no Passo 2.5 (validar agora pra não tropeçar no Capítulo 05).
- ⚠️ **Conta `live.com` (Visual Studio Enterprise) cria RG mas falha role assignments depois** — você consegue criar `rg-lab-avancado` sem problema neste Capítulo, mas **Capítulo 03 quebra** com `ConditionRequiresAuthorization` no role assignment do SP federado. ABAC só morde em RBAC writes, não em RG create. Workaround: validar ABAC **antes** (Capítulo 01) — se ABAC ativo, pivote sub agora, não depois.

---

## Próximo capítulo

[03 — Service Principal Federated](./03-service-principal-federated.md)
