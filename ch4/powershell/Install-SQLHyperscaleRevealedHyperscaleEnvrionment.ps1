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
    $AadUsernamePrincipalName
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

# Create user assigned managed identity for the logical servers in both
# regions to use to access the Key Vault for the TDE protector key.
Write-Verbose -Message "Creating user assigned managed identity '$baseResourcePrefix-$resourceNameSuffix-umi' for the logical server..." -Verbose
$newAzUserAssignedIdentity_parameters = @{
    Name = "$baseResourcePrefix-$resourceNameSuffix-umi"
    ResourceGroupName = $primaryRegionResourceGroupName
    Location = $primaryRegion
    Tag = $tags
}
New-AzUserAssignedIdentity @newAzUserAssignedIdentity_parameters | Out-Null
$userAssignedManagedIdentityId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$baseResourcePrefix-$resourceNameSuffix-umi"

# Prepare the Key Vault for the TDE protector key and grant access the
# user assigned managed identity permission to access the key.
Write-Verbose -Message "Assigning 'Key Vault Crypto Officer' role to the user '$AadUsernamePrincipalName' for the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv'..." -Verbose
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
$servicePrincipalId = (Get-AzADServicePrincipal -DisplayName "$baseResourcePrefix-$resourceNameSuffix-umi").Id

# Assign the Key Vault Crypto Service Encryption User role to the user assigned managed identity
# on the key in the Key Vault.
Write-Verbose -Message "Assigning 'Key Vault Crypto Service Encryption User' role to '$baseResourcePrefix-$resourceNameSuffix-umi' for the key '$baseResourcePrefix-$resourceNameSuffix-tdeprotector' in the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv' ..." -Verbose
$tdeProtectorKeyResourceId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv/keys/$baseResourcePrefix-$resourceNameSuffix-tdeprotector"
$newAzRoleAssignment_parameters = @{
    ObjectId =$servicePrincipalId
    RoleDefinitionName = 'Key Vault Crypto Service Encryption User'
    Scope = $tdeProtectorKeyResourceId
}
New-AzRoleAssignment @newAzRoleAssignment_parameters | Out-Null

# Create the new SQL logical server without AAD authentication.
# Due to a current issue with the New-AzSqlServer command in Az.Sql 3.11 when -ExternalAdminName
# is specified, we need to add -SqlAdministratorCredentials and then set the AAD administrator
# with the Set-AzSqlServerActiveDirectoryAdministrator command.
Write-Verbose -Message "Creating logical server '$primaryRegionPrefix-$resourceNameSuffix' ..." -Verbose
$sqlAdministratorCredential = Get-Credential -Message 'Temporary credential for SQL administrator'
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

# Remove the Key Vault Crypto Service Encryption User role from the user account as we shouldn't
# retain this access. Recommended to use Azure AD PIM to elevate temporarily.
Write-Verbose -Message "Removing 'Key Vault Crypto Officer' role from the user '$AadUsernamePrincipalName' for the Key Vault '$baseResourcePrefix-$resourceNameSuffix-kv'..." -Verbose
$removeAzRoleAssignment_parameters = @{
    ObjectId = $userId
    RoleDefinitionName = 'Key Vault Crypto Officer'
    Scope = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv"
}
Remove-AzRoleAssignment @removeAzRoleAssignment_parameters | Out-Null

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

# Create the private DNS zone - this is a global resource so only needs to be done once.
Write-Verbose -Message "Creating the private DNS Zone '$privateZone' ..." -Verbose
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
