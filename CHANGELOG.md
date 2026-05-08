# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e este projeto adere ao [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

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
