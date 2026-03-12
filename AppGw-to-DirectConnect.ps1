# ============================================================================
# Azure Application Gateway with Direct Connect
# Simplified Script - Creates App Gateway and exposes via Private Link Direct Connect
# Prerequisites: Provider VNet and Nginx VM already deployed (from overlap solution)
# ============================================================================
# USAGE:
#   .\AppGw-to-DirectConnect.ps1
#   .\AppGw-to-DirectConnect.ps1 -BackendVMName "MyVM" -BackendPort 8080
#   .\AppGw-to-DirectConnect.ps1 -ProviderRG "CustomRG" -ProviderVNetName "CustomVNet"
# ============================================================================

param(
    [string]$ProviderRG = "DirectConnect-Provider-RG",
    [string]$ProviderVNetName = "ProviderVNet",
    [string]$Location = "eastus",
    [string]$BackendVMName = "",  # Explicitly specify which VM to connect to (required if multiple VMs exist)
    [int]$BackendPort = 80        # Port the backend service is listening on
)

$ErrorActionPreference = "Continue"

# Helper function for error handling
function Assert-AzSuccess {
    param(
        [int]$ExitCode = $LASTEXITCODE,
        [string]$ErrorOutput = ""
    )

    if ($ExitCode -ne 0) {
        if ($ErrorOutput -like "*already exists*" -or $ErrorOutput -like "*AlreadyExists*" -or `
            $ErrorOutput -like "*Conflict*" -or $ErrorOutput -like "*in use*") {
            Write-Info "Resource already exists, continuing..."
            return $true
        }
        throw "Azure CLI command failed: $ErrorOutput"
    }
    return $true
}

# Write functions
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

function Write-Info {
    param([string]$Message)
    Write-Host "→ $Message" -ForegroundColor Gray
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

Write-Header "Azure Application Gateway with Direct Connect"
Write-Info "Provider RG: $ProviderRG"
Write-Info "Provider VNet: $ProviderVNetName"
Write-Info "Backend VM: $(if([string]::IsNullOrEmpty($BackendVMName)) { 'auto-detect' } else { $BackendVMName })"
Write-Info "Backend Port: $BackendPort"
Write-Info "Location: $Location"

# ============================================================================
# PHASE 1: GET EXISTING PROVIDER INFRASTRUCTURE
# ============================================================================

Write-Header "PHASE 1: Verifying Provider Infrastructure"

Write-Section "[1.1] Getting Provider VNet"
$vnet = az network vnet show -g $ProviderRG -n $ProviderVNetName -o json 2>&1 | ConvertFrom-Json
if (-not $vnet) {
    throw "Provider VNet '$ProviderVNetName' not found in RG '$ProviderRG'"
}
Write-Success "Provider VNet found: $($vnet.name)"

Write-Section "[1.2] Getting Provider VM and Backend IP"

# If BackendVMName not specified, auto-detect (gets first or only VM)
if ([string]::IsNullOrEmpty($BackendVMName)) {
    Write-Info "Backend VM not explicitly specified, auto-detecting..."
    $vmList = az vm list -g $ProviderRG -o json 2>&1 | ConvertFrom-Json

    if ($vmList -is [array]) {
        if ($vmList.Count -gt 1) {
            Write-Error-Custom "Multiple VMs found in $ProviderRG - please specify --BackendVMName"
            Write-Host "Available VMs:"
            $vmList | ForEach-Object { Write-Host "  - $($_.name)" }
            throw "Multiple VMs found. Use -BackendVMName to specify which one to use."
        }
        $vmData = $vmList[0]
    } else {
        $vmData = $vmList
    }

    if (-not $vmData) {
        throw "No VM found in Provider RG '$ProviderRG'"
    }
    $ProviderVMName = $vmData.name
} else {
    # Use explicitly provided VM name
    Write-Info "Using specified backend VM: $BackendVMName"
    $vmData = az vm show -g $ProviderRG -n $BackendVMName -o json 2>&1 | ConvertFrom-Json
    if (-not $vmData) {
        throw "VM '$BackendVMName' not found in RG '$ProviderRG'"
    }
    $ProviderVMName = $vmData.name
}

# Get NIC IP
$nicData = az vm nic list -g $ProviderRG --vm-name $ProviderVMName -o json 2>&1 | ConvertFrom-Json
$nicId = $nicData[0].id
$nicDetails = az network nic show --ids $nicId -o json 2>&1 | ConvertFrom-Json
$ProviderNICIP = $nicDetails.ipConfigurations[0].privateIpAddress

Write-Success "Provider VM: $ProviderVMName"
Write-Success "Backend IP: $ProviderNICIP (port $BackendPort)"

# ============================================================================
# PHASE 2: CREATE APP GATEWAY SUBNETS
# ============================================================================

Write-Header "PHASE 2: Creating Application Gateway Subnets"

Write-Section "[2.1] Creating App Gateway Subnet (delegated)"
$output = az network vnet subnet create `
    -g $ProviderRG `
    --vnet-name $ProviderVNetName `
    -n "appgw-subnet" `
    --address-prefixes "10.0.2.0/24" `
    --delegations "Microsoft.Network/applicationGateways" `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "App Gateway subnet created: 10.0.2.0/24"

Write-Section "[2.2] Creating Private Link NAT Subnet"
$output = az network vnet subnet create `
    -g $ProviderRG `
    --vnet-name $ProviderVNetName `
    -n "pls-nat-subnet" `
    --address-prefixes "10.0.3.0/24" `
    --disable-private-link-service-network-policies true `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Private Link NAT subnet created: 10.0.3.0/24"

# ============================================================================
# PHASE 3: CREATE APPLICATION GATEWAY
# ============================================================================

Write-Header "PHASE 3: Creating Application Gateway v2"

$appGWName = "appgw-provider"

Write-Section "[3.1] Creating Public IP for App Gateway"
$output = az network public-ip create `
    -g $ProviderRG `
    -n "appgw-pip" `
    --sku Standard `
    --allocation-method Static `
    -l $Location `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Public IP created: appgw-pip"

Write-Section "[3.2] Creating Application Gateway v2"
Write-Info "This may take 15-20 minutes..."

$output = az network application-gateway create `
    -g $ProviderRG `
    -n $appGWName `
    -l $Location `
    --sku Standard_v2 `
    --capacity 1 `
    --vnet-name $ProviderVNetName `
    --subnet "appgw-subnet" `
    --public-ip-address "appgw-pip" `
    --servers $ProviderNICIP `
    --frontend-port 80 `
    --http-settings-port $BackendPort `
    --http-settings-protocol Http `
    --priority 100 `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Application Gateway created: $appGWName"

Write-Section "[3.3] Adding Private Frontend IP to Application Gateway"
$output = az network application-gateway frontend-ip create `
    -g $ProviderRG `
    --gateway-name $appGWName `
    -n "appGatewayPrivateFrontendIP" `
    --vnet-name $ProviderVNetName `
    --subnet "appgw-subnet" `
    --private-ip-address "10.0.2.10" `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Private Frontend IP added: 10.0.2.10"

# ============================================================================
# PHASE 4: CREATE PRIVATE LINK SERVICE WITH DIRECT CONNECT
# ============================================================================

Write-Header "PHASE 4: Enabling Private Link with Direct Connect on App Gateway"

Write-Section "[4.1] Adding Private Link Configuration to App Gateway"
$output = az network application-gateway private-link add `
    -g $ProviderRG `
    --gateway-name $appGWName `
    --name "pls-config" `
    --frontend-ip "appGatewayPrivateFrontendIP" `
    --subnet "pls-nat-subnet" `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Private Link configuration added to Application Gateway"

Write-Section "[4.2] Creating HTTP Listener on Private Frontend"
$output = az network application-gateway http-listener create `
    -g $ProviderRG `
    --gateway-name $appGWName `
    -n "private-listener" `
    --frontend-ip "appGatewayPrivateFrontendIP" `
    --frontend-port "appGatewayFrontendPort" `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "HTTP Listener created"

Write-Section "[4.3] Creating Routing Rule"
$output = az network application-gateway rule create `
    -g $ProviderRG `
    --gateway-name $appGWName `
    -n "private-rule" `
    --priority 200 `
    --http-listener "private-listener" `
    --address-pool "appGatewayBackendPool" `
    --http-settings "appGatewayBackendHttpSettings" `
    --rule-type Basic `
    -o none 2>&1

Assert-AzSuccess -ExitCode $LASTEXITCODE -ErrorOutput "$output"
Write-Success "Routing rule created"

# ============================================================================
# PHASE 5: GET APP GATEWAY RESOURCE ID
# ============================================================================

Write-Header "PHASE 5: Getting App Gateway Details"

$appGWId = az network application-gateway show `
    -g $ProviderRG `
    -n $appGWName `
    --query id -o tsv 2>&1

if (-not $appGWId -or $appGWId -like "*error*") {
    throw "Failed to get Application Gateway ID"
}

Write-Success "App Gateway Resource ID: $appGWId"

# ============================================================================
# SUMMARY
# ============================================================================

Write-Header "DEPLOYMENT COMPLETE ✓"

Write-Host "`nAPPLICATION GATEWAY DETAILS:" -ForegroundColor Magenta
Write-Host ""
Write-Host "Provider Details:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ProviderRG"
Write-Host "  VNet: $ProviderVNetName (10.0.0.0/16)"
Write-Host "  Backend VM: $ProviderVMName"
Write-Host "  Backend IP: $ProviderNICIP"
Write-Host "  Backend Port: $BackendPort"
Write-Host ""
Write-Host "Application Gateway:" -ForegroundColor Cyan
Write-Host "  Name: $appGWName"
Write-Host "  SKU: Standard_v2"
Write-Host "  Private Frontend IP: 10.0.2.10"
Write-Host "  Backend Pool: $ProviderNICIP : $BackendPort"
Write-Host "  Public IP: appgw-pip"
Write-Host "  Private Link: Enabled (pls-config)"
Write-Host ""
Write-Host "Resource ID: $appGWId"
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Magenta
Write-Host "To create a Private Endpoint to this App Gateway, use:"
Write-Host "  az network private-endpoint create ."
Write-Host "    -g <consumer-rg> \"
Write-Host "    -n appgw-pe \"
Write-Host "    --vnet-name <consumer-vnet> \"
Write-Host "    --subnet default \"
Write-Host "    --private-connection-resource-id $appGWId \"
Write-Host "    --connection-name appgw-connection \"
Write-Host "    --group-id appGatewayPrivateFrontendIP"
Write-Host ""

Write-Host "CLEANUP:" -ForegroundColor Magenta
Write-Host "  az group delete -n $ProviderRG --yes --no-wait"
Write-Host ""
