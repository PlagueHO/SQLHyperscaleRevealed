<#
    .SYNOPSIS
        Deploys the Azure SQL Hyperscale environment using Azure Bicep and configures it with
        the following requirements:
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
            - Configures the logical server and database to send audit and diagnostic logs to
              the Log Analytics workspace.
            - Creates the fail over region resources, including the logical server and database.

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

    [Parameter(Mandatory = $true, ParameterSetName = 'ResourceNameSuffix', HelpMessage = 'The string that will be suffixed into the resource groups and resource names.')]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,4)]
    [System.String]
    $ResourceNameSuffix,

    [Parameter(Mandatory = $true, ParameterSetName = 'UseRandomResourceNameSuffix')]
    [Switch]
    $UseRandomResourceNameSuffix,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Environment = 'SQL Hyperscale Revealed demo'
)
#>

if ($UseRandomResourceNameSuffix) {
    # This line generates a random string of 4 characters
    $resourceNameSuffix = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_} )
    Write-Verbose -Message "Random resource name suffix generated is '$resourceNameSuffix'. Specify this value in the ResourceNameSuffix parameter to redploy the same environment." -Verbose
}

# Lookup the SID for the SQL Administrators group. This needs to be passed in to the
# Bicep template to configure the Hyperscale logical server administrators.
$sqlAdministratorsGroupId = (Get-AzADGroup -DisplayName 'SQL Administrators').Id

New-AzDeployment `
    -Name "sql-hyperscale-revealed-env-$resourceNameSuffix-$(Get-Date -Format 'yyyyMMddHHmm')" `
    -Location $primaryRegion `
    -TemplateFile (Split-Path -Path $MyInvocation.MyCommand.Path -Parent | Join-Path -ChildPath 'sql_hyperscale_revealed_environment.bicep') `
    -TemplateParameterObject @{
        'primaryRegion' = $PrimaryRegion
        'failoverRegion' = $FailoverRegion
        'resourceNameSuffix' = $ResourceNameSuffix
        'environment' = $Environment
        'sqlAdministratorsGroupId' = $sqlAdministratorsGroupId
    }

    Write-Verbose -Message "To redeploy this SQL Hyperscale Revealed environment use: ./New-SQLHyperscaleRevealedHyperscaleEnvironment.ps1 -PrimaryRegion '$PrimaryRegion' -FailoverRegion '$FailoverRegion' -ResourceNameSuffix '$resourceNameSuffix' -Environment '$Environment'" -Verbose
