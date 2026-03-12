metadata description = 'Overlapping Address Spaces Test - No Private Link'
metadata author = 'Azure'

@description('Deployment mode: provider or consumer')
param mode string = 'provider'

@description('Azure region')
param location string = 'eastus'

@description('SSH public key')
@secure()
param sshPublicKey string

var vmName = 'VM-Provider'
var vnetName = mode == 'provider' ? 'ProviderVNet' : 'ConsumerVNet'
var subnetName = 'default'
var nicName = '${vmName}-NIC'
var nsgName = '${mode}-NSG'

// Both use same address space to test overlap
var addressSpace = '10.0.0.0/16'
var subnetPrefix = '10.0.1.0/24'

// ============================================================================
// NETWORK SECURITY GROUP
// ============================================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowInternal'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '10.0.0.0/8'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ============================================================================
// VIRTUAL NETWORK
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// NETWORK INTERFACE
// ============================================================================

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

// ============================================================================
// VIRTUAL MACHINE
// ============================================================================

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// ============================================================================
// NGINX INSTALLATION (PROVIDER ONLY)
// ============================================================================

resource nginxExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (mode == 'provider') {
  parent: vm
  name: 'InstallNginx'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl start nginx && sudo systemctl enable nginx && echo "<h1>Welcome to $(hostname)</h1>" > /var/www/html/index.html'
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output mode string = mode
output vnetId string = vnet.id
output vnetName string = vnet.name
output vnetAddressSpace string = addressSpace
output subnetId string = '${vnet.id}/subnets/${subnetName}'
output subnetPrefix string = subnetPrefix
output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
output nicPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output nginxInstalled bool = mode == 'provider' ? true : false
output nginxUrl string = mode == 'provider' ? 'http://${nic.properties.ipConfigurations[0].properties.privateIPAddress}' : ''
