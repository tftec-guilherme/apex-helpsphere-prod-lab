# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e este projeto adere ao [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

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
