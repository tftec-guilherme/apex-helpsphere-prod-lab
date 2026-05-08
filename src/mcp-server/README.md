# MCP Server (placeholder)

> **Por que este diretorio existe?** Para deixar explicito que MCP Server **NAO** e re-implementado neste lab.

## Como funciona

O **MCP Server pre-pronto** esta disponivel em outro repo:

- Repo: [`tftec-guilherme/apex-helpsphere-agente-lab`](https://github.com/tftec-guilherme/apex-helpsphere-agente-lab)
- Stack: FastMCP + Azure Functions + Foundry tool registration
- Provisao: Lab Final D06 (Story 06.11)

## Integracao com este Lab Avancado

Este Lab Avancado **consome** o MCP Server via APIM gateway (`agent-api`), nao re-implementa.

O fluxo eh:

```
Frontend (apex-helpsphere)
    ↓ HTTPS + Bearer JWT
APIM Gateway (rate-limit + JWT validation + CORS)
    ↓
Function App agent_runner.py (este repo)
    ↓ Content Safety filter (input)
    ↓ Foundry Agent SDK call → MCP Server tool registration
    ↓ Content Safety filter (output)
    ↓ Custom App Insights metrics
Cliente recebe resposta
```

## Quando voce precisa do MCP Server

- Lab Avancado D06 (este lab) — voce **NAO precisa rodar MCP localmente**
- Lab Final D06 — la voce provisiona MCP Server e registra tools no Foundry Agent

## Se voce ainda quiser explorar localmente

```bash
git clone https://github.com/tftec-guilherme/apex-helpsphere-agente-lab.git
cd apex-helpsphere-agente-lab
# Siga README do repo
```

---

**Mantenedor:** Prof. Guilherme Campos
**Disciplina:** D06 — IA e Automacao no Azure
