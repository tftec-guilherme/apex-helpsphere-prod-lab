# Decision Log — apex-helpsphere-prod-lab (Lab Avançado D06)

Decisões arquiteturais cravadas durante construção do Lab Avançado D06. Cada decisão lista contexto, alternativas consideradas e rationale. Inspirado no padrão `apex-helpsphere/DECISION-LOG.md` (23 decisões cravadas no SaaS base).

---

## #1 — RG canonical `rg-lab-avancado` (D1 Story 06.19)

**Data:** 2026-05-10
**Status:** Cravada

**Contexto:** A Story 06.19 detectou mismatch entre 3 fontes (docs/Bicep/workflows) sobre nome do Resource Group. Bicep default era `rg-helpsphere-ia-prod-{env}`, docs criavam `rg-lab-avancado` manualmente, workflows hardcoded `rg-helpsphere-ia-prod-prod`. Resultado: deployment falhava ou criava recursos em RG errado.

**Decisão:** RG canonical = `rg-lab-avancado` (alinhado com Lab Inter `rg-lab-intermediario` e Lab Final `rg-lab-final`).

**Alternativas consideradas:**
- (b) `rg-helpsphere-ia-prod-{env}` — estende padrão SaaS mas confunde aluno (3 RGs com pattern parecido)
- (c) Algo novo — descartado, fragmentaria mais

**Rationale:** Pedagogicamente claro, FinOps isolado, cleanup vira UM único `az group delete --name rg-lab-avancado --yes --no-wait`. Pattern consistente entre os 3 labs.

---

## #2 — Bicep `targetScope='resourceGroup'` (D2 Story 06.19)

**Data:** 2026-05-10
**Status:** Cravada (BREAKING vs v0.1.0/v0.2.0)

**Contexto:** Bicep `infra/main.bicep` antes tinha `targetScope='subscription'` e criava o RG. Mas docs/02 também ensinavam criar RG manualmente no Portal — conflito.

**Decisão:** `targetScope='resourceGroup'`. Aluno cria `rg-lab-avancado` manualmente (docs/02) e deploya com `az deployment group create -g rg-lab-avancado`. Removidos params `rgName` e `location`.

**Alternativas consideradas:**
- (b) Manter `targetScope='subscription'` — Bicep cria RG, mas docs/02 precisariam ser reescritos para não criar RG manualmente
- (c) Dual-mode — Bicep aceita ambos — descartado, complexidade desnecessária

**Rationale:** 1 fonte de verdade (RG criado manualmente, Bicep só popula). Aluno aprende o ciclo "RG → recursos" explicitamente, sem mágica de subscription-scope.

---

## #3 — Remover `.github/workflows/` (D3 Story 06.19)

**Data:** 2026-05-10
**Status:** Cravada (BREAKING)

**Contexto:** Lab tinha 3 GitHub Actions workflows (`ci.yml`, `cd-staging.yml`, `cd-prod.yml`) com OIDC federated credentials. Durante audit `@aiox-master` em 2026-05-09, foi detectado que conta VSE pessoal `live.com` tem ABAC condition que bloqueia fork-by-student CI (ver `feedback_abac_condition_blocks_fork_by_student.md` na memória do projeto).

**Decisão:** Remover `.github/workflows/` desta versão (v0.3.0). Lab vira 100% Portal+CLI manual. CI/CD via GitHub Actions sai do escopo (capítulo futuro).

**Alternativas consideradas:**
- (b) Manter workflows + documentar requisito ABAC override — descartado, complexidade fora do escopo pedagógico
- (c) Workflows opcionais com flag — descartado, fragmenta jornada

**Rationale:** Aluno domina Bicep + `az deployment group create` primeiro (90% do valor pedagógico). CI/CD vira release dedicada quando tiver demanda real. Reduz superfície de falha (ABAC, OIDC trust, federated SP).

---

## #4 — `docs/03-service-principal-federated.md` marcado OPCIONAL (D3 derivada Story 06.19)

**Data:** 2026-05-10
**Status:** Cravada

**Contexto:** Após remover `.github/workflows/`, Service Principal federado deixa de ser pré-requisito para Cap 04+ (deploy de Bicep). Mantido como artefato pedagógico para alunos que querem aprender OIDC pattern.

**Decisão:** Marcar `docs/03` como OPCIONAL. Pré-requisito real reduz para `az login` + role Contributor em `rg-lab-avancado`.

**Alternativas consideradas:**
- (b) Deletar `docs/03` — descartado, perderia conteúdo OIDC valioso
- (c) Mover `docs/03` para appendix — descartado, mudaria numeração de outros caps

**Rationale:** Conteúdo OIDC valioso preservado para auto-estudo. Pré-req crítico fica mínimo (`az login`).

---

## #5 — Stack ISOLADA, não consome SaaS (D5 Story 06.19)

**Data:** 2026-05-10
**Status:** Cravada

**Contexto:** Inicialmente o Lab Avançado podia consumir ACR/logs do `apex-helpsphere` (SaaS base) para reusar infra. Mas isso exigiria permissions cross-RG complexas + acoplamento pedagógico ruim.

**Decisão:** Stack 100% isolada em `rg-lab-avancado`. Lab Avançado **NÃO consome** `apex-helpsphere`. Aluno aprende o pattern production-grade (APIM Developer, Content Safety, App Insights workspace-based, Azure Policy) em recursos paralelos.

**Alternativas consideradas:**
- (b) Cross-RG integration — lab consome ACR/log SaaS — descartado, complexidade adicional + permissions cross-RG
- (c) Apontar para recursos SaaS via service connections — descartado, fragmenta pedagogia

**Rationale:** Pedagogicamente limpo. Aluno aprende o pattern, não integra. FinOps isolado (cleanup único). Cada lab da disciplina tem sua "ilha" — pedagogia consistente.

> **Cross-ref:** ver `APPENDIX-SURPRESAS.md #1` para detalhes do ABAC condition que reforçou esta decisão.

---

## #6 — Wave 4 polish dirigido (vs outline expansion) (AMB-5 Story 06.21+)

**Data:** 2026-05-11
**Status:** Cravada (SUPERSEDED original AMB-5)

**Contexto:** Plan Wave 4 v1 (2026-05-09) presumia caps `docs/` em outline `v0.1.0-init` precisando expansion. Audit pré-execução em 2026-05-11 revelou que Stories 06.18/06.19 já haviam expandido todos os caps para `v0.2.0-portal` / `v0.3.0-cli-manual`.

**Decisão:** Reescopar Wave 4 para **polish dirigido + AMBs cirúrgicas** ao invés de outline expansion. Aplicar AMB-5 SUPERSEDED — manter split `04a-bicep-modules.md` + `04b-bicep-parameters-lint.md` (já implementado pela Story 06.16).

**Alternativas consideradas:**
- (b) Executar plan v1 mesmo assim — descartado, retrabalho 100%
- (c) Recriar caps do zero — descartado, perda de trabalho consolidado

**Rationale:** Audit antes de dispatch evita retrabalho. Lição salva em `feedback_plan_vs_reality_audit.md` (memória).

> **Cross-ref:** ver `APPENDIX-SURPRESAS.md #2` (lição metodológica audit 100% coverage).

---

## #7 — DECISION-LOG + APPENDIX-SURPRESAS reuso do padrão SaaS (Story 06.22)

**Data:** 2026-05-14
**Status:** Cravada (este arquivo)

**Contexto:** O repo `apex-helpsphere` (SaaS base) consolidou patterns pedagógicos valiosos: `DECISION-LOG.md` (23 decisões) + `APPENDIX-SURPRESAS.md` (35 surpresas). Story 06.22 catalogou esses gaps no prod-lab.

**Decisão:** Reusar os 2 patterns no prod-lab com conteúdo inicial consolidado (7 decisões + 8 surpresas iniciais). Crescer organicamente conforme novas decisões/surpresas emergirem.

**Alternativas consideradas:**
- (b) Concentrar tudo no CHANGELOG — descartado, mistura semântica errada (CHANGELOG = "o que mudou", DECISION-LOG = "por que decidimos assim", SURPRESAS = "armadilhas descobertas")
- (c) Arquivo único `LESSONS.md` — descartado, dificulta navegação pedagógica

**Rationale:** Pattern consistente entre `apex-helpsphere`, `apex-rag-lab` (se vier a adotar) e este repo. Aluno encontra o conteúdo nos lugares esperados.

---

## Referências cross-repo

- **Gold standard:** [`apex-helpsphere/DECISION-LOG.md`](https://github.com/tftec-guilherme/apex-helpsphere/blob/main/DECISION-LOG.md) — 23 decisões cravadas na fundação SaaS
- **Sibling:** [`apex-helpsphere-agente-lab`](https://github.com/tftec-guilherme/apex-helpsphere-agente-lab) — companion Lab Final D06
- **Predecessor:** [`apex-rag-lab`](https://github.com/tftec-guilherme/apex-rag-lab) — companion Lab Intermediário D06

---

**Última revisão:** 2026-05-14 (Story 06.22 — 7 decisões iniciais consolidadas pós Wave 4)
