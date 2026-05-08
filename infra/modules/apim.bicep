// =============================================================================
// APIM (API Management) — Developer SKU production-grade
// 1 product (helpsphere-prod) + 1 API (agent-api)
// Policies inbound: rate-limit 100/min + JWT validation + CORS
// =============================================================================
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Location')
param location string

@description('Resource token (deterministico)')
param resourceToken string

@description('APIM SKU')
@allowed(['Developer', 'Consumption'])
param apimSku string

@description('Publisher email (recebe notificacoes)')
param publisherEmail string

@description('Publisher name')
param publisherName string

@description('Tags comuns')
param tags object

@description('Tenant ID para JWT validation policy')
param tenantId string = subscription().tenantId

// -----------------------------------------------------------------------------
// APIM Service
// -----------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: 'apim-helpsphere-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: apimSku
    capacity: apimSku == 'Consumption' ? 0 : 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'None'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
    }
  }
}

// -----------------------------------------------------------------------------
// Product: helpsphere-prod
// -----------------------------------------------------------------------------
resource product 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'helpsphere-prod'
  properties: {
    displayName: 'HelpSphere IA Production'
    description: 'Produto production-grade com rate-limiting + JWT + CORS para agent-api'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// -----------------------------------------------------------------------------
// API: agent-api
// -----------------------------------------------------------------------------
resource agentApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'agent-api'
  properties: {
    displayName: 'HelpSphere Agent API'
    description: 'Foundry Agent endpoint via Function App backend'
    path: 'agent'
    protocols: ['https']
    serviceUrl: 'https://placeholder-function-app.azurewebsites.net'
    subscriptionRequired: true
  }
}

// -----------------------------------------------------------------------------
// Operation: POST /chat
// -----------------------------------------------------------------------------
resource chatOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'chat-completion'
  properties: {
    displayName: 'Chat completion'
    method: 'POST'
    urlTemplate: '/chat'
    request: {
      description: 'Envia mensagem do usuario para o agente Foundry'
    }
    responses: [
      {
        statusCode: 200
        description: 'Resposta do agente'
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Inbound policies: rate-limit + JWT + CORS
// -----------------------------------------------------------------------------
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: agentApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="100" renewal-period="60" />
    <quota calls="10000" renewal-period="86400" />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${tenantId}/.well-known/openid-configuration" />
      <required-claims>
        <claim name="aud" match="any">
          <value>api://helpsphere-prod-agent</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>https://*.azurestaticapps.net</origin>
        <origin>http://localhost:5173</origin>
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
    <set-header name="X-Powered-By" exists-action="delete" />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// -----------------------------------------------------------------------------
// Bind API to Product
// -----------------------------------------------------------------------------
resource productApi 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: product
  name: agentApi.name
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
