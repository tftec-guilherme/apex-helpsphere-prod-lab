# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e este projeto adere ao [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

## [0.4.0] - 2026-05-19

### Added

**Fork funcional incremental do `apex-rag-lab`** — Lab Avançado agora distribui
código funcional (frontend React 19 + backend Python Quart + tickets-service .NET 10 +
Azure Functions ingestion) **partindo do `apex-rag-lab`** (que herda do `apex-helpsphere`
base). Cada lab passa a ser uma evolução incremental do anterior:

```
apex-helpsphere (base SaaS multi-tenant)
      ↓ + RAG (Bloco 4 — Foundry + AI Search + Document Intelligence)
apex-rag-lab (Lab Inter — fork funcional)
      ↓ + CRUD melhorias + Bicep additions (APIM + Policy + Content Safety)
apex-helpsphere-prod-lab (Lab Avançado — fork funcional v0.4.0)
```

#### Novos diretórios (291 arquivos / ~2 MB)

- **`app/`** (NOVO) — frontend, backend, functions, tickets-service .NET 10
  herdados de `apex-rag-lab` com 5 melhorias CRUD aplicadas no Lab Avançado.
- **`data/`** (NOVO) — migrations + seeds + mocks.
- **`scripts/`** (NOVO) — auth_init, sql_init, setup_search_index, prepdocs etc.
- **`sample-kb/`** (NOVO) — 8 PDFs Apex Retail (RAG seed).
- **`tests/`** (NOVO) — xunit (.NET tickets-service) + pytest (Python).
- **`infra-base/`** (NOVO) — Bicep base do `apex-rag-lab` (Container Apps + SQL +
  ACR + AI Search + Foundry Hub) provisionado por `azd up`. O `infra/` original
  (APIM + Policy + Content Safety adições Lab Avançado) **permanece intacto** e
  continua sendo o foco do guia Portal-first em `docs/`.
- **`azure.yaml`** (NOVO) — `name: rg-lab-avancado` + `infra.path: infra-base`,
  permite `azd up` end-to-end igual ao `apex-rag-lab`.

#### 5 melhorias CRUD aplicadas no `app/`

##### Frontend (`app/frontend/src/`)

1. **UI "Novo Ticket"** (`pages/tickets/NewTicket.tsx` NOVO + rota `tickets/new`):
   anteriormente o botão estava `disabled title="Em breve"`. Agora form completo
   com validação client-side espelhando `RequestValidators.cs` (subject 5-200,
   description ≤16k, category/priority enum) + integração `createTicketApi` →
   redireciona para detalhe do ticket criado.

2. **Fix transition status endpoint** (`pages/tickets/TicketDetail.tsx`):
   anteriormente `patchStatus` chamava `PUT /api/tickets/{id}` com `{status}` que
   era **silenciosamente ignorado** pelo backend (`UpdateAsync` não inclui campo
   `status` no SET). Agora usa `transitionTicketStatusApi` → `POST /transitions`
   (state machine validada com auto-comment atomicamente).

3. **Add Comment habilitado** (`pages/tickets/TicketDetail.tsx`): MessageBar
   "Adicionar comentário — Lab Intermediário" substituída por form real com
   `addCommentApi` real (POST /api/tickets/{id}/comments).

4. **Priority filter server-side** (`pages/tickets/Tickets.tsx` + `api/tickets.ts`):
   filtro de prioridade migrou de client-side (em `useMemo`) para server-side
   (query param `priority` + `q`). Garante consistência de paginação (antes
   filter local podia esvaziar páginas).

5. **UPDATE form completo** (`pages/tickets/TicketDetail.tsx`): edição inline de
   `subject/description/priority` via botão "Editar" no header do detalhe.
   `category` permanece IMMUTABLE após criação (DECISION-LOG.md — preserva taxonomia).

##### Backend (`app/tickets-service/src/`)

- **POST /api/tickets/{id}/comments** (NOVO endpoint):
  - `Endpoints/Models/CreateCommentRequest.cs` — DTO body.
  - `RequestValidators.ValidateCommentContent` — content 1..4000 chars.
  - `ICommentsRepository.AddUserCommentAsync` — INSERT user-driven com defesa
    cross-tenant (SELECT COUNT(1) WHERE tenant_id antes de INSERT).
  - `CommentsRepository.AddUserCommentAsync` — implementa com fallback SQL Server
    (`OUTPUT INSERTED`) + SQLite (`last_insert_rowid()`) para testes.
  - `TicketsEndpoints.AddCommentAsync` — handler com 404 cross-tenant.

- **GET /api/tickets?priority=** (filter expandido):
  - `TicketFilter.Priority` adicionado ao record.
  - `RequestValidators.ValidateAndBuildFilter` parseia + valida enum.
  - `TicketsEndpoints.ListTicketsAsync` aceita `[FromQuery] priority`.
  - `TicketsRepository.BuildWhereClause` adiciona `priority = @priority`.

### Pedagogical impact

- **Aluno do Lab Avançado** exercita CRUD completo (Create + Read + Update +
  Transition + Comments) em produção-grade, não apenas read-mostly como no
  `apex-rag-lab` (que ainda mantém botões desabilitados).
- **Pipeline incremental Inter→Avançado** fica visível e defensável: "no Lab Inter
  fizemos `azd up` do RAG; no Lab Avançado adicionamos CRUD pleno + APIM + Policy
  + Content Safety por cima da mesma base".
- **Backend .NET 10 production-grade** demonstra padrões enterprise (state machine,
  defesa cross-tenant, validação manual, transações atômicas) — defensável em
  audiência sênior.

### QA evidence

- Audit prévio `apex-helpsphere-prod-lab` PowerShell compliance: gate
  `azure-retail/docs/qa/gates/audit-guia-portal-lab-avancado.yml` PASS_AFTER_FIX
  commit 38e61f5.
- Gap analysis produto vs disciplina D06 identificou 3 CRITICAL CRUD findings:
  Novo Ticket disabled, transition endpoint errado, Add Comment dormente —
  todas atendidas nesta release v0.4.0.

### Cross-references

- Origem: `apex-rag-lab` HEAD a9fa5fd (snapshot da árvore copiada 2026-05-19).
- Sister fix: `apex-helpsphere-agente-lab` commit c35f042 (PowerShell fix
  emergencial cap 00 Lab Final na mesma sessão).
- `apex-helpsphere` (base): badges CI/CD removidos do README (workflows
  inexistentes).

---

## [0.3.2] - 2026-05-19

### Fixed

**Compliance PowerShell-first no guia Portal cap 00 + cap 09** — audit `@qa Quinn` em 2026-05-19 (100% coverage, ~8000 linhas em 14 arquivos) detectou 12 findings reais bash residue concentrados no arquivo `docs/00-Lab_Avancado_IA_Producao_Guia_Portal.md` + 1 finding em `docs/09-runbook-eval.md`. Os outros 12 arquivos (caps 01-08 + 10 + PARA-O-ALUNO + README) já estavam CLEAN.

#### CRITICAL (5 fixes — alunos PowerShell travavam)

- **Cap 00 L215-256 — Passo 1.3 estrutura inicial:** trocado fence ```bash + `mkdir -p` + heredoc bash (`cat > README.md << 'EOF' ... EOF`) por fence ```powershell + `New-Item -ItemType Directory -Force -Path` + here-string `@'...'@ | Set-Content`. Quote "Alternativa via gh CLI" também migrada para PS com disclaimer Linux/Mac/WSL.
- **Cap 00 L877-883 — Passo 2.7 what-if Bicep:** trocado `\` line continuation por backtick `` ` ``.
- **Cap 00 L1666-1670 — Passo 5.4 deploy Function App:** trocado `FUNC_AGENT_NAME=$(...)` (atribuição inline bash) por `$FuncAgentName = ...` (PS); `cd` por `Set-Location`.
- **Cap 00 L1730-1740 — Passo 6.1 deploy Azure Policy subscription-scoped:** reescrito bloco com `$SpAppId/$SpObjectId/$Timestamp` (PS variables), backtick line continuation, e `Get-Date -UFormat %s` no lugar de `$(date +%s)`.
- **Cap 09 L312 — Passo 9.5 criar RUNBOOK.md:** trocado `mkdir -p docs/` (instrução numerada em prosa) por `New-Item -ItemType Directory -Force -Path docs`.

#### HIGH (5 fixes — inconsistências de fence)

- **Cap 00 L891-895:** ```bash → ```powershell (git commit Bicep)
- **Cap 00 L987-996:** quote "Alternativa via VS Code + git push" migrada para PS + disclaimer Linux/Mac/WSL.
- **Cap 00 L2056-2060:** ```bash → ```powershell (git commit RUNBOOK)
- **Cap 00 L2162:** ```bash → ```powershell (`az group exists`)
- **Cap 00 L1990-2053 — Passo 7.2 RUNBOOK.md:** wrapper externo ```markdown migrado para 4-backtick (` ```` `) permitindo fence interno ```powershell sem quebrar renderização CommonMark. Bash interno de rollback adaptado para PowerShell.

#### MEDIUM (2 fixes — disclaimers)

- **Cap 00 L2143 — Passo 7.4 cleanup Azure CLI:** quote "Alternativa via Azure CLI" rotulada "(Linux/Mac/WSL — PowerShell)" + `2>/dev/null` → `2>$null` + `echo` → `Write-Host` + disclaimer reverso para Linux/Mac.
- **Cap 00 — refactor consistência:** englobado pelos fixes individuais.

#### BONUS — 17 quotes "Alternativa via" rotuladas (Linux/Mac/WSL — bash)

Auditoria detectou 17 fences ```bash adicionais dentro de blockquotes "Alternativa via Azure CLI", "Alternativa via gh CLI", "Alternativa via curl externo" — sem disclaimer explícito Linux/Mac/WSL. Conteúdo bash (com `\`, `VAR=$()`, heredoc) trava alunos PowerShell que copiam pensando que `az ...` é multi-plat. Todos os 17 títulos atualizados para sinalizar "(Linux/Mac/WSL — bash)" claramente.

### QA evidence

- Gate: `azure-retail/docs/qa/gates/audit-guia-portal-lab-avancado.yml` (FAIL → fixes aplicados)
- Predecessores: Story 06.16 (commit `6253b9e` cobriu caps 01-10) + Story 06.19 (commit `6f497e8` alinhamento Azure real) — cap 00 escapou de ambos
- Stats: 32 fences ```powershell + 0 fences ```bash (era 25 ```bash antes do fix)

### Cross-references

- Stories irmãs Story 06.15 (commit `9635ac1` apex-helpsphere-agente-lab refactor PS) e Story 06.16 (commit `6253b9e` apex-helpsphere-prod-lab caps 01-10)
- Feedback memory: `feedback_d06_lab_windows_powershell_first.md`, `feedback_audit_100pct_coverage.md`, `feedback_validar_subagent_git_log_no_arquivo.md`

---

## [0.3.1] - 2026-05-14

### Added

**Patterns pedagógicos reusados do `apex-helpsphere`** (Story 06.22 Bloco B).

Auditoria `@aiox-master` em 2026-05-14 detectou que `apex-helpsphere` (SaaS base) consolidou `DECISION-LOG.md` (23 decisões) + `APPENDIX-SURPRESAS.md` (35 surpresas) como patterns pedagógicos valiosos, mas este repo não os reusava — mesmo tendo decisões cravadas (D1-D5 Story 06.19) e surpresas catalogáveis (Wave 4 polish, ABAC condition, APIM Developer, etc.).

- **`DECISION-LOG.md`** (novo arquivo) — 7 decisões iniciais consolidadas: D1 RG canonical, D2 Bicep targetScope, D3 remover workflows, D4 doc/03 OPCIONAL, D5 stack isolada, D6 Wave 4 polish dirigido, D7 adoção DECISION-LOG pattern (F-010)
- **`APPENDIX-SURPRESAS.md`** (novo arquivo) — 8 surpresas iniciais catalogadas: ABAC condition, audit sample-by-sample, APIM Developer auto-pause, Bicep targetScope subscription, bash heredoc, string slicing, plan vs reality drift, email config (F-011)
- **`README.md`** — nova seção `## Referências cross-repo` com tabela dos 4 repos D06 (apex-helpsphere SaaS + apex-rag-lab + agente-lab + prod-lab), antes da seção Suporte (F-012)
- **`PARA-O-ALUNO.md`** — nova seção `## Por que stack paralela e não integrada?` com 4 razões pedagógicas/operacionais, antes dos Disclaimers HIGH (F-013)

### Pedagogical impact

- Aluno encontra `DECISION-LOG.md` + `APPENDIX-SURPRESAS.md` nos mesmos lugares que `apex-helpsphere` — consistência pedagógica cross-repo
- "Por que stack paralela?" responde explicitamente pergunta recorrente de alunos que esperavam integração com SaaS
- Cross-link sibling `apex-helpsphere-agente-lab` evita aluno se perder na família de repos

### Cross-references

- Story 06.22: `azure-retail/docs/stories/06.22.companion-labs-readme-sync.md` (Bloco B AC9-AC13)
- Padrão gold standard: `apex-helpsphere/DECISION-LOG.md` + `apex-helpsphere/APPENDIX-SURPRESAS.md`
- Predecessor: Story 06.19 (D1-D5 cravadas) + Wave 4 polish (`e774af0`)

---

## [0.3.0] - 2026-05-10

### Changed (BREAKING)

- **Removido `.github/workflows/`** — Lab Avançado vira 100% Portal+CLI manual. CI/CD via GitHub Actions sai do escopo desta versão (capítulo futuro). Os 3 workflows (`ci.yml`, `cd-staging.yml`, `cd-prod.yml`) e o diretório `.github/` inteiro foram excluídos.
- **Bicep `targetScope='resourceGroup'`** — `infra/main.bicep` não cria mais o RG. Aluno cria `rg-lab-avancado` manualmente (docs/02) e deploya com `az deployment group create -g rg-lab-avancado`. Removidos params `rgName` e `location` (substituídos por `resourceGroup().name` e `resourceGroup().location`). Compilado ARM `infra/main.json` removido (stale).
- **RG canonical: `rg-lab-avancado`** — alinhado com pattern dos Labs Inter (`rg-lab-intermediario`) e Final (`rg-lab-final`). Substitui antigo `rg-helpsphere-ia-prod-{env}` em todos os arquivos (`infra/envs/*.parameters.json`, `README.md`). Cleanup vira UM único `az group delete --name rg-lab-avancado` (não 3 envs).
- **`docs/05-github-actions-pipelines.md` reescrito** para "Aplicar Bicep via Azure CLI" — 7 Passos PowerShell-first (`what-if` + 3 deploys + listar deployments + validação + checklist). Arquivo encolhe de 508L para 323L; substitui 3 workflows YAML por 3 comandos `az deployment group create`.
- **`docs/03-service-principal-federated.md` marcado como OPCIONAL** — SP federado não é mais pré-requisito para Cap 04+. Mantido como artefato pedagógico para alunos que querem aprender OIDC pattern ou estender lab com CI/CD próprio. Pré-requisito real reduz para `az login` + role Contributor em `rg-lab-avancado`.
- **PARA-O-ALUNO.md clarificado** — Lab Avançado é STACK PARALELA à SaaS (não em cima dela). Recursos isolados em `rg-lab-avancado` para fins pedagógicos. 8 pré-requisitos → 7 (item GitHub repo marcado opcional). 3 disclaimers HIGH → 2 (R6 ABAC removido — não relevante sem CI/CD).
- **README.md atualizado** — status v0.3.0-cli-manual. Quick start PowerShell-first com 7 passos. Pré-requisitos reorganizados (3 críticos + 5 opcionais). Stack production-grade table sem linha GitHub Actions. Cleanup com 1 comando único.
- **`infra/envs/*.parameters.json`** (3 arquivos: dev/staging/prod) — removidos params `location` e `rgName` (não usados mais pelo Bicep — RG vem do CLI `-g rg-lab-avancado` e location vem de `resourceGroup().location`).

### Rationale (D1-D5 decisões prof)

| Decisão | Conteúdo | Impacto |
|---------|----------|---------|
| D1 | RG canonical = `rg-lab-avancado` | Alinhamento com Labs Inter/Final |
| D2 | Bicep `targetScope='resourceGroup'` | Bicep não cria RG; aluno cria manual |
| D3 | Remover `.github/workflows/` | Lab vira 100% Portal+CLI manual |
| D4 | (não aplicado nesta release) | — |
| D5 | Stack isolada (não consome SaaS) | Recursos paralelos em RG dedicado |

### Migration notes (de v0.2.0 para v0.3.0)

- Quem já tinha `rg-helpsphere-ia-prod-{env}` provisionado: continua usando até cleanup; novos deploys vão para `rg-lab-avancado`
- Quem tinha SP federado funcional: continua válido para uso fora deste lab (capítulo futuro CI/CD); pode deletar via `docs/10-cleanup.md` se não for usar
- Quem deployava via `az deployment sub create`: migrar para `az deployment group create -g rg-lab-avancado` (mudança no comando obrigatória — não há mais subscription-scope)

### Cross-references

- Story 06.19: `azure-retail/docs/stories/06.19.lab-avancado-azure-alignment.md`
- Decisões D1-D5 do prof: 2026-05-10
- Audit fonte: subagente Explore `ab6651add368bee88`
- Predecessor: Story 06.16 (PowerShell-first refactor — manteve docs alinhados durante este pivot)

## [0.2.0] - 2026-05-10

### Changed

**Refactor PowerShell-First dos guias do Lab Avançado** (Story 06.16 — alinhado ao público Windows da Disciplina D06).

Após audit 100%-coverage `@dev` em 2026-05-10 aplicar a lição da Story 06.15 (audit sample-by-sample subestima em 60-70% — ver `feedback_audit_100pct_coverage.md`), descobrimos escopo real: **26 fences `bash`, 276 line continuations, 7 `VAR=$()`, 2 `export VAR=$()`** distribuídos em TODOS os 10 arquivos `docs/`. Audit anterior reportou apenas 21 findings (~6x menor).

Replicamos o padrão consolidado pela Story 06.13 (`apex-rag-lab`, commits `02b22a7`/`a42d349`/`61c5845`) e Story 06.15 (`apex-helpsphere-agente-lab`, commit `9635ac1`).

- **`docs/01-pre-requisitos.md`** — 9 edições (nota global "⚙️ Sintaxe de comandos shell" + 8 blocos shell convertidos: az login, tooling check, gh repo create, SP create + jq → ConvertFrom-Json, ml workspace show, gh repo view try/catch, grep → Select-String)
- **`docs/02-rg-github-setup.md`** — 5 edições (az group create, gh repo create, **heredoc `cat > README.md <<EOF` → here-string `Set-Content @'...'@`**, gh api branch protection, validação end-to-end com escape JMESPath)
- **`docs/03-service-principal-federated.md`** — 8 edições (2 fixes CRÍTICOS antigas linhas 349/353: `SP_OBJ=$()` e `APP_ID=$()` → atribuições PS)
- **`docs/04a-bicep-modules.md`** — 2 edições (`mkdir -p` → `New-Item`, `ls -la` → `Get-ChildItem -Force`)
- **`docs/04b-bicep-parameters-lint.md`** — 7 edições (build, lint, what-if RG/policy SP, validação end-to-end com `foreach` em vez de `for f in`)
- **`docs/05-github-actions-pipelines.md`** — 4 edições (alternativas VS Code + git push, alternativa gh CLI, validação end-to-end — **blocos YAML `run: |` preservados** porque runner é `ubuntu-latest`)
- **`docs/06-apim-gateway-policies.md`** — 9 edições (2 fixes CRÍTICOS linhas 420/432: `APIM_KEY=$()` e `TOKEN=$()`, polling `until [ ]` → `while`, loop `for i in $(seq 1 105)` → `1..105 | ForEach-Object`)
- **`docs/07-content-safety-app-insights.md`** — 5 edições (3 fixes CRÍTICOS linhas 332/346/347: `FUNC_NAME=$()`, `APIM_URL=$()`, `SUB_KEY=$()`, string slicing Bash `${VAR:0:8}` → `.Substring(0, 8)`)
- **`docs/08-azure-policy-cost-management.md`** — 7 edições (arquivo de maior densidade — 58 line continuations + `date -u +%Y-%m-01` → `Get-Date -Format`, pipe-chain `grep -q && echo OK || echo FAIL` → `if ($Output -match)`)
- **`docs/09-runbook-eval.md`** — 3 edições (**2 fixes CRÍTICOS linhas 345/352: `export APIM_SUBSCRIPTION_KEY=$()` e `export APIM_GATEWAY_URL=$()` → `$env:VAR =`** — únicas ocorrências `export` em todo o repo)
- **`docs/10-cleanup.md`** — 8 edições (4 fences raíz + 4 em blockquotes, `mkdir -p ~/dir`, `for X in $(...)`, `while ... | grep -q true`, `&&` chain → `;` chain)

### Verification

- `grep '^```bash'` nos 10 arquivos: **zero** matches (única exceção proposital: 1 bloco "Alternativa Linux/Mac/WSL (bash)" em `02:199` para heredoc — sintaxe fundamentalmente incompatível com PS)
- `grep '^export [A-Z_]+='` nos 10 arquivos: **zero** matches
- `grep ' \\$'` line continuation bash: **zero** matches em blocos shell (apenas YAML `run: |` em `docs/05`, propositalmente preservado — runner ubuntu-latest)
- `grep '^[A-Z_]+=\$\('` nos 10 arquivos: **zero** matches
- 67 edições totais em 10 arquivos `docs/` aplicadas por 5 subagentes paralelos (~16min wall-clock)

### Pedagogical impact

- **Bloqueante removido** para gravação Bloco 6 D06 (Lab Avançado production-grade). Alunos Windows-first copiam-colam sem quebrar.
- Linha de tradução para Linux/Mac/WSL preservada via nota global em `01-pre-requisitos.md` + notas inline em todos os blocos convertidos.
- AC10 da Story 06.16 (smoke test manual PowerShell 7 dos 3-5 comandos críticos: SP create, APIM key fetch, runbook eval) fica **GATED** para sessão QA separada.

### Cross-references

- Story 06.16: `azure-retail/docs/stories/06.16.lab-avancado-powershell-refactor.md`
- Padrão de fix: Story 06.13 (`apex-rag-lab` commit `61c5845`) + Story 06.15 (`apex-helpsphere-agente-lab` commit `9635ac1`)
- Lição metodológica: `feedback_audit_100pct_coverage.md` (audit 100% coverage obrigatório)

## [0.1.0-init] - 2026-05-07

### Added
- Scaffold inicial do repo companion Lab Avançado D06
- `infra/` com Bicep modules production-ready:
  - `main.bicep` (subscription-scope, cria RG + chama 4 modules)
  - `modules/apim.bicep` (APIM Developer + product `helpsphere-prod` + API `agent-api` + policies inbound rate-limit/JWT/CORS)
  - `modules/content-safety.bicep` (F0 free tier)
  - `modules/app-insights.bicep` (workspace-based + custom metrics LLM)
  - `modules/policy.bicep` (3 Azure Policy assignments: locations + tags + Cosmos public-access)
  - `envs/` com `dev.parameters.json` + `staging.parameters.json` + `prod.parameters.json`
- `.github/workflows/` com 3 YAMLs:
  - `ci.yml` (PR + push feature: bicep-lint + bicep-build + what-if + python-lint)
  - `cd-staging.yml` (push main: deploy + smoke)
  - `cd-prod.yml` (manual approval gate via GitHub Environments + post-deploy smoke)
- `src/agent/` com Function App agent runner:
  - `agent_runner.py` (HTTP trigger + Content Safety wrapper + custom App Insights metrics)
  - `requirements.txt` + `host.json`
- `src/mcp-server/README.md` placeholder (consumido via APIM, não reimplementado)
- `eval/` com offline evaluation harness:
  - `dataset.jsonl` (10 cenários)
  - `run_eval.py` (groundedness via embedding similarity + relevance via gpt-4.1-mini judge + latency)
  - `requirements.txt`
- `docs/` com 10 capítulos skeleton:
  - 01 Pré-requisitos
  - 02 RG + GitHub setup
  - 03 Service Principal Federated (R6 disclaimer ABAC)
  - 04 Bicep modules
  - 05 GitHub Actions pipelines (R6 disclaimer ABAC)
  - 06 APIM gateway + policies (R4 disclaimer Developer R$ 250/mês)
  - 07 Content Safety + App Insights
  - 08 Azure Policy + Cost Management
  - 09 Runbook eval
  - 10 Cleanup (R4 cleanup obrigatório APIM)
- Root files: `README.md` + `PARA-O-ALUNO.md` + `CONTRIBUTING.md` + `SECURITY.md` + `LICENSE` (MIT) + `.gitignore` + `.gitattributes`

### Disclaimers HIGH cravados
- **R4**: APIM Developer R$ 250/mês ligado — cleanup obrigatório OU use Consumption
- **R6**: CI/CD assume sub sem ABAC (TFTEC, PAYG sem ABAC, ou corporate)
- **Free Trial**: NÃO funciona — Azure OpenAI exige PAYG

### Notes
- Conteúdo Portal step-by-step real será cravado em pass posterior quando @ux-design-expert refatorar Lab Avançado guide (Story 06.12 Bloco A).
- Este scaffold é MVP — capítulos `docs/` são headings + outline, conteúdo detalhado vem depois.

[Unreleased]: https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/compare/v0.1.0-init...HEAD
[0.1.0-init]: https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/releases/tag/v0.1.0-init
