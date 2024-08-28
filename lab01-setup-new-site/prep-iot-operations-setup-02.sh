#!/bin/bash

set -e

required_vars=(
    "resource_group"
    "subscription_id"
    "location"
    "k8s_cluster_name"
    "keyvault_name"
)

parse_config_file() {
    local config_file="$1"
    # Parse the configuration file
    while read -r line; do
        key=$(echo "$line" | sed -e 's/[{}"]//g' | awk -F: '{print $1}')
        value=$(echo "$line" | sed -e 's/[{}"]//g' | awk -F: '{print $2}'| xargs)
        case "$key" in
            resource_group) resource_group="$value" ;;
            subscription_id) subscription_id="$value" ;;
            location) location="$value" ;;
            k8s_cluster_name) k8s_cluster_name="$value" ;;
            keyvault_name) keyvault_name="$value" ;;
        esac
    done < <(cat "$config_file" | grep -Eo '"[^"]*"\s*:\s*"[^"]*"')

    # Check if all required variables have been set
    missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    # If we have missing key-value pairs, then print all the pairs that are missing from the config file.
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "Error: Missing required values in config file:"
        for var in "${missing_vars[@]}"; do
            echo "  $var"
        done
        exit 1
    fi
}

# Set the current directory to where the script lives.
cd "$(dirname "$0")"

# Function to display usage information
usage() {
    echo "Usage: $0 [-c|--config-file] <SETTINGS_FILE_PATH>"
    echo ""
    echo "Example:"
    echo "  $0 -c settings.json"
}

check_argument_value() {
    if [[ -z "$2" ]]; then
        echo "Error: Missing value for option $1"
        usage
        exit 1
    fi
}

# Function to check if all required arguments have been set
check_required_arguments() {
    # Array to store the names of the missing arguments
    local missing_arguments=()

    # Loop through the array of required argument names
    for arg_name in "${required_vars[@]}"; do
        # Check if the argument value is empty
        if [[ -z "${!arg_name}" ]]; then
            # Add the name of the missing argument to the array
            missing_arguments+=("${arg_name}")
        fi
    done

    # Check if any required argument is missing
    if [[ ${#missing_arguments[@]} -gt 0 ]]; then
        echo -e "\nError: Missing required arguments:"
        printf '  %s\n' "${missing_arguments[@]}"
        [ ! \( \( $# == 1 \) -a \( "$1" == "-c" \) \) ] && echo "  Either provide a config file path or all the arguments, but not both at the same time."
        [ ! \( $# == 22 \) ] && echo "  All arguments must be provided."
        echo ""
        usage
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--config-file)
    config_file="$2"
    parse_config_file "$config_file"
    shift # past argument
    shift # past value
    break # break out of case statement if config file is provided
    ;;
    -h|--help)
    usage
    exit 0
    ;;
    *)
    echo "Unknown argument: $key"
    usage
    exit 1
esac
done

# Check if all required arguments have been set
check_required_arguments

az account set --subscription "$subscription_id"

# Resource group
rg_query=$(az group list --query "[?name=='$resource_group']")
if [ "$rg_query" == "[]" ]; then
    echo -e "\nCreating the Resource Group '$resource_group'"
    az group create --location $location --resource-group $resource_group --subscription $subscription_id
else
    echo "Resource group $resource_group already exists."
    location=$(az group show --name $resource_group --query location -o tsv)
fi

# Set K8s context
kubectl config use-context $k8s_cluster_name

# Arc enable the cluster
arc_query=$(az connectedk8s list --resource-group "$resource_group" --query "[?name=='$k8s_cluster_name']")
if [ "$arc_query" == "[]" ]; then
    echo -e "\nArc enabling the K8S cluster '$k8s_cluster_name'"
    az connectedk8s connect --name ${k8s_cluster_name} --resource-group ${resource_group}
else
    echo "K8S cluster $k8s_cluster_name is already ARC enabled."
fi

# Enable custom location support on your cluster.
# This command uses the objectId of the Microsoft Entra ID application that the Azure Arc service uses:
export OBJECT_ID=$(az ad sp show --id bc313c14-388c-4e7d-a58e-70017303ee3b --query id -o tsv)
az connectedk8s enable-features -n $k8s_cluster_name -g $resource_group --custom-locations-oid $OBJECT_ID --features cluster-connect custom-locations

# Install az extension
az extension add --upgrade --name azure-iot-ops

# Verify cluster
az iot ops verify-host

# To create a new key vault, with Permission model set to Vault access policy.
kv_query=$(az keyvault list --resource-group "$resource_group" --query "[?name=='$keyvault_name']")
if [ "$kv_query" == "[]" ]; then
    echo -e "\nCreating Key vault '$keyvault_name'"
    az keyvault create --enable-rbac-authorization false --name ${keyvault_name} --resource-group ${resource_group}
else
    echo "Key vault $keyvault_name already exists."
fi

exit 0