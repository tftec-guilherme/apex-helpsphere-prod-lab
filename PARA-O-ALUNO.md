# PARA O ALUNO — Lab Avançado D06

Bem-vindo ao **Lab Avançado** da Disciplina 06. Este é o repo companion do tema `apex-helpsphere` em modo **production-grade canônico** — você vai construir CI/CD via GitHub Actions, Bicep production-ready e governança com Azure Policy + Cost Management em cima da fundação SaaS já validada nos blocos anteriores.

> **Filosofia:** Production-grade significa **não simplificamos para "didático"**. Você vai ver APIM real, Content Safety real, custom metrics reais. É como uma empresa faria.

---

## 8 Pré-requisitos (cravados)

### 1. Subscription PAYG ativa
Azure OpenAI **exige** modelo Pay-As-You-Go. **Free Trial NÃO funciona** para Foundry Agents/Embeddings. Se você está em Free Trial, converta antes de começar.

### 2. Foundry Hub `aifhub-apex-prod` já provisionado
Pré-requisito de Bloco 6 do recording. Se ainda não tem, volte ao Bloco 6 antes deste lab.

### 3. Subscription sem ABAC condition
**HIGH disclaimer R6:** CI/CD via GitHub Actions com Federated Service Principal **NÃO funciona** em subscriptions com ABAC condition (ex: Visual Studio Enterprise pessoal `live.com` vem com ABAC default que bloqueia role assignments via SP federado).

| Sub que funciona | Sub que NÃO funciona |
|------------------|---------------------|
| TFTEC subscription | Visual Studio Enterprise (live.com) com ABAC |
| PAYG sem ABAC | Free Trial (sem ABAC mas sem PAYG) |
| Subscription corporate | Subs com Conditional Access policy bloqueando SP |

### 4. GitHub repo (este, forked)
Fork via `gh repo fork tftec-guilherme/apex-helpsphere-prod-lab --clone`.

### 5. Service Principal com Federated Credentials
Configurado via `az ad sp create-for-rbac --name "sp-helpsphere-prod-lab"` + Federated Credentials apontando para seu GitHub repo. Ver `docs/03-service-principal-federated.md`.

### 6. Az CLI + Bicep CLI atualizados
```bash
az --version  # >= 2.60
az bicep version  # >= 0.30
```

### 7. Python 3.11+ (opcional — só pra eval offline)
```bash
python --version
```

### 8. gh CLI autenticado
```bash
gh auth status
```

---

## 3 Disclaimers HIGH (leia ANTES de começar)

### Disclaimer R4 — APIM Developer R$ 250/mês ligado

**APIM SKU Developer** não tem auto-pause. Custo é cobrado **mesmo sem tráfego**.

- Custo: ~R$ 250/mês ligado 24/7
- **Cleanup obrigatório**: faça `az group delete` ao fim do lab (capítulo `docs/10-cleanup.md`)
- **Alternativa**: `param apimSku string = 'Consumption'` em `infra/envs/dev.parameters.json` — pay-per-call (mas algumas policies do Lab podem não funcionar; ver `docs/06`)

**Comprometa-se com o cleanup ou use Consumption SKU.**

### Disclaimer R6 — CI/CD requer subscription sem ABAC

CI/CD fork-by-student via Federated SP **descontinuado em sub VSE pessoal** desde 2026-05-06 (descoberta arquitetural cravada na sessão maratona).

Lab assume:
- Sub TFTEC sem ABAC (cenário ideal — ambiente de aula real)
- OU sub PAYG sem ABAC
- OU sub corporate

Se sua sub tem ABAC, **CI workflow falha** ao fazer role assignments. Você ainda consegue rodar `az deployment sub create` localmente, mas perde o valor pedagógico do CI/CD demo. **Recomendação:** consiga sub TFTEC ou PAYG sem ABAC para este lab.

### Disclaimer Free Trial — não suportado

Free Trial $200 USD funciona para fundação SaaS (Bloco 2 — `apex-helpsphere`), mas **não funciona** aqui porque:
- Azure OpenAI exige PAYG (não Free Trial)
- Foundry Hub `aifhub-apex-prod` precisa modelos PAYG provisionados

Se você fez Bloco 2 em Free Trial, **converta para PAYG agora**.

---

## Filosofia "Bicep IS canonical"

- `infra/main.bicep` é a **fonte de verdade**. Portal Azure é só pra visualizar e debugar.
- Você **NÃO** edita recursos no Portal — edita Bicep, abre PR, CI valida, CD deploya.
- Mudanças manuais no Portal são **drift** e o próximo `cd-staging` ou `cd-prod` vai sobrescrever.
- Se você quer testar algo no Portal, faça em outro RG fora deste lab.

Esta é a disciplina de "Production-grade canônico". Aceite a regra ou volte ao Lab Intermediário (Portal-first).

---

## Custos esperados detalhados

```
APIM Developer (ligado 24/7)        ~R$ 250/mês  ⚠️ cleanup OU use Consumption
Content Safety F0                   Free
App Insights workspace-based        ~R$ 10/mês (volume baixo lab)
Azure Policy assignments            Free
Logic App Consumption (circuit)     ~R$ 5/mês
Foundry Agent calls (gpt-4.1-mini)  ~R$ 15/mês (uso lab)
Storage (logs)                      ~R$ 2/mês
Cost Management Budget              Free
                                    ─────────
TOTAL aproximado                    ~R$ 280/mês
```

> **Mantenha custo < R$ 50/mês:** rode o lab em ~3-5 dias úteis e faça cleanup imediatamente. Se demorar 1 mês, custa ~R$ 280.

---

## Suporte

- Bugs/dúvidas: abrir issue em https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/issues
- Discussão pedagógica: canal oficial da disciplina

---

**Boa sorte. E não esqueça do cleanup.** 🧹
