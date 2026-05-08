// =============================================================================
// Apex HelpSphere — Lab Avancado D06 (IA Production-grade)
// Entry point: subscription scope
// Cria RG + 4 modules (apim + content-safety + app-insights + policy)
// =============================================================================
targetScope = 'subscription'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Environment name (dev|staging|prod)')
@allowed(['dev', 'staging', 'prod'])
param envName string = 'dev'

@description('Location for all resources')
param location string = 'eastus2'

@description('Resource group name')
param rgName string = 'rg-helpsphere-ia-prod-${envName}'

@description('Resource token for unique naming (4-13 chars deterministico)')
param resourceToken string = take(uniqueString(subscription().id, envName), 6)

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
// Resource Group
// -----------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// -----------------------------------------------------------------------------
// Modules
// -----------------------------------------------------------------------------
module apim 'modules/apim.bicep' = {
  scope: rg
  name: 'apim-${envName}'
  params: {
    location: location
    resourceToken: resourceToken
    apimSku: apimSku
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tags: commonTags
  }
}

module contentSafety 'modules/content-safety.bicep' = {
  scope: rg
  name: 'content-safety-${envName}'
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
  }
}

module appInsights 'modules/app-insights.bicep' = {
  scope: rg
  name: 'app-insights-${envName}'
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
  }
}

module policy 'modules/policy.bicep' = {
  scope: rg
  name: 'policy-${envName}'
  params: {
    rgName: rgName
    location: location
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output rgName string = rg.name
output apimName string = apim.outputs.apimName
output apimGatewayUrl string = apim.outputs.gatewayUrl
output contentSafetyEndpoint string = contentSafety.outputs.endpoint
output contentSafetyName string = contentSafety.outputs.name
output appInsightsConnectionString string = appInsights.outputs.connectionString
output appInsightsName string = appInsights.outputs.name
output budgetThresholdUsd int = budgetAmountUsd
