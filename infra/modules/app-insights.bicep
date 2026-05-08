// =============================================================================
// Application Insights — workspace-based (Log Analytics)
// Custom metrics LLM dimensions: model, tokens_input, tokens_output,
// latency_ms, content_safety_blocked
// =============================================================================
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Location')
param location string

@description('Resource token (deterministico)')
param resourceToken string

@description('Tags comuns')
param tags object

@description('Log Analytics retention em dias (30 = free tier)')
@minValue(30)
@maxValue(730)
param retentionDays int = 30

@description('Daily cap em GB (controle de custo)')
param dailyCapGb int = 1

// -----------------------------------------------------------------------------
// Log Analytics Workspace
// -----------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-helpsphere-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    workspaceCapping: {
      dailyQuotaGb: dailyCapGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// -----------------------------------------------------------------------------
// Application Insights (workspace-based)
// -----------------------------------------------------------------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-helpsphere-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    SamplingPercentage: 100
  }
}

// -----------------------------------------------------------------------------
// Custom metric definitions documentation (logical reference)
// Cravado no codigo Function App via OpenTelemetry / azure-monitor-opentelemetry
// Dimensions emitidas:
//   - model (gpt-4.1-mini, gpt-4.1, etc)
//   - tokens_input (int)
//   - tokens_output (int)
//   - latency_ms (int)
//   - content_safety_blocked (boolean — true se input/output filter rejeitou)
//   - tenant_id (multi-tenant tracking)
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output connectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey
output name string = appInsights.name
output workspaceId string = logAnalytics.id
output workspaceName string = logAnalytics.name
