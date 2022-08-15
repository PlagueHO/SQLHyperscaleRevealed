# Customize the regions you wish to deploy to.
# Ensure these are regional pairs. Check this list:
# https://docs.microsoft.com/azure/availability-zones/cross-region-replication-azure#azure-cross-region-replication-pairings-for-all-geographies
$primaryRegion = 'East US'
$failoverRegion = 'West US 3'

# The string that will be suffixed into the resource groups and resource names.
# This line generates a random string of 4 characters
$resourceNameSuffix = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_} )

# Uncomment this line if you prefer to use your own suffix string
# Ensure to keep it 4 characters or less.
# $resourceNameSuffix = 'a1b2'

# This string will be used to set the Environment tag in each resource and resource group.
# It can be used to easily identify that the resources that created by this script and allows
# the .\delete_environment.ps1 script to delete them.
$environment = 'SQL Hyperscale Reveaeled demo'

New-AzDeployment `
    -Name "sql-hyperscale-revealed-demo-$resourceNameSuffix-$(Get-Date -Format 'yyyyMMddHHmm')" `
    -Location $primaryRegion `
    -TemplateFile (Split-Path -Path $MyInvocation.MyCommand.Path -Parent | Join-Path -ChildPath 'starting_environment.bicep') `
    -TemplateParameterObject @{
        'primaryRegion' = $primaryRegion
        'failoverRegion' = $failoverRegion
        'resourceNameSuffix' = $resourceNameSuffix
        'Environment' = $environment
    }
