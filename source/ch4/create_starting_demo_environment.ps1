# Customize the regions you wish to deploy to.
# Ensure these are regional pairs. Check this list:
# https://docs.microsoft.com/azure/availability-zones/cross-region-replication-azure#azure-cross-region-replication-pairings-for-all-geographies
$primary_region = 'West US 3'
$failover_region = 'East US'

# The string that will be prefixed
$resource_name_prefix = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_} )

# Uncomment this line if you're prefer to use your own prefix string
# Keep it 4 characters or less.
# $resource_name_prefix = 'a1b2'

# These tags will be added to the resources created.
# They can be used to easily identify that the resource is created by this script.
$resource_tags = @{ environment = 'SQL Hyperscale Reveaeled demo' }

# Create the resource groups
Write-Progress -Activity "Creating primary region resource group '$resource_name_prefix-sqlhr01-rg' in '$primary_region'"
New-AzResourceGroup -Name "$resource_name_prefix-sqlhr01-rg" -Location $primary_region -Tag $resource_tags | Out-Null

Write-Progress -Activity "Creating failover region resource group '$resource_name_prefix-sqlhr01-rg' in '$failover_region'"
New-AzResourceGroup -Name "$resource_name_prefix-sqlhr02-rg" -Location $failover_region -Tag $resource_tags | Out-Null
