# Capítulo 08 — Azure Policy + Cost Management

> **Objetivo:** verificar que os 3 Azure Policy assignments cravados pelo módulo `infra/modules/policy.bicep` estão **Active** no `rg-lab-avancado`, validar negativamente que a policy `Allowed locations` bloqueia deploy fora de `East US 2`, criar 1 Cost Management Budget de **R$ 200/mês** com 3 thresholds (50% / 80% / 100%), provisionar 1 Action Group com email canalizando os alerts, e montar 1 Cost Analysis dashboard custom no Portal com breakdown por tag `cost-center` e por serviço — deixando o ambiente production-grade-coberto contra drift de região, drift de tag e drift de billing.
>
> **Tempo:** 60-75 min (não inclui ~15-30 min de latência ingest do Cost Management antes do primeiro ponto aparecer)
>
> **Adaptação:** o módulo `policy.bicep` cravado no Capítulo 04a usa **3 built-in policies** Azure (allowed-locations + require-tag + cosmos-deny-public) em vez de 3 custom policies. Equivalentes pedagogicamente, sem custo de manutenção. Circuit-breaker (Passo 8.8) usa **workflow n8n cross-repo** reusando o `ca-n8n-helpsphere` provisionado no Lab Final cap 07 — substitui Logic App por custo zero e flexibilidade visual.

---

## Pré-requisitos

- ✅ Capítulo 04a + 04b concluídos — `infra/modules/policy.bicep` escrito e validado via `az bicep build`
- ✅ Capítulo 05 concluído — pipeline `cd-staging.yml` rodou pelo menos uma vez, ou seja, `policyAssignments` foram criados pelo módulo `policy.bicep` (RG-scoped) durante `az deployment group create`
- ✅ Capítulo 06 concluído — APIM `apim-helpsphere-staging` provisionado (é o item **caro** do RG, vai dominar gráficos de Cost Analysis)
- ✅ Capítulo 07 concluído — Application Insights `ai-helpsphere-staging` ingerindo telemetria (vai aparecer em Cost breakdown ainda que dentro do free tier)
- ✅ Permissão **Cost Management Contributor** ou **Contributor** no escopo da subscription (Budget é subscription-scoped mesmo quando filtra por RG)
- ✅ `az` CLI logado e capaz de listar policy assignments (`az policy assignment list` não retorna `AuthorizationFailed`)
- ✅ **n8n ACA provisionado em outro Lab** (Lab Final cap 07 — `ca-n8n-helpsphere` em `rg-lab-final`) — você precisa do `$env:N8N_URL` capturado lá. Se ainda não fez aquele Lab, faça antes deste cap **ou** pule a seção 8.8 (circuit-breaker) e use apenas Action Group com email do Passo 8.5/8.6.

> **Atenção custo escondido:** Azure Policy é **gratuito** (assignments + compliance state evaluation são free). Cost Management Budget alerts são **gratuitos** (não há fee por alert disparado). Cost Analysis é **gratuito**. Action Group cobra **R$ 0,001 por notificação SMS/voice**, mas **email é gratuito** — usamos só email no lab. Resumo: **Capítulo 08 inteiro é R$ 0** desde que você não habilite SMS/voice/Push.

> **Atenção drift que esse capítulo previne:** sem policy `Allowed locations`, alguém faz `az deployment group create --location brazilsouth` e cria recursos fora do escopo planejado — Cost Analysis quebra (tag `cost-center` não captura) e billing surpresa. Sem `require-cost-center-tag`, recursos provisionados manualmente via Portal escapam do tracking. Sem Budget, você descobre o estouro **30 dias depois** quando vê fatura. Defesa em profundidade: 3 policies + 1 budget = **3 sinais antes do CFO chamar**.

---

## Resumo dos 3 Policies + 1 Budget + 1 Action Group + 1 Dashboard que vamos cravar

| Camada | Item | Onde fica | Custo absoluto |
|---|---|---|---|
| **Policy 1** | Allowed locations (East US 2 only) | RG `rg-lab-avancado` → Policy Assignments | R$ 0 |
| **Policy 2** | Require cost-center tag | RG `rg-lab-avancado` → Policy Assignments | R$ 0 |
| **Policy 3** | Cosmos DB public access denied (defensivo) | RG `rg-lab-avancado` → Policy Assignments | R$ 0 |
| **Budget** | `budget-helpsphere-ia` R$ 200/mês com 3 thresholds | Cost Management → escopo RG | R$ 0 |
| **Action Group** | `ag-helpsphere-ia-alerts` 2 emails (ops + cfo) | Monitor → Alerts → Action groups | R$ 0 (email free) |
| **Dashboard** | Cost Analysis custom view com 3 breakdowns | Cost Management → Cost Analysis → saved view | R$ 0 |

> **Nota pedagógica — por que 3 built-in policies e não 3 custom?** Custom policies (`helpsphere-model-allowlist`, `helpsphere-region-lock`, `helpsphere-cost-center-tag-required`) exigem `targetScope = 'subscription'` no Bicep + role assignment `Resource Policy Contributor` no UAA. Em sub `live.com` VSE com **ABAC condition**, isso falha. Built-in policies da Azure são RG-scoped, sem custom policy definition para autor — funciona em qualquer sub, inclusive PAYG pessoal apertada. Trade-off: perde-se a parte "definir custom rule JSON" mas ganha-se "funciona em qualquer ambiente do aluno".

> **Nota pedagógica — por que `R$ 200/mês` de budget e não `R$ 50` ou `R$ 500`?** APIM Developer ligado 1 mês inteiro = ~R$ 250. Se você não fizer cleanup no mesmo dia (lembrete forte do Capítulo 06), 1 mês de esquecimento = R$ 250 sozinho. Setting `R$ 200` força alerta **antes** de você atingir o custo do APIM ligado o mês inteiro — ou seja, alerta **funciona como auto-cleanup reminder**. Em produção real, o budget reflete OPEX planejado da feature; aqui ele reflete "burn pedagogicamente aceitável".

---

## Passo 8.1 — Verificar os 3 Policy Assignments criados pelo Bicep

O módulo `infra/modules/policy.bicep` é incluído no `main.bicep` e foi deployado na primeira run do pipeline `cd-staging.yml` (Capítulo 05). Vamos confirmar no Portal que os 3 assignments existem e estão **Active**.

**No Portal Azure:**

1. Topo → barra de busca → digite `Policy` → clique em **Policy** (ícone do escudo azul)
2. Menu lateral → **Authoring** → **Assignments**
3. Filtros no topo da lista → **Scope:** clique em `Select scope` → escolha sua subscription → drill para `rg-lab-avancado` → **Select**
4. Lista deve mostrar 3 assignments com display names:
   - `Allowed locations — eastus2 only` (nome interno: `allowed-locations-<hash>`)
   - `Require cost-center tag`
   - `Cosmos DB — disable public network access`
5. Clique em `Allowed locations — eastus2 only` → tab **Definition** mostra o `policyRule` JSON com `effect: deny` e `field: location` ≠ `eastus2`
6. Tab **Parameters** mostra `listOfAllowedLocations = ["eastus2"]`

<!-- screenshot: cap08-passo8.1-policy-assignments-rg.png -->

7. Volte → menu lateral **Policy** → **Compliance**
8. Filtre por scope `rg-lab-avancado` → você deve ver os 3 assignments com **Compliance state: Compliant** (todos os recursos atuais respeitam as policies)

<!-- screenshot: cap08-passo8.1-policy-compliance-state.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> # Listar assignments no escopo do RG
> az policy assignment list `
>   --scope /subscriptions/<sub-id>/resourceGroups/rg-lab-avancado `
>   --query "[].{name:displayName, definitionId:policyDefinitionId, state:enforcementMode}" `
>   -o table
>
> # Ver compliance state agregada
> az policy state summarize `
>   --resource-group rg-lab-avancado `
>   --query "results" -o json
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\`.

> **Custo:** R$ 0 — Azure Policy não cobra por assignment, por evaluation, nem por compliance check. **Cobra R$ 0 mesmo deletando e recriando** (ao contrário de APIM que cobra parado).

> **Nota pedagógica — `enforcementMode: Default` vs `DoNotEnforce`:** o Bicep cravou `enforcementMode: 'Default'` (= `Enabled`) nas 3 policies. Isso significa que **deny** é ativo: tentativa de criar recurso violando = HTTP 403 `RequestDisallowedByPolicy`. Em rollout em produção real, você normalmente cria a policy em `DoNotEnforce` primeiro (~1 semana de **observação** sem bloquear), olha compliance state, e **depois** vira pra `Default`. No lab pedagógico assumimos greenfield e enforce direto.

> **Nota pedagógica — RG-scoped vs Subscription-scoped:** o `policy.bicep` deste lab usa `targetScope = 'resourceGroup'` (assignments criados dentro do `rg-lab-avancado`). O guia canônico usa `targetScope = 'subscription'` (assignments cravados na sub inteira, custom policies). RG-scoped é **mais barato pedagogicamente** (sem custom definition) e **mais seguro** (não vaza para outros RGs do aluno) — por isso o companion divergiu. Em prod real, sub-scoped é o pattern para garantir cobertura uniforme.

---

## Passo 8.2 — Negative test: tentar deploy fora de East US 2 e ver Azure bloquear

A maneira mais didática de validar uma policy `deny` é tentando criar um recurso que viola e ver Azure bloqueando explicitamente. Vamos tentar criar um Storage Account em `Brazil South`.

**No Portal Azure:**

1. Topo → barra de busca → digite `Storage account` → clique → **+ Create**
2. Tab **Basics**:
   - **Subscription:** sua
   - **Resource group:** `rg-lab-avancado`
   - **Storage account name:** `sttestpolicy<seu-username>` (3-24 chars, lowercase, único globalmente)
   - **Region:** `(South America) Brazil South` (intencionalmente fora da policy)
   - **Performance:** `Standard`
   - **Redundancy:** `LRS`
3. **Review** → **Create**
4. Erro esperado em ~5s: banner vermelho com **`RequestDisallowedByPolicy`** mencionando `allowed-locations-<hash>` e listando `eastus2` como única região permitida

<!-- screenshot: cap08-passo8.2-policy-deny-banner-storage.png -->

> **Alternativa via Azure CLI (deve falhar):**
>
> ```powershell
> # Deve retornar erro de policy denial
> az storage account create `
>   --name sttestpolicy<seu-username> `
>   --resource-group rg-lab-avancado `
>   --location brazilsouth `
>   --sku Standard_LRS `
>   --kind StorageV2
> # Saída esperada:
> # ERROR: (RequestDisallowedByPolicy) Resource 'sttestpolicy...' was disallowed by policy.
> # Reasons: 'Allowed locations'
> # Policy identifiers: '[{"policyAssignment":{"name":"allowed-locations-..."}}]'
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\`.

5. Re-tente trocando **Region: East US 2** → deploy é aceito → delete o Storage logo após validar (custo desprezível, mas evite deixar lixo)

> **Custo do teste:** R$ 0 (deploy bloqueado nem chega a provisionar). Se você completar o teste positivo (Region East US 2) e esquecer de deletar, Storage LRS Standard custa ~R$ 0,02/GB/mês — desprezível, mas higiene importa.

> **Nota pedagógica — por que negative test antes de positive?** Em segurança, sempre validar que o **bloqueio funciona** antes de confiar nele. Pattern OWASP: "trust, but verify". Se você só testa o caminho feliz (East US 2), pode ter uma policy mal-configurada (ex.: `enforcementMode: DoNotEnforce` por engano) que **não bloqueia nada** e você descobre tarde. Negative test valida o guard-rail.

> **Por que outros recursos do RG passaram?** Eles foram criados pelo Bicep com `location: 'eastus2'` hardcoded em `main.bicep` (parameter file `staging.parameters.json` define `location: "eastus2"`). Policy só **bloqueia o que viola** — recursos compliant são invisíveis ao mecanismo de deny.

---

## Passo 8.3 — Negative test: tentar deploy sem tag `cost-center` e ver bloqueio

A policy 2 (`Require cost-center tag`) força que **todos os novos recursos** tenham a tag `cost-center` preenchida. Drift comum: alguém cria App Service via Portal, esquece da tag, e o recurso fica órfão de cost tracking.

**No Portal Azure:**

1. Topo → barra de busca → digite `App Service` → clique → **+ Create** → **Web App**
2. Tab **Basics**:
   - **Resource group:** `rg-lab-avancado`
   - **Name:** `app-test-no-tag-<random>`
   - **Region:** `East US 2` (compliant com policy 1)
   - **Runtime stack:** `.NET 8` (qualquer)
   - **Pricing plan:** **Free F1** (sem custo)
3. Tab **Tags** → **deixe vazio intencionalmente** (sem `cost-center`)
4. **Review + create** → **Create**
5. Erro esperado: banner vermelho **`RequestDisallowedByPolicy`** mencionando `Require cost-center tag`

<!-- screenshot: cap08-passo8.3-policy-deny-tag-missing.png -->

6. Volte → tab **Tags** → adicionar:
   - **Name:** `cost-center` · **Value:** `apex-helpsphere-ia`
7. **Review + create** → **Create** → agora aceita
8. Após deploy, delete o `app-test-no-tag-*` (mesmo Free F1, evite lixo no RG)

> **Alternativa via Azure CLI (deve falhar sem tag):**
>
> ```powershell
> # Sem tag — deve falhar
> az appservice plan create `
>   --name plan-test-no-tag `
>   --resource-group rg-lab-avancado `
>   --location eastus2 `
>   --sku FREE
> # Saída: ERROR: (RequestDisallowedByPolicy) ... Require cost-center tag
>
> # Com tag — deve aceitar
> az appservice plan create `
>   --name plan-test-with-tag `
>   --resource-group rg-lab-avancado `
>   --location eastus2 `
>   --sku FREE `
>   --tags cost-center=apex-helpsphere-ia
> # Cleanup
> az appservice plan delete --name plan-test-with-tag -g rg-lab-avancado --yes
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\`.

> **Custo:** R$ 0 — Free F1 plan sempre é gratuito, mesmo quando não bloqueado. O valor é pedagógico, não financeiro.

> **Nota pedagógica — `Require tag` vs `Modify tag`:** o built-in `Require a tag on resources` é **deny**: bloqueia se faltar. Existe variante `Append a tag and its value` (`modify` effect) que **adiciona automaticamente** a tag se faltar — mais permissiva, menos pedagógica. Decisão de pattern: **deny em greenfield**, **modify em brownfield** (para não quebrar deploys legados). Aqui escolhemos deny porque o lab é greenfield.

---

## Passo 8.4 — Criar Cost Management Budget de R$ 200/mês com 3 thresholds

Budget alerts disparam **antes** do gasto real explodir. Configuramos 3 thresholds: 50% (sinal verde), 80% (sinal amarelo — chamar ops), 100% (sinal vermelho — circuit breaker entraria aqui).

**No Portal Azure:**

1. Topo → barra de busca → digite `Cost Management` → clique em **Cost Management + Billing** → **Cost Management** (sub-blade)
2. Topo da página → **Scope** → clique no botão `Change` → escolha sua subscription → drill para `Resource group: rg-lab-avancado` → **Select**
3. Menu lateral → **Cost Management** → **Budgets** → **+ Add**
4. Tab **Create budget**:
   - **Name:** `budget-helpsphere-ia`
   - **Reset period:** `Monthly`
   - **Creation date:** mês atual (default)
   - **Expiration date:** +12 meses (default OK)
   - **Budget amount:** `200` (na moeda da sub — BRL se sub BR, USD ~$40 se sub USD)
5. **Next: Set alerts**
6. Configurar 3 alert conditions clicando **+ Add condition** entre cada:
   - **Condition 1:** **Type** `Actual` · **% of budget** `50` · **Alert recipients (email):** `ops@apex.com.br`
   - **Condition 2:** **Type** `Actual` · **% of budget** `80` · **Alert recipients (email):** `ops@apex.com.br;cto@apex.com.br`
   - **Condition 3:** **Type** `Forecasted` · **% of budget** `100` · **Alert recipients (email):** `ops@apex.com.br;cfo@apex.com.br`
7. **Action group:** deixe vazio por enquanto (linkamos no Passo 8.5)
8. **Create**

<!-- screenshot: cap08-passo8.4-cost-budget-created.png -->

9. Após criação, lista **Budgets** mostra `budget-helpsphere-ia` com **Current spend: 0.00** e **Forecasted: <X>** baseado em consumo dos últimos dias

> **Alternativa via Azure CLI:**
>
> ```powershell
> # Capturar mês atual no formato yyyy-MM-01
> $Start = (Get-Date -Format "yyyy-MM-01")
>
> az consumption budget create `
>   --resource-group rg-lab-avancado `
>   --budget-name budget-helpsphere-ia `
>   --amount 200 `
>   --time-grain Monthly `
>   --time-period start-date=$Start `
>   --notifications `
>     operator=GreaterThan threshold=50 contact-emails="ops@apex.com.br" `
>   --notifications `
>     operator=GreaterThan threshold=80 contact-emails="ops@apex.com.br" "cto@apex.com.br" `
>   --notifications `
>     operator=GreaterThan threshold=100 contact-emails="ops@apex.com.br" "cfo@apex.com.br"
> ```
>
> **Linux/Mac/WSL:** troque `$Start = (Get-Date -Format "yyyy-MM-01")` por `START=$(date -u +%Y-%m-01)` e `` ` `` por `\`.

> **Custo:** R$ 0 — Budget alerts não cobram. Cobra-se apenas se o budget atingir threshold, mas **a notificação em si** (email) é gratuita.

> **Nota pedagógica — `Actual` vs `Forecasted`:** `Actual` dispara quando o gasto **acumulado real** atinge o %. `Forecasted` dispara quando o **modelo de projeção** (Azure ML linear regression sobre últimos 14 dias) prevê que vai passar do % até o fim do período. Forecasted é o **leading indicator** — você é avisado **antes** do estouro. Pattern production-grade: 50%/80% Actual + 100% Forecasted (você quer saber **antes** que vai estourar, não depois).

> **Nota pedagógica — escala dos thresholds (50/80/100 vs 80/95/110):** 50% é "atenção, está consumindo no ritmo esperado, sem surpresa". 80% é "ok, time pra revisar dashboards de Cost Analysis e identificar quem está crescendo desproporcional". 100% Forecasted é "STOP, intervenção humana necessária — circuit breaker em prod real". Thresholds 80/95/110 são tarde demais — pelos 110% você já gastou.

---

## Passo 8.5 — Criar Action Group `ag-helpsphere-ia-alerts` com 2 emails

Action Group é o **fan-out hub** dos alerts. Mesma config de notification reutilizada por Budget alerts, Application Insights alerts, Service Health alerts, etc. Pattern: **1 Action Group por equipe owner** (ops, sec, finance), não 1 por tipo de alert.

**No Portal Azure:**

1. Topo → barra de busca → digite `Monitor` → clique
2. Menu lateral → **Alerts** → **Action groups** → **+ Create**
3. Tab **Basics**:
   - **Subscription:** sua
   - **Resource group:** `rg-lab-avancado`
   - **Region:** `Global` (Action Groups são always-global)
   - **Action group name:** `ag-helpsphere-ia-alerts`
   - **Display name:** `HSphereIA` (até 12 chars — usado em SMS/voice se algum dia habilitar)
4. Tab **Notifications** → **+ Add notification**:
   - **Notification type:** `Email/SMS message/Push/Voice`
   - **Name:** `ops-email`
   - Marcar ☑ **Email** → digitar `ops@apex.com.br` → **OK**
5. **+ Add notification** novamente:
   - **Name:** `cfo-email`
   - **Email:** `cfo@apex.com.br`
6. Tab **Actions** → deixe vazio agora (o webhook do circuit-breaker n8n será adicionado no Passo 8.8 — `+ Add notification` tipo `Webhook` apontando para o n8n cross-repo)
7. **Review + create** → **Create**

<!-- screenshot: cap08-passo8.5-action-group-created.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> az monitor action-group create `
>   --name ag-helpsphere-ia-alerts `
>   --resource-group rg-lab-avancado `
>   --short-name HSphereIA `
>   --action email ops "ops@apex.com.br" `
>   --action email cfo "cfo@apex.com.br"
> ```
>
> **Linux/Mac/WSL:** troque `` ` `` por `\`.

> **Custo:** R$ 0 — Action Group por si não cobra. **Email** é gratuito ilimitado. **SMS** cobra ~R$ 0,30/msg (BR), **voice call** ~R$ 0,75/call, **push** gratuito (precisa app Azure Mobile). Para o lab, só email.

> **Nota pedagógica — por que Region Global e não East US 2?** Action Groups são **always-global** porque precisam ser invocáveis de qualquer região (alert de recurso em West Europe precisa fan-out via Action Group; se AG estivesse em West Europe e a região caísse, alert ficaria órfão). É uma exceção arquitetural deliberada da plataforma Azure.

---

## Passo 8.6 — Linkar Action Group ao Budget threshold 100%

Voltamos ao Budget para conectar o Action Group ao threshold de 100% Forecasted. Neste passo só linkamos email; o webhook que dispara o circuit-breaker n8n será adicionado ao Action Group no Passo 8.8.

**No Portal Azure:**

1. Topo → barra de busca → digite `Cost Management` → escopo `rg-lab-avancado` → **Budgets** → clique `budget-helpsphere-ia`
2. **Edit** (topo) → role até a seção **Set alerts**
3. Localize **Condition 3** (threshold `Forecasted 100%`)
4. **Action group** → dropdown → selecione `ag-helpsphere-ia-alerts`
5. Repita para **Condition 2** (`Actual 80%`) → **Action group:** `ag-helpsphere-ia-alerts`
6. **Save**

<!-- screenshot: cap08-passo8.6-budget-action-group-linked.png -->

7. Validar end-to-end via teste do Action Group (sem precisar estourar budget de verdade):
   - Volte → **Monitor** → **Alerts** → **Action groups** → clique `ag-helpsphere-ia-alerts`
   - Topo → botão **Test action group**
   - Escolha **Action type:** `Email` → **Test**
   - Em ~30s, `ops@apex.com.br` e `cfo@apex.com.br` devem receber email **"Sample alert from Azure Monitor"**

<!-- screenshot: cap08-passo8.6-action-group-test-email.png -->

> **Custo do test:** R$ 0 (email free).

> **Atenção SMS/voice se você habilitar:** o **Test action group** dispara TODAS as notification methods configuradas — se você adicionou SMS pro celular do prof, **vai chegar SMS real e cobrar R$ 0,30**. Em ambiente de desenvolvimento, prefira **só email** para test.

> **Nota pedagógica — por que linkar Action Group em 80% e 100%, mas não em 50%?** 50% é informativo — disparar email nesse limite gera **alert fatigue** (ops ignora se chega 4x/mês). 80% e 100% são **acionáveis**. Pattern production-grade: linkar Action Group apenas em thresholds que disparam **runbook de resposta**, não nos informativos.

---

## Passo 8.7 — Cost Analysis dashboard custom com 3 breakdowns

Cost Analysis é o **diagnóstico**: depois que budget alerta, você precisa saber **quem está queimando**. Salvamos uma view com breakdown por tag `cost-center`, por serviço (APIM vai dominar) e por dia (identificar spike).

**No Portal Azure:**

1. **Cost Management** → escopo `rg-lab-avancado` → menu lateral → **Cost analysis**
2. Topo → **View:** `Accumulated costs` (default)
3. Filtros no topo direito → **Date range:** `Last 30 days` (ou `MTD` se sub é nova)
4. Painel direito → **Group by:** **Service name** → gráfico mostra breakdown por serviço (APIM dominará após Capítulo 06; Application Insights aparece dentro do free tier)

<!-- screenshot: cap08-passo8.7-cost-analysis-by-service.png -->

5. Topo → **Save** (disquete) → **Save as new** → name: `helpsphere-ia-by-service` → **Save**
6. Topo → **+ New chart** → repetir com:
   - **Group by:** `Tag → cost-center` → name: `helpsphere-ia-by-tag`
   - **Group by:** `Resource group name` → name: `helpsphere-ia-by-rg` (útil se aluno tiver múltiplos RGs na mesma sub)
7. Para fixar daily granularity → **Granularity:** `Daily` → você vê spikes de provisioning (APIM Developer aparece em D0 quando deploy ocorreu, depois pancake até cleanup)

<!-- screenshot: cap08-passo8.7-cost-analysis-saved-views.png -->

8. **Pin to dashboard** (canto superior direito) → escolher dashboard `helpsphere-ia-dashboard` (criado no Capítulo 07) → **Pin**

> **Alternativa via Azure CLI (consultas brutas, sem visualização):**
>
> ```powershell
> # Custo por serviço últimos 30 dias
> $StartDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
> $EndDate = (Get-Date).ToString("yyyy-MM-dd")
> az consumption usage list `
>   --start-date $StartDate `
>   --end-date $EndDate `
>   --query "[?contains(instanceId, 'rg-lab-avancado')].{service:meterDetails.serviceName, cost:pretaxCost}" `
>   -o table
> ```
>
> **Linux/Mac/WSL:** troque `$StartDate = ...` por `START=$(date -u -d '30 days ago' +%Y-%m-%d)` e `` ` `` por `\`.
>
> Atenção: `consumption usage list` retorna **dados crus** sem agregação — usa-se Cost Analysis Portal para visualização agregada.

> **Custo:** R$ 0 — Cost Analysis e saved views não cobram.

> **Nota pedagógica — latência ingest do Cost Management (~8-24h):** os primeiros recursos provisionados na Capítulo 02 podem **não aparecer** ainda em Cost Analysis no momento que você roda este Passo. Latência típica do Cost Management = **8-24h** (Microsoft documenta 24h, real fica em ~8-12h). Se gráfico vier vazio, **não é erro** — é ingest pendente. Volte no dia seguinte.

> **Nota pedagógica — por que tag `cost-center` é ouro:** `Group by: Service name` mostra **APIM = R$ 250/mês** mas você não sabe se isso é do projeto Apex ou de outro. **Group by: Tag cost-center** filtra por projeto: se você tem 5 projetos na mesma sub, só `cost-center=apex-helpsphere-ia` aparece. Isso só funciona se a policy 2 (`Require cost-center tag`) **bloqueia drift** — daí o link entre Capítulos: policy → tag uniforme → Cost Analysis útil.

---

## Passo 8.8 — Circuit-breaker via workflow n8n (cross-repo · reusa n8n do Lab Final)

**Conceito:** Quando o Budget alert dispara (gasto previsto ultrapassa threshold), em vez de só enviar email, queremos **pausar recursos caros automaticamente** (APIM Developer, AI Search Standard, Container Apps com auto-scaling alto). O Action Group dispara um **webhook que aciona um workflow n8n** que executa as actions de pausa.

**Por que n8n e não Logic App:**

- Logic App: ~R$ 0,40/execução (Consumption tier) + complexidade extra de conectores Azure + designer Portal pesado.
- n8n: você **já tem provisionado** no Lab Final (cap 07 — `ca-n8n-helpsphere` em `rg-lab-final`); reusa sem custo extra.
- Padrão n8n é mais flexível para customização visual e auditoria, e o workflow vive em JSON versionável.

**Pré-requisito:** ter feito o Lab Final cap 07 com sucesso. Anote a `$env:N8N_URL` de lá (formato `https://ca-n8n-helpsphere.<random>.eastus2.azurecontainerapps.io`).

**No terminal local (Windows PowerShell 7) — criar workflow JSON no repo:**

```powershell
# 1. Confirme variáveis ambiente do Lab Final
$env:N8N_URL
$env:SUB_ID = az account show --query id -o tsv

# 2. Crie pasta n8n-workflows no repo prod-lab
New-Item -ItemType Directory -Force -Path "n8n-workflows" | Out-Null

# 3. Crie o arquivo pause-resources-on-budget.json
$WorkflowJson = @'
{
  "name": "pause-resources-on-budget",
  "nodes": [
    {
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "budget-circuit-breaker",
        "httpMethod": "POST",
        "authentication": "headerAuth"
      }
    },
    {
      "name": "Pause APIM",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "https://management.azure.com/subscriptions/{{$env.SUB_ID}}/resourceGroups/rg-lab-avancado/providers/Microsoft.ApiManagement/service/apim-helpsphere-prod?api-version=2023-05-01-preview",
        "method": "PATCH",
        "body": "{\"sku\": {\"name\": \"Consumption\"}}"
      }
    },
    {
      "name": "Notify Teams",
      "type": "n8n-nodes-base.httpRequest"
    }
  ]
}
'@
Set-Content -Path "n8n-workflows/pause-resources-on-budget.json" -Value $WorkflowJson -Encoding UTF8
```

> **Alternativa Linux/Mac/WSL (bash):** troque `$env:N8N_URL` por `echo $N8N_URL`, `New-Item -ItemType Directory -Force -Path` por `mkdir -p`, e use `cat > n8n-workflows/pause-resources-on-budget.json <<'EOF' ... EOF`.

**No Portal n8n (abrir `$env:N8N_URL` no browser):**

1. Login no n8n já provisionado no Lab Final (credenciais capturadas naquele cap)
2. **Workflows** → **+ Add workflow** → menu três pontinhos (canto superior direito) → **Import from File** → selecionar `n8n-workflows/pause-resources-on-budget.json` do repo local
3. Configurar credentials Azure: clique no node **Pause APIM** → **Credentials** → **Create New** → tipo `Azure Service Principal` (use o SP do Cap 03 prod-lab se disponível, senão crie SP novo com role `Contributor` em `rg-lab-avancado` via `az ad sp create-for-rbac --role Contributor --scopes /subscriptions/$env:SUB_ID/resourceGroups/rg-lab-avancado`)
4. Configurar **Header Auth** no node Webhook: **Credentials** → **Create New** → name: `webhook-budget-secret` → **Header name:** `X-Webhook-Secret` → **Header value:** gere um GUID (`[guid]::NewGuid().ToString()` em PowerShell) e anote
5. **Activate workflow** (toggle no canto superior direito)
6. Copiar **Webhook URL** do node Webhook (formato `https://$env:N8N_URL/webhook/budget-circuit-breaker`)

<!-- screenshot: cap08-passo8.8-n8n-workflow-imported.png -->

**No Portal Azure (Action Group do Passo 8.5/8.6):**

7. **Monitor** → **Alerts** → **Action groups** → `ag-helpsphere-ia-alerts` → **Edit**
8. Aba **Actions** → **+ Add notification** → tipo **Webhook**
   - **Name:** `n8n-circuit-breaker`
   - **URI:** colar a URL do webhook n8n copiada no passo 6
   - **Common alert schema:** `Yes` (envia payload normalizado Azure Monitor)
9. **Save**

<!-- screenshot: cap08-passo8.8-action-group-webhook-added.png -->

10. **Validação:** Forçar simulação do Budget alert via Portal → **Cost Management** → `budget-helpsphere-ia` → topo → **Send test alert** (ou disparar Action Group `Test action group` tipo `Webhook`) → verificar no n8n histórico de **Executions** que o workflow `pause-resources-on-budget` rodou e o node `Pause APIM` retornou HTTP 200/202

<!-- screenshot: cap08-passo8.8-n8n-execution-history.png -->

> **Custo:** R$ 0 extras — reusa n8n já provisionado no Lab Final. Workflow JSON é arquivo de config, sem cobrança. Cada execução do webhook é ~R$ 0,0001 no n8n self-hosted (uso desprezível).

> **Nota pedagógica — n8n é ferramenta transversal multi-lab:** Esse pattern (provisionar uma vez, reusar em N labs) é comum em ambientes corporativos. n8n vira **plataforma de automação compartilhada** entre squads — Cost Management circuit-breaker, Security incident response, deploy approvals, GitHub issue triage, etc. Em produção real, isso seria n8n self-hosted em cluster dedicado com SLA, RBAC granular e audit log centralizado. No lab, 1 instância single-tenant atende N forks de aluno sem overhead.

> **Nota pedagógica — por que `Header Auth` no webhook:** o webhook n8n é endpoint **público** (qualquer IP da internet alcança). Sem auth, qualquer pessoa que descobrir a URL pode disparar `pause-resources` repetidamente e fazer DoS no seu lab (APIM oscilando entre Developer→Consumption→Developer custa tempo + dinheiro). Header Auth resolve em 30s: n8n built-in valida `X-Webhook-Secret` antes de executar o workflow. Action Group Azure permite custom headers em webhooks (aba **Advanced** ao adicionar webhook) — passe o mesmo secret.

> **Nota pedagógica — recovery do circuit-breaker:** o workflow acima é **trip-only** (pausa, mas não religa). Em prod real, você teria um segundo workflow `resume-resources-on-budget-reset` que dispara quando o budget reseta no primeiro dia do mês (cron trigger no n8n: `0 0 1 * *`). No lab, o **aluno reseta manualmente** após investigar o gasto — força reflexão sobre RCA antes de religar.

---

## Validação end-to-end

```powershell
# 1. Verificar que os 3 policy assignments existem no RG
$SubId = az account show --query id -o tsv
az policy assignment list `
  --scope "/subscriptions/$SubId/resourceGroups/rg-lab-avancado" `
  --query "[].{name:displayName, mode:enforcementMode}" `
  -o table
# Esperado: 3 linhas, todas com mode=Default

# 2. Verificar compliance state agregada
az policy state summarize `
  --resource-group rg-lab-avancado `
  --query "results[].{name:policyAssignment, compliant:results.resourceDetails[?complianceState=='Compliant'] | length(@)}" `
  -o table

# 3. Verificar budget criado
az consumption budget list `
  --resource-group rg-lab-avancado `
  --query "[].{name:name, amount:amount, period:timeGrain}" `
  -o table
# Esperado: budget-helpsphere-ia | 200 | Monthly

# 4. Verificar action group + emails
az monitor action-group show `
  --name ag-helpsphere-ia-alerts `
  --resource-group rg-lab-avancado `
  --query "{name:name, emails:emailReceivers[].emailAddress}" `
  -o json
# Esperado: name=ag-helpsphere-ia-alerts, emails=["ops@apex.com.br","cfo@apex.com.br"]

# 5. Negative test policy: deve falhar
$Timestamp = [int][double]::Parse((Get-Date -UFormat %s))
$Output = az storage account create `
  --name "sttestpolicy$Timestamp" `
  --resource-group rg-lab-avancado `
  --location brazilsouth `
  --sku Standard_LRS 2>&1 | Out-String
if ($Output -match "RequestDisallowedByPolicy") {
    Write-Host "OK — policy bloqueou Brazil South"
} else {
    Write-Host "FAIL — policy nao bloqueou (verificar enforcementMode)"
}
```

> **Linux/Mac/WSL:** troque `$Var = cmd` por `VAR=$(cmd)`, `` ` `` por `\`, `Get-Date -UFormat %s` por `date +%s`, e o `if ($Output -match ...)` por `... 2>&1 | grep -q "RequestDisallowedByPolicy" && echo OK || echo FAIL`.

---

## Checklist final

```text
[ ] 3 policy assignments visíveis em Portal Policy → Authoring → Assignments (scope rg-lab-avancado)
[ ] Compliance state = Compliant para os 3 (após primeira evaluation, ~30 min pós-assignment)
[ ] Negative test storage Brazil South → bloqueado com RequestDisallowedByPolicy
[ ] Negative test web app sem tag → bloqueado com RequestDisallowedByPolicy
[ ] Budget budget-helpsphere-ia criado com R$ 200/mês + 3 thresholds (50/80/100)
[ ] Action group ag-helpsphere-ia-alerts com 2 emails (ops + cfo)
[ ] Test action group disparou email recebido em ambas inboxes
[ ] Action group linkado em budget thresholds 80% e 100%
[ ] Cost Analysis saved views (by-service, by-tag, by-rg) criados
[ ] Saved view by-service pinned em helpsphere-ia-dashboard
[ ] Workflow n8n pause-resources-on-budget importado e ativado em $env:N8N_URL (Passo 8.8)
[ ] Webhook n8n configurado com Header Auth (X-Webhook-Secret)
[ ] Action Group ag-helpsphere-ia-alerts tem notification tipo Webhook apontando para n8n
[ ] Test action group disparou execução visível no histórico de Executions do n8n
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **Compliance state demora ~30 min após primeiro assignment** — recém-deployado o `policy.bicep`, abrir **Policy → Compliance** mostra `Not started` ou compliance vazio. Não é erro: Azure Policy roda evaluation engine assíncrono. Workaround: aguarde 30 min ou rode `az policy state trigger-scan --resource-group rg-lab-avancado` para forçar.
- ⚠️ **`RequestDisallowedByPolicy` mostra hash em vez de display name** — error message inclui `policyAssignment: allowed-locations-<unique-hash>`, não `Allowed locations — eastus2 only`. O hash vem do `uniqueString(rgName)` no Bicep. Para mapear hash→displayName, rode `az policy assignment list` ou abra Portal blade. Mensagem de erro é confusa mas técnica está certa.
- ⚠️ **Cost Management latency 8-24h zera dashboards no D0** — após primeiro deploy do RG, abrir Cost Analysis pode mostrar `No data available` mesmo com APIM rodando. Não é bug: ingest do Cost Management roda batch. Volte no D+1 para ver dados completos. Workaround para sessão de gravação: tire screenshots de uma sub madura como referência.
- ⚠️ **Action Group `Test` dispara TODOS os methods configurados** — se você adicionou SMS para celular do prof + email + push, **todos disparam** (e SMS cobra). Em desenvolvimento, **só configure email** para evitar surpresa de R$ 0,30/SMS no test.
- ⚠️ **Budget em sub multi-currency cria confusão** — sub PAYG BR cobra em **BRL**, sub corporate AAD pode estar em **USD**. Budget amount é interpretado **na moeda da sub**, não na do usuário. Se você criar budget `200` em sub USD, é US$ 200 (~R$ 1.000), não R$ 200. Verifique **Cost Management → Subscriptions → seu sub → Settings → Currency** antes de criar.
- ⚠️ **Policy `Require cost-center tag` quebra deploy de stacks pré-existentes** — se outro Lab apontou ao mesmo RG e os recursos child do Foundry Hub não tem `cost-center` tag, redeploy falha. Workaround: parameter files devem propagar `tags: { 'cost-center': 'apex-helpsphere-ia' }` em todos os recursos. Como o `rg-lab-avancado` é stack paralela isolada, na prática isso só aparece se aluno apontou Bicep externo aqui.
- ⚠️ **n8n webhook precisa de auth header se exposto público** — workflow do Passo 8.8 sem auth aceita POST de qualquer IP da internet. Em produção, ative **Header Auth** no node Webhook (n8n built-in, ~30s de config) ou ponha n8n atrás de APIM com policy de validação JWT. Não exponha webhook público sem auth — qualquer um pode disparar `pause-resources` e DoS o lab fazendo APIM oscilar entre Developer→Consumption custando tempo + dinheiro.
- ⚠️ **n8n cross-repo precisa de RBAC explícito no `rg-lab-avancado`** — o Service Principal usado no n8n (provisionado no Lab Final) **não** tem permissão default em `rg-lab-avancado`. Workaround: rode `az role assignment create --assignee <sp-app-id> --role Contributor --scope /subscriptions/$env:SUB_ID/resourceGroups/rg-lab-avancado` no Passo 8.8 antes de testar o workflow. Erro típico se esquecer: `AuthorizationFailed` no node `Pause APIM`.
- ⚠️ **Action Group webhook tem retry policy escondida** — se o n8n estiver fora do ar quando budget dispara, Azure Monitor **retenta 3x com backoff exponencial** (1min, 5min, 25min). Se todas falharem, alert vira `dropped` silencioso no Activity Log. Workaround: monitore o próprio Action Group via secondary alert (`az monitor activity-log alert create` no `ActionGroupActionFailed`) — meta-alerting clássico.

---

## Próximo capítulo

[09 — Runbook eval](./09-runbook-eval.md)
