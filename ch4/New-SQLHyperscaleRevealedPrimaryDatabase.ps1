<#
    .SYNOPSIS
        Deploys the Hyperscale database to an existing starting envrionment in Azure.

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

    .EXAMPLE
        Deploy the primary Hyperscale database and related resources to Azure in Australia with the resource name suffix of 'a1b2'
        ./New-SQLHyperscaleRevealedPrimaryDatabase.ps1 -PrimaryRegion 'Australia East' -FailoverRegion 'Australia Southeast' -ResourceNameSuffix 'a1b2'
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
    $Environment = 'SQL Hyperscale Revealed demo'
)

New-AzDeployment `
    -Name "sql-hyperscale-revealed-database-$resourceNameSuffix-$(Get-Date -Format 'yyyyMMddHHmm')" `
    -Location $primaryRegion `
    -TemplateFile (Split-Path -Path $MyInvocation.MyCommand.Path -Parent | Join-Path -ChildPath 'hyperscale_primary_region.bicep') `
    -TemplateParameterObject @{
        'primaryRegion' = $primaryRegion
        'failoverRegion' = $failoverRegion
        'resourceNameSuffix' = $resourceNameSuffix
        'environment' = $Environment
    }

Write-Verbose -Message "To redeploy this SQL Hyperscale Revealed database use: ./New-SQLHyperscaleRevealedStartingEnvironment.ps1 -PrimaryRegion '$PrimaryRegion' -FailoverRegion '$FailoverRegion' -ResourceNameSuffix '$resourceNameSuffix' -Environment '$Environment'" -Verbose
