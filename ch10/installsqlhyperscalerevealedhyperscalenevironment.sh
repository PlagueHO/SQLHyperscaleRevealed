#!/bin/bash

# ======================================================================================================================
# SET SCRIPT PARAMETER DEFAULTS
# ======================================================================================================================
PrimaryRegion='East US'
FailoverRegion='West US 3'
ResourceNameSuffix=''
Environment='SQL Hyperscale Revealed demo'
AadUserPrincipalName=''
NoFailoverRegion=false

# ======================================================================================================================
# PROCESS THE SCRIPT PARAMETERS
# ======================================================================================================================
while [[ $# > 0 ]]
do
    case "$1" in

        -p|--primary-region)
            shift
            if [[ "$1" != "" ]]; then
                PrimaryRegion="${1/%\//}"; shift
            else
                echo "E: Arg missing for --primary-region option"; exit 1
            fi
            ;;

        -f|--failover-region)
            shift
            if [[ "$1" != "" ]]; then
                FailoverRegion="${1/%\//}"; shift
            else
                echo "E: Arg missing for --failover-region option"; exit 1
            fi
            ;;

        -r|--resource-name-suffix)
            shift
            if [[ "$1" != "" ]]; then
                ResourceNameSuffix="${1/%\//}"; shift
            else
                echo "E: Arg missing for --resource-name-suffix"; exit 1
            fi
            ;;

        -e|--environment)
            shift
            if [[ "$1" != "" ]]; then
                Environment="${1/%\//}"; shift
            else
                echo "E: Arg missing for --environment"; exit 1
            fi
            ;;

        -u|--aad-user-principal-name)
            shift
            if [[ "$1" != "" ]]; then
                AadUserPrincipalName="${1/%\//}"; shift
            else
                echo "E: Arg missing for --aad-user-principal-name"; exit 1
            fi
            ;;

        --no-failover-region)
            shift
            NoFailoverRegion=true
            ;;

        -h|--help)
            echo "Deploys the Hyperscale database and configures it with the following requirements:"
            echo "- Creates user assigned managed identity for the Hyperscale database."
            echo "- Generates TDE protector key in Key Vault."
            echo "- Reconfigures the primary region virtual network to add AzureBastionSubnet and management_Subnet."
            echo "- Logical server (SQL Server) in primary region with user assigned managed identity, TDE customer-managed key, only allowing Azure AD authentication with the SQL admin set to the SQL Administrators group."
            echo "- Add networking components required to connect the Hyperscale database to the primary region virtual network: Private Link, DNS Zone."
            echo "- Connects primary region logical server to VNET in primary region."
            echo "- Creates the Hyperscale database in the primary region logical server with 2 AZ enabled replicas and Geo-zone-redundant backups."
            echo "- Configures the logical server and database to send audit and diagnostic logs to the Log Analytics workspace."
            echo "- Creates the fail over region resources, including the logical server and database."
            echo ""
            echo "Usage:"
            echo "    -p\\--primary-region           The Azure region to use as the primary region."
            echo "    -f\\--failover-region          The Azure region to use as the failover region."
            echo "    -r\\--resource-name-suffix     The string that will be suffixed into the resource names to try to ensure resource names are globally unique."
            echo "    -e\\--environment              This string will be used to set the Environment tag in each resource."
            echo "    -u\\--aad-user-principal-name  The Azure AD principal user account name running this script."
            echo "    --no-failover-region           This switch prevents deployment of the resources in the failover region."
            echo "    --help"
            exit 1
            ;;

        *)
            echo "E: Unknown option: $1"; exit 1
            ;;
    esac
done

if [[ "$ResourceNameSuffix" == "" ]]; then
    echo "E: The resource name suffix is required."
    exit 1
fi

if [[ "$AadUserPrincipalName" == "" ]]; then
    echo "E: The Azure AD principal user account name running this script is required."
    exit 1
fi

# Variables to help with resource naming in the script.
baseResourcePrefix='sqlhr'
primaryRegionPrefix=$baseResourcePrefix'01'
failoverRegionPrefix=$baseResourcePrefix'02'
primaryRegionResourceGroupName=$primaryRegionPrefix-$ResourceNameSuffix-rg
failoverRegionResourceGroupName=$failoverRegionPrefix-$ResourceNameSuffix-rg
subscriptionId="$(az account list --query "[?isDefault].id" -o tsv)"
userId="$(az ad user show --id $AadUserPrincipalName --query 'id' -o tsv)"
privateZone='privatelink.database.windows.net'
sqlAdministratorsGroupSid="$(az ad group show --group 'SQL Administrators' --query 'id' -o tsv)"

# ======================================================================================================================
# VIRTUAL NETWORK PREPARATION FOR MANAGEMENT AND BASTION SUBNETS
# ======================================================================================================================

# Update the VNET subnets to add the management and Bastion subnets in case
# they are needed for the management VM and Azure Bastion - although we won't
# deploy these resources in this script. This is just here for convenience.
echo "Adding 'management_subnet' and 'AzureBastionSubnet' to the primary virtual network '$baseResourcePrefix-$ResourceNameSuffix-vnet' ..."
az network vnet subnet create \
    --resource-group "$primaryRegionResourceGroupName" \
    --vnet-name "$primaryRegionPrefix-$ResourceNameSuffix-vnet" \
    --name 'management_subnet' --address-prefixes 10.0.3.0/24 \
    --output none
az network vnet subnet create \
    --resource-group "$primaryRegionResourceGroupName" \
    --vnet-name "$primaryRegionPrefix-$ResourceNameSuffix-vnet" \
    --name 'AzureBastionSubnet' --address-prefixes 10.0.4.0/24 \
    --output none
echo "Adding 'management_subnet' and 'AzureBastionSubnet' to the failover virtual network '$baseResourcePrefix-$ResourceNameSuffix-vnet' ..."
az network vnet subnet create \
    --resource-group "$failoverRegionResourceGroupName" \
    --vnet-name "$failoverRegionPrefix-$ResourceNameSuffix-vnet" \
    --name 'management_subnet' --address-prefixes 10.1.3.0/24 \
    --output none
az network vnet subnet create \
    --resource-group "$failoverRegionResourceGroupName" \
    --vnet-name "$failoverRegionPrefix-$ResourceNameSuffix-vnet" \
    --name 'AzureBastionSubnet' --address-prefixes 10.1.4.0/24 \
    --output none

# ======================================================================================================================
# PREPARE USER ASSIGNED MANAGED IDENTITY FOR THE HYPERSCALE DATABASES
# ======================================================================================================================

# Create user assigned managed identity for the logical servers in both
# regions to use to access the Key Vault for the TDE protector key.
echo "Creating user assigned managed identity '$baseResourcePrefix-$ResourceNameSuffix-umi' for the logical server ..."
az identity create \
    --name "$baseResourcePrefix-$ResourceNameSuffix-umi" \
    --resource-group "$primaryRegionResourceGroupName" \
    --location "$primaryRegion" \
    --tags Environment="$Environment" \
    --output none
userAssignedManagedIdentityId="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.ManagedIdentity"\
"/userAssignedIdentities/$baseResourcePrefix-$ResourceNameSuffix-umi"

# ======================================================================================================================
# PREPARE CUSTOMER-MANAGED TDE PROTECTOR KEY IN KEY VAULT
# ======================================================================================================================

# Prepare the Key Vault for the TDE protector key and grant access the
# user assigned managed identity permission to access the key.
echo "Assigning 'Key Vault Crypto Officer' role to the user '$AadUserPrincipalName' for the Key Vault '$baseResourcePrefix-$ResourceNameSuffix-kv' ..."
scope="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.KeyVault"\
"/vaults/$baseResourcePrefix-$ResourceNameSuffix-kv"
az role assignment create \
    --role 'Key Vault Crypto Officer' \
    --assignee-object-id "$userId" \
    --assignee-principal-type User \
    --scope "$scope" \
    --output none

# Generate the TDE protector key in the Key Vault.
echo "Creating the TDE Protector Key '$baseResourcePrefix-$ResourceNameSuffix-tdeprotector' in the Key Vault '$baseResourcePrefix-$ResourceNameSuffix-kv' ..."
az keyvault key create \
    --name "$baseResourcePrefix-$ResourceNameSuffix-tdeprotector" \
    --vault-name "$baseResourcePrefix-$ResourceNameSuffix-kv" \
    --kty RSA \
    --size 2048 \
    --ops encrypt decrypt \
    --tags Environment="$Environment" \
    --output none
tdeProtectorKeyId="$(az keyvault key show --name "$baseResourcePrefix-$ResourceNameSuffix-tdeprotector" --vault-name "$baseResourcePrefix-$ResourceNameSuffix-kv" --query 'key.kid' -o tsv)"

# Get the Service Principal Id of the user assigned managed identity.
# This may take a few seconds to propagate, so wait for it.
servicePrincipalId="$(az ad sp list --display-name "$baseResourcePrefix-$ResourceNameSuffix-umi" --query '[0].id' -o tsv)"
while [[ "$servicePrincipalId" == "" ]]
do
    echo "Waiting for the service principal of user assigned managed identity '$baseResourcePrefix-$ResourceNameSuffix-umi' to be available ..."
    sleep 5
    servicePrincipalId="$(az ad sp list --display-name "$baseResourcePrefix-$ResourceNameSuffix-umi" --query '[0].id' -o tsv)"
done

# Assign the Key Vault Crypto Service Encryption User role to the user assigned managed identity
# on the key in the Key Vault.
echo "Assigning 'Key Vault Crypto Service Encryption User' role to '$baseResourcePrefix-$ResourceNameSuffix-umi' for the key '$baseResourcePrefix-$ResourceNameSuffix-tdeprotector' in the Key Vault '$baseResourcePrefix-$ResourceNameSuffix-kv' ..."
scope="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.KeyVault"\
"/vaults/$baseResourcePrefix-$ResourceNameSuffix-kv"\
"/keys/$baseResourcePrefix-$ResourceNameSuffix-tdeprotector"
az role assignment create \
    --role 'Key Vault Crypto Service Encryption User' \
    --assignee-object-id "$servicePrincipalId" \
    --assignee-principal-type ServicePrincipal \
    --scope "$scope" \
    --output none

# ======================================================================================================================
# DEPLOY LOGICAL SERVER IN PRIMARY REGION
# ======================================================================================================================

# Create the primary SQL logical server without AAD authentication.
echo "Creating logical server '$primaryRegionPrefix-$ResourceNameSuffix' ..."
az sql server create \
    --name "$primaryRegionPrefix-$ResourceNameSuffix" \
    --resource-group "$primaryRegionResourceGroupName" \
    --location "$primaryRegion" \
    --enable-ad-only-auth \
    --assign-identity \
    --identity-type UserAssigned \
    --user-assigned-identity-id "$userAssignedManagedIdentityId" \
    --primary-user-assigned-identity-id "$userAssignedManagedIdentityId" \
    --key-id "$tdeProtectorKeyId" \
    --external-admin-principal-type Group \
    --external-admin-name 'SQL Administrators' \
    --external-admin-sid "$sqlAdministratorsGroupSid" \
    --output none

# ======================================================================================================================
# CONNECT LOGICAL SERVER IN PRIMARY REGION TO VIRTUAL NETWORK
# ======================================================================================================================

# Create the private endpoint, and connect the logical server to it and the virtal network and configure the DNS zone.
# Create the private link service connection
echo "Creating the private endpoint '$primaryRegionPrefix-$ResourceNameSuffix-pl' for the logical server '$primaryRegionPrefix-$ResourceNameSuffix' ..."
sqlServerResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.Sql"\
"/servers/$primaryRegionPrefix-$ResourceNameSuffix"
az network private-endpoint create \
    --name "$primaryRegionPrefix-$ResourceNameSuffix-pe" \
    --resource-group "$primaryRegionResourceGroupName" \
    --location "$primaryRegion" \
    --vnet-name "$primaryRegionPrefix-$ResourceNameSuffix-vnet" \
    --subnet "data_subnet" \
    --private-connection-resource-id "$sqlServerResourceId" \
    --group-id sqlServer \
    --connection-name "$primaryRegionPrefix-$ResourceNameSuffix-pl" \
    --output none

# Create the private DNS zone.
echo "Creating the private DNS Zone for '$privateZone' in resource group '$primaryRegionResourceGroupName' ..."
az network private-dns zone create \
    --name "$privateZone" \
    --resource-group "$primaryRegionResourceGroupName" \
    --output none

# Connect the private DNS Zone to the primary region VNET.
echo "Connecting the private DNS Zone '$privateZone' to the virtual network '$primaryRegionPrefix-$ResourceNameSuffix-vnet' ..."
az network private-dns link vnet create \
    --name "$primaryRegionPrefix-$ResourceNameSuffix-dnslink" \
    --resource-group "$primaryRegionResourceGroupName" \
    --zone-name "$privateZone" \
    --virtual-network "$primaryRegionPrefix-$ResourceNameSuffix-vnet" \
    --registration-enabled false \
    --output none

# Create the DNS zone group for the private endpoint.
echo "Creating the private DNS Zone Group '$primaryRegionPrefix-$ResourceNameSuffix-zonegroup' and connecting it to the '$primaryRegionPrefix-$ResourceNameSuffix-pe' ..."
az network private-endpoint dns-zone-group create \
    --name "$primaryRegionPrefix-$ResourceNameSuffix-zonegroup" \
    --resource-group "$primaryRegionResourceGroupName" \
    --endpoint-name "$primaryRegionPrefix-$ResourceNameSuffix-pe" \
    --private-dns-zone "$privateZone" \
    --zone-name "$privateZone" \
    --output none

# ======================================================================================================================
# CREATE HYPERSCALE DATABASE IN PRIMARY REGION
# ======================================================================================================================

# Create the hyperscale database in the primary region
echo "Creating the primary hyperscale database in the logical server '$primaryRegionPrefix-$ResourceNameSuffix' ..."
az sql db create \
    --name 'hyperscaledb' \
    --server "$primaryRegionPrefix-$ResourceNameSuffix" \
    --resource-group "$primaryRegionResourceGroupName" \
    --edition 'Hyperscale' \
    --capacity 2 \
    --family 'Gen5' \
    --compute-model 'Provisioned' \
    --ha-replicas 2 \
    --zone-redundant \
    --backup-storage-redundancy 'GeoZone' \
    --tags $tags \
    --output none

# ======================================================================================================================
# CONFIGURE DIAGNOSTIC AND AUDIT LOGS TO SEND TO LOG ANALYTICS
# ======================================================================================================================

# Enable sending primary logical server audit logs to the Log Analytics workspace
echo "Configuring the primary logical server '$primaryRegionPrefix-$ResourceNameSuffix' to send audit logs to the Log Analytics workspace '$primaryRegionPrefix-$ResourceNameSuffix-law' ..."
logAnalyticsWorkspaceResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/microsoft.operationalinsights"\
"/workspaces/$primaryRegionPrefix-$ResourceNameSuffix-law"
az sql server audit-policy update \
    --name "$primaryRegionPrefix-$ResourceNameSuffix" \
    --resource-group "$primaryRegionResourceGroupName" \
    --log-analytics-workspace-resource-id "$logAnalyticsWorkspaceResourceId" \
    --log-analytics-target-state Enabled \
    --state Enabled \
    --output none

# Enable sending database diagnostic logs to the Log Analytics workspace
echo "Configuring the primary hyperscale database 'hyperscaledb' to send all diagnostic logs to the Log Analytics workspace '$primaryRegionPrefix-$ResourceNameSuffix-law' ..."
logAnalyticsWorkspaceResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/microsoft.operationalinsights"\
"/workspaces/$primaryRegionPrefix-$ResourceNameSuffix-law"
databaseResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.Sql"\
"/servers/$primaryRegionPrefix-$ResourceNameSuffix"\
"/databases/hyperscaledb"
logs='[
    {
        "category": "SQLInsights",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "AutomaticTuning",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "QueryStoreRuntimeStatistics",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "Errors",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "DatabaseWaitStatistics",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "Timeouts",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "Blocks",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    },
    {
        "category": "Deadlocks",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    }
]'
az monitor diagnostic-settings create \
    --name "Send all logs to $primaryRegionPrefix-$ResourceNameSuffix-law" \
    --resource "$databaseResourceId" \
    --logs "$logs" \
    --workspace "$logAnalyticsWorkspaceResourceId" \
    --output none

if [[ "$NoFailoverRegion" == false ]]; then
    # ======================================================================================================================
    # DEPLOY LOGICAL SERVER IN FAILOVER REGION
    # ======================================================================================================================

    # Create the failover SQL logical server without AAD authentication.
    echo "Creating logical server '$failoverRegionPrefix-$ResourceNameSuffix' ..."
    az sql server create \
        --name "$failoverRegionPrefix-$ResourceNameSuffix" \
        --resource-group "$failoverRegionResourceGroupName" \
        --location "$failoverRegion" \
        --enable-ad-only-auth \
        --identity-type UserAssigned \
        --user-assigned-identity-id "$userAssignedManagedIdentityId" \
        --primary-user-assigned-identity-id "$userAssignedManagedIdentityId" \
        --key-id "$tdeProtectorKeyId" \
        --external-admin-principal-type Group \
        --external-admin-name 'SQL Administrators' \
        --external-admin-sid "$sqlAdministratorsGroupSid" \
        --output none

    # ======================================================================================================================
    # CONNECT LOGICAL SERVER IN FAILOVER REGION TO VIRTUAL NETWORK
    # ======================================================================================================================

    # Create the private endpoint, and connect the logical server to it and the virtal network and configure the DNS zone.
    # Create the private link service connection
    echo "Creating the private endpoint '$failoverRegionPrefix-$ResourceNameSuffix-pl' for the logical server '$failoverRegionPrefix-$ResourceNameSuffix' ..."
    sqlServerResourceId="/subscriptions/$subscriptionId"\
    "/resourcegroups/$failoverRegionResourceGroupName"\
    "/providers/Microsoft.Sql"\
    "/servers/$failoverRegionPrefix-$ResourceNameSuffix"
    az network private-endpoint create \
        --name "$failoverRegionPrefix-$ResourceNameSuffix-pe" \
        --resource-group "$failoverRegionResourceGroupName" \
        --location "$failoverRegion" \
        --vnet-name "$failoverRegionPrefix-$ResourceNameSuffix-vnet" \
        --subnet "data_subnet" \
        --private-connection-resource-id "$sqlServerResourceId" \
        --group-id sqlServer \
        --connection-name "$failoverRegionPrefix-$ResourceNameSuffix-pl" \
        --output none

    # Create the private DNS zone.
    echo "Creating the private DNS Zone for '$privateZone' in resource group '$failoverRegionResourceGroupName' ..."
    az network private-dns zone create \
        --name "$privateZone" \
        --resource-group "$failoverRegionResourceGroupName" \
        --output none

    # Connect the private DNS Zone to the failover region VNET.
    echo "Connecting the private DNS Zone '$privateZone' to the virtual network '$failoverRegionPrefix-$ResourceNameSuffix-vnet' ..."
    az network private-dns link vnet create \
        --name "$failoverRegionPrefix-$ResourceNameSuffix-dnslink" \
        --resource-group "$failoverRegionResourceGroupName" \
        --zone-name "$privateZone" \
        --virtual-network "$failoverRegionPrefix-$ResourceNameSuffix-vnet" \
        --registration-enabled false \
        --output none

    # Create the DNS zone group for the private endpoint.
    echo "Creating the private DNS Zone Group '$failoverRegionPrefix-$ResourceNameSuffix-zonegroup' and connecting it to the '$failoverRegionPrefix-$ResourceNameSuffix-pe' ..."
    az network private-endpoint dns-zone-group create \
        --name "$failoverRegionPrefix-$ResourceNameSuffix-zonegroup" \
        --resource-group "$failoverRegionResourceGroupName" \
        --endpoint-name "$failoverRegionPrefix-$ResourceNameSuffix-pe" \
        --private-dns-zone "$privateZone" \
        --zone-name "$privateZone" \
        --output none

    # ======================================================================================================================
    # CREATE REPLICA HYPERSCALE DATABASE IN FAILOVER REGION
    # ======================================================================================================================

    # Establish the active geo-replication from the primary region to the failover region.
    echo "Creating the geo-replica 'hyperscaledb' from '$primaryRegionPrefix-$ResourceNameSuffix' to '$failoverRegionPrefix-$ResourceNameSuffix' ..."
    az sql db replica create \
        --name "hyperscaledb" \
        --resource-group "$primaryRegionResourceGroupName" \
        --server "$primaryRegionPrefix-$ResourceNameSuffix" \
        --partner-resource-group "$failoverRegionResourceGroupName" \
        --partner-server "$failoverRegionPrefix-$ResourceNameSuffix" \
        --secondary-type Geo \
        --family Gen5 \
        --capacity 2 \
        --zone-redundant false \
        --ha-replicas 1 \
        --read-scale "Enabled" \
        --output none

    # ======================================================================================================================
    # CONFIGURE DIAGNOSTIC AND AUDIT LOGS TO SEND TO LOG ANALYTICS
    # ======================================================================================================================

    # Enable sending failover logical server audit logs to the Log Analytics workspace
    echo "Configuring the failover logical server '$failoverRegionPrefix-$ResourceNameSuffix' to send audit logs to the Log Analytics workspace '$failoverRegionPrefix-$ResourceNameSuffix-law' ..."
    logAnalyticsWorkspaceResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$failoverRegionResourceGroupName"\
"/providers/microsoft.operationalinsights"\
"/workspaces/$failoverRegionPrefix-$ResourceNameSuffix-law"
    az sql server audit-policy update \
        --name "$failoverRegionPrefix-$ResourceNameSuffix" \
        --resource-group "$failoverRegionResourceGroupName" \
        --log-analytics-workspace-resource-id "$logAnalyticsWorkspaceResourceId" \
        --log-analytics-target-state Enabled \
        --state Enabled \
        --output none

    # Enable sending database diagnostic logs to the Log Analytics workspace
    echo "Configuring the failover hyperscale database 'hyperscaledb' to send all diagnostic logs to the Log Analytics workspace '$failoverRegionPrefix-$ResourceNameSuffix-law' ..."
    logAnalyticsWorkspaceResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$failoverRegionResourceGroupName"\
"/providers/microsoft.operationalinsights"\
"/workspaces/$failoverRegionPrefix-$ResourceNameSuffix-law"
    databaseResourceId="/subscriptions/$subscriptionId"\
"/resourcegroups/$failoverRegionResourceGroupName"\
"/providers/Microsoft.Sql"\
"/servers/$failoverRegionPrefix-$ResourceNameSuffix"\
"/databases/hyperscaledb"
    logs='[
        {
            "category": "SQLInsights",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "AutomaticTuning",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "QueryStoreRuntimeStatistics",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "Errors",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "DatabaseWaitStatistics",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "Timeouts",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "Blocks",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        },
        {
            "category": "Deadlocks",
            "enabled": true,
            "retentionPolicy": {
                "enabled": false,
                "days": 0
            }
        }
    ]'
    az monitor diagnostic-settings create \
        --name "Send all logs to $failoverRegionPrefix-$ResourceNameSuffix-law" \
        --resource "$databaseResourceId" \
        --logs "$logs" \
        --workspace "$logAnalyticsWorkspaceResourceId" \
        --output none
fi

# ======================================================================================================================
# REMOVE ACCESS TO KEY VAULT FOR USER
# ======================================================================================================================

# Remove the Key Vault Crypto Service Encryption User role from the user account as we shouldn't
# retain this access. Recommended to use Azure AD PIM to elevate temporarily.
echo "Removing 'Key Vault Crypto Officer' role from the user '$AadUserPrincipalName' for the Key Vault '$baseResourcePrefix-$ResourceNameSuffix-kv' ..."
scope="/subscriptions/$subscriptionId"\
"/resourcegroups/$primaryRegionResourceGroupName"\
"/providers/Microsoft.KeyVault"\
"/vaults/$baseResourcePrefix-$ResourceNameSuffix-kv"
az role assignment delete \
    --assignee "$userId" \
    --role "Key Vault Crypto Officer" \
    --scope "$scope" \
    --output none
