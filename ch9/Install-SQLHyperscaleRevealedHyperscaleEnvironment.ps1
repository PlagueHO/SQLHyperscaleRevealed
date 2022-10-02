<#
    .SYNOPSIS
        Deploys the Hyperscale database and configures it with the following
        requirements:
            - Creates user assigned managed identity for the Hyperscale database.
            - Generates TDE protector key in Key Vault.
            - Reconfigures the primary region virtual network to add AzureBastionSubnet
              and management_Subnet.
            - Logical server (SQL Server) in primary region with user assigned managed identity,
              TDE customer-managed key, only allowing Azure AD authentication with the SQL admin
              set to the SQL Administrators group.
             - Add networking components required to connect the Hyperscale database to the
               primary region virtual network: Private Link, DNS Zone.
            - Connects primary region logical server to VNET in primary region.
            - Creates the Hyperscale database in the primary region logical server with 2 AZ
              enabled replicas and Geo-zone-redundant backups.

    .PARAMETER PrimaryRegion
        The Azure region to use as the primary region.
        Use this page for a list of Azure regions: https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#azure-regions

    .PARAMETER FailoverRegion
        The Azure region to use as the failover region.
        Use this page for a list of Azure regions: https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#azure-regions

    .PARAMETER ResourceNameSuffix
        The string that will be suffixed into the resource names to
        try to ensure resource names are globally unique. Must be 4 characters or less.

    .PARAMETER Environment
        This string will be used to set the Environment tag in each resource.
        It can be used to easily identify that the resources that created by this script.

    .PARAMETER AadUsernamePrincipalName
        The Azure AD principal user account name running this script.
        Required because Cloud Shell uses a Service Principal which obfuscates the user account.

    .PARAMETER NoFailoverRegion
        This switch prevents deployment of the resources in the failover region.
#>
[CmdletBinding(DefaultParameterSetName = 'ResourceNameSuffix')]

param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $PrimaryRegion = 'East US',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $FailoverRegion = 'West US 3',

    [Parameter(Mandatory = $true, HelpMessage = 'The string that will be suffixed into the resource groups and resource names.')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,4)]
    [System.String]
    $ResourceNameSuffix,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Environment = 'SQL Hyperscale Revealed demo',

    [Parameter(Mandatory = $true, HelpMessage = 'The Azure AD principal user account name running this script.')]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $AadUsernamePrincipalName,

    [Parameter()]
    [Switch]
    $NoFailoverRegion
)
#>

# Variables to help with resource naming in the script.
$tags = @{ Environment = $Environment }
$baseResourcePrefix = 'sqlhr'
$primaryRegionPrefix = "$($baseResourcePrefix)01"
$failoverRegionPrefix = "$($baseResourcePrefix)02"
$primaryRegionResourceGroupName = "$primaryRegionPrefix-$resourceNameSuffix-rg"
$failoverRegionResourceGroupName = "$failoverRegionPrefix-$resourceNameSuffix-rg"
$subscriptionId = (Get-AzContext).Subscription.Id
$userId = (Get-AzAdUser -UserPrincipalName $AadUsernamePrincipalName).Id
$privateZone = 'privatelink.database.windows.net'

# ======================================================================================================================
# VIRTUAL NETWORK PREPARATION FOR MANAGEMENT AND BASTION SUBNETS
# ======================================================================================================================

# Update the VNET subnets to add the management and Bastion subnets in case
# they are needed for the management VM and Azure Bastion - although we won't
# deploy these resources in this script.
Write-Verbose -Message "Adding 'management_subnet' and 'AzureBastionSubnet' to the primary virtual network '$baseResourcePrefix-$resourceNameSuffix-vnet' ..." -Verbose
$vnet = Get-AzVirtualNetwork -Name "$primaryRegionPrefix-$resourceNameSuffix-vnet" -ResourceGroupName $primaryRegionResourceGroupName
Add-AzVirtualNetworkSubnetConfig -Name 'management_subnet' -AddressPrefix '10.0.3.0/24' -VirtualNetwork $vnet | Out-Null
Add-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.0.4.0/24' -VirtualNetwork $vnet | Out-Null
$vnet | Set-AzVirtualNetwork | Out-Null

Write-Verbose -Message "Adding 'management_subnet' and 'AzureBastionSubnet' to the failover virtual network '$baseResourcePrefix-$resourceNameSuffix-vnet' ..." -Verbose
$vnet = Get-AzVirtualNetwork -Name "$failoverRegionPrefix-$resourceNameSuffix-vnet" -ResourceGroupName $failoverRegionResourceGroupName
Add-AzVirtualNetworkSubnetConfig -Name 'management_subnet' -AddressPrefix '10.1.3.0/24' -VirtualNetwork $vnet | Out-Null
Add-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.1.4.0/24' -VirtualNetwork $vnet | Out-Null
$vnet | Set-AzVirtualNetwork | Out-Null

# ======================================================================================================================
# PREPARE USER ASSIGNED MANAGED IDENTITY FOR THE HYPERSCALE DATABASES
# ======================================================================================================================

# Create user assigned managed identity for the logical servers in both
# regions to use to access the Key Vault for the TDE protector key.
Write-Verbose -Message "Creating user assigned managed identity '$baseResourcePrefix-$resourceNameSuffix-umi' for the logical server ..." -Verbose
$newAzUserAssignedIdentity_parameters = @{
    Name = "$baseResourcePrefix-$resourceNameSuffix-umi"
    ResourceGroupName = $primaryRegionResourceGroupName
    Location = $primaryRegion
    Tag = $tags
}
New-AzUserAssignedIdentity @newAzUserAssignedIdentity_parameters | Out-Null
$userAssignedManagedIdentityId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$baseResourcePrefix-$resourceNameSuffix-umi"

# ======================================================================================================================
# PREPARE CUSTOMER-MANAGED TDE PROTECTOR KEY IN KEY VAULT
# ======================================================================================================================

# Prepare the Key Vault for the TDE protector key and grant access the
# user assigned managed identity permission to access the key.
Write-Verbose -Message "Assigning 'Key Vault Crypto Officer' role to the user '$AadUsernamePrincipalName' for the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv' ..." -Verbose
$newAzRoleAssignment_parameters = @{
    ObjectId = $userId
    RoleDefinitionName = 'Key Vault Crypto Officer'
    Scope = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv"
}
New-AzRoleAssignment @newAzRoleAssignment_parameters | Out-Null

# Generate the TDE protector key in the Key Vault.
Write-Verbose -Message "Creating the TDE Protector Key '$baseResourcePrefix-$resourceNameSuffix-tdeprotector' in the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv' ..." -Verbose
$addAzKeyVaultKey_parameters = @{
    KeyName = "$baseResourcePrefix-$resourceNameSuffix-tdeprotector"
    VaultName = "$baseResourcePrefix-$resourceNameSuffix-kv"
    KeyType = 'RSA'
    Size = 2048
    Destination = 'Software'
    Tag = $tags
}
Add-AzKeyVaultKey  @addAzKeyVaultKey_parameters | Out-Null
$tdeProtectorKeyId = (Get-AzKeyVaultKey -KeyName "$baseResourcePrefix-$resourceNameSuffix-tdeprotector" -VaultName "$baseResourcePrefix-$resourceNameSuffix-kv").Id

# Get the Service Principal Id of the user assigned managed identity.
# This may take a few seconds to propagate, so wait for it.
$servicePrincipalId = (Get-AzADServicePrincipal -DisplayName "$baseResourcePrefix-$resourceNameSuffix-umi").Id
while ($null -eq $servicePrincipalId) {
    Write-Verbose -Message "Waiting for the service principal of user assigned managed identity '$baseResourcePrefix-$resourceNameSuffix-umi' to be available ..." -Verbose
    Start-Sleep -Seconds 5
    $servicePrincipalId = (Get-AzADServicePrincipal -DisplayName "$baseResourcePrefix-$resourceNameSuffix-umi").Id
}

# Assign the Key Vault Crypto Service Encryption User role to the user assigned managed identity
# on the key in the Key Vault.
Write-Verbose -Message "Assigning 'Key Vault Crypto Service Encryption User' role to '$baseResourcePrefix-$resourceNameSuffix-umi' for the key '$baseResourcePrefix-$resourceNameSuffix-tdeprotector' in the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv' ..." -Verbose
$tdeProtectorKeyResourceId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv/keys/$baseResourcePrefix-$resourceNameSuffix-tdeprotector"
$newAzRoleAssignment_parameters = @{
    ObjectId = $servicePrincipalId
    RoleDefinitionName = 'Key Vault Crypto Service Encryption User'
    Scope = $tdeProtectorKeyResourceId
}
New-AzRoleAssignment @newAzRoleAssignment_parameters | Out-Null

# ======================================================================================================================
# DEPLOY PRIMARY REGION
# ======================================================================================================================

# Create the primary SQL logical server without AAD authentication.
# Due to a current issue with the New-AzSqlServer command in Az.Sql 3.11 when -ExternalAdminName
# is specified, we need to add -SqlAdministratorCredentials and then set the AAD administrator
# with the Set-AzSqlServerActiveDirectoryAdministrator command.
Write-Verbose -Message "Creating logical server '$primaryRegionPrefix-$resourceNameSuffix' ..." -Verbose
$sqlAdministratorPassword = -join ((48..57) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_} )
$sqlAdministratorCredential = [PSCredential]::new('sqltempadmin', (ConvertTo-SecureString -String $sqlAdministratorPassword -AsPlainText -Force))
$newAzSqlServer_parameters = @{
    ServerName = "$primaryRegionPrefix-$resourceNameSuffix"
    ResourceGroupName = $primaryRegionResourceGroupName
    Location = $primaryRegion
    ServerVersion = '12.0'
    PublicNetworkAccess = 'Disabled'
    SqlAdministratorCredentials = $sqlAdministratorCredential
    AssignIdentity = $true
    IdentityType = 'UserAssigned'
    UserAssignedIdentityId = $userAssignedManagedIdentityId
    PrimaryUserAssignedIdentityId = $userAssignedManagedIdentityId
    KeyId = $tdeProtectorKeyId
    Tag = $tags
}
New-AzSqlServer @newAzSqlServer_parameters | Out-Null

Write-Verbose -Message "Configure administartors of logical server '$primaryRegionPrefix-$resourceNameSuffix' to be Azure AD 'SQL Administrators' group ..." -Verbose
$sqlAdministratorsGroupId = (Get-AzADGroup -DisplayName 'SQL Administrators').Id
$setAzSqlServerActiveDirectoryAdministrator_parameters = @{
    ObjectId = $sqlAdministratorsGroupId
    DisplayName = 'SQL Administrators'
    ServerName = "$primaryRegionPrefix-$resourceNameSuffix"
    ResourceGroupName = $primaryRegionResourceGroupName
}
Set-AzSqlServerActiveDirectoryAdministrator @setAzSqlServerActiveDirectoryAdministrator_parameters | Out-Null

# Create the private endpoint, and connect the logical server to it and the virtal network and configure the DNS zone.
# Create the private link service connection
Write-Verbose -Message "Creating the private link service connection '$primaryRegionPrefix-$resourceNameSuffix-pl' for the logical server '$primaryRegionPrefix-$resourceNameSuffix' ..." -Verbose
$sqlServerResourceId = (Get-AzSqlServer -ServerName "$primaryRegionPrefix-$resourceNameSuffix" -ResourceGroupName $primaryRegionResourceGroupName).ResourceId
$newAzPrivateLinkServiceConnection_parameters = @{
    Name = "$primaryRegionPrefix-$resourceNameSuffix-pl"
    PrivateLinkServiceId = $sqlServerResourceId
    GroupId = 'SqlServer'
}
$privateLinkServiceConnection = New-AzPrivateLinkServiceConnection @newAzPrivateLinkServiceConnection_parameters

# Create the private endpoint for the logical server in the subnet.
Write-Verbose -Message "Creating the private endpoint '$primaryRegionPrefix-$resourceNameSuffix-pe' in the 'data_subnet' for the logical server '$primaryRegionPrefix-$resourceNameSuffix' ..." -Verbose
$vnet = Get-AzVirtualNetwork -Name "$primaryRegionPrefix-$resourceNameSuffix-vnet" -ResourceGroupName $primaryRegionResourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'data_subnet'
$newAzPrivateEndpoint_parameters = @{
    Name = "$primaryRegionPrefix-$resourceNameSuffix-pe"
    ResourceGroupName = $primaryRegionResourceGroupName
    Location = $primaryRegion
    Subnet = $subnet
    PrivateLinkServiceConnection = $privateLinkServiceConnection
    Tag = $tags
}
New-AzPrivateEndpoint @newAzPrivateEndpoint_parameters | Out-Null

# Create the private DNS zone.
Write-Verbose -Message "Creating the private DNS Zone for '$privateZone' in resource group '$primaryRegionResourceGroupName' ..." -Verbose
$newAzPrivateDnsZone_parameters = @{
    Name = $privateZone
    ResourceGroupName = $primaryRegionResourceGroupName
}
$privateDnsZone = New-AzPrivateDnsZone @newAzPrivateDnsZone_parameters

# Connect the private DNS Zone to the primary region VNET.
Write-Verbose -Message "Connecting the private DNS Zone '$privateZone' to the virtual network '$primaryRegionPrefix-$resourceNameSuffix-vnet' ..." -Verbose
$newAzPrivateDnsVirtualNetworkLink_parameters = @{
    Name = "$primaryRegionPrefix-$resourceNameSuffix-dnslink"
    ResourceGroupName = $primaryRegionResourceGroupName
    ZoneName = $privateZone
    VirtualNetworkId = $vnet.Id
    Tag = $tags
}
New-AzPrivateDnsVirtualNetworkLink @newAzPrivateDnsVirtualNetworkLink_parameters | Out-Null

# Create the private DNS record for the logical server.
Write-Verbose -Message "Creating the private DNS Zone Group '$primaryRegionPrefix-$resourceNameSuffix-zonegroup' and connecting it to the '$primaryRegionPrefix-$resourceNameSuffix-pe' ..." -Verbose
$privateDnsZoneConfig = New-AzPrivateDnsZoneConfig -Name $privateZone -PrivateDnsZoneId $privateDnsZone.ResourceId
$newAzPrivateDnsZoneGroup_parameters = @{
    Name = "$primaryRegionPrefix-$resourceNameSuffix-zonegroup"
    ResourceGroupName = $primaryRegionResourceGroupName
    PrivateEndpointName = "$primaryRegionPrefix-$resourceNameSuffix-pe"
    PrivateDnsZoneConfig = $privateDnsZoneConfig
}
New-AzPrivateDnsZoneGroup @newAzPrivateDnsZoneGroup_parameters | Out-Null

# Create the hyperscale database in the primary region
Write-Verbose -Message "Creating the primary hyperscale database in the logical server '$primaryRegionPrefix-$resourceNameSuffix' ..." -Verbose
$newAzSqlDatabase_parameters = @{
    DatabaseName = 'hyperscaledb'
    ServerName = "$primaryRegionPrefix-$resourceNameSuffix"
    ResourceGroupName = $primaryRegionResourceGroupName
    Edition = 'Hyperscale'
    Vcore = 2
    ComputeGeneration = 'Gen5'
    ComputeModel = 'Provisioned'
    HighAvailabilityReplicaCount = 2
    ZoneRedundant = $true
    BackupStorageRedundancy = 'GeoZone'
    Tags = $tags
}
New-AzSqlDatabase @newAzSqlDatabase_parameters | Out-Null

# Enable sending primary logical server audit logs to the Log Analytics workspace
Write-Verbose -Message "Configuring the primary logical server '$primaryRegionPrefix-$resourceNameSuffix' to send audit logs to the Log Analytics workspace '$primaryRegionPrefix-$resourceNameSuffix-law' ..." -Verbose
$logAnalyticsWorkspaceResourceId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/microsoft.operationalinsights/workspaces/$primaryRegionPrefix-$resourceNameSuffix-law"
$setAzSqlServerAudit_Parameters = @{
    ServerName = "$primaryRegionPrefix-$resourceNameSuffix"
    ResourceGroupName = $primaryRegionResourceGroupName
    WorkspaceResourceId = $logAnalyticsWorkspaceResourceId
    LogAnalyticsTargetState = 'Enabled'
}
Set-AzSqlServerAudit @setAzSqlServerAudit_Parameters | Out-Null

# Enable sending database diagnostic logs to the Log Analytics workspace
Write-Verbose -Message "Configuring the primary hyperscale database 'hyperscaledb' to send all diagnostic logs to the Log Analytics workspace '$primaryRegionPrefix-$resourceNameSuffix-law' ..." -Verbose
$logAnalyticsWorkspaceResourceId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/microsoft.operationalinsights/workspaces/$primaryRegionPrefix-$resourceNameSuffix-law"
$databaseResourceId = (Get-AzSqlDatabase -ServerName "$primaryRegionPrefix-$resourceNameSuffix" -ResourceGroupName $primaryRegionResourceGroupName -DatabaseName 'hyperscaledb').ResourceId
$SetAzDiagnosticSetting_parameters = @{
    ResourceId = $databaseResourceId
    Name = "Send all logs to $primaryRegionPrefix-$resourceNameSuffix-law"
    WorkspaceId = $logAnalyticsWorkspaceResourceId
    Category = @('SQLInsights','AutomaticTuning','QueryStoreRuntimeStatistics','QueryStoreWaitStatistics','Errors','DatabaseWaitStatistics','Timeouts','Blocks','Deadlocks')
    Enabled = $true
    EnableLog = $true
}
Set-AzDiagnosticSetting @setAzDiagnosticSetting_parameters | Out-Null

# ======================================================================================================================
# DEPLOY FAILOVER REGION
# ======================================================================================================================

if (-not $NoFailoverRegion.IsPresent) {
    # Create the failover SQL logical server without AAD authentication.
    # Due to a current issue with the New-AzSqlServer command in Az.Sql 3.11 when -ExternalAdminName
    # is specified, we need to add -SqlAdministratorCredentials and then set the AAD administrator
    # with the Set-AzSqlServerActiveDirectoryAdministrator command.
    Write-Verbose -Message "Creating logical server '$failoverRegionPrefix-$resourceNameSuffix' ..." -Verbose
    $newAzSqlServer_parameters = @{
        ServerName = "$failoverRegionPrefix-$resourceNameSuffix"
        ResourceGroupName = $failoverRegionResourceGroupName
        Location = $failoverRegion
        ServerVersion = '12.0'
        PublicNetworkAccess = 'Disabled'
        SqlAdministratorCredentials = $sqlAdministratorCredential
        AssignIdentity = $true
        IdentityType = 'UserAssigned'
        UserAssignedIdentityId = $userAssignedManagedIdentityId
        PrimaryUserAssignedIdentityId = $userAssignedManagedIdentityId
        KeyId = $tdeProtectorKeyId
        Tag = $tags
    }
    New-AzSqlServer @newAzSqlServer_parameters | Out-Null

    Write-Verbose -Message "Configure administartors of logical server '$failoverRegionPrefix-$resourceNameSuffix' to be Azure AD 'SQL Administrators' group ..." -Verbose
    $sqlAdministratorsGroupId = (Get-AzADGroup -DisplayName 'SQL Administrators').Id
    $setAzSqlServerActiveDirectoryAdministrator_parameters = @{
        ObjectId = $sqlAdministratorsGroupId
        DisplayName = 'SQL Administrators'
        ServerName = "$failoverRegionPrefix-$resourceNameSuffix"
        ResourceGroupName = $failoverRegionResourceGroupName
    }
    Set-AzSqlServerActiveDirectoryAdministrator @setAzSqlServerActiveDirectoryAdministrator_parameters | Out-Null

    # Create the private endpoint, and connect the logical server to it and the virtal network and configure the DNS zone.
    # Create the private link service connection
    Write-Verbose -Message "Creating the private link service connection '$failoverRegionPrefix-$resourceNameSuffix-pl' for the logical server '$failoverRegionPrefix-$resourceNameSuffix' ..." -Verbose
    $sqlServerResourceId = (Get-AzSqlServer -ServerName "$failoverRegionPrefix-$resourceNameSuffix" -ResourceGroupName $failoverRegionResourceGroupName).ResourceId
    $newAzPrivateLinkServiceConnection_parameters = @{
        Name = "$failoverRegionPrefix-$resourceNameSuffix-pl"
        PrivateLinkServiceId = $sqlServerResourceId
        GroupId = 'SqlServer'
    }
    $privateLinkServiceConnection = New-AzPrivateLinkServiceConnection @newAzPrivateLinkServiceConnection_parameters

    # Create the private endpoint for the logical server in the subnet.
    Write-Verbose -Message "Creating the private endpoint '$failoverRegionPrefix-$resourceNameSuffix-pe' in the 'data_subnet' for the logical server '$failoverRegionPrefix-$resourceNameSuffix' ..." -Verbose
    $vnet = Get-AzVirtualNetwork -Name "$failoverRegionPrefix-$resourceNameSuffix-vnet" -ResourceGroupName $failoverRegionResourceGroupName
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'data_subnet'
    $newAzPrivateEndpoint_parameters = @{
        Name = "$failoverRegionPrefix-$resourceNameSuffix-pe"
        ResourceGroupName = $failoverRegionResourceGroupName
        Location = $failoverRegion
        Subnet = $subnet
        PrivateLinkServiceConnection = $privateLinkServiceConnection
        Tag = $tags
    }
    New-AzPrivateEndpoint @newAzPrivateEndpoint_parameters | Out-Null

    # Create the private DNS zone.
    Write-Verbose -Message "Creating the private DNS Zone for '$privateZone' in resource group '$failoverRegionResourceGroupName' ..." -Verbose
    $newAzPrivateDnsZone_parameters = @{
        Name = $privateZone
        ResourceGroupName = $failoverRegionResourceGroupName
    }
    $privateDnsZone = New-AzPrivateDnsZone @newAzPrivateDnsZone_parameters

    # Connect the private DNS Zone to the failover region VNET.
    Write-Verbose -Message "Connecting the private DNS Zone '$privateZone' to the virtual network '$failoverRegionPrefix-$resourceNameSuffix-vnet' ..." -Verbose
    $newAzPrivateDnsVirtualNetworkLink_parameters = @{
        Name = "$failoverRegionPrefix-$resourceNameSuffix-dnslink"
        ResourceGroupName = $failoverRegionResourceGroupName
        ZoneName = $privateZone
        VirtualNetworkId = $vnet.Id
        Tag = $tags
    }
    New-AzPrivateDnsVirtualNetworkLink @newAzPrivateDnsVirtualNetworkLink_parameters | Out-Null

    # Create the private DNS record for the logical server.
    Write-Verbose -Message "Creating the private DNS Zone Group '$failoverRegionPrefix-$resourceNameSuffix-zonegroup' and connecting it to the '$failoverRegionPrefix-$resourceNameSuffix-pe' ..." -Verbose
    $privateDnsZoneConfig = New-AzPrivateDnsZoneConfig -Name $privateZone -PrivateDnsZoneId $privateDnsZone.ResourceId
    $newAzPrivateDnsZoneGroup_parameters = @{
        Name = "$failoverRegionPrefix-$resourceNameSuffix-zonegroup"
        ResourceGroupName = $failoverRegionResourceGroupName
        PrivateEndpointName = "$failoverRegionPrefix-$resourceNameSuffix-pe"
        PrivateDnsZoneConfig = $privateDnsZoneConfig
    }
    New-AzPrivateDnsZoneGroup @newAzPrivateDnsZoneGroup_parameters | Out-Null

    # Establish the active geo-replication from the primary region to the failover region.
    Write-Verbose -Message "Creating the geo-replica 'hyperscaledb' from '$primaryRegionPrefix-$resourceNameSuffix' to '$failoverRegionPrefix-$resourceNameSuffix' ..." -Verbose
    $newAzSqlDatabaseSecondary = @{
        ServerName = "$failoverRegionPrefix-$resourceNameSuffix"
        ResourceGroupName = $failoverRegionResourceGroupName
        PartnerServerName  = "$primaryRegionPrefix-$resourceNameSuffix"
        PartnerServerResourceGroupName = $primaryRegionResourceGroupName
        AllowConnections = "All"
        SecondaryVCore = 2
        SecondaryComputeGeneration = 'Gen5'
    }
    New-AzSqlDatabaseSecondary @newAzSqlDatabaseSecondary | Out-Null

    # Enable sending failover logical server audit logs to the Log Analytics workspace
    Write-Verbose -Message "Configuring the failover logical server '$failoverRegionPrefix-$resourceNameSuffix' to send audit logs to the Log Analytics workspace '$failoverRegionPrefix-$resourceNameSuffix-law' ..." -Verbose
    $logAnalyticsWorkspaceResourceId = "/subscriptions/$subscriptionId/resourcegroups/$failoverRegionResourceGroupName/providers/microsoft.operationalinsights/workspaces/$failoverRegionPrefix-$resourceNameSuffix-law"
    $setAzSqlServerAudit_Parameters = @{
        ServerName = "$failoverRegionPrefix-$resourceNameSuffix"
        ResourceGroupName = $failoverRegionResourceGroupName
        WorkspaceResourceId = $logAnalyticsWorkspaceResourceId
        LogAnalyticsTargetState = 'Enabled'
    }
    Set-AzSqlServerAudit @setAzSqlServerAudit_Parameters | Out-Null

    # Enable sending database diagnostic logs to the Log Analytics workspace
    Write-Verbose -Message "Configuring the failover hyperscale database 'hyperscaledb' to send all diagnostic logs to the Log Analytics workspace '$failoverRegionPrefix-$resourceNameSuffix-law' ..." -Verbose
    $logAnalyticsWorkspaceResourceId = "/subscriptions/$subscriptionId/resourcegroups/$failoverRegionResourceGroupName/providers/microsoft.operationalinsights/workspaces/$failoverRegionPrefix-$resourceNameSuffix-law"
    $databaseResourceId = (Get-AzSqlDatabase -ServerName "$failoverRegionPrefix-$resourceNameSuffix" -ResourceGroupName $failoverRegionResourceGroupName -DatabaseName 'hyperscaledb').ResourceId
    $SetAzDiagnosticSetting_parameters = @{
        ResourceId = $databaseResourceId
        Name = "Send all logs to $failoverRegionPrefix-$resourceNameSuffix-law"
        WorkspaceId = $logAnalyticsWorkspaceResourceId
        Category = @('SQLInsights','AutomaticTuning','QueryStoreRuntimeStatistics','QueryStoreWaitStatistics','Errors','DatabaseWaitStatistics','Timeouts','Blocks','Deadlocks')
        Enabled = $true
        EnableLog = $true
    }
    Set-AzDiagnosticSetting @setAzDiagnosticSetting_parameters | Out-Null
}

# ======================================================================================================================
# REMOVE ACCESS TO KEY VAULT FOR USER
# ======================================================================================================================

# Remove the Key Vault Crypto Service Encryption User role from the user account as we shouldn't
# retain this access. Recommended to use Azure AD PIM to elevate temporarily.
Write-Verbose -Message "Removing 'Key Vault Crypto Officer' role from the user '$AadUsernamePrincipalName' for the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv' ..." -Verbose
$removeAzRoleAssignment_parameters = @{
    ObjectId = $userId
    RoleDefinitionName = 'Key Vault Crypto Officer'
    Scope = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv"
}
Remove-AzRoleAssignment @removeAzRoleAssignment_parameters | Out-Null
