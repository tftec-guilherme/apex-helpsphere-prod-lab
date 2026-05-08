// =============================================================================
// Azure Policy — 3 assignments defensivos
// 1. Allowed locations (East US 2 only)
// 2. Required tags (cost-center + environment + application)
// 3. Cosmos DB Public Access denied
// =============================================================================
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
@description('Resource Group name (escopo dos assignments)')
param rgName string

@description('Location permitido (single)')
param location string = 'eastus2'

// -----------------------------------------------------------------------------
// Built-in Policy Definition IDs (Azure)
// -----------------------------------------------------------------------------
var allowedLocationsPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
// "Allowed locations"

var requireTagPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
// "Require a tag on resources"

var cosmosDenyPublicAccessPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/797b37f7-06b8-444c-b1ad-fc62867f335a'
// "Azure Cosmos DB should disable public network access"

// -----------------------------------------------------------------------------
// Assignment 1: Allowed locations (East US 2 only)
// -----------------------------------------------------------------------------
resource allowedLocations 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'allowed-locations-${uniqueString(rgName)}'
  properties: {
    displayName: 'Allowed locations — ${location} only'
    description: 'Restringe deployments para apenas ${location} no RG ${rgName}'
    policyDefinitionId: allowedLocationsPolicyId
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: [location]
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Assignment 2: Require cost-center tag
// -----------------------------------------------------------------------------
resource requireCostCenterTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'require-cost-center-${uniqueString(rgName)}'
  properties: {
    displayName: 'Require cost-center tag'
    description: 'Exige tag cost-center em todos os recursos do RG ${rgName}'
    policyDefinitionId: requireTagPolicyId
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: 'cost-center'
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Assignment 3: Cosmos DB public access denied (defensivo)
// -----------------------------------------------------------------------------
resource cosmosDenyPublic 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'cosmos-deny-public-${uniqueString(rgName)}'
  properties: {
    displayName: 'Cosmos DB — disable public network access'
    description: 'Bloqueia Cosmos DB com public network access habilitado'
    policyDefinitionId: cosmosDenyPublicAccessPolicyId
    enforcementMode: 'Default'
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output assignments array = [
  allowedLocations.name
  requireCostCenterTag.name
  cosmosDenyPublic.name
]
