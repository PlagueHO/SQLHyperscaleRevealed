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
#>

# Configure these variables to suit your needs
$aadUsernamePrincipalName = '<your Azure AD user principal name>' # required when running in Cloud Shell
$primaryRegion = 'East US'
$failoverRegion = 'West US 3'
$resourceNameSuffix = 'a1b2'
$environment = 'SQL Hyperscale Revealed demo'
$tags = @{ Environment = $environment }

# Variables to help with resource naming in the script.
$baseResourcePrefix = 'sqlhr'
$primaryRegionPrefix = "$($baseResourcePrefix)01"
$failoverRegionPrefix = "$($baseResourcePrefix)02"
$primaryRegionResourceGroupName = "$primaryRegionPrefix-$resourceNameSuffix-rg"
$failoverRegionResourceGroupName = "$failoverRegionPrefix-$resourceNameSuffix-rg"
$subscriptionId = (Get-AzContext).Subscription.Id
$userId = (Get-AzAdUser -UserPrincipalName $aadUsernamePrincipalName).Id

# Create user assigned managed identity for the logical servers in both
# regions to use to access the Key Vault for the TDE protector key.
New-AzUserAssignedIdentity -Name "$baseResourcePrefix-$resourceNameSuffix-umi" `
    -ResourceGroupName $primaryRegionResourceGroupName -Location $primaryRegion -Tag $tags
$userAssignedManagedIdentityId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$baseResourcePrefix-$resourceNameSuffix-umi"

# Prepare the Key Vault for the TDE protector key and grant access the
# user assigned managed identity permission to access the key.
New-AzRoleAssignment -ObjectId $userId -RoleDefinitionName 'Key Vault Crypto Officer' `
    -Scope "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv"

# Generate the TDE protector key in the Key Vault.
Add-AzKeyVaultKey -KeyName "$baseResourcePrefix-$resourceNameSuffix-tdeprotector" `
    -VaultName "$baseResourcePrefix-$resourceNameSuffix-kv" -KeyType 'RSA' -Size 2048 -Tag $tags -Destination Software
$tdeProtectorKeyId = (Get-AzKeyVaultKey -KeyName "$baseResourcePrefix-$resourceNameSuffix-tdeprotector" -VaultName "$baseResourcePrefix-$resourceNameSuffix-kv").Id

# Get the Service Principal Id of the user assigned managed identity.
$servicePrincipalId = (Get-AzADServicePrincipal -DisplayName "$baseResourcePrefix-$resourceNameSuffix-umi").Id

# Assign the Key Vault Crypto Service Encryption User role to the user assigned managed identity
# on the key in the Key Vault.
$tdeProtectorKeyResourceId = "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv/keys/$baseResourcePrefix-$resourceNameSuffix-tdeprotector"
New-AzRoleAssignment -ObjectId $servicePrincipalId -RoleDefinitionName 'Key Vault Crypto Service Encryption User' `
    -Scope $tdeProtectorKeyResourceId

# Prepare the network components required to connect the logical server to the virtual network.
New-AzDnsZone -Name $environment -ResourceGroupName $resourceNameSuffix -Location $primaryRegion

# Create the new SQL logical server without AAD authentication.
# Due to a current issue with the New-AzSqlServer command in Az.Sql 3.11 when -ExternalAdminName
# is specified, we need to add -SqlAdministratorCredentials and then set the AAD administrator
# with the Set-AzSqlServerActiveDirectoryAdministrator command.
$sqlAdministratorCredential = Get-Credential -Message 'Temporary credential for SQL administrator'
New-AzSqlServer -ServerName "$primaryRegionPrefix-$resourceNameSuffix" -ResourceGroupName $primaryRegionResourceGroupName `
    -Location $primaryRegion -ServerVersion '12.0' -PublicNetworkAccess Disabled `
    -SqlAdministratorCredentials $sqlAdministratorCredential `
    -AssignIdentity -IdentityType UserAssigned -UserAssignedIdentityId $userAssignedManagedIdentityId -PrimaryUserAssignedIdentityId $userAssignedManagedIdentityId `
    -KeyId $tdeProtectorKeyId -Tag $tags

$sqlAdministratorsGroupId = (Get-AzADGroup -DisplayName 'SQL Administrators').Id
Set-AzSqlServerActiveDirectoryAdministrator -ObjectId $sqlAdministratorsGroupId -DisplayName 'SQL Administrators' `
    -ServerName "$primaryRegionPrefix-$resourceNameSuffix" -ResourceGroupName $primaryRegionResourceGroupName

# Remove the Key Vault Crypto Service Encryption User role from the user account as we shouldn't
# retain this access. Recommended to use Azure AD PIM to elevate temporarily.
Remove-AzRoleAssignment -ObjectId $userId -RoleDefinitionName 'Key Vault Crypto Officer' `
    -Scope "/subscriptions/$subscriptionId/resourcegroups/$primaryRegionResourceGroupName/providers/Microsoft.KeyVault/vaults/$baseResourcePrefix-$resourceNameSuffix-kv"

# Create the private endpoint, and connect the logical server to it and the virtal network and configure the DNS zone.
$sqlServerResourceId = (Get-AzSqlServer -ServerName "$primaryRegionPrefix-$resourceNameSuffix" -ResourceGroupName $primaryRegionResourceGroupName).ResourceId
$privateLinkServiceConnection = New-AzPrivateLinkServiceConnection -Name "$primaryRegionPrefix-$resourceNameSuffix-pl" `
    -PrivateLinkServiceId $sqlServerResourceId -GroupId 'SqlServer'
$vnet = Get-AzVirtualNetwork -Name "$primaryRegionPrefix-$resourceNameSuffix-vnet" -ResourceGroupName $primaryRegionResourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name 'data_subnet'
New-AzPrivateEndpoint -Name "$primaryRegionPrefix-$resourceNameSuffix-pe" `
    -ResourceGroupName $primaryRegionResourceGroupName -Location $primaryRegion `
    -Subnet $subnet -PrivateLinkServiceConnection $privateLinkServiceConnection -Tag $tags

$privateDnsZone = New-AzPrivateDnsZone -Name 'privatelink.database.windows.net' -ResourceGroupName $primaryRegionResourceGroupName
New-AzPrivateDnsVirtualNetworkLink -Name "$primaryRegionPrefix-$resourceNameSuffix-dnslink" -ResourceGroupName $primaryRegionResourceGroupName `
    -ZoneName 'privatelink.database.windows.net' -VirtualNetworkId $vnet.Id -Tag $tags

$privateDnsZoneConfig = New-AzPrivateDnsZoneConfig -Name 'privatelink.database.windows.net' -PrivateDnsZoneId $privateDnsZone.ResourceId
New-AzPrivateDnsZoneGroup -Name "$primaryRegionPrefix-$resourceNameSuffix-zonegroup" -ResourceGroupName $primaryRegionResourceGroupName `
    -PrivateEndpointName "$primaryRegionPrefix-$resourceNameSuffix-pe" -PrivateDnsZoneConfig $privateDnsZoneConfig
