# Capítulo 09 — Runbook eval

> **Objetivo:** cravar a **estrutura completa** do ciclo de **avaliação offline** do agente HelpSphere Tier 1 com dataset de 10 cenários canônicos (`eval/eval_scenarios.json` JSON array — cenários S01-S10 cobrindo Comercial, TI/Fiscal, TI/Loja, TI/Rede, Operacional, RH, Fallback, Financeiro), `eval/run_eval.py` v0.1.0 esqueleto com `NotImplementedError` em `run_scenario` (implementação completa em release futura), 3 métricas com thresholds enforced (latency p95, precision de citações, fallback rate), harness pytest stub para validar estrutura do dataset, e `docs/RUNBOOK.md` com 4 cenários operacionais comuns + procedimentos de rollback/key-rotation/DR.
>
> **Tempo:** 60-80 min (não inclui ~5-15 min de propagação do APIM key + ingest do App Insights)
>
> **Status:** `v0.2.0-portal` — entrega estrutura pedagógica completa (script esqueleto + dataset + métricas + harness + runbook), eval runner real fica fora do escopo desta versão

---

## Pré-requisitos

- ✅ Capítulo 05 concluído — Bicep deployado em `rg-lab-avancado` cobrindo APIM + Content Safety + App Insights + Policy Assignments
- ✅ Capítulo 06 concluído — APIM `apim-helpsphere-staging` provisionado com Product `helpsphere-prod` publicado e endpoint `/agent/chat` atrás de `<validate-jwt>` + rate-limit
- ✅ Capítulo 07 concluído — Function `func-helpsphere-agent` instrumentada com 6 custom metrics OTel (`llm.cost_brl`, `llm.prompt_tokens`, `llm.groundedness`, `llm.latency_p95`, `safety.hit`, `agent.escalation`); App Insights `ai-helpsphere-staging` recebendo dados
- ✅ Capítulo 08 concluído — 3 policies + Budget + Action Group cravados (relevante para o cenário "Custo dispara além do budget" no RUNBOOK)
- ✅ Agente HelpSphere Tier 1 endpoint disponível (provisionado em lab anterior cross-repo) — variável `AGENT_URL` apontando para o endpoint do agente que usa RAG sobre KB corporativo
- ✅ Python 3.11 local com `pip install -r eval/requirements.txt` (`requests`, `tenacity`, `python-dotenv`, `pytest`) instalado
- ✅ APIM **subscription key** (master) via `az apim subscription show` ou Portal → APIM → Subscriptions → `master` → Show keys
- ✅ Vars `.env` local (não commitar): `APIM_SUBSCRIPTION_KEY`, `APIM_GATEWAY_URL=https://apim-helpsphere-staging.azure-api.net`, `AGENT_URL=<endpoint do agente Tier 1>`
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first

> **Nota pedagógica — por que stubs e não eval rodando?** Este Capítulo entrega a **estrutura completa** (script esqueleto, dataset 10 cenários, métricas, thresholds, harness pytest) mas o **eval runner em si fica como `NotImplementedError`**. A implementação completa (asyncio + httpx + parser de citações + report agregado) é entregue em release futura — fora do escopo deste lab. **Foco aqui:** você aprende **o quê medir** em produção (precision, fallback rate, latency p95) — bem mais importante que **como medir** (boilerplate Python). Em produção real, ferramentas como `azure-ai-evaluation` SDK ou Phoenix da Arize fazem isso pronto.

---

## Resumo do que vamos cravar nesta etapa

| Camada | Item | Onde fica | Custo absoluto |
|---|---|---|---|
| **Dataset** | `eval/eval_scenarios.json` 10 cenários (S01-S10 cobrindo Comercial, TI/Fiscal, TI/Loja, TI/Rede, Operacional, RH, Fallback, Financeiro) | Repo raíz `eval/` | R$ 0 |
| **Runner** | `eval/run_eval.py` v0.1.0 esqueleto com `NotImplementedError` | `eval/run_eval.py` | — |
| **Métricas** | 3 métricas com thresholds documentados (latency_p95_ms, precision, fallback_rate) | Constantes do runner | — |
| **Harness** | `tests/test_eval_smoke.py` valida estrutura do dataset (3 testes) | `tests/test_eval_smoke.py` | R$ 0 |
| **Output** | `eval/report.json` artifact uploaded por `actions/upload-artifact@v4` | gerado em cada run staging (release futura) | R$ 0 |
| **Runbook** | `docs/RUNBOOK.md` com 4 cenários + 3 procedimentos | `docs/RUNBOOK.md` no repo | R$ 0 |
| **Smoke (futuro)** | run local contra agente Tier 1 staging (10 chamadas) | sua máquina | ~R$ 0,05 (gpt-4.1-mini) |

> **Custo do smoke run (release futura):** `gpt-4.1-mini` (in ~R$ 0,75/1M tokens, out ~R$ 3,00/1M) × 10 cenários × ~700 tokens = ~**R$ 0,03-0,05/run**. Mesmo com 100 PRs/mês: < R$ 5/mês.

> **Nota pedagógica — por que stubs + 10 cenários em vez de implementação completa e dataset gigante?** Separar **estrutura** (thresholds, dataset shape, formato report.json, integração pipeline) da **implementação semântica** (embeddings, judge prompt, sampling, asyncio HTTP client) reduz risco — se a métrica falha em prod, troca-se a implementação sem mexer em pipeline/runbook (TDD aplicado a eval). 10 cenários = amostra mínima cobrindo as principais categorias do KB corporativo (Comercial, TI, Operacional, RH, Fiscal, Financeiro, Fallback) sem inflar custo por PR; em produção real cresce para ~200 cenários por persona × jornada rodando nightly.

---

## Passo 9.1 — Criar `eval/eval_scenarios.json` com os 10 cenários canônicos

O dataset é o coração do eval offline. Cada cenário tem **input + expected_citations + expected_outcome + category**. Ele vive no repo (versionado) para que mudanças sejam revisadas via PR.

**No VS Code (workspace local):**

1. Crie a pasta `eval/` na raiz do repo se ainda não existir:

```powershell
New-Item -ItemType Directory -Force eval
```

2. Crie `eval/eval_scenarios.json` (JSON array com 10 objetos — formato canônico legível para humano + diff-friendly)
3. Cole o conteúdo abaixo (10 cenários `S01-S10` cravados completos):

```json
[
  {
    "id": "S01-devolucao-cdc",
    "category": "Comercial",
    "input": "Cliente comprou geladeira em 12/03 e quer devolver em 25/03 alegando desistência. Já passou dos 7 dias CDC.",
    "expected_citations": ["faq_pedidos_devolucao.pdf", "politica_reembolso_lojista.pdf"],
    "expected_outcome": "agente escala para alçada (R$ 2-5k = Marina), oferece opções flexíveis"
  },
  {
    "id": "S02-nfe-rejeicao-539",
    "category": "TI/Fiscal",
    "input": "SEFAZ-SP retornou Rejeição 539 num B2B R$ 18.430. Travado há 4h.",
    "expected_citations": ["runbook_sap_fi_integracao.pdf"],
    "expected_outcome": "agente identifica CFOP incompatível, sugere validar 5102 vs 6102"
  },
  {
    "id": "S03-pos-nfce-travando",
    "category": "TI/Loja",
    "input": "Caixa 03 Pinheiros: POS trava em NFC-e com >8 itens. 3x hoje.",
    "expected_citations": ["manual_pos_funcionamento.pdf"],
    "expected_outcome": "agente cita TKT-11 referência, sugere upgrade thread pool BIGiPOS"
  },
  {
    "id": "S04-vpn-loggi-cert",
    "category": "TI/Rede",
    "input": "VPN Loggi caiu após renew cert. IPsec phase-2 'no proposal chosen'.",
    "expected_citations": ["runbook_problemas_rede.pdf"],
    "expected_outcome": "agente cita TKT-20, identifica divergência SHA1/SHA256"
  },
  {
    "id": "S05-doca-atraso",
    "category": "Operacional",
    "input": "Caminhão Tok&Stok agendado 08h chegou 12h. Doca ocupada.",
    "expected_citations": ["manual_operacao_loja_v3.pdf"],
    "expected_outcome": "agente cita política demurrage após 2h, calcula R$ 380/hora"
  },
  {
    "id": "S06-rh-gestacao",
    "category": "RH",
    "input": "Operadora caixa turno noturno atestado gravidez risco — recomenda turno diurno.",
    "expected_citations": ["politica_dados_lgpd.pdf"],
    "expected_outcome": "agente encaminha para coordenação + RH-Folha, política transferência prioritária"
  },
  {
    "id": "S07-fallback-pergunta-fora-kb",
    "category": "Fallback test",
    "input": "Qual a previsão do tempo amanhã em São Paulo?",
    "expected_citations": [],
    "expected_outcome": "agente responde 'fora do meu escopo, sou Tier 1 HelpSphere'"
  },
  {
    "id": "S08-mei-retencao",
    "category": "Financeiro",
    "input": "Contratação consultoria MEI R$ 12.500 — orientação retenções aplicáveis.",
    "expected_citations": ["politica_reembolso_lojista.pdf"],
    "expected_outcome": "agente cita IRRF 1,5% + INSS 11% MEI, recomenda confirmar enquadramento"
  },
  {
    "id": "S09-sped-contribuicoes",
    "category": "Fiscal",
    "input": "PVA-SPED Contribuições rejeitou março/2026 erro M210. Diferença R$ 12.300 a maior.",
    "expected_citations": ["politica_reembolso_lojista.pdf"],
    "expected_outcome": "agente identifica parametrização CFOP devolução, sugere ajuste retroativo"
  },
  {
    "id": "S10-tv-cancelamento-online",
    "category": "Comercial",
    "input": "Cliente Smart TV 65 parcelada cartão Itaú, pediu cancelar 28h depois.",
    "expected_citations": ["faq_pedidos_devolucao.pdf"],
    "expected_outcome": "agente cita CDC 7 dias online + política interna escalonamento >24h"
  }
]
```

4. Save em UTF-8 (sem BOM). Commit local.

<!-- screenshot: cap09-passo9.1-eval-scenarios-json-vscode.png -->

> **Alternativa Linux/Mac/WSL (bash):** `mkdir -p eval` + criar `eval/eval_scenarios.json` via editor de preferência. Custo R$ 0.

> **Nota pedagógica — JSON array vs JSONL:** JSON array é mais legível para humano e funciona com `json.loads(Path("...").read_text())` em uma linha. JSONL ganha quando o dataset cresce >1000 cenários e você quer streaming linha-a-linha sem carregar tudo em RAM. Para 10 cenários, JSON array é a escolha pragmática — diff de PR mostra mudança por cenário (cada um em ~5 linhas), igual a JSONL na prática.

> **Nota pedagógica — por que cenário S07 (fallback) no dataset?** **Você precisa testar o piso do fallback.** Se algum dia o agente parar de reconhecer perguntas fora do escopo (drift de prompt, KB contaminado), S07 falha no CI — **regressão de fallback vira build vermelho**. Cenário Fallback explícito é parte do contrato production-grade.

> **Nota pedagógica — por que `expected_citations` aponta para PDFs específicos?** O agente HelpSphere Tier 1 usa **RAG** sobre um KB corporativo de ~8 PDFs (FAQs, runbooks, políticas). A métrica `precision` (definida no Passo 9.3) compara as citações reais do agente contra `expected_citations` — se ele responder S02 sem citar `runbook_sap_fi_integracao.pdf`, perde precision. **Atenção tiktoken truncation 8192 tokens:** PDFs grandes podem ser truncados no indexing — se um PDF essencial sumir do KB, cenário relacionado falha. Re-indexar com chunking <8000 tokens (margem segura).

> **Nota pedagógica — `VectorizedQuery` vs `VectorizableTextQuery`:** o agente Tier 1 usa `VectorizedQuery` (vetor pré-computado, index sem vectorizer integrado) ao consultar o AI Search. Se algum dia o index for re-criado com vectorizer integrado, mudará para `VectorizableTextQuery`. Diferença afeta latency p95 — manter olho na métrica quando re-indexar.

---

## Passo 9.2 — Criar `eval/requirements.txt`

Dependências mínimas do runner + harness pytest. **Não inclui `azure-ai-projects` nem `httpx`/`asyncio`** — ficam para release futura quando o eval runner real for implementado.

```text
# eval/requirements.txt
requests==2.32.3
tenacity==9.0.0
python-dotenv==1.0.1
pytest==8.3.3
```

Salve em `eval/requirements.txt` na raiz do repo, commit local.

> **Custo:** R$ 0.

> **Nota pedagógica — pin exato (`==`) e não range (`>=`):** evita "build verde hoje, vermelho amanhã" se um patch quebrar o eval. Pinning estrito + Dependabot PRs = você vê a atualização proposta antes dela entrar.

---

## Passo 9.3 — Criar `eval/run_eval.py` esqueleto (com `NotImplementedError`)

Este é o esqueleto do runner. **A função `run_scenario` levanta `NotImplementedError("Implementação completa em release futura")`** — explicitado no docstring do módulo e no comentário inline. O foco aqui é **estrutura + thresholds + categorização** — não implementação.

**No VS Code:**

1. Crie `eval/run_eval.py` (~30 linhas — esqueleto minimalista com TODOs marcados)
2. **Estrutura mínima** (cole no arquivo):

```python
"""
run_eval.py — Eval runner para o agente HelpSphere Tier 1
Status: v0.1.0 stub — implementação completa em release futura.
"""
import json
import asyncio
from pathlib import Path

THRESHOLDS = {
    "latency_p95_ms": 2000,      # latência 95th percentile <2s
    "precision": 0.85,            # >85% citações corretas do KB
    "fallback_rate": 0.15,        # <15% queries cain em fallback
}

async def run_scenario(scenario: dict) -> dict:
    """Executa 1 cenário contra o agente, retorna métricas."""
    # TODO: implementar scenario runner
    # 1. httpx POST para endpoint do agente
    # 2. Capturar response + latency
    # 3. Parse citações e comparar com expected_citations
    # 4. Retornar dict com metrics
    raise NotImplementedError("Implementação completa em release futura")

async def main():
    scenarios = json.loads(Path("eval_scenarios.json").read_text(encoding="utf-8"))
    results = []
    for scenario in scenarios:
        result = await run_scenario(scenario)
        results.append(result)
    # TODO: agregar + report markdown contra THRESHOLDS

if __name__ == "__main__":
    asyncio.run(main())
```

3. Save em UTF-8 (sem BOM). Commit local.

<!-- screenshot: cap09-passo9.3-run-eval-py-vscode-stub.png -->

> **Custo:** R$ 0 (arquivo Python versionado).

### 3 métricas + thresholds documentados

| Métrica | Threshold | Significado | Como medir (release futura) |
|---|---|---|---|
| `latency_p95_ms` | < 2000 ms | 95º percentil de latência por chamada (P95 cobre tail) | `httpx.AsyncClient` time.perf_counter ao redor do POST |
| `precision` | > 0.85 | Fração de citações retornadas pelo agente que batem com `expected_citations` | Set intersection / Set returned |
| `fallback_rate` | < 0.15 | Fração de queries que caíram em fallback (resposta "fora do meu escopo") | Detectar via padrão regex/keyword na resposta |

> **Nota pedagógica — por que P95 e não P50/P99?** P50 esconde tail (50% dos usuários ainda têm experiência ruim). P99 é volátil em datasets pequenos (10 cenários → 1 outlier dispara P99). P95 é o sweet spot — produção SLA típico (Microsoft, Google, Anthropic todos publicam P95).

> **Nota pedagógica — por que `precision` e não `recall`?** Em RAG, citar **lixo** (PDF errado) é pior que **não citar** documento válido — usuário desconfia da resposta inteira. Precision penaliza false positives no set de citações; recall penalizaria false negatives. Para Tier 1 com KB pequeno (~8 PDFs), precision >> recall em importância.

> **Nota pedagógica — por que `NotImplementedError` e não placeholder retornando dummy?** `NotImplementedError` **falha alto** em qualquer pipeline CI que tentar rodar `python run_eval.py`. Placeholder retornando dummy poderia mascarar como sucesso e gerar `report.json` com dados inventados — pior que falhar. **Logs honestos > aspiracionais.** Quando a implementação real entrar, troca-se só o corpo de `run_scenario` — resto do esqueleto (THRESHOLDS, main loop, scenarios loading) permanece igual.

> **Nota pedagógica — `tenacity` ficará no runner real:** APIM Developer ocasionalmente retorna 502/504 sob carga (~1-2% das chamadas em smoke). Backoff 2-10s × 3 tentativas elimina ~99% dos flakes — pattern padrão de production HTTP clients. Adicionar `@retry(stop=stop_after_attempt(3), wait=wait_exponential(min=2, max=10))` ao redor do `httpx.post` quando implementar.

---

## Passo 9.4 — Criar `tests/test_eval_smoke.py` (harness pytest)

O harness pytest valida que o **dataset está bem formado** mesmo antes do runner real existir. Roda em CI hoje (mesmo com `run_scenario` levantando `NotImplementedError`) — garante que ninguém edita o `eval_scenarios.json` e quebra a estrutura silenciosamente.

**No VS Code:**

1. Crie a pasta `tests/` na raiz do repo se não existir:

```powershell
New-Item -ItemType Directory -Force tests
```

2. Crie `tests/test_eval_smoke.py` (~15 linhas):

```python
"""Smoke test do eval runner — não roda eval real, só valida estrutura."""
import json
from pathlib import Path

def test_scenarios_file_exists():
    assert Path("eval_scenarios.json").exists()

def test_scenarios_count():
    data = json.loads(Path("eval_scenarios.json").read_text(encoding="utf-8"))
    assert len(data) == 10

def test_each_scenario_has_required_fields():
    data = json.loads(Path("eval_scenarios.json").read_text(encoding="utf-8"))
    required = {"id", "category", "input", "expected_citations", "expected_outcome"}
    for s in data:
        assert required.issubset(s.keys()), f"Missing fields in {s.get('id', 'unknown')}"
```

3. Save em UTF-8. Commit local.

4. Rode local (assumindo `eval_scenarios.json` está em working dir ou ajuste path):

```powershell
# Da raiz do repo (com eval/ adjacente a tests/)
Set-Location eval
pytest ..\tests\test_eval_smoke.py -v
Set-Location ..
```

**Output esperado:**

```
test_eval_smoke.py::test_scenarios_file_exists PASSED
test_eval_smoke.py::test_scenarios_count PASSED
test_eval_smoke.py::test_each_scenario_has_required_fields PASSED

3 passed in 0.05s
```

<!-- screenshot: cap09-passo9.4-pytest-smoke-output.png -->

> **Alternativa Linux/Mac/WSL (bash):** `cd eval && pytest ../tests/test_eval_smoke.py -v && cd ..`

> **Custo:** R$ 0.

> **Nota pedagógica — pytest harness antes do runner real:** padrão **contract testing**. O dataset é o **contrato** entre o runner e o KB do agente. Mudar shape do JSON (renomear campo, deletar cenário) quebra o contrato — pytest pega na PR. Quando o `run_scenario` real entrar, adicionam-se testes funcionais (mock HTTP + assertions), mas estes 3 smoke tests permanecem como **piso de validação**.

> **Nota pedagógica — por que 3 testes e não 1?** Granularidade. Se `test_scenarios_count` falha, sei que alguém deletou/adicionou cenário. Se `test_each_scenario_has_required_fields` falha, sei que alguém renomeou campo. 1 teste único reportaria "deu ruim" sem dizer **onde**. Pytest names = documentação executável.

---

## Passo 9.5 — Criar `docs/RUNBOOK.md`

O runbook documenta **o que fazer quando o agente quebra em produção** — endereços de contato, cenários comuns, procedimentos de rollback/key-rotation/DR.

**No VS Code:**

1. `New-Item -ItemType Directory -Force -Path docs` (se não existir)
2. Crie `docs/RUNBOOK.md` com 4 seções fixas (esqueleto abaixo — preencher cada bloco com 3-5 passos numerados):

```markdown
# RUNBOOK — HelpSphere Tier 1
> Runbook operacional do agente HelpSphere Tier 1 em produção.

## 0. Contatos de incidente
- On-call DevOps: ops@apex.com.br · Eng Lead: lead-eng@apex.com.br · CTO: cto@apex.com.br
- Microsoft FastTrack: support.azure.com (severity A)
- Action Group: `ag-helpsphere-ia-alerts` (provisionado no Capítulo 08)

## 1. Cenários comuns
### 1.1 Latency p95 > 5s
KQL `customMetrics | where name == "llm.latency_p95"` → quota TPM (`az cognitiveservices account list-usage`) → se >80% saturada: aumentar TPM ou PTU reservado (~R$ 8K/mês) → se Search lento: S2 (~R$ 1,2K/mês) → se APIM saturado: Standard (~R$ 4K/mês).

### 1.2 Custo dispara além do budget
Action Group já alertou (verifique spam) → KQL `customMetrics | where name == "llm.cost_brl" | summarize by tenant` → rate-limit APIM mais agressivo (calls/60s = 5) → emergência: `az functionapp stop -n func-helpsphere-agent`.

### 1.3 Content Safety bloqueando legítimos (false positive)
KQL `customMetrics | where name == "safety.hit" | summarize count() by tostring(customDimensions.severity)` → se severity média 2-3 mas alta taxa de bloqueio: ajustar `SAFETY_BLOCK_THRESHOLD` de 4 → 5 ou 6 em Function App settings → re-deploy → validar com cenário de gray-area do dataset.

### 1.4 Pipeline CI quebrou
Bicep what-if erro: corrigir em PR · Eval regrediu: revisar `eval/report.json` artifact, achar regressor (KB stale ou prompt drift) · Smoke prod falhou: rollback automático já disparou (job `rollback` em `cd-prod.yml`).

## 2. Procedimentos
### 2.1 Rollback de deploy prod
`PREV=$(az deployment group list -g rg-lab-avancado --query "[?starts_with(name, 'prod-')] | [1].name" -o tsv)` → redeploy do template anterior via `--template-uri` `exportTemplate` API + `--rollback-on-error true`.

### 2.2 Rotation de keys (cada 90 dias)
Tabela com 5 recursos (Azure OpenAI, AI Search, APIM subs, Content Safety, App Registration MCP) × Procedimento Portal × Comando CLI. **Padrão duas-keys:** sempre regenerar **secundária** primeiro, propagar via deploy, validar prod, **só então** regenerar primária. Zero downtime.

### 2.3 Disaster Recovery
- **AI Search index:** backup diário via REST → blob `stbackuphelpsphere` · restore via REST `POST /indexes/{name}/docs/index`
- **Foundry Hub:** redeploy Bicep em Sweden Central · RTO ~2h, RPO ~24h
- **APIM Developer NÃO suporta geo-replication** (só Premium); em DR, redeploy APIM em region secundária · RTO ~60min
- **App Insights:** retention 90 dias default; se precisa archive longo, Continuous Export para blob

## 3. Métricas-chave a acompanhar (alvos)
`llm.cost_brl` < R$ 5K/mês · `llm.groundedness` > 0.9 · `agent.escalation` < 30% · `safety.hit` < 1% req · Latency p95 < 2s · SLO availability 99.5% · Eval `precision` > 0.85 · Eval `fallback_rate` < 0.15.
```

3. Save. Commit local:

```powershell
git add docs/RUNBOOK.md eval/ tests/
git commit -m "feat: RUNBOOK + eval pipeline esqueleto + dataset 10 cenarios + pytest harness"
```

<!-- screenshot: cap09-passo9.5-runbook-vscode.png -->

> **Alternativa Linux/Mac/WSL (bash):** `git add docs/RUNBOOK.md eval/ tests/ && git commit -m "..."`

> **Custo:** R$ 0.

> **Nota pedagógica — runbook em markdown no repo + tabela rotation de keys:** versionado + revisado por PR + próximo do código (quando alguém muda threshold de safety, PR mostra o diff em RUNBOOK.md). Confluence drift é a causa #1 de runbooks obsoletos em prod — pattern **docs as code**. A tabela de rotation = auditoria pronta: em incidente de leak você abre o RUNBOOK e diz **exatamente** quais 5 keys precisam regenerar.

---

## Passo 9.6 — Smoke run local (validar estrutura via pytest + confirmar `NotImplementedError`)

Como o runner real está em release futura, o "smoke run" desta versão valida **estrutura** (dataset bem formado + esqueleto com `NotImplementedError` cravado), não eval end-to-end.

**No terminal local (raiz do repo):**

```powershell
# 1. Capturar APIM key (para release futura quando runner real entrar)
$env:APIM_SUBSCRIPTION_KEY = az apim subscription show `
  --resource-group rg-lab-avancado `
  --service-name apim-helpsphere-staging `
  --sid master `
  --query primaryKey -o tsv

# 2. Capturar APIM gateway URL
$env:APIM_GATEWAY_URL = az apim show `
  -n apim-helpsphere-staging -g rg-lab-avancado `
  --query gatewayUrl -o tsv

# 3. Capturar AGENT_URL do agente Tier 1 (cross-repo, vem do Lab Final)
# Ajuste para o endpoint real do seu agente:
$env:AGENT_URL = "https://func-helpsphere-agent.azurewebsites.net/api/chat"

# 4. Instalar deps
pip install -r eval/requirements.txt

# 5. Rodar pytest harness (3 testes — passam se dataset está bem formado)
Set-Location eval
pytest ..\tests\test_eval_smoke.py -v
Set-Location ..

# 6. Confirmar que run_eval.py levanta NotImplementedError (esperado)
Set-Location eval
python run_eval.py
# Esperado: traceback com `NotImplementedError: Implementação completa em release futura`
Set-Location ..
```

> **Linux/Mac/WSL:** troque `$env:VAR =` por `export VAR=$(...)`, `` ` `` por `\`, `Set-Location` por `cd`, e referências `$env:VAR` por `"$VAR"`.

**Output esperado da Etapa 5 (pytest):**

```
test_eval_smoke.py::test_scenarios_file_exists PASSED
test_eval_smoke.py::test_scenarios_count PASSED
test_eval_smoke.py::test_each_scenario_has_required_fields PASSED

3 passed in 0.05s
```

**Output esperado da Etapa 6 (run_eval.py):**

```
Traceback (most recent call last):
  ...
NotImplementedError: Implementação completa em release futura
```

**Esse traceback é o sinal de saúde** — confirma que o esqueleto está intacto e que ninguém implementou parcialmente por engano. Quando a implementação real chegar, este passo vira "rode `python run_eval.py` e veja `report.json` ser gerado".

<!-- screenshot: cap09-passo9.6-pytest-passed-and-notimplemented.png -->

> **Alternativa via gh CLI (rodar pipeline em vez de local):** `gh workflow run cd-staging.yml --ref main` + `gh run watch` + `gh run download --name eval-results-staging` (pipeline também roda só o pytest harness na versão stub).

> **Custo:** R$ 0 (pytest + NotImplementedError não geram tráfego para Azure). Quando o runner real entrar, custo estimado ~R$ 0,03-0,05 por smoke run (10 chamadas × ~700 tokens avg em gpt-4.1-mini).

> **Nota pedagógica — validar local antes de CI:** loop tight. Iterar local em ~30s vs commit-push-wait-CI em ~5min. Production-grade: 20% de confiança local, deixe CI provar os outros 80%.

---

## Passo 9.7 — Validar visualmente no Portal — App Insights + APIM diagnostics

Quando o runner real entrar (release futura) e gerar tráfego via `AGENT_URL`, os dados aparecem no App Insights. Mesmo agora (modo esqueleto), você pode **navegar o Portal** para confirmar que App Insights está pronto a receber dados — fecha o ciclo de validação visual.

**No Portal Azure:**

1. Buscar `Application Insights` → selecionar `ai-helpsphere-staging`
2. Menu lateral → **Logs** (não confundir com Log stream)
3. Cole a query KQL (vai retornar vazio agora, mas confirma que o workspace está OK):

```kusto
requests
| where timestamp > ago(15m)
| where url contains "agent/chat"
| project timestamp, name, resultCode, duration, customDimensions
| order by timestamp desc
| take 20
```

4. Esperado (modo esqueleto): **0 linhas** — runner real ainda não roda. Quando entrar: 10 linhas (uma por cenário S01-S10), `resultCode` em `200` para a maioria, possivelmente `200` com fallback flag em S07
5. Custom metrics (release futura): tab **Metrics** → namespace `azure.applicationinsights` → métrica `customMetrics/llm.latency_p95` → ver gráfico crescer
6. **Validação visual mínima desta versão:** abra o blade **Overview** do App Insights e confirme que `Server requests` mostra **algum** tráfego histórico (pode ser de outro lab que usou o mesmo endpoint) — isto confirma que `instrumentationKey` está correto

<!-- screenshot: cap09-passo9.7-app-insights-overview-staging.png -->

> **Atenção latência ingestão:** App Insights tem ~3-30 min entre request e disponibilidade em **Metrics**. KQL em **Logs** retorna ~2-3min — debug live: **sempre Logs primeiro**. Custo R$ 0 (free tier 5GB/mês).

---

## Validação end-to-end

```powershell
# 1. Arquivos esperados (4 esperados em eval/ + 1 em tests/)
Get-ChildItem eval/        # eval_scenarios.json, requirements.txt, run_eval.py
Get-ChildItem tests/       # test_eval_smoke.py

# 2. Pytest harness passa (3 testes)
Set-Location eval
pytest ..\tests\test_eval_smoke.py -v
Write-Host "Exit pytest: $LASTEXITCODE"   # 0 = passou
Set-Location ..

# 3. run_eval.py levanta NotImplementedError (esperado modo esqueleto)
Set-Location eval
python run_eval.py 2>&1 | Select-String "NotImplementedError"
Set-Location ..

# 4. Sanity check no JSON
$scenarios = Get-Content eval/eval_scenarios.json | ConvertFrom-Json
Write-Host "Total cenarios: $($scenarios.Count)"   # 10
Write-Host "Primeiro ID: $($scenarios[0].id)"      # S01-devolucao-cdc
```

> **Linux/Mac/WSL:** troque `Get-ChildItem` por `ls`, `Write-Host` por `echo`, `Select-String` por `grep`, `Set-Location` por `cd`, e `$LASTEXITCODE` por `$?`.

---

## Checklist final

```text
[ ] eval/eval_scenarios.json com 10 cenários S01-S10 cravados completos
[ ] eval/requirements.txt com 4 deps pinned (requests, tenacity, dotenv, pytest)
[ ] eval/run_eval.py esqueleto com `raise NotImplementedError("Implementação completa em release futura")`
[ ] tests/test_eval_smoke.py com 3 testes (file_exists, count, required_fields)
[ ] docs/RUNBOOK.md com 4 cenários + 3 procedimentos + tabela métricas
[ ] pytest harness passa local (3 PASSED in 0.05s)
[ ] python run_eval.py levanta NotImplementedError (esperado)
[ ] App Insights workspace `ai-helpsphere-staging` confirmado no Portal (Overview blade)
[ ] AGENT_URL identificado no Lab Final cross-repo (para release futura)
[ ] 3 thresholds documentados: latency_p95_ms<2000, precision>0.85, fallback_rate<0.15
[ ] Categorias do dataset cobrem 7 áreas: Comercial, TI/Fiscal, TI/Loja, TI/Rede, Operacional, RH, Fallback, Financeiro, Fiscal
[ ] Commit local concluído (`feat: RUNBOOK + eval pipeline esqueleto`)
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **JSON com BOM no Windows** — VS Code às vezes salva UTF-8 com BOM, `json.loads()` falha com `Unexpected character: ﻿`. Fix: bottom-right do VS Code → encoding → **Save with Encoding** → **UTF-8** (sem BOM). Vale para `eval_scenarios.json` e para `run_eval.py`.
- ⚠️ **`pytest` rodando no diretório errado não acha `eval_scenarios.json`** — os testes usam `Path("eval_scenarios.json")` (relativo ao CWD). Se você rodar da raiz do repo, falha. Fix: `Set-Location eval` antes do `pytest`, ou ajuste o teste para `Path(__file__).parent.parent / "eval" / "eval_scenarios.json"`.
- ⚠️ **`NotImplementedError` no CI vira build vermelho** — quando o pipeline `cd-staging.yml` ainda invoca `python run_eval.py`, o job falha. Fix: condicione o step ao modo esqueleto, ou comente o invoke do runner real e deixe **só** o pytest harness rodando até a implementação chegar.
- ⚠️ **AI Search tiktoken truncation 8192 tokens corta PDFs grandes** — se um PDF essencial (~10K tokens) for indexado sem chunking, o final é truncado e o agente perde citação. Cenário relacionado falha (precision cai). Re-indexar com chunking <8000 tokens (margem segura).
- ⚠️ **`VectorizableTextQuery` vs `VectorizedQuery`** — index sem vectorizer integrado **exige** `VectorizedQuery` (vetor pré-computado pelo client). Se o agente usa `VectorizableTextQuery` num index sem vectorizer, retorna `400 Bad Request`. Fix: revisar o código de busca do agente Tier 1 ou re-criar index com vectorizer integrado.
- ⚠️ **APIM rate-limit dispara em smoke real (release futura)** — 10 cenários em < 60s × policy `calls=10/60s` = a partir do 11º request (retries) aparecem `429`. Fix futuro: adicionar `time.sleep(2)` entre cases OU subir limite de policy temporariamente.
- ⚠️ **Categoria "Fallback test" não tem `expected_citations`** — cenário S07 espera **lista vazia** `[]`. Se o agente citar QUALQUER coisa, precision não bate (ele inventou citação para pergunta fora do KB). Fix esperado: agente reconhece OOS e retorna `expected_citations=[]` + outcome "fora do meu escopo".

---

## Próximo capítulo

[10 — Cleanup](./10-cleanup.md)
