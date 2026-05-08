// =============================================================================
// Content Safety — F0 free tier
// Filtro input + output do agente Foundry
// Managed Identity binding para Function App acessar later
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

@description('SKU — F0 (free) ou S0 (standard pay-per-call)')
@allowed(['F0', 'S0'])
param sku string = 'F0'

// -----------------------------------------------------------------------------
// Content Safety account
// -----------------------------------------------------------------------------
resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'cs-helpsphere-${resourceToken}'
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    customSubDomainName: 'cs-helpsphere-${resourceToken}'
    disableLocalAuth: false
    restore: false
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output endpoint string = contentSafety.properties.endpoint
output name string = contentSafety.name
output principalId string = contentSafety.identity.principalId
output id string = contentSafety.id
