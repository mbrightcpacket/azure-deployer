@description('Location for the resources.')
param location string = resourceGroup().location

@description('User name for the Virtual Machine.')
param adminUsername string = 'ubuntu'

@allowed([
  'password'
  'sshPublicKey'
])
@description('Type of authentication to use on the Virtual Machine.')
param authenticationType string

@secure()
@description('Password or ssh key for the Virtual Machine.')
param adminPasswordOrKey string

@description('virtualNetwork properties from VirtualNetworkCombo')
param virtualNetwork object

// cClear
@description('cclear VM size')
param cClearVMSize string = 'Standard_D8s_v5'

@description('Number of cClears')
param cClearCount int = 1

@description('cClear VM Name')
param cClearVmName string = 'cclear'

@description('cClear Image URI')
param cClearImage object

@description('cClear Image Version')
param cClearImageURI string

// cVu
@description('cvu VM size')
param cvuVMSize string = 'Standard_D2s_v5'

@description('Number of cVus')
param cvuCount int = 3

@description('cVu Base VM Name')
param cvuVmName string = 'cvu'

@description('cvu Image URI')
param cvuImage object

@description('cvu Image Version')
param cVuImageURI string

@description('cVu 3rd Party Tools')
param cVu3rdPartyToolIPs string

// cStor
@description('cvu VM size')
param cstorVMSize string = 'Standard_D4s_v5'

@description('Number of cStors')
param cstorCount int = 1

@description('cStor VM Name')
param cstorVmName string = 'cstor'

@description('cStor Disk Count')
param cstorDiskCount int = 2

@description('cStor Size Count')
param cstorDiskSize int = 500

@description('cstor Image URI')
param cstorImage object

@description('cstor Image Version')
param cStorImageURI string

@description('tags from TagsByResource')
param tagsByResource object

@description('The name of the function app that you wish to create.')
param appName string = 'fnapp${uniqueString(resourceGroup().id)}'

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for Application Insights')
param appInsightsLocation string = location

@description('The language worker runtime to load in the function app.')
@allowed([
  'node'
  'dotnet'
  'java'
])
param runtime string = 'node'

var cvuv_cloud_init_header = '''
#!/bin/bash
set -ex

boot_config_file="/home/cpacket/boot_config.toml"
capture_nic_ip="$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
capture_nic="eth0"

touch "$boot_config_file"
chmod a+w "$boot_config_file"
cat >"$boot_config_file"  <<BOOTCONFIG
vm_type = "azure"
cvuv_mode = "inline"
cvuv_mirror_eth_0 = "$capture_nic"

'''

var cvuv_cloud_init_footer = '''
BOOTCONFIG
'''

var cvuv_cloud_init_body = '''
cvuv_vxlan_id_0 = 1337
cvuv_vxlan_srcip_0 = "$capture_nic_ip"
cvuv_vxlan_remoteip_0 = "REPLACE_WITH_REMOTE_IP"
'''

var cvuv_cloud_init = '${cvuv_cloud_init_header}${replace(cvuv_cloud_init_body, 'REPLACE_WITH_REMOTE_IP', cVu3rdPartyToolIPs)}${cvuv_cloud_init_footer}'

var functionAppName = appName
var hostingPlanName = appName
var applicationInsightsName = appName
var storageAccountName = '${uniqueString(resourceGroup().id)}azfunctions'
var functionWorkerRuntime = runtime

var cvulbName = '${cvuVmName}_iLB'
var cstorlbName = '${cstorVmName}_iLB'

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}

var cclear_enabled = cClearCount > 0 ? true : false
var cvu_enabled = cvuCount > 0 ? true : false
var cstor_enabled = cstorCount > 0 ? true : false

var cstorilb_enabled = cstorCount > 1 ? true : false
var cvuilb_enabled = cvuCount > 1 ? true : false

var monsubnetId = virtualNetwork.newOrExisting == 'new' ? monsubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.monSubnet.name)

var cclearImageURI = empty(cClearImageURI) ? cClearImage.id : cClearImageURI
var cstorImageURI = empty(cStorImageURI) ? cstorImage.id : cStorImageURI
var cvuImageURI = empty(cVuImageURI) ? cvuImage.id : cVuImageURI

resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: virtualNetwork.addressPrefixes
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Network/virtualNetworks') ? tagsByResource['Microsoft.Network/virtualNetworks'] : null
}

resource monsubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.subnets.monSubnet.name
  parent: vnet
  properties: {
    addressPrefix: virtualNetwork.subnets.monSubnet.addressPrefix
  }
}

/*
  cClear Section
*/

resource cclearnic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cClearCount): if (cclear_enabled) {
  name: '${cClearVmName}-${i}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cClearVmName}-${i}-ipconfig-nic'
        properties: {
          subnet: {
            id: monsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cclearvm 'Microsoft.Compute/virtualMachines@2021-03-01' = [for i in range(0, cClearCount): if (cclear_enabled) {
  name: '${cClearVmName}-${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: cClearVMSize
    }
    storageProfile: {
      imageReference: {
        id: cclearImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      dataDisks: [
        {
          name: '${cClearVmName}-${i}-DataDisk1'
          lun: 1
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
          deleteOption: 'Delete'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cclearnic[i].id
        }
      ]
    }
    osProfile: {
      computerName: '${cClearVmName}-${i}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
      customData: loadFileAsBase64('./cclearv-cloud-init.sh')
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}]

/*
  cStor Section
*/

resource cstorcapturenic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cstorCount): if (cstor_enabled) {
  name: '${cstorVmName}-${i}-capture-nic'
  location: location
  dependsOn: any(cstorilb_enabled) ? [
    cstorlb01
  ] : []
  properties: {
    ipConfigurations: [
      {
        name: '${cstorVmName}-${i}-capture-ipconfig-nic'
        properties: {
          subnet: {
            id: monsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: any(cstorilb_enabled) ? [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cstorlbName, '${cstorlbName}-backend')
            }
          ] : []
        }
      }
    ]
    enableAcceleratedNetworking: true
    enableIPForwarding: true
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cstorvm 'Microsoft.Compute/virtualMachines@2021-03-01' = [for i in range(0, cstorCount): if (cstor_enabled) {
  name: '${cstorVmName}-${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: cstorVMSize
    }
    storageProfile: {
      imageReference: {
        id: cstorImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      dataDisks: [for j in range(0, cstorDiskCount): {
        name: '${cstorVmName}-${i}-DataDisk-${j}'
        lun: j
        createOption: 'Empty'
        diskSizeGB: cstorDiskSize
        caching: 'ReadWrite'
        //TODO: Make the delete option portal selectable  
        deleteOption: 'Delete'
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cstorcapturenic[i].id
          properties: {
            primary: true
          }
        }
      ]
    }
    osProfile: {
      computerName: '${cstorVmName}-${i}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
      customData: loadFileAsBase64('./cstorv-cloud-init.sh')
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}]

resource cvucapturenic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cvuCount): if (cvu_enabled) {
  name: '${cvuVmName}-${i}-capture-nic'
  location: location
  dependsOn: any(cvuilb_enabled) ? [
    cvulb01
  ] : []
  properties: {
    ipConfigurations: [
      {
        name: '${cvuVmName}-${i}-capture-ipconfig-nic'
        properties: {
          subnet: {
            id: monsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: any(cvuilb_enabled) ? [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cvulbName, '${cvulbName}-backend')
            }
          ] : []
        }
      }
    ]
    enableAcceleratedNetworking: true
    enableIPForwarding: true
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cvuvm 'Microsoft.Compute/virtualMachines@2021-03-01' = [for i in range(0, cvuCount): if (cvu_enabled) {
  name: '${cvuVmName}-${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: cvuVMSize
    }
    storageProfile: {
      imageReference: {
        id: cvuImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cvucapturenic[i].id
          properties: {
            primary: false
          }
        }
      ]
    }
    osProfile: {
      computerName: '${cvuVmName}-${i}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
      customData: base64(cvuv_cloud_init)
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}]

resource cvulb01 'Microsoft.Network/loadBalancers@2021-03-01' = if (cvuilb_enabled) {
  name: cvulbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: '${cvulbName}-frontend'
        properties: {
          subnet: {
            id: monsubnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${cvulbName}-backend'
      }
    ]
    loadBalancingRules: [
      {
        name: '${cvulbName}-to_server'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', cvulbName, '${cvulbName}-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cvulbName, '${cvulbName}-backend')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', cvulbName, '${cvulbName}-probe')
          }
          frontendPort: 0
          backendPort: 0
          protocol: 'All'
        }
      }
    ]
    probes: [
      {
        name: '${cvulbName}-probe'
        properties: {
          protocol: 'Tcp'
          port: 22
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/loadBalancers') ? tagsByResource['Microsoft.Network/loadBalancers'] : null
}

resource cstorlb01 'Microsoft.Network/loadBalancers@2021-03-01' = if (cstorilb_enabled) {
  name: cstorlbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: '${cstorlbName}-frontend'
        properties: {
          subnet: {
            id: monsubnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${cstorlbName}-backend'
      }
    ]
    loadBalancingRules: [
      {
        name: '${cstorlbName}-to_server'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', cstorlbName, '${cstorlbName}-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cstorlbName, '${cstorlbName}-backend')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', cstorlbName, '${cstorlbName}-probe')
          }
          frontendPort: 0
          backendPort: 0
          protocol: 'All'
        }
      }
    ]
    probes: [
      {
        name: '${cstorlbName}-probe'
        properties: {
          protocol: 'Tcp'
          port: 22
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/loadBalancers') ? tagsByResource['Microsoft.Network/loadBalancers'] : null
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: appInsightsLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

output To_Finish_Provisioning string = cclear_enabled ? 'ssh ${adminUsername}@${cclearnic[0].properties.ipConfigurations[0].properties.privateIPAddress}' : 'No cClear is Deployed. There is no action to take.'
output Copy_This_and_Paste_Into_ssh_Prompt string = cclear_enabled ? 'until [ -x /opt/cloud/deployer.py ]; do echo "still deploying, please wait..."; sleep 5; done; /opt/cloud/deployer.py' : 'No cClear is Deployed. There is no action to take.'
output cclear_ip string = cclear_enabled ? cclearnic[0].properties.ipConfigurations[0].properties.privateIPAddress : ''

output cvu_ilb_frontend_ip string = cvuilb_enabled ? cvulb01.properties.frontendIPConfigurations[0].properties.privateIPAddress : ''
output cvu_provisioning array = [for i in range(0, cvuCount): cvu_enabled ? {
  index: i
  name: cvuvm[i].name
  nic_name: cvucapturenic[i].name
  private_ip: cvucapturenic[i].properties.ipConfigurations[0].properties.privateIPAddress
} : []]
output cvu_3rd_party_tools string = cVu3rdPartyToolIPs

output cstor_ilb_frontend_ip string = cstorilb_enabled ? cstorlb01.properties.frontendIPConfigurations[0].properties.privateIPAddress : ''
output cstor_provisioning array = [for i in range(0, cstorCount): cstor_enabled ? {
  index: i
  name: cstorvm[i].name
  nic_name: cstorcapturenic[i].name
  private_ip: cstorcapturenic[i].properties.ipConfigurations[0].properties.privateIPAddress
} : []]
