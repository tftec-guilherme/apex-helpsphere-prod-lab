// =============================================================================
// Apex HelpSphere — Lab Avancado D06 (IA Production-grade)
// Entry point: resourceGroup scope
// Deploya 4 modules (apim + content-safety + app-insights + policy) DENTRO de
// um Resource Group EXISTENTE (criado manualmente no docs/02 — rg-lab-avancado).
//
// Deploy:
//   az deployment group create \
//     -g rg-lab-avancado \
//     -f infra/main.bicep \
//     -p @infra/envs/dev.parameters.json
// =============================================================================
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Environment name (dev|staging|prod)')
@allowed(['dev', 'staging', 'prod'])
param envName string = 'dev'

@description('Resource token for unique naming (4-13 chars deterministico)')
param resourceToken string = take(uniqueString(resourceGroup().id, envName), 6)

@description('APIM SKU — Developer (R$ 250/mes ligado) or Consumption (pay-per-call)')
@allowed(['Developer', 'Consumption'])
param apimSku string = 'Developer'

@description('APIM publisher email (obrigatorio — recebe notificacoes)')
param apimPublisherEmail string

@description('APIM publisher name')
param apimPublisherName string = 'Apex HelpSphere IA'

@description('Cost Management Budget threshold em USD/mes')
param budgetAmountUsd int = 100

@description('Tags aplicados em todos os recursos')
param commonTags object = {
  'cost-center': 'apex-helpsphere-ia'
  environment: envName
  application: 'helpsphere-ia-prod'
  'managed-by': 'bicep'
  lab: 'd06-avancado'
}

// -----------------------------------------------------------------------------
// Modules (deployam DENTRO do RG pre-existente)
// -----------------------------------------------------------------------------
module apim 'modules/apim.bicep' = {
  name: 'apim-${envName}'
  params: {
    location: resourceGroup().location
    resourceToken: resourceToken
    apimSku: apimSku
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tags: commonTags
  }
}

module contentSafety 'modules/content-safety.bicep' = {
  name: 'content-safety-${envName}'
  params: {
    location: resourceGroup().location
    resourceToken: resourceToken
    tags: commonTags
  }
}

module appInsights 'modules/app-insights.bicep' = {
  name: 'app-insights-${envName}'
  params: {
    location: resourceGroup().location
    resourceToken: resourceToken
    tags: commonTags
  }
}

module policy 'modules/policy.bicep' = {
  name: 'policy-${envName}'
  params: {
    rgName: resourceGroup().name
    location: resourceGroup().location
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output rgName string = resourceGroup().name
output apimName string = apim.outputs.apimName
output apimGatewayUrl string = apim.outputs.gatewayUrl
output contentSafetyEndpoint string = contentSafety.outputs.endpoint
output contentSafetyName string = contentSafety.outputs.name
output appInsightsConnectionString string = appInsights.outputs.connectionString
output appInsightsName string = appInsights.outputs.name
output budgetThresholdUsd int = budgetAmountUsd
