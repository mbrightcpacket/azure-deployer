@description('Location for the resources.')
param location string

@description('User name for the Virtual Machine.')
param adminUsername string

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

@description('default values for cclear VM')
param VMSizeSettings object = {
  cclear: 'Standard_D4s_v3'
  cvu: 'Standard_D4s_v3'
  cstor: 'Standard_D4s_v3'
}

// cClear

@description('cClear VM Name')
param cClearVmName string

@description('cClear Image URI')
param cClearImage object

@description('cClear Image Version')
param cClearVersion string = ''

// cVu

@description('Number of cVus')
param cvuCount int = 3

@description('cVu Base VM Name')
param cvuVmName string

@description('cvu Image URI')
param cvuImage object

@description('cvu Image Version')
param cvuVersion string = ''

// cStor

@description('Number of cStors')
param cstorCount int = 1

@description('cStor VM Name')
param cstorVmName string

@description('cstor Image URI')
param cstorImage object

@description('cstor Image Version')
param cstorVersion string = ''

@description('tags from TagsByResource')
param tagsByResource object

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

var mgmtsubnetId = virtualNetwork.newOrExisting == 'new' ? mgmtsubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.mgmtSubnet.name)
var monsubnetId = virtualNetwork.newOrExisting == 'new' ? monsubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.monSubnet.name)
var cstorsubnetId = virtualNetwork.newOrExisting == 'new' ? cstorsubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.cstorSubnet.name)

var cclearImageURI = empty(cClearVersion) ? cClearImage.id : '${cClearImage.id}/versions/${cClearVersion}'
var cstorImageURI = empty(cstorVersion) ? cstorImage.id : '${cstorImage.id}/versions/${cstorVersion}'
var cvuImageURI = empty(cvuVersion) ? cvuImage.id : '${cvuImage.id}/versions/${cvuVersion}'

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

resource mgmtsubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.subnets.mgmtSubnet.name
  parent: vnet
  properties: {
    addressPrefix: virtualNetwork.subnets.mgmtSubnet.addressPrefix
  }
}

resource monsubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.subnets.monSubnet.name
  parent: vnet
  properties: {
    addressPrefix: virtualNetwork.subnets.monSubnet.addressPrefix
  }
}

resource cstorsubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.subnets.cstorSubnet.name
  parent: vnet
  properties: {
    addressPrefix: virtualNetwork.subnets.cstorSubnet.addressPrefix
  }
}

/*
  cClear Section
*/

resource cclearnic01 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: '${cClearVmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cClearVmName}-ipconfig-nic'
        properties: {
          subnet: {
            id: mgmtsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}

resource cclearvm01 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: cClearVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: VMSizeSettings.cclear
    }
    storageProfile: {
      imageReference: {
        id: cclearImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
      }
      dataDisks: [
        {
          name: '${cClearVmName}-DataDisk1'
          lun: 1
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cclearnic01.id
        }
      ]
    }
    osProfile: {
      computerName: cClearVmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}

/*
  cStor Section
*/

resource cstorcapturenic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cstorCount): {
  name: '${cstorVmName}-${i}-capture-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cstorVmName}-${i}-capture-ipconfig-nic'
        properties: {
          subnet: {
            id: cstorsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cstorlbName, '${cstorlbName}-backend')
            }
          ]
        }
      }
    ]
    enableAcceleratedNetworking: true
    enableIPForwarding: true
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cstormgmtnic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cstorCount): {
  name: '${cstorVmName}-${i}-mgmt-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cstorVmName}-${i}-mgmt-ipconfig-nic'
        properties: {
          subnet: {
            id: mgmtsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cstorvm 'Microsoft.Compute/virtualMachines@2021-03-01' = [for i in range(0, cstorCount): {
  name: '${cstorVmName}-${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: VMSizeSettings.cstor
    }
    storageProfile: {
      imageReference: {
        id: cstorImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
      }
      dataDisks: [
        {
          name: '${cstorVmName}-${i}-DataDisk0'
          lun: 0
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
        }
        {
          name: '${cstorVmName}-${i}-DataDisk1'
          lun: 1
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cstorcapturenic[i].id
          properties: {
            primary: true
          }
        }
        {
          id: cstormgmtnic[i].id
          properties: {
            primary: false
          }
        }
      ]
    }
    osProfile: {
      computerName: cstorVmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
      customData: loadFileAsBase64('./userdata-cstor.bash')
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}]

resource cvucapturenic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cvuCount): {
  name: '${cvuVmName}-${i}-capture-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cvuVmName}-${i}-capture-ipconfig-nic'
        properties: {
          subnet: {
            id: monsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', cstorlbName, '${cstorlbName}-backend')
            }
          ]
        }
      }
    ]
    enableAcceleratedNetworking: true
    enableIPForwarding: true
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cvumgmtnic 'Microsoft.Network/networkInterfaces@2020-11-01' = [for i in range(0, cvuCount): {
  name: '${cvuVmName}-${i}-mgmt-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cvuVmName}-${i}-mgmt-ipconfig-nic'
        properties: {
          subnet: {
            id: mgmtsubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  tags: contains(tagsByResource, 'Microsoft.Network/networkInterfaces') ? tagsByResource['Microsoft.Network/networkInterfaces'] : null
}]

resource cvuvm 'Microsoft.Compute/virtualMachines@2021-03-01' = [for i in range(0, cvuCount): {
  name: '${cvuVmName}-${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: VMSizeSettings.cvu
    }
    storageProfile: {
      imageReference: {
        id: cvuImageURI
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
      }
      dataDisks: [
        {
          name: '${cvuVmName}-${i}-DataDisk0'
          lun: 0
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
        }
        {
          name: '${cvuVmName}-${i}-DataDisk1'
          lun: 1
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cvucapturenic[i].id
          properties: {
            primary: true
          }
        }
        {
          id: cvumgmtnic[i].id
          properties: {
            primary: false
          }
        }
      ]
    }
    osProfile: {
      computerName: '${cvuVmName}-${cvuCount}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: any(authenticationType == 'password' ? null : linuxConfiguration) // TODO: workaround for https://github.com/Azure/bicep/issues/449
      customData: loadFileAsBase64('./userdata-cvu.bash')
    }
  }
  tags: contains(tagsByResource, 'Microsoft.Compute/virtualMachines') ? tagsByResource['Microsoft.Compute/virtualMachines'] : null
}]

resource cvulb01 'Microsoft.Network/loadBalancers@2021-03-01' = {
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

resource cstorlb01 'Microsoft.Network/loadBalancers@2021-03-01' = {
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
            id: cstorsubnetId
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
