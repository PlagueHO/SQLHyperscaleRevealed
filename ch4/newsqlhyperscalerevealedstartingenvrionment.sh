#!/bin/bash

# ======================================================================================================================
# SET SCRIPT PARAMETER DEFAULTS
# ======================================================================================================================
scriptPath=$(dirname $0)
PrimaryRegion='East US'
FailoverRegion='West US 3'
ResourceNameSuffix=''
Environment='SQL Hyperscale Revealed demo'

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

        -u|--use-random-resource-name-suffix)
            shift
            UseRandomResourceNameSuffix=true
            ;;

        -e|--environment)
            shift
            if [[ "$1" != "" ]]; then
                Environment="${1/%\//}"; shift
            else
                echo "E: Arg missing for --environment"; exit 1
            fi
            ;;

        -h|--help)
            echo "Deploys the SQL Hyperscale Revealed starting environment in Azure."
            echo ""
            echo "Usage:"
            echo "    -p\\--primary-region                   The Azure region to use as the primary region."
            echo "    -f\\--failover-region                  The Azure region to use as the failover region."
            echo "    -r\\--resource-name-suffix             The string that will be suffixed into the resource groups and resource names to try to ensure resource names are globally unique. Must be 4 characters or less. Do not specify this if the UseRandomResourceNameSuffix parameter is set."
            echo "    -u\\--use-random-resource-name-suffix  Randomly generates a ResourceNameSuffix value. Do not specify this if the ResourceNameSuffix parameter is set."
            echo "    -e\\--environment                      This string will be used to set the Environment tag in each resource."
            echo "    --help"
            exit 1
            ;;

        *)
            echo "E: Unknown option: $1"; exit 1
            ;;
    esac
done

if [[ "$UseRandomResourceNameSuffix" == true ]]; then
    # This line generates a random string of 4 characters
    ResourceNameSuffix=$(cat /dev/urandom | tr -dc A-Z-a-z | head -c4)
    echo "Random resource name suffix generated is '$ResourceNameSuffix'. Specify this value in the ResourceNameSuffix parameter to redploy the same environment."
fi

if [[ "$ResourceNameSuffix" == "" ]]; then
    echo "E: The resource name suffix is required."
    exit 1
fi

date=$(date +"%Y%m%d%H%M")
az deployment sub create \
    --name "sql-hyperscale-revealed-starting-env-$resourceNameSuffix-$date" \
    --location "$PrimaryRegion" \
    --template-file "$scriptPath/starting_environment.bicep" \
    --parameters "primaryRegion=$PrimaryRegion" "failoverRegion=$FailoverRegion" "resourceNameSuffix=$ResourceNameSuffix" "environment=$Environment"

echo "To redeploy this SQL Hyperscale Revealed starting environment use: ./newsqlhyperscalerevealedstartingenvrionment -p '$PrimaryRegion' -f '$FailoverRegion' -r '$ResourceNameSuffix' -e '$Environment'"
