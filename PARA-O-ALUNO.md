# PARA O ALUNO — Lab Avançado D06

Bem-vindo ao **Lab Avançado** da Disciplina 06. Este é o repo companion do tema `apex-helpsphere` em modo **production-grade canônico em STACK PARALELA à fundação SaaS** — mesmos padrões técnicos (APIM Developer, Content Safety, App Insights workspace-based, Azure Policy), mas recursos completamente isolados em `rg-lab-avancado` para fins pedagógicos. NÃO consome a SaaS (apex-helpsphere) — você aprende o pattern, não integra.

Esta versão é **100% Portal+CLI manual**. CI/CD via GitHub Actions é capítulo futuro (fora do escopo). Você aplica Bicep com `az deployment group create` em terminal local — domina a IaC e a stack production-grade primeiro.

> **Filosofia:** Production-grade significa **não simplificamos para "didático"**. Você vai ver APIM real, Content Safety real, custom metrics reais. É como uma empresa faria.

---

## 7 Pré-requisitos (cravados)

### 1. Subscription PAYG ativa
Azure OpenAI **exige** modelo Pay-As-You-Go. **Free Trial NÃO funciona** para Foundry Agents/Embeddings. Se você está em Free Trial, converta antes de começar.

### 2. Foundry Hub `aifhub-apex-prod` já provisionado
Pré-requisito de Bloco 6 do recording. Se ainda não tem, volte ao Bloco 6 antes deste lab.

### 3. (Opcional) GitHub repo
Esta versão é Portal+CLI manual — você NÃO precisa de repo GitHub para rodar o lab. Os artefatos (Bicep, parameter files) existem em `infra/` e você os aplica direto com `az deployment group create` no terminal local. Fork opcional via `gh repo fork tftec-guilherme/apex-helpsphere-prod-lab --clone` se quiser manter histórico/portfolio.

### 4. (Opcional) Service Principal com Federated Credentials
Necessário SOMENTE se você quiser estender o lab com CI/CD via GitHub Actions (capítulo futuro). Para esta versão Portal+CLI, basta `az login` com seu usuário e role Contributor em `rg-lab-avancado`. Ver `docs/03-service-principal-federated.md` (marcado como OPCIONAL).

### 5. Az CLI + Bicep CLI atualizados
```powershell
az --version  # >= 2.60
az bicep version  # >= 0.30
```
**Linux/Mac/WSL:** comandos `az` são idênticos.

### 6. Python 3.11+ (opcional — só pra eval offline)
```powershell
python --version
```

### 7. (Opcional) gh CLI autenticado
```powershell
gh auth status
```
Só necessário se você quer fork via CLI (Pré-requisito 3).

---

## 2 Disclaimers HIGH (leia ANTES de começar)

### Disclaimer R4 — APIM Developer R$ 250/mês ligado

**APIM SKU Developer** não tem auto-pause. Custo é cobrado **mesmo sem tráfego**.

- Custo: ~R$ 250/mês ligado 24/7
- **Cleanup obrigatório**: faça `az group delete` ao fim do lab (capítulo `docs/10-cleanup.md`)
- **Alternativa**: `param apimSku string = 'Consumption'` em `infra/envs/dev.parameters.json` — pay-per-call (mas algumas policies do Lab podem não funcionar; ver `docs/06`)

**Comprometa-se com o cleanup ou use Consumption SKU.**

### Disclaimer Free Trial — não suportado

Free Trial $200 USD funciona para fundação SaaS (Bloco 2 — `apex-helpsphere`), mas **não funciona** aqui porque:
- Azure OpenAI exige PAYG (não Free Trial)
- Foundry Hub `aifhub-apex-prod` precisa modelos PAYG provisionados

Se você fez Bloco 2 em Free Trial, **converta para PAYG agora**.

---

## Filosofia "Bicep IS canonical"

- `infra/main.bicep` é a **fonte de verdade**. Portal Azure é só pra visualizar e debugar.
- Você **NÃO** edita recursos no Portal — edita Bicep, roda `what-if`, deploya com `az deployment group create`.
- Mudanças manuais no Portal são **drift** e o próximo `az deployment group create` vai sobrescrever.
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
