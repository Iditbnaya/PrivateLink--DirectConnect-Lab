# Quick Reference Guide - PLS Direct Connect Lab

## Scenario Overview

This lab has **TWO deployment scenarios**:

### Scenario 1: Overlapping IPs with Nginx VM (Primary)
**Script**: `overlapp-direct-connect-solution.ps1`
- Fully automated, zero parameters required
- Duration: 15-20 minutes
- Creates: Provider RG + Consumer RG with overlapping VNets

### Scenario 2: Application Gateway with Direct Connect (Optional)
**Script**: `AppGw-to-DirectConnect.ps1`
- Manual deployment with parameters required
- Duration: 15-20 minutes
- Creates: App Gateway infrastructure only (reuses Provider VNet)

---

## Scenario 1: Deployment

### Quick Deploy (Fully Automated)
```powershell
# Run from the script directory
# Deploy with all defaults (east us, auto-generated RG names)
.\overlapp-direct-connect-solution.ps1
```

### Deploy with Custom Location
```powershell
.\overlapp-direct-connect-solution.ps1 -Location "eastus"
```

---

## Scenario 2: Deployment (Optional)

### Prerequisites
- Scenario 1 must be deployed first
- Find your deployed Resource Group name (has random GUID suffix)

### Find Deployed Resources
```powershell
# Find the Provider RG with GUID suffix
$rg = az group list --query "[?contains(name, 'DirectConnect-Provider-RG')].name" -o tsv | Select-Object -First 1
Write-Host "Provider RG: $rg"

# List VMs in that RG
az vm list -g $rg --query "[].name" -o tsv
```

### Deploy App Gateway
```powershell
# Basic deployment (with discovered RG and VM names)
.\AppGw-to-DirectConnect.ps1 `
    -ProviderRG "Resource group Name" ` #replace with your RG name
    -BackendVMName "VM-Provider" #replace with your VM name if changed

# With custom backend port
.\AppGw-to-DirectConnect.ps1 `
    -ProviderRG "DirectConnect-Provider-RG-da00bd55" ` #replace with your RG name
    -BackendVMName "VM-Provider" ` #replace with your VM name if changed `
    -BackendPort 8080
---

## Scenario 1: Resource Discovery

### Find Resource Groups (Scenario 1)
```powershell
# List all DirectConnect-related RGs
az group list --query "[?contains(name, 'DirectConnect')].name" -o tsv

# Get latest Provider RG (most recent with GUID)
$providerRG = az group list --query "[?contains(name, 'DirectConnect-Provider-RG')].name" -o tsv | Select-Object -First 1

# Get latest Consumer RG (most recent with GUID)
$consumerRG = az group list --query "[?contains(name, 'DirectConnect-Consumer-RG')].name" -o tsv | Select-Object -First 1
```

### Get VNet Details
```powershell
# Provider VNet info
az network vnet show -g $providerRG -n "ProviderVNet" -o table

# Consumer VNet info
az network vnet show -g $consumerRG -n "ConsumerVNet" -o table

# List all subnets in Provider VNet
az network vnet subnet list -g $providerRG --vnet-name "ProviderVNet" -o table
```

### Get VM Information
```powershell
# Get Provider VM details
az vm show -g $providerRG -n "VM-Provider" -d -o json

# Get Provider VM public IP
$vmIP = az vm show -d -g $providerRG -n "VM-Provider" --query publicIps -o tsv
Write-Host "VM Public IP: $vmIP"

# Get Provider VM private IP
az vm show --ids $(az vm list -g $providerRG --query "[0].id" -o tsv) `
  --query "hardwareProfile, osProfile.computerName, networkProfile.networkInterfaces[0]" -o json
```

### Get Network Interface Details
```powershell
# List all NICs in Provider RG
az network nic list -g $providerRG -o table

# Get specific NIC details (Nginx VM NIC)
$vmId = az vm list -g $providerRG --query "[0].id" -o tsv
$nicId = az vm show --ids $vmId --query "networkProfile.networkInterfaces[0].id" -o tsv
az network nic show --ids $nicId -o json

# Get NIC private IP
az network nic show --ids $nicId --query "ipConfigurations[0].properties.privateIpAddress" -o tsv
```

### Get Private Link Service
```powershell
# List Private Link Services
az network private-link-service list -g $providerRG -o table

# Get PLS details
az network private-link-service show -g $providerRG -n "pls-direct-connect" -o json

# Check if Direct Connect is enabled
az network private-link-service show -g $providerRG -n "pls-direct-connect" `
  --query "properties.directConnectEnabled"
```

### Get Private Endpoints
```powershell
# List Private Endpoints
az network private-endpoint list -g $consumerRG -o table

# Get endpoint connection status
az network private-endpoint show -g $consumerRG -n "ConsumerEndpoint" `
  --query "properties.privateLinkServiceConnections[0].properties.connectionState"
```

---

## Testing & Verification

### Scenario 1: Test Nginx Connectivity
```powershell
# Get Consumer VM IP
$consumerVMIP = az vm show -d -g $consumerRG -n "VM-Consumer" --query publicIps -o tsv

# SSH to Consumer VM
ssh azureuser@$consumerVMIP

# From inside Consumer VM, test Nginx (overlapping IPs - both 10.0.1.x)
curl http://10.0.1.5
# Should return: <h1>Welcome to VM-Provider</h1>

# Or get exact Nginx VM IP
curl http://10.0.1.4
```

### Scenario 2: Test App Gateway
```powershell
# Get App Gateway details
$rg = "DirectConnect-Provider-RG-6cd49640"  # Use actual RG from deployment
az network application-gateway show -g $rg -n "appgw-provider" -o json

# Get App Gateway private frontend IP
az network application-gateway frontend-ip list -g $rg --gateway-name "appgw-provider" -o table
```

---

## Direct Connect Verification

### Check Direct Connect Status
```powershell
az network private-link-service show -g $providerRG -n "pls-direct-connect" `
  --query "properties.directConnectEnabled"
# Expected output: true
```

### Verify Network Isolation (Scenario 2)
```powershell
# Check if NSP is disabled on App Gateway (should be null)
az network application-gateway show -g $rg -n "appgw-provider" `
  --query "properties.networkSecurityPerimeter"
# Expected output: null (disabled)
```

### Check Connection States
```powershell
# Provider-side: PLS
az network private-link-service show -g $providerRG -n "pls-direct-connect" `
  --query "properties.provisioningState"

# Consumer-side: Private Endpoint
az network private-endpoint show -g $consumerRG -n "ConsumerEndpoint" `
  --query "properties.privateLinkServiceConnections[0].properties.provisioningState"

# Connection state
az network private-endpoint show -g $consumerRG -n "ConsumerEndpoint" `
  --query "properties.privateLinkServiceConnections[0].properties.connectionState.status"
```

---

## Network Security Groups

### View Provider NSG Rules
```powershell
az network nsg rule list -g $providerRG --nsg-name "provider-nsg" -o table
```

### View Consumer NSG Rules
```powershell
az network nsg rule list -g $consumerRG --nsg-name "consumer-nsg" -o table
```

### Add SSH Rule to Provider
```powershell
az network nsg rule create `
  -g $providerRG `
  --nsg-name "provider-nsg" `
  -n AllowSSHfromIP `
  --priority 100 `
  --direction Inbound `
  --access Allow `
  --protocol Tcp `
  --source-address-prefixes "<YOUR_IP>/32" `
  --source-port-ranges '*' `
  --destination-port-ranges 22
```

---

## VM Management

### SSH to Provider VM (Scenario 1)
```powershell
# Get public IP
$vmIP = az vm show -d -g $providerRG -n "VM-Provider" --query publicIps -o tsv

# SSH in
ssh azureuser@$vmIP

# Inside Provider VM - verify Nginx
curl http://localhost
```

### SSH to Consumer VM (Scenario 1)
```powershell
# Get public IP
$vmIP = az vm show -d -g $consumerRG -n "VM-Consumer" --query publicIps -o tsv

# SSH in
ssh azureuser@$vmIP

# Inside Consumer VM - test connectivity to Provider (overlapping IPs)
curl http://10.0.1.4
```

### VM Operations
```powershell
# Start VM
az vm start -g $providerRG -n "VM-Provider"

# Stop VM (deallocate to save costs)
az vm deallocate -g $providerRG -n "VM-Provider"

# Restart VM
az vm restart -g $providerRG -n "VM-Provider"

# Get VM details
az vm show -g $providerRG -n "VM-Provider" -d -o json
```

---

## Cleanup

### Delete Specific Scenario 1 Resources
```powershell
# Delete only the resources
# Note: You'll need to use the actual RG names with GUIDs

# Delete Consumer RG
az group delete -g $consumerRG --yes --no-wait

# Delete Provider RG
az group delete -g $providerRG --yes --no-wait

# Check deletion status
az group list --query "[?contains(name, 'DirectConnect')].name" -o tsv
```

### Delete Scenario 2 App Gateway (keeps other resources)
```powershell
$rg = "DirectConnect-Provider-RG-6cd49640"  # Use actual RG

# Delete App Gateway
az network application-gateway delete -g $rg -n "appgw-provider" --yes --no-wait

# Delete App Gateway subnets
az network vnet subnet delete -g $rg --vnet-name "ProviderVNet" -n "appgw-subnet" --yes
az network vnet subnet delete -g $rg --vnet-name "ProviderVNet" -n "pls-nat-subnet" --yes

# Delete public IP
az network public-ip delete -g $rg -n "appgw-pip" --yes
```

### Delete All Resources
```powershell
# Find all DirectConnect RGs
$rgs = az group list --query "[?contains(name, 'DirectConnect')].name" -o tsv

# Delete all
foreach ($rg in $rgs) {
    Write-Host "Deleting $rg..."
    az group delete -g $rg --yes --no-wait
}

# Verify deletion
az group list --query "[?contains(name, 'DirectConnect')].name" -o tsv
```

---

## Troubleshooting

### Connection Issues
```powershell
# Check Private Endpoint connection state
az network private-endpoint show -g $consumerRG -n "ConsumerEndpoint" `
  --query "properties.privateLinkServiceConnections[0]" -o json

# Check NSG rules on Consumer subnet
az network nsg rule list -g $consumerRG --nsg-name "consumer-nsg" -o table

# Check subnet policies
az network vnet subnet show -g $consumerRG --vnet-name "ConsumerVNet" -n "default" `
  --query "properties.{PrivateEndpointNetworkPolicies, PrivateLinkServiceNetworkPolicies}"
```

### SSH Issues
```powershell
# Verify SSH rule exists
az network nsg rule show -g $providerRG --nsg-name "provider-nsg" -n "AllowSSH"

# Check public IP is assigned
az vm show -d -g $providerRG -n "VM-Provider" --query "{Name:name, PublicIP:publicIps}"

# Get latest deployment error
az deployment group list -g $providerRG --query "[-1].properties.outputs" -o json
```

### Direct Connect Not Enabled
```powershell
# Check feature registration
az feature show --namespace Microsoft.Network --name DLCDirectConnectFeature

# Register if needed
az feature register --namespace Microsoft.Network --name DLCDirectConnectFeature

# Refresh provider
az provider register --namespace Microsoft.Network
```

### App Gateway Network Isolation Error (Scenario 2)
```powershell
# If deployment fails with NetworkIsolation error:
# The AppGw-to-DirectConnect.ps1 script handles this automatically
# But if manual fix needed:

$rg = "DirectConnect-Provider-RG-6cd49640"
$appGWName = "appgw-provider"

# Get current status
az network application-gateway show -g $rg -n $appGWName `
  --query "properties.networkSecurityPerimeter"
```

---

## Useful Queries

### Get All Resource IDs
```powershell
az resource list -g $providerRG --query "[].id" -o tsv
```

### Get All IP Addresses
```powershell
# All private IPs
az network nic list -g $providerRG --query "[].ipConfigurations[].properties.privateIPAddress" -o tsv

# All public IPs
az network public-ip list -g $providerRG --query "[].ipAddress" -o tsv
```

### Export Resource Template
```powershell
az group export -n $providerRG -o json > exported-provider-template.json
az group export -n $consumerRG -o json > exported-consumer-template.json
```

### Get Deployment Operations
```powershell
# List all deployment operations
az deployment group operation list -g $providerRG --query "[].{Name:name, Status:properties.provisioningState}"
```

---

## Quick Deployment Checklist

### For Scenario 1:
- [ ] SSH key exists: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa`
- [ ] Run: `.\overlapp-direct-connect-solution.ps1`
- [ ] Wait 15-20 minutes
- [ ] Test: `curl http://10.0.1.4` from Consumer VM
- [ ] Verify: `az network private-link-service show ... --query directConnectEnabled`

### For Scenario 2:
- [ ] Scenario 1 deployed successfully
- [ ] Find your Provider RG name with GUID
- [ ] Find VM name in that RG
- [ ] Run: `.\AppGw-to-DirectConnect.ps1 -ProviderRG "..." -BackendVMName "..."`
- [ ] Wait 15-20 minutes
- [ ] Test: Verify App Gateway created and private frontend IP (10.0.2.10)

---

## Cost Optimization

### Deallocate VMs to Save Costs
```powershell
# Stop and deallocate both VMs
az vm deallocate -g $providerRG -n "VM-Provider"
az vm deallocate -g $consumerRG -n "VM-Consumer"

# Cost estimate: saves ~$30/month per VM when deallocated
```

### Clean Up Unused Public IPs
```powershell
# List public IPs
az network public-ip list --query "[].{Name:name, ResourceGroup:resourceGroup}" -o table

# Delete if not needed
az network public-ip delete -g $providerRG -n "VM-Provider-pip" --yes
```

---

## References

- **Azure CLI Docs**: https://docs.microsoft.com/cli/azure/
- **Private Link Docs**: https://learn.microsoft.com/azure/private-link/
- **Direct Connect (Preview)**: https://learn.microsoft.com/azure/private-link/configure-private-link-service-direct-connect
- **Application Gateway**: https://learn.microsoft.com/azure/application-gateway/
- **Network Security Groups**: https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview

---

**Last Updated**: March 2026
**Scenarios**: 2 (Overlapping IPs + App Gateway)
**Scripts**: `overlapp-direct-connect-solution.ps1`, `AppGw-to-DirectConnect.ps1`
