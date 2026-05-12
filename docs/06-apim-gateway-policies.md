# Capítulo 06 — APIM gateway + policies

> **Objetivo:** aguardar APIM Developer ficar `Online` no `rg-lab-avancado`, importar uma API REST de negócio (ex.: backend HelpSphere) como API gerenciada, aplicar a política inbound canônica (validate-jwt + rate-limit-by-key + quota-by-key + CORS + audit `<log-to-eventhub>`), e validar via **Test blade** + `curl.exe` que sem token retorna **401** e com token válido o request chega ao backend.
>
> **Tempo:** 60-90 min (não inclui ~30-45 min de provisão APIM já em background desde Capítulo 05 — siga em paralelo se ainda estiver `Activating`)

---

## 🚨 ATENÇÃO BILLING — APIM Developer cobra ~R$ 240/mês LIGADO (sem auto-pause)

APIM SKU **Developer** **não tem auto-pause**. O recurso é cobrado **mesmo sem tráfego**, na taxa fixa de uma instância dedicada — diferente da Consumption SKU (pay-per-call) e diferente de App Services free tier. Se você esquece o RG ligado por 1 mês, queima ~R$ 240 sem rodar 1 request.

### TL;DR (3 fatos que você precisa saber agora)

1. **Custo:** ~R$ 240/mês (~R$ 8/dia) ligado, R$ 0 deletado. Não há tier intermediário.
2. **Provisioning:** primeiro deploy demora **30-45 min**. Não é erro, é o SKU.
3. **Cleanup obrigatório no mesmo dia da prática** — `az group delete --name rg-lab-avancado --yes --no-wait` zera tudo. Detalhes em [Capítulo 10 — Cleanup](./10-cleanup.md).

### Custo absoluto comparado

| SKU | Custo R$ ligado | Custo R$ por chamada | Adequação ao lab |
|---|---|---|---|
| **Developer** (default lab) | **🚨 ~R$ 240/mês** (~R$ 8/dia) | incluído | ✅ Pedagógico — todas features (named values, products, JWT) |
| **Consumption** | R$ 0 parado | ~R$ 0,30 / 1M chamadas | ⚠️ Sem IP outbound estático — não cabe enterprise; só callout |
| **Premium** | ~R$ 13.000/mês | incluído | ❌ Fora de escopo — multi-region, VNet, scale 1-10 unidades |

> **Por que Developer e não Consumption no lab?** Developer entrega o **mesmo XML policy engine**, named values com Key Vault, products com subscription keys e Test blade visualmente equivalente ao Premium — único limite real é SLA (sem SLA na Developer). Consumption pay-per-call é mais barato, mas **não fornece outbound IP estático** (inviável para integrações enterprise que dependem de firewall allowlist), além de perder features pedagogicamente importantes: sem custom domain HTTPS, sem named values com Key Vault references diretas, cold-start de ~2s na primeira chamada após idle, sem APIM-internal cache. **APIM sempre Developer tier neste lab.**

### Cleanup OBRIGATÓRIO (cravar no calendário)

```powershell
# AO FIM da prática, OBRIGATÓRIO rodar:
az group delete --name rg-lab-avancado --yes --no-wait

# Confirme em ~5 min (deletion async):
az group exists --name rg-lab-avancado
# Esperado: false
```

> **Alternativa Linux/Mac/WSL (bash):** comandos `az` são idênticos.

Se você esquecer, abra **Cost Management + Billing** no Portal Azure → **Cost analysis** → filtro `Service name = API Management` para confirmar que o burn parou.

### Alternativa Consumption (callout — sem walkthrough completo)

Se sua sub não tolera ~R$ 240/mês fixos (ex.: PAYG pessoal apertado), edite `infra/envs/dev.parameters.json` (gerado no Capítulo 04):

```json
{
  "apimSku": { "value": "Consumption" }
}
```

Re-deploy via `az deployment group create` (Capítulo 05). **Atenção:** vários Passos abaixo assumem Developer — Test blade funciona igual, mas o Passo de inbound policy tem **3 limitações conhecidas em Consumption**:

- ❌ `<log-to-eventhub>` exige logger registrado — `app-insights-logger` precisa ser criado via CLI (`az apim logger create`) antes de salvar policy
- ❌ Named values com **Key Vault references diretas** não são suportados — você precisa hardcodar `{tenant-id}` ou usar named value tipo `Plain`
- ❌ **Sem outbound IP estático** — integrações que precisam allowlist no firewall do backend não funcionam
- ❌ Cold-start de ~2s na primeira chamada após 20 min idle — visivelmente piora UX em demo ao vivo

**Para o lab pedagógico canônico, mantenha Developer.** Use Consumption só se o aluno tem restrição financeira explícita.

---

## Pré-requisitos

- ✅ Capítulo 04 concluído — Bicep `infra/main.bicep` + módulo `infra/modules/apim.bicep` validados via `az bicep build` + `what-if`
- ✅ Capítulo 05 concluído — `az deployment group create` rodou ao menos 1x e provisionou `apim-helpsphere-staging` no `rg-lab-avancado` (mesmo que o status ainda esteja `Activating`)
- ✅ APIM **mínimo 30 min** desde o início do `az deployment group create` — caso contrário, espere antes de tentar Passo 4.1
- ✅ `az` CLI logado na sub correta (`az account show --query id -o tsv` confirma)
- ✅ Tenant ID em mãos (`az account show --query tenantId -o tsv`) — vai cravar no policy XML do Passo 4.3
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first
- ✅ Decisão tomada sobre backend da API: **(a)** mock via `func-mock.bicep`, **(b)** API REST existente em `rg-helpsphere-saas` (cross-RG), ou **(c)** skip Passo 4.2 como exercício conceitual (ver detalhe no Passo 4.2)

> **Nota pedagógica — APIM gateway é para APIs de negócio, NÃO para RAG interno:** A Function App RAG (provisionada no Lab Intermediário) é chamada DIRETO pelo agente SDK via HTTP, sem passar pelo APIM Gateway. APIM neste Lab Avançado é reservado para APIs de negócio (HelpSphere REST API ou similar consumida por frontends/parceiros externos), não para tools internos do agente. Em produção real, você pode reposicionar RAG atrás de APIM para ganhar rate limiting, caching e telemetry centralizada — fica como evolução opcional.

> **Nota pedagógica — backend cross-RG (`rg-helpsphere-saas`):** se o backend da API que você vai expor (ex.: HelpSphere REST) já existe em outro RG (típico: `rg-helpsphere-saas` em westus3, separado da infra de gateway em `rg-lab-avancado/eastus2`), o APIM aceita backend URL completo (ex.: `https://app-helpsphere-prod.azurewebsites.net`) sem precisar mover o backend. Cross-region latência: ~50-80ms adicionais entre regiões US — aceitável para lab, em prod real prefira mesma região.

> **Atenção gotcha — APIM ainda `Activating` quando você abrir o capítulo:** se o `az deployment group create` rodou há menos de ~30 min, o recurso provavelmente ainda está em `Activating`. Você consegue navegar para o blade, mas **não consegue salvar policies nem importar APIs** — Portal mostra erro `OperationNotAllowed: Service is not yet active`. Workaround: deixe Capítulo 06 aberto, comece [Capítulo 07 — Content Safety + App Insights](./07-content-safety-app-insights.md) em paralelo (Content Safety provisiona em ~3 min). Volte aqui quando o badge mudar para 🟢 `Online`.

> **Placeholders deste capítulo:** ao longo dos próximos Passos você verá referências a valores que dependem do seu ambiente:
>
> - `APIM_GATEWAY_URL` → URL do Gateway capturada no Passo 4.1 (ex.: `https://apim-helpsphere-staging.azure-api.net`)
> - `BACKEND_URL` → URL HTTPS do backend que o APIM vai roteado (ex.: Function App `func-helpsphere-agent` ou App Service em `rg-helpsphere-saas`)
> - `JWT_KEY` / `tenant-id` → tenant ID do Entra capturado via `az account show --query tenantId -o tsv` (cravado no named value `tenant-id` do Passo 4.3.a)
> - `<seu-username>` → fallback de uniqueness para `apim-helpsphere-staging-<seu-username>` se o nome global colidir

---

## Resumo dos 4 artefatos que vamos cravar no APIM

| # | Artefato | Onde vive no APIM | Persistido em | Observação |
|---|---|---|---|---|
| 1 | API gerenciada `helpsphere-agent` | APIs → APIs | Bicep `apim.bicep` (idempotente) | Path `/agent`, importada da Function App |
| 2 | Policy inbound XML (4 blocos) | All operations → Inbound processing | Editor inline (XML) | JWT + rate-limit-by-key + quota-by-key + CORS + audit |
| 3 | Named value `tenant-id` | Settings → Named values | Manual neste lab | Em prod real → Key Vault reference |
| 4 | Subscription key `master` (built-in) | Subscriptions → Built-in | Auto-criado pelo APIM | Usada nos `curl` de smoke |

> **Por que policy em "All operations" e não por operação?** No APIM, policy XML é hierárquico: **product > API > all operations > operation específica**. Cravar JWT + rate-limit em "All operations" da API significa que **toda nova operação** (ex.: futuras `escalate`, `health`) **herda automaticamente** o pacote inbound — você não esquece de proteger uma operação nova. Se uma operação precisar de exceção (ex.: `health` sem JWT pra liveness probe), você sobrescreve naquela operação específica com `<base />` removido. Pattern: **secure by default, exceção explícita**.

> **Nota pedagógica — por que rate-limit-by-key e não rate-limit?** A policy `<rate-limit>` (sem `-by-key`) aplica o limite **globalmente na API** — 100 chamadas/min divididas entre **todos os usuários**. Em produção isso é fácil de DoSar: 1 user agressivo zera o limite pra todo mundo. `<rate-limit-by-key>` com `counter-key="...Claims["oid"]..."` faz **partição por user OID do JWT** → cada user tem seu próprio bucket de 100 chamadas/min. Custo computacional adicional é desprezível, ganho de fairness e blast-radius é enorme.

---

## Passo 4.1 — Aguardar APIM ficar `Online` no Portal

**No Portal Azure:**

1. Abra `https://portal.azure.com` → barra de busca (topo) → digite `API Management services` → clicar
2. Localize `apim-helpsphere-staging` na lista (do RG `rg-lab-avancado`) — pode estar em qualquer região, nome do RG é o filtro confiável
3. Status na coluna **Status** (ou tab **Overview** após clicar) deve mostrar uma destas 3 transições:
   - 🟡 `Activating` (ou `Creating`) — **30-45 min normalmente** · paciência, é o SKU
   - 🟡 `Failed` — algo errado, ver troubleshooting abaixo
   - 🟢 `Online` — pronto pra Passos 4.2-4.4
4. Clique no recurso → tab **Overview** → anote o **Gateway URL** (ex.: `https://apim-helpsphere-staging.azure-api.net`)
5. Tire um screenshot do Overview (status `Online` + Gateway URL) — você vai querer evidência no portfolio

<!-- screenshot: cap06-passo4.1-apim-overview-online.png -->

> **Alternativa via Azure CLI (polling em loop até `Online`):**
>
> ```powershell
> # Verifica state pontual
> az apim show -n apim-helpsphere-staging -g rg-lab-avancado --query "provisioningState" -o tsv
>
> # Polling a cada 60s até mudar para Succeeded
> while ((az apim show -n apim-helpsphere-staging -g rg-lab-avancado --query 'provisioningState' -o tsv) -ne "Succeeded") {
>   Write-Host "Aguardando APIM... $(Get-Date -Format 'HH:mm:ss')"
>   Start-Sleep -Seconds 60
> }
> $GatewayUrl = az apim show -n apim-helpsphere-staging -g rg-lab-avancado --query gatewayUrl -o tsv
> Write-Host "✅ APIM Online — Gateway URL: $GatewayUrl"
> ```
>
> **Linux/Mac/WSL:** use `until [ "$(...)" = "Succeeded" ]; do echo ...; sleep 60; done` com `$(date '+%H:%M:%S')`.

> **Custo:** ~R$ 240/mês ligado independentemente de você estar olhando ou não — o relógio começou no momento do `az deployment group create` do Capítulo 05. Se cleanup acontecer no mesmo dia: ~R$ 8 absolutos (8 horas × R$ 1/h aproximado).

> **Nota pedagógica — por que 30-45 min e não 30 segundos?** APIM Developer/Premium provisiona uma **VM dedicada de gateway** + scale set + cluster Cassandra interno + integração com Entra para mTLS + DNS-as-a-service público. Não é container start. Compare com APIM Consumption (~5 min) que é shared multi-tenant. Pattern: **infra dedicada = cold start lento, hot performance previsível**.

> **Em paralelo enquanto APIM provisiona, abra Capítulo 07** (Content Safety provisiona em ~3 min). Não trave 45min em frente da tela.

> **Se ficar em `Failed`:** abra **Activity log** do RG → filtre `Operation name = Update API Management Service` → último erro normalmente é (a) **quota de cores APIM** na sub (Microsoft.ApiManagement / serviços APIM por sub é 5 default — pode estar estourado se você fez vários labs), ou (b) **nome global duplicado** (`apim-helpsphere-staging` precisa ser único no Azure inteiro — se outro aluno cravou primeiro, o Bicep falha). Workaround: edite `infra/envs/staging.parameters.json` para `apimName = "apim-helpsphere-staging-<seu-username>"` e re-deploy.

---

## Passo 4.2 — Importar API `helpsphere-agent` a partir da Function App

> **⚠️ Decisão de backend obrigatória antes de seguir:** este Passo importa a Function App `func-helpsphere-agent` como backend de exemplo. Se a Function não existe na sua sub (você não tem um lab anterior provisionado), você tem 3 opções pedagogicamente válidas:
>
> **(a) Re-provisionar mock rapidamente via Bicep `func-mock.bicep` (RECOMENDADO, ~3 min):** placeholder Function App com endpoint `/api/agent/chat` retornando JSON 200 estático. Suficiente pra validar import APIM + policies inbound (JWT, rate-limit, CORS) sem 502 do backend. Deploy:
>
> ```powershell
> az deployment group create `
>   --resource-group rg-lab-avancado `
>   --template-file infra-mocks/func-mock.bicep `
>   --parameters location=eastus2
> # Depois: func azure functionapp publish func-helpsphere-agent --python  (~2min)
> ```
>
> **Linux/Mac/WSL (bash):** troque `` ` `` (backtick) por `\` para continuação de linha.
>
> **(b) Reusar backend existente em `rg-helpsphere-saas` (cross-RG, ~0 min):** se você já tem o backend HelpSphere REST em outra resource group (ex.: stack SaaS em `rg-helpsphere-saas/westus3`), passe a URL absoluta dele no Bicep do APIM (`backendUrl = "https://app-helpsphere-prod.azurewebsites.net"`). APIM aceita backend cross-RG e cross-region — a única coisa que muda é latência (~50-80ms entre US regions).
>
> **(c) Skip Passo 4.2 e marcar como exercício conceitual (~0 min):** se está com pressa ou sua sub está sem quota, pula a parte de importar a API e segue pro Passo 4.3 explicando "em produção, o API import seria assim" — vale como demo arquitetural, mas você perde o Test blade ao vivo.
>
> **Recomendação default:** opção **(a)** — mock rápido, baixo custo, valida toda a camada APIM sem depender de outro stack rodando.

**No Portal Azure (APIM → importar API a partir da Function App):**

1. Em `apim-helpsphere-staging` → menu lateral → **APIs** → submenu **APIs** → clicar botão **+ Add API**
2. Galeria de templates aparece — escolher card **Function App** (ícone azul "fx", segunda fileira normalmente)
3. Painel "Create from Function App" abre à direita → clique **Browse** → painel de seleção de Function Apps na sub atual
4. Selecione `func-helpsphere-agent` (do Lab Final OU do mock criado acima) → **Select**
5. Preencha:
   - **Display name:** `HelpSphere Agent API`
   - **Name:** `helpsphere-agent` (slug — vira parte da URL)
   - **API URL suffix:** `agent` (vira `https://apim-helpsphere-staging.azure-api.net/agent`)
   - **Products:** marque ☑ `Unlimited` (default — built-in product sem rate limit, vamos sobrescrever via policy)
   - **Version this API?:** **desmarcado** para o lab (versionamento de API é tópico avançado, fora do escopo deste capítulo)
6. Clique **Create**
7. Aguardar ~10-20s — operações da Function App aparecem listadas na coluna esquerda (ex.: `chat`, possivelmente `escalate` ou `health`)

<!-- screenshot: cap06-passo4.2-apim-import-from-function-app.png -->

> **Alternativa via Azure CLI:**
>
> ```powershell
> # Captura o resourceId da Function App
> $FuncId = az functionapp show -n func-helpsphere-agent -g rg-lab-avancado --query id -o tsv
> Write-Host "Function ID: $FuncId"
>
> # Import API via CLI (equivalente ao wizard Portal)
> az apim api import `
>   --resource-group rg-lab-avancado `
>   --service-name apim-helpsphere-staging `
>   --api-id helpsphere-agent `
>   --display-name "HelpSphere Agent API" `
>   --path agent `
>   --specification-format OpenApiJson `
>   --service-url "https://func-helpsphere-agent.azurewebsites.net" `
>   --subscription-required true
> ```
>
> **Linux/Mac/WSL:** troque `$FuncId = cmd` por `FUNC_ID=$(cmd)`, `$FuncId` por `"$FUNC_ID"`, `` ` `` por `\`.

> **Custo:** zero adicional — APIM já está cobrando R$ 8/dia desde Passo 4.1. Importar API + criar policies não move o ponteiro.

> **Nota pedagógica — por que importar via Function App e não OpenAPI URL?** O wizard "Function App" do APIM **autodescobre o `host.json` + bindings da Function** e cria operations APIM 1:1 com bindings HTTP — você ganha `chat`, `escalate`, `health` automaticamente, sem escrever OpenAPI à mão. Em vez disso, se você importa por **OpenAPI URL**, precisa servir um `swagger.json` válido (que a Function pode ou não expor — Python v2 model não expõe por default). Pattern: **autodescoberta sempre que possível, OpenAPI quando o backend é não-Function** (App Service, AKS, externa).

> **Nota pedagógica — `subscription-required: true`:** força o consumer a passar header `Ocp-Apim-Subscription-Key: <key>` em **todo request**. Sem isso, APIM rejeita com **401 Subscription not found**. Combinado com JWT, você tem **2 camadas de auth**: subscription key (gateway-level) + JWT (user-level). Defesa em profundidade — uma key vazada não permite acesso sem token Entra válido também.

---

## Passo 4.3 — Aplicar policy inbound canônica (JWT + rate-limit + quota + CORS + audit)

A policy é o coração do APIM como gateway: 1 XML cobre auth, throttling, CORS e logging em ~50 linhas. Vamos cravar a versão production-grade canônica do Lab Avançado.

### Passo 4.3.a — Criar named value `tenant-id` (parametrização)

**No Portal Azure (APIM → Settings → Named values):**

1. Em `apim-helpsphere-staging` → menu lateral → **APIs** (seção) → **Named values** → **+ Add**
2. Preencher:
   - **Name:** `tenant-id`
   - **Display name:** `tenant-id`
   - **Value type:** `Plain` (em prod real seria `Key Vault` com reference)
   - **Value:** `<seu tenant ID>` — rode `az account show --query tenantId -o tsv` localmente e cole
   - **Tags:** `auth, entra` (opcional, ajuda filtragem em APIMs grandes)
3. Clique **Save**

<!-- screenshot: cap06-passo4.3a-apim-named-value-tenant-id.png -->

> **Em produção real:** `Value type = Key Vault` aponta para um secret `tenant-id` no Key Vault `kv-helpsphere-prod`, com Managed Identity do APIM autorizada via role `Key Vault Secrets User`. Rotação acontece sem editar policy XML. Para o lab, named value Plain é suficiente — você troca `<seu tenant ID>` pelo valor real e segue.

### Passo 4.3.b — Aplicar policy XML em "All operations"

**No Portal Azure (APIM → APIs → HelpSphere Agent API → Design → Inbound processing):**

1. Em `apim-helpsphere-staging` → **APIs** → **APIs** → clicar em `HelpSphere Agent API`
2. Coluna esquerda → seleção topo da lista: **All operations** (primeiro item, antes das operations específicas)
3. Painel central → seção **Inbound processing** → ícone `</>` (canto superior direito da seção) — abre editor XML inline em modal
4. Apague o XML default (`<inbound><base /></inbound>...`) e cole o XML completo abaixo:

<!-- screenshot: cap06-passo4.3b-apim-inbound-policy-editor.png -->

```xml
<!-- APIM policy: inbound JWT + rate-limit-by-key + quota-by-key + CORS + outbound audit -->
<policies>
    <inbound>
        <base />

        <!-- Auth: validate Entra ID JWT (Bearer) -->
        <validate-jwt header-name="Authorization"
                      require-scheme="Bearer"
                      output-token-variable-name="jwt"
                      require-signed-tokens="true"
                      failed-validation-httpcode="401"
                      failed-validation-error-message="Unauthorized: invalid Entra JWT">
            <openid-config url="https://login.microsoftonline.com/{{tenant-id}}/v2.0/.well-known/openid-configuration" />
            <required-claims>
                <claim name="aud" match="any">
                    <value>api://helpsphere-ia</value>
                </claim>
            </required-claims>
        </validate-jwt>

        <!-- Rate limit por user (OID do JWT): 100 req/min -->
        <rate-limit-by-key calls="100"
                          renewal-period="60"
                          counter-key="@(((Jwt)context.Variables["jwt"]).Claims["oid"].FirstOrDefault())" />

        <!-- Quota mensal por tenant (TID do JWT): 50.000 req / 30d -->
        <quota-by-key calls="50000"
                      renewal-period="2628000"
                      counter-key="@(((Jwt)context.Variables["jwt"]).Claims["tid"].FirstOrDefault())" />

        <!-- CORS para frontend HelpSphere -->
        <cors allow-credentials="false">
            <allowed-origins>
                <origin>https://app-helpsphere-prod.azurewebsites.net</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
                <method>OPTIONS</method>
            </allowed-methods>
            <allowed-headers>
                <header>*</header>
            </allowed-headers>
        </cors>
    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />

        <!-- Audit log estruturado para Application Insights via Event Hub logger -->
        <log-to-eventhub logger-id="app-insights-logger">
            @{
                var auditPayload = new {
                    timestamp = DateTime.UtcNow.ToString("o"),
                    operation = context.Operation.Name,
                    tenant = ((Jwt)context.Variables["jwt"]).Claims["tid"].FirstOrDefault(),
                    user = ((Jwt)context.Variables["jwt"]).Claims["oid"].FirstOrDefault(),
                    response_code = context.Response.StatusCode,
                    duration_ms = context.Elapsed.TotalMilliseconds
                };
                return Newtonsoft.Json.JsonConvert.SerializeObject(auditPayload);
            }
        </log-to-eventhub>
    </outbound>

    <on-error>
        <base />
    </on-error>
</policies>
```

5. Confirme que o `{{tenant-id}}` (com **2 chaves**, sintaxe APIM named value) está presente — esse é o ponto de parametrização. Se você cravar `{tenant-id}` (1 chave) em vez de `{{tenant-id}}`, o APIM trata como literal e o JWT validation falha com `OpenIdConnectConfiguration retrieved is null`.
6. Clique **Save** (botão azul no rodapé do editor)
7. APIM valida o XML e mostra ✅ `Saved successfully` no topo · se houver erro de XML mal-formado, o editor destaca a linha

> **Alternativa via Azure CLI (atomic policy update):**
>
> ```powershell
> # Salve o XML acima em $env:TEMP\apim-inbound.xml localmente, com {{tenant-id}} já correto
> az apim api policy create `
>   --resource-group rg-lab-avancado `
>   --service-name apim-helpsphere-staging `
>   --api-id helpsphere-agent `
>   --policy-format xml `
>   --value "@$env:TEMP\apim-inbound.xml"
> ```
>
> **Linux/Mac/WSL:** use `/tmp/apim-inbound.xml`, troque `` ` `` por `\`.

> **Custo:** zero adicional. Policy execution é incluída no tier Developer/Premium (não há cobrança por execução de policy).

> **Nota pedagógica — `<log-to-eventhub>` exige logger registrado:** o atributo `logger-id="app-insights-logger"` referencia um **APIM Logger** que precisa existir antes de salvar o policy. Se você ainda não criou (vai criar no Capítulo 07 quando configurar App Insights + Event Hub bridge), o **Save falha com erro `Logger 'app-insights-logger' not found`**. Workaround temporário: comente o bloco `<log-to-eventhub>` inteiro (envolva em `<!-- ... -->`), salve, configure o logger no Capítulo 07, depois descomente e re-save. Pattern: **dependency-aware editing** — XML APIM tem dependências runtime que o editor não valida em tempo de digitação.

> **Nota pedagógica — por que `audience = api://helpsphere-ia` e não Client ID?** Em Entra App Registrations, **Application ID URI** (`api://...`) é a **identidade lógica da API**, separada do client ID que é a **identidade do app cliente**. JWTs emitidos para acessar a API têm `aud=api://helpsphere-ia`, JWTs emitidos para o cliente em si têm `aud=<client-id>`. Validar `aud=api://helpsphere-ia` garante que o token foi emitido **pra essa API especificamente**, não reutilizado de outro app. Sem isso, qualquer JWT do tenant passaria pela policy. Pattern: **resource-scoped audience validation, sempre**.

---

## Passo 4.4 — Testar gateway via Test blade do APIM

**No Portal Azure (APIM → APIs → HelpSphere Agent API → Test):**

1. Ainda em `HelpSphere Agent API` → tab **Test** (ao lado de Design no painel central)
2. Coluna esquerda mostra as operations descobertas. Selecione `chat` (ou `POST /api/agent/chat` — nome equivalente da Function App)
3. **Cenário 1 — sem Authorization (esperado: 401):**
   - Não preencha nada · clique **Send**
   - Painel direito → **HTTP response** → verifique:
     - **Status:** `401 Unauthorized`
     - **Body:** `{ "statusCode": 401, "message": "Unauthorized: invalid Entra JWT" }` (mensagem do `failed-validation-error-message` da policy)
   - ✅ JWT validation funcionando — sem token, gateway bloqueia antes de chegar no backend

<!-- screenshot: cap06-passo4.4-apim-test-401-no-token.png -->

4. **Cenário 2 — com token Entra válido (esperado: 200):**
   - Localmente, capture um token de acesso para a API:

     ```powershell
     $Token = az account get-access-token --resource api://helpsphere-ia --query accessToken -o tsv
     Write-Host ($Token.Substring(0, 60) + "...")  # Confirme que tem ~1500 chars
     ```

     **Linux/Mac/WSL:** `TOKEN=$(az account get-access-token --resource api://helpsphere-ia --query accessToken -o tsv); echo "$TOKEN" | head -c 60; echo "..."`

   - Volte ao Test blade → tab **Headers** → **+ Add header**:
     - **Name:** `Authorization` · **Value:** `Bearer <cole o token>`
   - Tab **Body** → escolha `application/json` → cole `{"message": "Olá"}`
   - **Send**
   - Esperado: **200 OK** com body do backend Function App (mock retorna `{"reply": "Echo: Olá"}` ou similar)

<!-- screenshot: cap06-passo4.4-apim-test-200-with-token.png -->

5. **Cenário 3 — rate-limit (esperado: 429 após 100 chamadas):**
   - Para validar rate-limit-by-key, rode em loop:

     ```powershell
     1..105 | ForEach-Object {
       $i = $_
       $code = curl.exe -s -o $null -w "%{http_code}" `
         -X POST "https://apim-helpsphere-staging.azure-api.net/agent/api/agent/chat" `
         -H "Authorization: Bearer $Token" `
         -H "Content-Type: application/json" `
         -d '{"message":"loop"}'
       Write-Host "${i}: $code"
     }
     ```

     **Linux/Mac/WSL:** `for i in $(seq 1 105); do curl -s -o /dev/null -w "$i: %{http_code}\n" -X POST ... -H "Authorization: Bearer $TOKEN" ...; done` com `\` no fim de cada linha.

   - Esperado: chamadas 1-100 retornam 200, chamadas 101-105 retornam **429 Too Many Requests** (rate-limit-by-key cravando)

> **Alternativa via curl externo (sem Test blade):**
>
> ```powershell
> $ApimUrl = az apim show -n apim-helpsphere-staging -g rg-lab-avancado --query gatewayUrl -o tsv
>
> # Sem token — esperado 401
> curl.exe -i "$ApimUrl/agent/api/agent/chat"
>
> # Com token Entra
> $Token = az account get-access-token --resource api://helpsphere-ia --query accessToken -o tsv
> curl.exe -i -X POST "$ApimUrl/agent/api/agent/chat" `
>   -H "Authorization: Bearer $Token" `
>   -H "Content-Type: application/json" `
>   -d '{"message": "Olá"}'
> ```
>
> **Linux/Mac/WSL:** troque `$ApimUrl = cmd` por `APIM_URL=$(cmd)`, `$ApimUrl` por `"$APIM_URL"`, `curl.exe` por `curl`, `` ` `` por `\`.

> **Custo:** chamadas Test blade são gratuitas (Developer SKU inclui chamadas ilimitadas). Apenas o backend Function App cobra por execução (free tier ou Consumption ~R$ 0,002 por chamada).

> **Nota pedagógica — Test blade vs curl externo:** Test blade injeta automaticamente o **subscription key** do APIM (header `Ocp-Apim-Subscription-Key`) — você não precisa cravar manualmente. Em `curl` externo, **você precisa adicionar** `-H "Ocp-Apim-Subscription-Key: <key>"` ou o gateway rejeita com 401 antes de chegar no JWT validate. Pattern útil em demo ao vivo: Test blade pra mostrar happy path rápido, `curl` pra mostrar o que o frontend real precisa fazer.

> **Validar audit log no App Insights:** após algumas requests com token válido, abra **Application Insights** (`ai-helpsphere-staging`, criado no Capítulo 04 Bicep) → **Logs** → cole query:
>
> ```kql
> ApiManagementGatewayLogs
> | where TimeGenerated > ago(15m)
> | project TimeGenerated, OperationName, ResponseCode, BackendResponseCode, RequestSize, ResponseSize
> | take 50
> ```
>
> Esperado: linhas com `OperationName = chat`, `ResponseCode = 200/401/429`. Se o `<log-to-eventhub>` estiver configurado (Capítulo 07), você também terá custom payload com `tenant`, `user`, `duration_ms`.

---

## Validação end-to-end

```powershell
# 1. Confirma APIM Online + Gateway URL
az apim show -n apim-helpsphere-staging -g rg-lab-avancado `
  --query "{name:name, state:provisioningState, sku:sku.name, gatewayUrl:gatewayUrl}" -o table
# Esperado: state=Succeeded, sku=Developer

# 2. Lista APIs registradas
az apim api list -g rg-lab-avancado --service-name apim-helpsphere-staging `
  --query "[].{id:name, path:path, displayName:displayName}" -o table
# Esperado: 1+ linha com id=helpsphere-agent, path=agent

# 3. Captura subscription key built-in (master)
$ApimKey = az apim subscription show `
  --resource-group rg-lab-avancado `
  --service-name apim-helpsphere-staging `
  --sid master `
  --query primaryKey -o tsv

# 4. Smoke sem token → 401 esperado
curl.exe -i -X POST "https://apim-helpsphere-staging.azure-api.net/agent/api/agent/chat" `
  -H "Ocp-Apim-Subscription-Key: $ApimKey"
# Esperado: HTTP/1.1 401 Unauthorized

# 5. Smoke com token → 200 esperado
$Token = az account get-access-token --resource api://helpsphere-ia --query accessToken -o tsv
curl.exe -i -X POST "https://apim-helpsphere-staging.azure-api.net/agent/api/agent/chat" `
  -H "Ocp-Apim-Subscription-Key: $ApimKey" `
  -H "Authorization: Bearer $Token" `
  -H "Content-Type: application/json" `
  -d '{"message":"smoke"}'
# Esperado: HTTP/1.1 200 OK com body do backend
```

> **Linux/Mac/WSL:** troque `$ApimKey = cmd` por `APIM_KEY=$(cmd)`, `$Token = cmd` por `TOKEN=$(cmd)`, referências `$ApimKey`/`$Token` por `"$APIM_KEY"`/`"$TOKEN"`, `curl.exe` por `curl`, `` ` `` por `\`.

---

## Checklist final

```text
[ ] APIM apim-helpsphere-staging com provisioningState=Succeeded
[ ] Gateway URL anotado (https://apim-helpsphere-staging.azure-api.net)
[ ] API helpsphere-agent importada com path /agent + subscription-required=true
[ ] Operations da Function App descobertas (chat + outras)
[ ] Named value tenant-id criado (tipo Plain, valor = az account show tenantId)
[ ] Policy inbound cravada em "All operations" — 4 blocos (validate-jwt + rate-limit-by-key + quota-by-key + cors) + outbound log-to-eventhub
[ ] Sem token (Test blade) → 401 com mensagem custom
[ ] Com token Entra válido → 200 chega ao backend
[ ] Loop de 105 chamadas → 429 a partir da 101 (rate-limit-by-key validado)
[ ] Subscription key master capturada e validada via curl externo
[ ] (Opcional Capítulo 07) Audit log aparecendo em ApiManagementGatewayLogs no App Insights
```

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **APIM Developer provisiona em ~30-45 min — abra outro terminal e faça caps em paralelo** — é o SKU dedicado, não cold-start de container. Não trave em frente da tela: enquanto APIM está `Activating`, comece [Capítulo 07 — Content Safety + App Insights](./07-content-safety-app-insights.md) (Content Safety provisiona em ~3 min). Voltando aqui quando o badge mudar para 🟢 `Online`. Anti-padrão: ficar olhando o Portal por 45 min sem progredir nos outros capítulos.
- ⚠️ **`{tenant-id}` (1 chave) em vez de `{{tenant-id}}` (2 chaves) na policy** — APIM trata 1 chave como literal e o `<openid-config url>` vira `https://login.microsoftonline.com/{tenant-id}/v2.0/...` (404). JWT validation passa silenciosamente com `OpenIdConnectConfiguration retrieved is null`, então requests 200 mesmo sem token. Anti-pattern grave: **gateway aberto sem você notar**. Workaround: sempre `{{...}}` para named values, validar com Test blade sem token (deve dar 401, não 200).
- ⚠️ **`<rate-limit-by-key>` SEM `counter-key` literal aplica throttle global, não por usuário** — se você cravar `<rate-limit-by-key calls="100" renewal-period="60" />` sem o atributo `counter-key="@(context.Subscription.Id)"` (ou `Claims["oid"]`), APIM **trata como `<rate-limit>` global** silenciosamente. 1 usuário agressivo zera o bucket de 100 chamadas/min pra todos. Workaround: SEMPRE explicite `counter-key` com uma expressão policy (`@(...)`) ou string literal — sem essa, a policy degrada para global sem warning.
- ⚠️ **`<validate-jwt>` com `<openid-config url>` exige endpoint HTTPS discoverable** — Entra ID free/standard expõe `https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration` automaticamente, mas se você apontar para um **tenant custom dev** (B2C, ADFS on-prem, IdP self-hosted), a URL precisa: (1) ser HTTPS válida com cert público, (2) retornar JSON com `jwks_uri` discoverable, (3) responder em <5s (APIM faz cache 1h). Se o `openid-config` falhar, JWT validation cai pra `OpenIdConnectConfiguration retrieved is null` (mesmo cenário do gotcha acima). Workaround: teste a URL com `curl.exe https://login.microsoftonline.com/{tenant}/v2.0/.well-known/openid-configuration` antes de cravar na policy.
- ⚠️ **APIM hostname custom (CNAME) requer cert TLS — Let's Encrypt manual ou Azure managed cert** — por default, APIM expõe `https://apim-helpsphere-staging.azure-api.net` com cert wildcard `*.azure-api.net` (Microsoft-managed). Se você quer hostname próprio (`api.helpsphere.com`), cravar CNAME para `apim-helpsphere-staging.azure-api.net` **não basta** — APIM rejeita TLS handshake porque o cert não cobre o domain custom. Opções: (a) `az apim custom-domain create` apontando para cert do Key Vault (Let's Encrypt renovado manualmente ou cert pago), (b) Azure DNS managed cert (preview, free, só funciona se o domínio é Azure DNS zone). Workaround para o lab: **fique no hostname `*.azure-api.net` default** — custom domain é evolução pós-lab.
- ⚠️ **Subscription key vs OAuth Bearer — qual usar quando?** APIM Developer aceita **ambos por default**: `Ocp-Apim-Subscription-Key` (gateway-level, identifica o **app cliente**) E `Authorization: Bearer <jwt>` (user-level, identifica o **usuário**). Pattern produção: **subscription key obrigatória** + **JWT obrigatório** = defesa em profundidade. Pattern dev/lab: subscription-key suficiente para smoke rápido. Anti-pattern: produção sem subscription-key porque "JWT já valida" — você perde a camada de revogação no APIM (revogar uma subscription é 1 click; revogar JWT exige short-lived tokens + caching).
- ⚠️ **`Logger 'app-insights-logger' not found` ao salvar policy** — você ainda não criou o APIM logger (vai criar Capítulo 07). Workaround: comente `<log-to-eventhub>` inteiro com `<!-- ... -->`, salve, descomente após Capítulo 07. Não tenta criar o logger antes de App Insights existir.
- ⚠️ **APIM ainda `Activating` quando você abre Passo 4.2** — Portal abre o blade, mas Save de qualquer coisa retorna `OperationNotAllowed: Service is not yet active`. Workaround: aguarde badge mudar para 🟢 `Online` no Overview · em paralelo, comece Capítulo 07 (Content Safety provisiona em ~3 min).
- ⚠️ **`AADSTS500011: The resource principal named api://helpsphere-ia was not found`** ao tentar `az account get-access-token --resource api://helpsphere-ia` — significa que o **App Registration** com Application ID URI `api://helpsphere-ia` ainda não foi criado no Entra. Workaround: criar mock manualmente: `az ad app create --display-name helpsphere-ia --identifier-uris api://helpsphere-ia`.
- ⚠️ **CORS preflight OPTIONS retornando 401** — frontend Angular/React faz `OPTIONS` antes de POST e o `<validate-jwt>` bloqueia OPTIONS porque preflight não carrega JWT. Workaround: a policy oficial já tem `<cors>` que **intercepta OPTIONS antes do `<validate-jwt>` chegar** (porque `<base />` da hierarquia inclui CORS handling). Se você reordenar e colocar `<validate-jwt>` antes de `<cors>`, quebra preflight. Pattern: **CORS sempre antes de auth** na ordem inbound.
- ⚠️ **Subscription key vaza no log de `curl.exe -v`** — `Ocp-Apim-Subscription-Key` aparece em texto plano em logs verbose. Em produção, `curl.exe --no-progress-meter -s` ou redirecione stderr. Em pipelines CI, sempre passe key como secret (`${{ secrets.APIM_KEY }}` no GitHub Actions, variável segura no Azure DevOps) para mascarar automaticamente no log.
- ⚠️ **Loop de 105 chamadas atinge 429 antes de 101** — se você abriu múltiplas sessões `az` ou outro lab usa o mesmo `oid` no token (ex.: você é admin global de várias subs), o counter `Claims["oid"]` já tinha contagem prévia. Workaround: aguarde 60s (renewal-period) entre testes, ou use uma conta de teste dedicada.

---

## Próximo capítulo

[07 — Content Safety + App Insights](./07-content-safety-app-insights.md)
