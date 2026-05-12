# Capítulo 04a — Bicep modules (5 templates)

> **Objetivo:** criar `infra/main.bicep` (entry point scope=resourceGroup) + 4 módulos canônicos (`apim`, `content-safety`, `app-insights`, `policy`) cobrindo o stack completo de IA production-grade. Este capítulo crava **só os templates Bicep** — parameter files por env, build local e lint ficam no Capítulo 04b.
>
> **Tempo:** 60-90 min (varia conforme familiaridade com Bicep)
>
> **Status:** `v0.2.0-portal` ⚠️ EXPANDIDO (era `v0.1.0-init` outline)

---

## Pré-requisitos

- ✅ RG `rg-lab-avancado` existe em East US 2 com 4 tags FinOps aplicadas (`cost-center=apex-helpsphere-ia environment=lab application=helpsphere-ia owner=<seu-email>`)
- ✅ Repo local clonado (VS Code) — pasta `infra/` ainda vazia
- ✅ VS Code com extensão **Bicep** instalada (autocomplete + lint inline + symbol references)
- ✅ Azure CLI logado (`az login`) — `az bicep version` retorna `>=0.30`
- ✅ PowerShell 7+ no Windows (ou bash em Linux/Mac/WSL) — comandos abaixo são PowerShell-first
- ✅ Subscription ID anotado — `az account show --query id -o tsv` exibe o GUID
- ⚠️ Service Principal Federated **NÃO é pré-requisito desta versão** — o módulo `policy.bicep` (Passo 2.5) declara role grants para um SP, mas o deploy real fica fora do escopo (CLI manual usa o usuário logado). Mantenha o template para fidelidade ao pattern production-grade, mesmo que você só rode `az bicep build` localmente.

> **Atenção preview:** APIM **Developer SKU** vai ser declarado neste capítulo (~R$ 8/dia ligado = ~R$ 240/mês). O recurso **só provisiona quando você rodar `az deployment group create`** (capítulo seguinte). Aqui você está só descrevendo o template — custo zero.

---

## Resumo dos 5 templates Bicep que vamos cravar

| Arquivo | Scope | Responsabilidade | SKU/tier | Custo provisionado |
|---|---|---|---|---|
| `infra/main.bicep` | `resourceGroup` (default) | Orquestra 3 módulos: APIM, Content Safety, App Insights | — | — |
| `infra/modules/apim.bicep` | `resourceGroup` | APIM + Logger + Diagnostic settings + Named Value secret | Developer | ~R$ 8/dia ligado (~R$ 240/mês) |
| `infra/modules/content-safety.bicep` | `resourceGroup` | Cognitive Services kind=ContentSafety | F0 (free) | R$ 0 (5K req/mês free) |
| `infra/modules/app-insights.bicep` | `resourceGroup` | App Insights workspace-based (Log Analytics) | — | R$ 0 nos primeiros 5GB/mês (free tier); ~R$ 5-15/mês acima |
| `infra/modules/policy.bicep` | **`subscription`** | 3 Policy Definitions + Policy Assignments + role grants compensatórios | — | R$ 0 |

> **Nota pedagógica — por que `policy.bicep` é `targetScope=subscription` e os outros são `resourceGroup`?** Policy Definitions e Assignments **só existem no escopo da subscription** no Azure ARM model. Misturá-los com recursos resource-group-scoped faz Bicep falhar com `InvalidTemplate: scope mismatch`. Pattern canônico: `main.bicep` = `scope=resourceGroup` chama 3 módulos resource-group-scoped; `policy.bicep` é deployado **separadamente** como bootstrap subscription-level via `az deployment sub create`.

> **Nota pedagógica — Bicep IS canonical:** **tudo** que vai pra Azure passa por Bicep. Mudanças manuais no Portal = drift. Drift é detectado e sobrescrito no próximo `az deployment group create`. Filosofia: o template é a fonte da verdade, o Portal é só pra **visualizar** o que o Bicep declarou.

---

## Passo 2.1 — Criar `infra/main.bicep` (entry point)

**No VS Code (ou editor de sua preferência):**

1. Na raiz do clone local, crie a estrutura de pastas:

   ```powershell
   New-Item -ItemType Directory -Force -Path infra/modules, infra/envs | Out-Null
   ```

   > **Linux/Mac/WSL:** `mkdir -p infra/modules infra/envs`

2. Crie o arquivo `infra/main.bicep` com o conteúdo abaixo:

```bicep
// infra/main.bicep
@description('Environment name')
param env string

@description('Azure region')
param location string = 'eastus2'

@description('Tags applied to all resources')
param tags object = {
  'cost-center': 'apex-helpsphere-ia'
  environment: env
  application: 'helpsphere-ia'
}

@description('APIM SKU - Developer for non-prod, Standard for prod')
param apimSku string = (env == 'prod') ? 'Standard' : 'Developer'

@description('Content Safety SKU')
@allowed(['F0', 'S0'])
param contentSafetySku string = 'F0'

@description('Subscription ID for cross-RG references')
param subscriptionId string = subscription().subscriptionId

// =========================================================================
// Modules
// =========================================================================

module appInsights 'modules/app-insights.bicep' = {
  name: 'app-insights-deployment'
  params: {
    location: location
    name: 'ai-helpsphere-${env}'
    workspaceId: '/subscriptions/${subscriptionId}/resourceGroups/rg-lab-avancado/providers/Microsoft.OperationalInsights/workspaces/log-helpsphere-lab'
    tags: tags
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    name: 'apim-helpsphere-${env}'
    sku: apimSku
    tags: tags
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
  }
}

module contentSafety 'modules/content-safety.bicep' = {
  name: 'content-safety-deployment'
  params: {
    location: location
    name: 'cs-helpsphere-${env}'
    sku: contentSafetySku
    tags: tags
  }
}

// NOTE: o módulo policy.bicep tem targetScope='subscription' (definitions + role grants
// no escopo da subscription). Por isso NÃO é instanciado aqui (este main.bicep tem
// scope=resourceGroup). Deploy separado:
//   az deployment sub create --location <region> --template-file infra/modules/policy.bicep ...
// Veja Passo 2.5 para detalhes do template.

// =========================================================================
// Outputs
// =========================================================================
output apimGatewayUrl string = apim.outputs.gatewayUrl
output contentSafetyEndpoint string = contentSafety.outputs.endpoint
output appInsightsConnectionString string = appInsights.outputs.connectionString
```

<!-- screenshot: cap04a-passo2.1-vscode-main-bicep.png -->

> **Alternativa via Portal Azure:**
> Não tem alternativa Portal — Bicep é code-first por design. O Portal Azure tem **Export Template** que gera ARM JSON, mas **não Bicep**. Workflow correto: VS Code + extensão Bicep + `az bicep build`.

> **Custo:** zero — Bicep template é só código local. Custo só acontece quando você rodar `az deployment group create` no capítulo seguinte.

> **Nota pedagógica — por que `appInsights` declarado ANTES de `apim`?** Porque `apim.bicep` precisa do output `appInsights.outputs.instrumentationKey` como parameter (`appInsightsInstrumentationKey`). Bicep resolve dependências por **referências entre símbolos**, não por ordem de declaração no arquivo — mas escrever na ordem topológica deixa o template auto-documentado.

> **Nota pedagógica — `param env string` sem `@allowed`:** poderíamos travar com `@allowed(['dev', 'staging', 'prod'])`. Não fizemos porque o lab quer mostrar o pattern **expandível**: amanhã você adiciona `qa` ou `preview` sem reabrir o template. Trade-off: digitação livre permite typo (`stagging`). Em prod real, **trave com allowed**.

---

## Passo 2.2 — Criar `infra/modules/apim.bicep` (gateway + observability)

**No VS Code:**

Crie o arquivo `infra/modules/apim.bicep`:

> **TECH-AVA-006 fix:** o `logger` referencia o named value `instrumentation-key`. Em Bicep, a ordem dos `resource` no template não garante ordem de criação no Azure — declaramos `dependsOn` explícito para forçar `namedValue` ANTES do `logger`. Sem isso, o deploy falha com `ResourceNotFound: instrumentation-key` na primeira execução.
>
> Adicionamos também o parâmetro `appInsightsInstrumentationKey` (passado pelo `main.bicep` via output do módulo App Insights) e marcamos o named value como `secret: true` para o instrumentation key não vazar em logs/templates exportados.

```bicep
// infra/modules/apim.bicep
param location string
param name string
param sku string
param tags object

@description('Instrumentation key do Application Insights — vem do output appInsights.instrumentationKey no main.bicep')
@secure()
param appInsightsInstrumentationKey string

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: 1
  }
  properties: {
    publisherName: 'Apex Group'
    publisherEmail: 'platform@apex.com.br'
    virtualNetworkType: 'None'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// 1) Named value criado PRIMEIRO (logger depende dele)
//    secret: true para o instrumentation key não vazar em template exports / portal UI
resource namedValueInstrumentationKey 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'instrumentation-key'
  properties: {
    displayName: 'instrumentation-key'
    value: appInsightsInstrumentationKey
    secret: true
  }
}

// 2) Logger criado APÓS named value (dependsOn explícito)
resource logger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apim
  name: 'app-insights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'App Insights logger for audit'
    credentials: {
      instrumentationKey: '{{instrumentation-key}}'  // referência ao named value criado acima
    }
  }
  dependsOn: [
    namedValueInstrumentationKey
  ]
}

// 3) Diagnostic settings — usa o logger
resource diagnostic 'Microsoft.ApiManagement/service/diagnostics@2023-09-01-preview' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    logClientIp: true
    loggerId: logger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    verbosity: 'information'
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
```

<!-- screenshot: cap04a-passo2.2-vscode-apim-bicep-symbols.png -->

> **Alternativa via Portal Azure:**
> Não há — APIM **pode** ser criado pelo Portal manualmente, mas isso quebra o princípio "Bicep IS canonical". Se você criar pelo Portal e depois tentar deploy do Bicep, ARM **substitui** as configurações manuais (drift detection). Não misture.

> **Custo:** APIM Developer = **~R$ 8/dia ligado** (~R$ 240/mês mesmo com zero requests — APIM cobra pela alocação compute, não por chamada). Provisione e delete **no mesmo dia** durante o lab via `az group delete -n rg-lab-avancado --yes`. Em prod real, Standard = ~R$ 1.500/mês, Premium = ~R$ 11.000+/mês.

> **Surpresa pedagógica — `sku.name = 'Developer'` é o único tier não-prod viável para lab:** `Consumption` SKU (serverless) NÃO tem outbound IP estático nem custom domain, e não suporta `namedValues`/`loggers` ricos. `Basic`/`Standard`/`Premium` cobram 5x-50x mais. Developer é o ponto doce para validar pattern production-grade sem queimar R$ 1.500+ em uma semana de lab.

> **Nota pedagógica — por que 3 recursos separados (`namedValue` + `logger` + `diagnostic`) e não inline?** Porque APIM Logger **referencia** o named value via `{{instrumentation-key}}` — se o named value não existe ainda, deploy falha. O `dependsOn` explícito é o que garante ordem em ARM. Sem `dependsOn`, ARM tenta criar paralelo → race condition. **Pattern canônico Microsoft** documentado em [APIM ARM templates](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service).

> **Nota pedagógica — `@secure()` no parameter + `secret: true` no named value:** double-protection. `@secure()` impede o instrumentation key de aparecer no `az deployment group show` (output do deploy). `secret: true` impede que o named value apareça em texto claro no Portal blade ou em `az apim nv show`. Em prod real, **sempre dois layers** quando lidando com chaves.

---

## Passo 2.3 — Criar `infra/modules/content-safety.bicep`

**No VS Code:**

Crie o arquivo `infra/modules/content-safety.bicep`:

```bicep
// infra/modules/content-safety.bicep
param location string
param name string
param sku string
param tags object

resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
  }
}

output endpoint string = contentSafety.properties.endpoint
output id string = contentSafety.id
```

<!-- screenshot: cap04a-passo2.3-vscode-content-safety-bicep.png -->

> **Alternativa via Portal Azure (apenas para inspecionar resource provider):**
> Portal → **Create a resource** → busque **Content Safety** → você vê os mesmos campos (location, sku, customSubDomainName). Use isso só para **conferir nomenclatura de propriedades**, depois volte e implemente em Bicep.

> **Custo:** Content Safety **F0 (free tier)** = R$ 0 com até 5.000 requests/mês + 10 RPS. Em prod real, S0 = R$ 0,75 por 1.000 req. Para o lab inteiro, F0 sobra.

> **Nota pedagógica — por que `customSubDomainName` é obrigatório?** Cognitive Services exige um **subdomain único globalmente** (não só dentro da sub) para construir o endpoint `https://<name>.cognitiveservices.azure.com/`. Se você usar `name: 'cs-test'` e alguém no mundo já tomou, deploy falha com `SubdomainAlreadyExists`. Pattern: incluir env no nome (`cs-helpsphere-staging` vs `cs-helpsphere-prod`) reduz colisão.

> **Nota pedagógica — `publicNetworkAccess: 'Enabled'` é production-grade?** Não — em prod real, você usa **Private Endpoints + VNet integration** (`publicNetworkAccess: 'Disabled'` + private DNS). Para o lab, `Enabled` simplifica o smoke test. O **pattern de fronteira pública** (APIM com JWT validation isolando Content Safety) fica fora deste capítulo — quando você plugar o APIM provisionado no Passo 2.2, vale acrescentar policy `validate-jwt` antes do `backend` apontando para Content Safety.

> **Surpresa pedagógica — `kind = 'ContentSafety'` ≠ `kind = 'AIServices'`:** se você copiou de outro Cognitive Services template e o `kind` ficou `'AIServices'` (multi-service umbrella), o deploy passa mas o endpoint Content Safety **não responde** os paths `/contentsafety/text:analyze`. O resource provider é o mesmo (`Microsoft.CognitiveServices/accounts`), mas o `kind` muda o SKU plane disponível. Sempre `'ContentSafety'` literal para este módulo.

---

## Passo 2.4 — Criar `infra/modules/app-insights.bicep`

**No VS Code:**

Crie o arquivo `infra/modules/app-insights.bicep`:

```bicep
// infra/modules/app-insights.bicep
param location string
param name string
param workspaceId string
param tags object

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
  }
}

output connectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey
```

<!-- screenshot: cap04a-passo2.4-vscode-app-insights-bicep.png -->

> **Alternativa via Portal Azure (apenas referência):**
> Portal → **Application Insights** → **Create** → você confirma os campos (Application_Type, Workspace-based, Workspace ID). Pattern Bicep replica isso em template versionado.

> **Custo:** App Insights cobra por **GB ingerido** (não por número de eventos). Os primeiros **5GB/mês são free tier** (cobre o lab inteiro com folga). Daily cap default = 100GB — para evitar surpresa, configure manualmente daily cap em 1GB pelo Portal (`Application Insights → Usage and estimated costs → Daily cap`) após o deploy. Sem cap, Function App com logs verbose pode estourar R$ 100+/mês.

> **Surpresa pedagógica — `WorkspaceResourceId` obrigatório:** App Insights "classic" (sem workspace) está deprecated. Se você omitir a property `WorkspaceResourceId` ou apontar para um workspace que não existe, o deploy falha com `LinkedAuthorizationFailed` (a mensagem é enganosa — parece RBAC, mas é resource-not-found). Sempre rode `az monitor log-analytics workspace show -g rg-lab-avancado -n log-helpsphere-lab` ANTES de `az deployment group create`.

> **Nota pedagógica — workspace-based (Log Analytics) vs classic (legacy):** App Insights **classic** já está EOL — **sempre workspace-based** em novos projetos. O `workspaceId` aponta para um Log Analytics workspace pré-existente (`log-helpsphere-lab` em `rg-lab-avancado`). Se você ainda não criou esse workspace, rode antes do deploy: `az monitor log-analytics workspace create -g rg-lab-avancado -n log-helpsphere-lab -l eastus2`.

> **Nota pedagógica — output `instrumentationKey` mesmo sendo "legacy":** APIM Logger **só aceita** instrumentation key (não Connection String — ainda). Por isso outputamos os dois. Aplicações novas (Function App, ACA) usam **Connection String**. APIM Logger usa **Instrumentation Key**. É inconsistência da Microsoft, não sua.

---

## Passo 2.5 — Criar `infra/modules/policy.bicep` (subscription scope)

**No VS Code:**

Crie o arquivo `infra/modules/policy.bicep`:

> **Bug recorrente 1 (scope mismatch):** `Microsoft.Authorization/policyDefinitions` e `policyAssignments` em **scope = subscription** não podem ser declarados num módulo cujo deployment alvo é `resourceGroup`. Isso faz Bicep falhar com `InvalidTemplate: scope mismatch`. A correção é **`targetScope = 'subscription'`** no topo do arquivo + chamar este módulo via `az deployment sub create` (não `az deployment group create`).
>
> **Bug recorrente 2 (RBAC compensatório):** se você for usar um Service Principal (em vez do usuário logado) para rodar este deploy, ele precisa de role `Contributor` **+** `User Access Administrator` (UAA) no escopo da subscription. Policy Assignment **cria role assignments compensatórios** (para o managed identity da policy ler/auditar recursos), e isso exige `Microsoft.Authorization/roleAssignments/write` — que `Contributor` NÃO tem. UAA tem. Para rodar com o usuário logado em `az login` (caminho desta versão), seu próprio Owner/UAA na sub já cobre.

```bicep
// infra/modules/policy.bicep — somente em prod
// Deploy via: az deployment sub create --location <region> --template-file infra/modules/policy.bicep
targetScope = 'subscription'

@description('Object ID do principal que vai aplicar policy assignments — pode ser SP (`az ad sp show --id <appId> --query id -o tsv`) ou seu user (`az ad signed-in-user show --query id -o tsv`)')
param githubActionsSpObjectId string

@description('RG onde os Policy Assignments aplicam')
param targetRgName string = 'rg-lab-avancado'

// =========================================================================
// STEP 1 — Role grants ao SP do GitHub Actions ANTES de Policy Assignment
// =========================================================================
// Policy Assignment exige 'Microsoft.Authorization/roleAssignments/write' para
// criar role assignments compensatórios (ex.: managed identity da policy lendo
// recursos). Contributor NÃO tem essa permissão. UAA tem.
// Damos os 2 roles ao SP no escopo da subscription:
//   - Contributor: criar/editar policy definitions e assignments
//   - User Access Administrator: criar role assignments compensatórios

// Built-in role IDs (constantes Azure — não mudam)
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var userAccessAdminRoleId = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'

resource contributorAssign 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, githubActionsSpObjectId, contributorRoleId)
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: githubActionsSpObjectId
    principalType: 'ServicePrincipal'
  }
}

resource uaaAssign 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, githubActionsSpObjectId, userAccessAdminRoleId)
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', userAccessAdminRoleId)
    principalId: githubActionsSpObjectId
    principalType: 'ServicePrincipal'
  }
}

// =========================================================================
// STEP 2 — Policy Definitions (criadas na subscription)
// =========================================================================
resource modelAllowlistDef 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'helpsphere-model-allowlist'
  properties: {
    displayName: 'Allow only approved OpenAI models'
    policyType: 'Custom'
    mode: 'All'
    parameters: {
      allowedModels: {
        type: 'Array'
        defaultValue: ['gpt-4.1', 'gpt-4.1-mini', 'text-embedding-3-large']
      }
    }
    policyRule: {
      if: {
        allOf: [
          { field: 'type', equals: 'Microsoft.CognitiveServices/accounts/deployments' }
          { not: { field: 'Microsoft.CognitiveServices/accounts/deployments/model.name', in: '[parameters(\'allowedModels\')]' } }
        ]
      }
      then: { effect: 'deny' }
    }
  }
}

resource regionLockDef 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'helpsphere-region-lock'
  properties: {
    displayName: 'Allow only approved regions for AI'
    policyType: 'Custom'
    mode: 'All'
    parameters: {
      allowedRegions: {
        type: 'Array'
        defaultValue: ['eastus2', 'swedencentral', 'switzerlandnorth']
      }
    }
    policyRule: {
      if: {
        allOf: [
          { field: 'type', equals: 'Microsoft.CognitiveServices/accounts' }
          { field: 'kind', equals: 'OpenAI' }
          { not: { field: 'location', in: '[parameters(\'allowedRegions\')]' } }
        ]
      }
      then: { effect: 'deny' }
    }
  }
}

resource tagRequiredDef 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'helpsphere-cost-center-tag-required'
  properties: {
    displayName: 'Require cost-center tag on AI resources'
    policyType: 'Custom'
    mode: 'Indexed'
    policyRule: {
      if: {
        allOf: [
          { field: 'type', in: ['Microsoft.CognitiveServices/accounts', 'Microsoft.Search/searchServices'] }
          { field: 'tags[\'cost-center\']', exists: 'false' }
        ]
      }
      then: { effect: 'deny' }
    }
  }
}

// =========================================================================
// STEP 3 — Policy Assignments no escopo do RG (depois das role grants)
// =========================================================================
// dependsOn explícito força ordem: role grants COMPLETAM antes de assignments rodarem
var rgScope = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${targetRgName}'

resource modelAllowlistAssign 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'helpsphere-model-allowlist'
  scope: tenantResourceId('Microsoft.Resources/resourceGroups', targetRgName)
  properties: {
    policyDefinitionId: modelAllowlistDef.id
    enforcementMode: 'Default'
  }
  dependsOn: [
    contributorAssign
    uaaAssign
  ]
}

resource regionLockAssign 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'helpsphere-region-lock'
  scope: tenantResourceId('Microsoft.Resources/resourceGroups', targetRgName)
  properties: {
    policyDefinitionId: regionLockDef.id
    enforcementMode: 'Default'
  }
  dependsOn: [
    contributorAssign
    uaaAssign
  ]
}

resource tagRequiredAssign 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'helpsphere-cost-center-tag-required'
  scope: tenantResourceId('Microsoft.Resources/resourceGroups', targetRgName)
  properties: {
    policyDefinitionId: tagRequiredDef.id
    enforcementMode: 'Default'
  }
  dependsOn: [
    contributorAssign
    uaaAssign
  ]
}

output rgScope string = rgScope
```

<!-- screenshot: cap04a-passo2.5-vscode-policy-bicep-target-scope.png -->

> **Atenção ABAC (conta `live.com` Visual Studio Enterprise):** se sua subscription pessoal tem condition ABAC ativada por default (caso comum em VSE pessoal), a tentativa de assignar `User Access Administrator` ao SP **vai falhar silenciosamente** ou retornar `RoleAssignmentExistsButNotEffective`. Nesse caso, **substitua UAA por `Owner` no escopo APENAS do `rg-lab-avancado`** (mais restrito que UAA na subscription inteira):
>
> ```bicep
> // Alternativa para subscriptions com ABAC: Owner no RG do lab apenas
> // (mais restrito do ponto de vista de blast radius)
> var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
>
> resource ownerOnLabRg 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
>   name: guid(targetRgName, githubActionsSpObjectId, ownerRoleId)
>   scope: tenantResourceId('Microsoft.Resources/resourceGroups', targetRgName)
>   properties: {
>     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleId)
>     principalId: githubActionsSpObjectId
>     principalType: 'ServicePrincipal'
>   }
> }
> ```
>
> Aceite que policies sem UAA na subscription terão escopo limitado ao RG do lab — não é production-grade, mas é o que dá pra fazer em conta pessoal restrita. Em sub corporativa (ex.: TFTEC), use o caminho UAA original.

> **Custo:** Azure Policy = **zero** (built-in service). Custo só aparece se policy `audit` gera muitas avaliações que vão para Activity Log → ingest no Log Analytics.

> **Nota pedagógica — por que `dependsOn` explícito em assignments?** Sem `dependsOn`, ARM tenta criar `modelAllowlistAssign` paralelo às role grants. Se assignment roda **antes** da role grant aplicar (ARM eventual consistency), falha com `AuthorizationFailed`. `dependsOn` linearize: role grants completam → assignments começam. Pattern canônico **toda vez que policy/RBAC misturam**.

> **Nota pedagógica — `targetScope = 'subscription'` força deploy command diferente:** templates subscription-scoped exigem `az deployment sub create --location <region>` em vez de `az deployment group create`. Por isso este módulo é **deployado separadamente** do `main.bicep`.

---

## Passo 2.6 — Validação visual (Bicep extension + `az bicep build`)

Antes de fechar este capítulo, faça **validação visual de zero erros** em todos os 5 templates — combine VS Code Bicep extension (lint inline) com `az bicep build` (compilação para ARM JSON).

**1. Estrutura de pastas:**

```powershell
Get-ChildItem -Force infra/, infra/modules/
# Esperado: infra/main.bicep + infra/modules/{apim,content-safety,app-insights,policy}.bicep
# Total: 5 arquivos .bicep (1 main + 4 modules)
```

> **Linux/Mac/WSL:** `ls -la infra/ infra/modules/`

**2. Validação inline VS Code (visual):**

Abra cada um dos 5 arquivos `.bicep` no VS Code. Confirme:

- ❌ **Zero squiggles vermelhos** (errors) em qualquer linha
- ⚠️ Squiggles amarelos (warnings) são aceitáveis se forem `BCP081` (preview API version) — comum em `2023-09-01-preview` do APIM
- ✅ **Outline panel** (Ctrl+Shift+O) mostra symbols `resource`, `param`, `output` corretamente — confirma que o Bicep extension parseou o arquivo inteiro
- ✅ **Hover sobre `module 'modules/x.bicep'`** em `main.bicep` mostra o tipo inferido dos outputs (`apim.outputs.gatewayUrl` deve aparecer como `string`)

<!-- screenshot: cap04a-passo2.6-vscode-bicep-extension-zero-errors.png -->

**3. Compilação para ARM (`az bicep build`):**

```powershell
# Compilar main.bicep (encadeia automaticamente os 3 modules resource-group-scoped)
az bicep build --file infra/main.bicep

# Compilar policy.bicep separado (subscription-scoped)
az bicep build --file infra/modules/policy.bicep

# Listar JSON gerados — esperado: 2 arquivos .json (main.json + modules/policy.json)
Get-ChildItem -Recurse infra/ -Filter *.json
```

**Output esperado:** comando retorna **sem mensagens** (silêncio = sucesso em CLI Azure). Os arquivos `infra/main.json` e `infra/modules/policy.json` aparecem ao lado dos `.bicep`. Se houver erro de sintaxe, `az bicep build` imprime o caminho + linha + mensagem (ex.: `Error BCP033: Expected a value of type "string" but the provided value is of type "int"`).

> **Linux/Mac/WSL:** mesmos comandos, sem mudanças (Azure CLI é cross-platform).

> **Custo:** R$ 0 — `az bicep build` é compilação local.

> **Nota pedagógica — `.json` gerados devem entrar no `.gitignore`?** Sim. O `.bicep` é a fonte da verdade; o `.json` é artefato de build (como `*.pyc`). Adicione `infra/**/*.json` ao `.gitignore` antes de commitar.

---

## Checklist final

```text
[ ] infra/main.bicep criado com 3 module references (appInsights, apim, contentSafety)
[ ] infra/modules/apim.bicep com namedValue + logger + diagnostic + dependsOn explícito
[ ] infra/modules/content-safety.bicep com customSubDomainName e publicNetworkAccess
[ ] infra/modules/app-insights.bicep workspace-based (não classic legacy)
[ ] infra/modules/policy.bicep com targetScope=subscription + 3 definitions + role grants
[ ] Output instrumentationKey wireado de app-insights.bicep para apim.bicep
[ ] Comentário inline em main.bicep explicando por que policy não é instanciado lá
[ ] VS Code Bicep extension não reporta erros (squiggles vermelhos) em nenhum arquivo
[ ] az bicep build infra/main.bicep retorna silêncio (sucesso) e gera infra/main.json
[ ] az bicep build infra/modules/policy.bicep retorna silêncio e gera infra/modules/policy.json
```

> **Nota:** ainda **NÃO commit** este capítulo isolado. Feche o próximo (parameter files + lint) antes de commitar tudo junto.

---

## Surpresas pedagógicas (capturadas em smoke runs)

- ⚠️ **`InvalidTemplate: scope mismatch` em policy.bicep** — você esqueceu de cravar `targetScope = 'subscription'` na primeira linha. Bicep default é `resourceGroup`, e Policy Definitions exigem subscription scope. Workaround: adicione `targetScope = 'subscription'` antes de qualquer `param` ou `resource`.
- ⚠️ **`ResourceNotFound: instrumentation-key` no logger APIM** — você esqueceu o `dependsOn: [namedValueInstrumentationKey]` no recurso logger. ARM tenta criar logger paralelo ao named value e perde a corrida. Workaround: cravar `dependsOn` explícito sempre que recurso A referencia recurso B via expressão dinâmica em string (`{{instrumentation-key}}`), porque Bicep **não** infere essa dependência automaticamente.
- ⚠️ **`SubdomainAlreadyExists` no Content Safety deploy** — `customSubDomainName: 'cs-test'` colide globalmente. Você não percebe na hora porque `az bicep build` passa (validação local não checa Azure). Só falha em `az deployment group create`. Workaround: incluir env no nome (`cs-helpsphere-staging`) e adicionar sufixo random com `uniqueString(resourceGroup().id)` em prod real.
- ⚠️ **Bicep extension VS Code não detecta `WorkspaceResourceId` apontando para workspace inexistente** — `az bicep build` passa, deploy real falha com `LinkedAuthorizationFailed` (mensagem enganosa — parece RBAC, mas é resource-not-found). Workaround: rode `az monitor log-analytics workspace show -g rg-lab-avancado -n log-helpsphere-lab` ANTES de deploy para confirmar.
- ⚠️ **Path relativo de `module` quebra se você mover `main.bicep`** — `module x 'modules/x.bicep'` resolve relativo ao arquivo que **declara** o module, não ao cwd. Se você ter `infra/main.bicep` e mover para `infra/deploy/main.bicep`, o path `'modules/x.bicep'` quebra (busca `infra/deploy/modules/x.bicep`). Workaround: sempre use `'./modules/x.bicep'` (com `./` explícito) para deixar a intenção clara e fácil de refatorar.
- ⚠️ **Output Bicep não declarado retorna `null` no parent sem erro** — se você esquecer `output gatewayUrl string = apim.properties.gatewayUrl` em `apim.bicep`, o `main.bicep` referenciando `apim.outputs.gatewayUrl` **não falha em build** — só retorna `null` no `az deployment group show`. Você descobre quando o capítulo seguinte tenta usar a URL vazia. Workaround: para todo output que parent consome, valide com `az bicep build` + grep no `.json` gerado por `"outputs"`.
- ⚠️ **APIM Developer demora ~30-45 min para provisionar** — não é erro, é o SKU. Provisione com `az deployment group create` rodando em background e use outro terminal para seguir os capítulos seguintes em paralelo.

---

## Próximo capítulo

[04b — Bicep parameters & lint local](./04b-bicep-parameters-lint.md)
