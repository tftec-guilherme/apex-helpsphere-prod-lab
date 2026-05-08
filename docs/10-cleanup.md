# Capítulo 10 — Cleanup

> **HIGH disclaimer R4 cravado neste capítulo. Cleanup é OBRIGATÓRIO.**

## Status do scaffold

> Conteúdo Portal step-by-step real será cravado em pass posterior. Este é o esqueleto inicial.

---

## DISCLAIMER R4 — Cleanup OBRIGATÓRIO

**APIM SKU Developer custa ~R$ 250/mês ligado.** Se você esquecer ligado:

- 1 mês: ~R$ 250
- 6 meses: ~R$ 1.500
- 1 ano: ~R$ 3.000

**Faça cleanup imediatamente ao fim do lab.**

---

## Outline

### 1. Cleanup completo (deleta tudo)

```bash
# Delete os 3 RGs criados pelo Bicep
az group delete --name rg-helpsphere-ia-prod-dev --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-staging --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-prod --yes --no-wait

# Verifica que sumiu
az group list --query "[?starts_with(name, 'rg-helpsphere-ia-prod')].name" -o tsv
# Output esperado: vazio
```

### 2. Cleanup parcial (só staging/prod, mantém dev pra reinstalar)

```bash
az group delete --name rg-helpsphere-ia-prod-staging --yes --no-wait
az group delete --name rg-helpsphere-ia-prod-prod --yes --no-wait
```

### 3. Cleanup APIM apenas (se quiser manter App Insights)

> **Aviso:** Não recomendado — APIM tem dependências de Diagnostic Settings que podem deixar lixo se removido individual.

```bash
# Não recomendado — prefer cleanup completo
az apim delete --name apim-helpsphere-XXXX --resource-group rg-helpsphere-ia-prod-staging --yes
```

### 4. Cleanup Service Principal

```bash
# Liste SPs criados
az ad sp list --display-name sp-helpsphere-prod-lab --query "[].{appId:appId, name:displayName}"

# Delete
az ad sp delete --id <APP_ID>
```

### 5. Cleanup GitHub repo

- Settings → Danger Zone → Delete repository
- OU manter como portfolio learning

### 6. Cleanup Azure Policy assignments

> Policy assignments são deletados junto com RG. **Mas** verifique:

```bash
az policy assignment list --resource-group rg-helpsphere-ia-prod-staging --query "[].name"
# Output esperado após delete RG: vazio
```

### 7. Cleanup Cost Management Budget

```bash
# Lista budgets
az consumption budget list --query "[].name"

# Delete (substitua <NAME>)
az consumption budget delete --budget-name <NAME>
```

### 8. Cleanup Foundry Hub `aifhub-apex-prod`

> **NÃO DELETE** — `aifhub-apex-prod` é compartilhado entre todos os Labs D06 (Intermediário, Final, Avançado). Mantenha.

### 9. Verificação final

```bash
# Verifica que todos os 3 RGs sumiram
az group list --query "[?starts_with(name, 'rg-helpsphere-ia-prod')].name" -o tsv

# Verifica budget consumption último 7 dias
az consumption usage list --start-date $(date -d "7 days ago" +%Y-%m-%d) --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'helpsphere')]" -o table

# Verifica nenhum resource órfão
az resource list --tag application=helpsphere-ia-prod -o table
# Output esperado: vazio
```

---

## Checklist

```
[ ] az group delete rodou sem erro nos 3 RGs
[ ] Verificação final mostra 0 RGs com prefix rg-helpsphere-ia-prod-
[ ] Service Principal deletado (opcional)
[ ] Cost Management Budget deletado
[ ] Custo último 7 dias verificado (esperado decrescente)
[ ] Foundry Hub aifhub-apex-prod NÃO deletado (compartilhado outros labs)
```

---

## Pos-cleanup — economia validada

```bash
# 7 dias depois, verifica que custo zerou
az consumption usage list \
  --start-date $(date -d "1 day ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'helpsphere-ia-prod')]" \
  -o table
# Esperado: vazio ou só remanescentes esperados
```

---

**Parabéns!** Você completou o Lab Avançado D06. 🎓

**Próximos passos sugeridos:**
- Aplicar conceitos production-grade em projeto real
- Estudar APIM Premium tier (multi-region, VNET integration)
- Estudar Foundry Agents avançados (multi-agent collaboration)
