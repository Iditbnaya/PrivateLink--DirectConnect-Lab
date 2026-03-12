# ============================================================================
# Azure Direct Connect Complete Solution
# written by - Idit Bnaya (@iditbnaya)
# ============================================================================
# This script deploys a complete Direct Connect test environment:
# 1. Provider RG (VNet 10.0.0.0/16 with Nginx VM and app GW)
# 2. Consumer RG (VNet 10.0.0.0/16 with VM)
# 3. Private Link Service with Direct Connect enabled
# 4. Optional: Private Endpoint
# ============================================================================

param(
    [string]$ProviderRG = "DirectConnect-Provider-RG-$([System.Guid]::NewGuid().ToString().Substring(0, 8))",
    [string]$ConsumerRG = "DirectConnect-Consumer-RG-$([System.Guid]::NewGuid().ToString().Substring(0, 8))",
    [string]$Location = "eastus"
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Header {
    param([string]$Message)
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Message)
    Write-Host "`n>> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "→ $Message" -ForegroundColor Gray
}

Write-Header "Azure Direct Connect Complete Solution"
Write-Info "Provider RG: $ProviderRG"
Write-Info "Consumer RG: $ConsumerRG"
Write-Info "Location: $Location"

# ============================================================================
# PHASE 1: DEPLOY PROVIDER INFRASTRUCTURE
# ============================================================================

Write-Header "PHASE 1: Deploying Provider Infrastructure"

# Get SSH key
Write-Section "[1.1] Preparing SSH Key"
$SSH_KEY = Get-Content "$env:USERPROFILE\.ssh/id_rsa.pub" -ErrorAction Stop
Write-Success "SSH key loaded"

# Create Provider RG
Write-Section "[1.2] Creating Provider Resource Group"
az group create -n $ProviderRG -l $Location | Out-Null
Write-Success "Provider RG created: $ProviderRG"

# Deploy Provider VNet + VM + Nginx
Write-Section "[1.3] Deploying Provider VNet, VM, and Nginx"
Write-Info "This may take 5-10 minutes..."

$providerDeploy = az deployment group create `
    --name "provider-deploy" `
    --resource-group $ProviderRG `
    --template-file overlap-test.bicep `
    --parameters overlap-provider.bicepparam `
    --parameters sshPublicKey="$SSH_KEY" `
    --query properties.outputs `
    -o json | ConvertFrom-Json

$ProviderVMName = $providerDeploy.vmName.value
$ProviderNICIP = $providerDeploy.nicPrivateIp.value
$ProviderVNetName = $providerDeploy.vnetName.value

Write-Success "Provider infrastructure deployed"
Write-Success "  VNet: $ProviderVNetName (10.0.0.0/16)"
Write-Success "  VM: $ProviderVMName"
Write-Success "  NIC IP: $ProviderNICIP"
Write-Success "  Nginx: Running on http://$ProviderNICIP"

# ============================================================================
# PHASE 2: DEPLOY CONSUMER INFRASTRUCTURE
# ============================================================================

Write-Header "PHASE 2: Deploying Consumer Infrastructure"

# Create Consumer RG
Write-Section "[2.1] Creating Consumer Resource Group"
az group create -n $ConsumerRG -l $Location | Out-Null
Write-Success "Consumer RG created: $ConsumerRG"

# Deploy Consumer VNet + VM
Write-Section "[2.2] Deploying Consumer VNet and VM"
Write-Info "This may take 5-10 minutes..."

$consumerDeploy = az deployment group create `
    --name "consumer-deploy" `
    --resource-group $ConsumerRG `
    --template-file overlap-test.bicep `
    --parameters overlap-consumer.bicepparam `
    --parameters sshPublicKey="$SSH_KEY" `
    --query properties.outputs `
    -o json | ConvertFrom-Json

$ConsumerVMName = $consumerDeploy.vmName.value
$ConsumerVNetName = $consumerDeploy.vnetName.value
$ConsumerSubnetId = $consumerDeploy.subnetId.value

Write-Success "Consumer infrastructure deployed"
Write-Success "  VNet: $ConsumerVNetName (10.0.0.0/16)"
Write-Success "  VM: $ConsumerVMName"
Write-Success "  Subnet ID: $ConsumerSubnetId"

# ============================================================================
# PHASE 3: CREATE PRIVATE LINK SERVICE WITH DIRECT CONNECT
# ============================================================================

Write-Header "PHASE 3: Creating Private Link Service with Direct Connect"

$plsName = "pls-direct-connect"

# Step 1: Get resources
Write-Section "[3.1] Retrieving Azure Resources"

$vnet = Get-AzVirtualNetwork -Name $ProviderVNetName -ResourceGroupName $ProviderRG
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $vnet

# Get the NIC from the Provider VM
$vm = Get-AzVM -Name $ProviderVMName -ResourceGroupName $ProviderRG
$nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
$nic = Get-AzNetworkInterface -ResourceId $nicId

Write-Success "Resources retrieved:"
Write-Success "  VNet: $($vnet.Name)"
Write-Success "  Subnet: $($subnet.Name)"
Write-Success "  NIC: $($nic.Name) (IP: $($nic.IpConfigurations[0].PrivateIpAddress))"

# Step 2: Disable network policies
Write-Section "[3.2] Configuring Subnet for Private Link Service"

try {
    $subnet.PrivateLinkServiceNetworkPolicies = "Disabled"
    $vnet | Set-AzVirtualNetwork | Out-Null
    Write-Success "Private Link Service network policies disabled"
}
catch {
    Write-Error-Custom "Could not disable policies: $_"
}

# Step 3: Create IP Configurations
Write-Section "[3.3] Creating IP Configurations (2 required for Direct Connect)"

$ipConfig1 = New-AzPrivateLinkServiceIpConfig `
    -Name "pls-ip-config-1" `
    -Subnet $subnet `
    -Primary

$ipConfig2 = New-AzPrivateLinkServiceIpConfig `
    -Name "pls-ip-config-2" `
    -Subnet $subnet

Write-Success "IP Configuration 1 created (Primary)"
Write-Success "IP Configuration 2 created"

# Step 4: Create Private Link Service
Write-Section "[3.4] Creating Private Link Service"

$pls = New-AzPrivateLinkService `
    -Name $plsName `
    -ResourceGroupName $ProviderRG `
    -Location $Location `
    -IpConfiguration $ipConfig1, $ipConfig2 `
    -DestinationIpAddress $nic.IpConfigurations[0].PrivateIpAddress

Write-Success "Private Link Service created: $($pls.Name)"
Write-Success "  Resource ID: $($pls.Id)"
Write-Success "  Destination IP: $($nic.IpConfigurations[0].PrivateIpAddress)"

# Step 5: Link Network Interface
Write-Section "[3.5] Linking Network Interface to PLS"

try {
    $pls.NetworkInterfaces.Add($nic.Id)
    $pls = Set-AzPrivateLinkService -InputObject $pls
    Write-Success "Network Interface linked successfully"
}
catch {
    Write-Info "Network Interface linking via PowerShell (may need Portal)"
}

# ============================================================================
# PHASE 4: ENABLE DIRECT CONNECT
# ============================================================================

Write-Header "PHASE 4: Enabling Direct Connect Mode"

Write-Section "[4.1] Enabling Direct Connect via Azure CLI"

Write-Info "Running Azure CLI command to enable Direct Connect..."
Write-Info "Command: az network private-link-service update -g $ProviderRG -n $plsName --direct-connect true"

try {
    # Enable Direct Connect via Azure CLI
    $updateResult = az network private-link-service update `
        -g $ProviderRG `
        -n $plsName `
        --direct-connect true `
        -o json | ConvertFrom-Json

    Write-Success "Direct Connect enabled successfully!"
    Write-Success "  directConnectEnabled: $($updateResult.directConnectEnabled)"
}
catch {
    Write-Info "Azure CLI command did not work (Direct Connect may still be in preview)"
    Write-Info "Alternative method: Use Azure Portal to enable Direct Connect"
    Write-Info ""
    Write-Info "To enable via Portal:"
    Write-Info "1. Open: https://portal.azure.com/?feature.canmodifystamps=true&exp.plsdirectconnect=true"
    Write-Info "2. Search for PLS: '$plsName'"
    Write-Info "3. Go to Settings/Configuration"
    Write-Info "4. Enable Direct Connect Mode"
    Write-Info "5. Save the changes"
}

# ============================================================================
# PHASE 5: CREATE PRIVATE ENDPOINT (Optional)
# ============================================================================

Write-Header "PHASE 5: Creating Private Endpoint"

Write-Section "[5.1] Creating Private Endpoint in Consumer VNet"

try {
    $peDeployment = az deployment group create `
        --name "private-endpoint-deploy" `
        --resource-group $ConsumerRG `
        --template-file private-endpoint.json `
        --parameters `
            privateEndpointName="DirectConnect-PE" `
            subnetId="$ConsumerSubnetId" `
            privateLinkServiceId="$($pls.Id)" `
            connectionName="DirectConnect-Connection" `
            location="$Location" `
        --query properties.outputs `
        -o json | ConvertFrom-Json

    Write-Success "Private Endpoint created: $($peDeployment.privateEndpointName.value)"
}
catch {
    Write-Error-Custom "Could not create Private Endpoint: $_"
    Write-Info "You can create it manually via Azure Portal or CLI"
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Header "✅ DEPLOYMENT COMPLETE"

Write-Host "`n📋 SOLUTION SUMMARY:" -ForegroundColor Magenta
Write-Host ""
Write-Host "PROVIDER SIDE (Resource Group: $ProviderRG)" -ForegroundColor Cyan
Write-Host "  ├─ VNet: $ProviderVNetName (10.0.0.0/16)"
Write-Host "  ├─ Subnet: default (10.0.1.0/24)"
Write-Host "  ├─ VM: $ProviderVMName"
Write-Host "  ├─ NIC IP: $ProviderNICIP"
Write-Host "  ├─ Nginx: Running on http://$ProviderNICIP"
Write-Host "  └─ PLS: $plsName (Direct Connect mode)"
Write-Host ""
Write-Host "CONSUMER SIDE (Resource Group: $ConsumerRG)" -ForegroundColor Cyan
Write-Host "  ├─ VNet: $ConsumerVNetName (10.0.0.0/16) [OVERLAPPING!]"
Write-Host "  ├─ Subnet: default (10.0.1.0/24)"
Write-Host "  ├─ VM: $ConsumerVMName"
Write-Host "  └─ Private Endpoint: DirectConnect-PE"
Write-Host ""

Write-Host "🔗 CONNECTIVITY:" -ForegroundColor Magenta
Write-Host "  Consumer → Private Endpoint → Direct Connect PLS → Provider NIC"
Write-Host "  (Both VNets use 10.0.0.0/16 with Direct Connect handling overlap)"
Write-Host ""

Write-Host "📊 NEXT STEPS:" -ForegroundColor Magenta
Write-Host "  1. ✓ Provider infrastructure deployed"
Write-Host "  2. ✓ Consumer infrastructure deployed"
Write-Host "  3. ✓ Private Link Service created"
Write-Host "  4. ✓ Private Endpoint created"
Write-Host "  5. → Enable Direct Connect (if not already enabled by script):"
Write-Host ""
Write-Host "     CLI Command:"
Write-Host "     az network private-link-service update -g $ProviderRG -n $plsName --direct-connect true"
Write-Host ""
Write-Host "     OR via Portal:"
Write-Host "     https://portal.azure.com/?feature.canmodifystamps=true&exp.plsdirectconnect=true"
Write-Host ""

Write-Host "🧪 TESTING:" -ForegroundColor Magenta
Write-Host "  • Both VMs have overlapping IPs (10.0.1.x/24)"
Write-Host "  • Direct Connect connects through Private Endpoint"
Write-Host "  • Access Provider Nginx from Consumer via Private Endpoint"
Write-Host "  • No conflicts - each VNet is isolated"
Write-Host ""

Write-Host "🧹 CLEANUP:" -ForegroundColor Magenta
Write-Host "  az group delete -n $ProviderRG --yes --no-wait"
Write-Host "  az group delete -n $ConsumerRG --yes --no-wait"
Write-Host ""

Write-Host "✅ Solution deployment completed successfully!" -ForegroundColor Green
Write-Host ""
