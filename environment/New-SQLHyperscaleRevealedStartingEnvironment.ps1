<#
    .SYNOPSIS
        Deploys the SQL Hyperscale Revealed starting environment in Azure.

    .PARAMETER PrimaryRegion
        The Azure region to use as the primary region.
        Use this page for a list of Azure regions: https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#azure-regions

    .PARAMETER FailoverRegion
        The Azure region to use as the failover region.
        Use this page for a list of Azure regions: https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#azure-regions

    .PARAMETER ResourceNameSuffix
        The string that will be suffixed into the resource groups and resource names to
        try to ensure resource names are globally unique. Must be 4 characters or less.
        Do not specify this if the UseRandomResourceNameSuffix parameter is set.

    .PARAMETER UseRandomResourceNameSuffix
        Randomly generates a ResourceNameSuffix value.
        Do not specify this if the ResourceNameSuffix parameter is set.

    .PARAMETER Environment
        This string will be used to set the Environment tag in each resource and resource group.
        It can be used to easily identify that the resources that created by this script and allows
        the .\delete_environment.ps1 script to delete them.

    .EXAMPLE
        Deploy the starting environment to Azure in Australia with the resource name suffix of 'a1b2'
        ./New-SQLHyperscaleRevealedStartingEnvironment.ps1 -PrimaryRegion 'Australia East' -FailoverRegion 'Australia Southeast' -ResourceNameSuffix 'a1b2'

    .EXAMPLE
        Deploy the starting environment to Azure in Australia with a random resource name suffix.
        ./New-SQLHyperscaleRevealedStartingEnvironment.ps1 -PrimaryRegion 'Australia East' -FailoverRegion 'Australia Southeast' -UseRandomResourceNameSuffix

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
    $Environment = 'SQL Hyperscale Reveaeled demo'
)

if ($UseRandomResourceNameSuffix) {
    # This line generates a random string of 4 characters
    $resourceNameSuffix = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_} )
    Write-Verbose -Message "Random resource name suffix generated is '$resourceNameSuffix'. Specify this value in the ResourceNameSuffix parameter to redploy the same environment." -Verbose
}

New-AzDeployment `
    -Name "sql-hyperscale-revealed-starting-env-$resourceNameSuffix-$(Get-Date -Format 'yyyyMMddHHmm')" `
    -Location $primaryRegion `
    -TemplateFile (Split-Path -Path $MyInvocation.MyCommand.Path -Parent | Join-Path -ChildPath 'starting_environment.bicep') `
    -TemplateParameterObject @{
        'primaryRegion' = $PrimaryRegion
        'failoverRegion' = $FailoverRegion
        'resourceNameSuffix' = $ResourceNameSuffix
        'Environment' = $Environment
    }

Write-Verbose -Message "To redeploy this SQL Hyperscale Revealed starting environment use: ./New-SQLHyperscaleRevealedStartingEnvironment.ps1 -PrimaryRegion '$PrimaryRegion' -FailoverRegion '$FailoverRegion' -ResourceNameSuffix '$resourceNameSuffix' -Environment '$Environment'" -Verbose
