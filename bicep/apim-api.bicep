param apimServiceName string
param apiId string
param apiDisplayName string
param apiPath string
param backendUrl string

param operationId string
param operationDisplayName string
param operationMethod string
param operationUrlTemplate string

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimServiceName
}

resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: apiId
  properties: {
    displayName: apiDisplayName
    path: apiPath
    protocols: [ 'https' ]
    serviceUrl: backendUrl
    subscriptionRequired: false
  }
}

resource operation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: operationId
  properties: {
    displayName: operationDisplayName
    method: operationMethod
    urlTemplate: operationUrlTemplate
    responses: [
      { statusCode: 200 }
    ]
  }
}
