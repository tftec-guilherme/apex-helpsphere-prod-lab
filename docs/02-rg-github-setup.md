# Capítulo 02 — Resource Group + GitHub repo setup

> **Objetivo:** provisionar o **Resource Group** `rg-lab-avancado` com tags de FinOps obrigatórias, criar o repositório GitHub `helpsphere-ia` (privado, com `.gitignore` Python + estrutura de pastas IaC), commitar o scaffold inicial e cravar branch protection em `main` — deixando o terreno pronto para os próximos capítulos de Service Principal e Bicep modules.
>
> **Tempo:** 25-35 min

---

## Pré-requisitos

- ✅ Capítulo 01 concluído — subscription Azure validada (PAYG sem ABAC OU TFTEC OU corporate sem CA restritiva)
- ✅ Foundry Hub `aifhub-apex-prod` provisionado anteriormente em `rg-lab-intermediario` — apenas referência: este Capítulo não toca AOAI
- ✅ `az` CLI logado (`az login` + `az account show` retornando subscription correta)
- ✅ `gh` CLI autenticado (`gh auth status` mostrando login + scopes `repo`, `workflow`)
- ✅ `git` configurado com `user.name` + `user.email` globais
- ✅ Editor local pronto (VS Code recomendado — usado a partir dos capítulos de Bicep)
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first

> **Atenção breaking — nomenclatura canônica:** este lab usa **`rg-lab-avancado`** como Resource Group e **`helpsphere-ia`** como nome do repo GitHub. Esses dois nomes são referenciados em **todos os Capítulos seguintes** (workflows, Bicep parameters, federated credentials). Se você renomear, terá que substituir em 8+ arquivos depois — não vale.

---

## Resumo dos 4 artefatos que vamos cravar

| # | Artefato | Onde vive | Observação |
|---|---|---|---|
| 1 | Resource Group `rg-lab-avancado` | Azure (East US 2) | Tags FinOps obrigatórias (4 tags) |
| 2 | GitHub repo `helpsphere-ia` | GitHub (Private) | `.gitignore` Python + README customizado |
| 3 | Estrutura de pastas IaC | clone local | `.github/workflows`, `infra/`, `src/`, `eval/`, `docs/` |
| 4 | Branch protection rule em `main` | GitHub Settings | PR obrigatório + ≥1 review |

> **Nota pedagógica — por que criar RG manualmente se Bicep faz isso?** Em Bicep você pode declarar RGs no escopo `subscription`, mas **role assignments precisam de um RG existente** para serem aplicados. Criamos um RG-base manualmente e os Bicep modules deployam **dentro** dele. Pattern enterprise: RG = unidade de governança/billing, criado fora do pipeline de aplicação.

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
4. Tab **Tags** (FinOps obrigatórias — uma Azure Policy futura bloqueia recursos sem `cost-center`):
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

> **Custo:** R$ 0 — Resource Groups são gratuitos (containers lógicos, sem billing próprio). Os recursos **dentro** do RG são cobrados — neste Capítulo, ainda nada custa. APIM Developer (~R$ 250/mês ligado) e Content Safety (~R$ 50-100/mês) entram em capítulos posteriores.

> **Nota pedagógica — por que `East US 2` e não `Brazil South`?** Azure OpenAI tem disponibilidade regional limitada — `East US 2` tem todos os modelos gpt-4.1 + embeddings + Content Safety. `Brazil South` ainda não tem todos os SKUs. Latência Brasil → East US 2 é ~120ms (aceitável). Em produção real você usa Azure Front Door + região regional pra reduzir.

> **Nota pedagógica — quatro tags, por que todas obrigatórias?** Uma Azure Policy futura (`helpsphere-cost-center-tag-required`) bloqueia qualquer recurso sem tag `cost-center`. As outras 3 (`environment`, `application`, `owner`) não são bloqueantes mas são best-practice CAF (Cloud Adoption Framework). Comece certo — corrigir tags em 30+ recursos depois é trabalho manual chato.

---

## Passo 2.2 — Criar repositório GitHub `helpsphere-ia`

Este lab é IaC end-to-end — Bicep + workflows + Python vivem num repo GitHub que serve como source-of-truth do código de infra e aplicação. Sem repo, sem pipeline.

**No GitHub (https://github.com):**

1. Logado no GitHub → canto superior direito → **+** → **New repository**
2. Preencher formulário:
   - **Owner:** seu user (ou organization se você tem uma)
   - **Repository name:** `helpsphere-ia` (exatamente — minúsculas, com hífen)
   - **Description:** `Lab Avançado — IA Production-grade (Apex HelpSphere)`
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
>   --description "Lab Avançado — IA Production-grade (Apex HelpSphere)" `
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

> **Custo:** R$ 0 — GitHub Free tier inclui repos privados ilimitados + **2.000 minutos/mês** de GitHub Actions em repos privados (em públicos é ilimitado). Este lab consome ~50-100 min/mês em rodadas de CI — você fica longe do limite.

> **Nota pedagógica — `.gitignore` Python específico:** o template padrão do GitHub para Python ignora `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/` etc. **Não cobre** `.env` nem `.azure/` — precisa adicionar manualmente (Passo 2.3). **Nunca** commite `sp-credentials.json` nem `.env` — credencial vazada no GitHub público é exfiltrada em segundos por bots.

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

Stack production-ready de IA para HelpSphere Apex (Lab Avançado).

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `.github/workflows/` | CI + CD Staging + CD Prod |
| `infra/` | Bicep templates parametrizados |
| `infra/modules/` | Módulos reutilizáveis (apim, content-safety, app-insights, policy) |
| `infra/envs/` | Parameter files por ambiente (`staging.parameters.json`, `prod.parameters.json`) |
| `src/agent/` | Foundry Agent SDK |
| `src/mcp-server/` | MCP server containerizado |
| `src/functions/` | Azure Functions Python |
| `eval/` | Dataset + script de eval offline |
| `docs/RUNBOOK.md` | Operação em produção |

## Como rodar

Ver `docs/RUNBOOK.md`.

## Deploy

Infra deployada via Azure CLI manual (`az deployment group create`) ou via GitHub Actions com OIDC federated. Sem secrets de Azure no repo.
'@

# 4. Append IaC-specifics ao .gitignore Python que o GitHub criou
Add-Content -Path .gitignore -Value @'

# Lab Avançado specifics
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
> # Lab Avançado specifics
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

> **Custo:** R$ 0 — push pra GitHub é gratuito em qualquer tier.

> **Atenção breaking — nome `helpsphere-ia` é cravado downstream:** o nome do repo aparece em **8+ arquivos** de Bicep parameters, federated credentials e workflows ao longo dos próximos capítulos. Renomear depois exige sweep manual em todos. Mantenha exatamente `helpsphere-ia`.

> **Nota pedagógica — por que separar `infra/modules/` de `infra/envs/`?** Modules contêm a **lógica** (parâmetros, recursos, outputs), parameter files contêm os **valores por ambiente**. Mesmo Bicep `main.bicep` deploya staging e prod, mudando apenas o `--parameters infra/envs/<env>.parameters.json`. Pattern Microsoft canônico — você não duplica template por ambiente, apenas o values file.

> **Nota pedagógica — por que pasta `eval/` separada de `src/`?** `eval/` roda apenas em CI (job `eval-offline`), não em runtime de produção. Isolar em pasta própria mantém `src/` enxuto pra container builds (Dockerfile copia só `src/`, não `eval/` que tem datasets pesados de teste).

---

## Passo 2.4 — Cravar branch protection rule em `main`

Branch protection garante que **ninguém commita direto em `main`** — todo push passa por PR + review. Em squad de 1 (você), parece formalismo, mas um futuro CI workflow (`ci.yml` em `pull_request`) **só roda se PRs forem o caminho obrigatório**. Sem branch protection, você commita direto, pula CI, e o lab perde valor pedagógico.

**No GitHub (Repository → Settings → Branches):**

1. Acesse `https://github.com/<seu-username>/helpsphere-ia/settings/branches`
2. Seção **Branch protection rules** → **Add branch protection rule**
3. **Branch name pattern:** `main`
4. Marque as protections (mínimas para este lab):
   - ☑ **Require a pull request before merging**
     - ☑ **Require approvals** → set `1` (você como reviewer de você mesmo — pattern formal)
     - ☑ **Dismiss stale pull request approvals when new commits are pushed**
   - ☑ **Require status checks to pass before merging** (deixe a lista de checks vazia por enquanto — um capítulo futuro vai cravar `lint-bicep` + `lint-python` + `bicep-what-if` aqui)
   - ☑ **Require conversation resolution before merging**
   - ☐ **Allow deletions** (deixe **desmarcado** — proteção extra contra `git push --delete origin main` acidental)
   - ☐ **Do not allow bypassing the above settings** (deixe **desmarcado** por enquanto — você precisa hotfixar como admin se algo travar)
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
>   "required_conversation_resolution": true,
>   "allow_deletions": false
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

> **Custo:** R$ 0 — branch protection é feature do GitHub Free tier (público ou privado).

> **Nota pedagógica — por que `Require approvals = 1` em squad de 1?** O pattern importa, não o número. Em prod real, `Required reviewers` aponta pra time GitHub (`@org/sre`) e qualquer membro aprova. Em lab solo, você se aprova — mas o **fluxo PR → review → merge** força você a olhar o diff antes de mergear. Atrapalha hotfix (precisa abrir PR pra você mesmo), mas é parte do treino.

> **Nota pedagógica — por que NÃO marcar "Do not allow bypassing"?** Como repo owner você é admin. Bloquear bypass agora trava você se o CI quebrar antes dos status checks estarem cravados e estáveis. Marque depois, quando o pipeline já estiver de pé.

---

## Passo 2.5 — Validar setup no Portal + GitHub UI

**No Portal Azure:**

1. Barra superior → buscar **"Resource groups"** → confirmar `rg-lab-avancado` listado
2. Clique em `rg-lab-avancado` → menu lateral → **Tags** → confirmar 4 tags presentes (`cost-center`, `environment`, `application`, `owner`)
3. **Overview** → confirmar **Status: Succeeded** + **Location: East US 2**

<!-- screenshot: cap02-passo2.5-rg-overview-tags.png -->

**No GitHub UI:**

1. `https://github.com/<seu-username>/helpsphere-ia` → confirmar README customizado renderizado + arquivos commitados (`README.md`, `.gitignore`) visíveis na listagem da raiz
2. Aba **Code** → confirmar pastas `.github/`, `infra/`, `src/`, `eval/`, `docs/` visíveis
3. Settings → Branches → confirmar protection rule em `main` ativa (linha mostrando `main` + `Require a pull request before merging`)
4. Settings → Actions → General → **Workflow permissions** → confirmar **Read and write permissions** (necessário para futuros workflows com `id-token: write` para login OIDC federated)

<!-- screenshot: cap02-passo2.5-github-repo-overview.png -->
<!-- screenshot: cap02-passo2.5-actions-workflow-permissions.png -->

> **Checkpoint visual final:** três telas devem estar lado a lado:
>
> 1. **Portal Azure** → RG `rg-lab-avancado` blade Overview com `Status: Succeeded`, `Location: East US 2` e 4 tags na aba Tags
> 2. **GitHub Code page** → `https://github.com/<seu-username>/helpsphere-ia` mostrando README renderizado + pastas `.github/`, `infra/`, `src/`, `eval/`, `docs/` na listagem
> 3. **GitHub Settings → Branches** → linha de protection rule cravada em `main`
>
> Se os três checks estão verdes, o terreno está pronto para o próximo capítulo.

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
- ⚠️ **`gh repo create --private` retorna 403 silencioso sem scope `repo`** — gh CLI default em algumas instalações vem sem o scope `repo` completo (só `public_repo`). Tentativa de criar repo privado falha com mensagem genérica ou retorna repo público sem aviso claro. Workaround: rodar `gh auth status` antes — se faltar `repo` scope, executar `gh auth refresh -s repo,workflow` ANTES do `gh repo create`.
- ⚠️ **`gh repo create` falha sem scope `workflow` quando você for cravar `.github/workflows/*.yml`** — gh CLI default vem só com `repo` scope. Push posterior de YAMLs em `.github/workflows/` falha com `refusing to allow an OAuth App to create or update workflow`. Workaround: rodar `gh auth refresh -s workflow,repo` AGORA, antes de criar o repo.
- ⚠️ **`.gitignore` Python do GitHub NÃO ignora `.azure/` nem `.env`** — o template padrão pega `__pycache__/`, `*.pyc`, `.venv/` mas deixa de fora `.azure/` (state local do `azd`) e `.env` (variáveis de ambiente com secrets). Sem append no `.gitignore`, você commita tokens e secrets ao primeiro push. Workaround: o append do Passo 2.3 cobre ambos — confirme via `git check-ignore -v .env` e `git check-ignore -v .azure/test`.
- ⚠️ **Repo nome `helpsphere-ia` é cravado em 8+ arquivos downstream** — Bicep parameters, federated credentials e workflows nos capítulos seguintes assumem exatamente esse nome. Renomear depois exige sweep manual completo (cada arquivo). Workaround: mantenha `helpsphere-ia` literal no Passo 2.2 — se quiser nome diferente, decida AGORA antes de avançar.
- ⚠️ **Branch protection bloqueia primeiro push para `main` se você marcou "Require approvals" ANTES do scaffold** — sequência errada: criar protection → tentar push inicial → bloqueado. Workaround: sempre estruturar pastas + push **primeiro** (Passo 2.3), branch protection **depois** (Passo 2.4). A ordem deste Capítulo já está correta.
- ⚠️ **Branch protection `Allow deletions` é default-ON em alguns templates** — em repos novos com algumas configs de organização, o checkbox `Allow deletions` pode vir marcado. Isso permite `git push --delete origin main` por engano, perdendo o branch. Workaround: cravar `Allow deletions` desmarcado explicitamente no Passo 2.4 (mesmo que default já seja off, vale confirmar — `gh api` set `allow_deletions: false` no JSON).
- ⚠️ **Tags com valor contendo espaço quebram `--tags` em Azure CLI** — `owner="João Silva"` no Azure CLI com aspas escapadas funciona, mas `cost-center="apex helpsphere ia"` quebra silenciosamente em alguns shells (PowerShell vs bash diferem). Workaround: sem espaços em values de tag — sempre `kebab-case`.
- ⚠️ **Tags FinOps obrigatórias são pré-requisito para Policy futura** — sem as 4 tags (`environment`, `application`, `cost-center`, `owner`) no RG, a Azure Policy `require-cost-center-tag` cravada em capítulo posterior bloqueia novos recursos com `RequestDisallowedByPolicy`. Workaround: cravar as 4 tags AGORA no Passo 2.1 — corrigir depois exige re-tag de cada recurso individualmente.
- ⚠️ **Workflow permissions default é "Read repository contents"** — em repos novos, GitHub define **Read-only** como default em Settings → Actions → General. Sem mudar pra "Read and write", o `id-token: write` em workflow YAML futuro funciona, mas `actions/checkout` em PR de fork falha em escrever artifacts. Workaround: ajustar no Passo 2.5 (validar agora).
- ⚠️ **Conta `live.com` (Visual Studio Enterprise) cria RG mas falha role assignments depois** — você consegue criar `rg-lab-avancado` sem problema neste Capítulo, mas o próximo (Service Principal Federated) quebra com `ConditionRequiresAuthorization` no role assignment do SP federado. ABAC só morde em RBAC writes, não em RG create. Workaround: validar ABAC **antes** (Capítulo 01) — se ABAC ativo, pivote sub agora, não depois.

---

## Próximo capítulo

[03 — Service Principal Federated](./03-service-principal-federated.md)
