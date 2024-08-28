#!/bin/bash

# Display Help message
Help()
{
   # Display Help
   echo "Create a new K8s (AKS + ARC) Site."
   echo
   echo "Syntax: ./site-create.sh [-h|r|s]"
   echo "options:"
   echo "h     Print this Help."
   echo "s     Site name (e.g., hq or moura)."
   echo "r     Resource group name (e.g., energy-hq)."
   echo
}

# Check input options
while getopts "hs:r:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      s) # Enter a name
         SITE_NAME=$OPTARG;;
      r) # Enter a name
         RG=$OPTARG;;
     \?) # Invalid option
         Help
         exit;;
   esac
done

# mandatory arguments
if [ ! "$SITE_NAME" ]; then
  echo "arguments -s with site name (e.g., hq or moura) must be provided"
  Help; exit 1
fi

if [ ! "$RG" ]; then
  echo "arguments -r with resource group name (e.g., energy-hq or energy-moura) must be provided"
  Help; exit 1
fi

K8S_NAME=${SITE_NAME}
ACR_NAME=energygrid
VM_SIZE="standard_d2as_v5"
#LOCATION="eastus"
LOCATION="westus"

#
# Create/Get a resource group.
#
rg_query=$(az group list --query "[?name=='$RG']")
if [ "$rg_query" == "[]" ]; then
   echo -e "\nCreating Resource group '$RG'"
   az group create --name ${RG} --location ${LOCATION}
else
   echo "Resource group $RG already exists."
   #RG_ID=$(az group show --name $RESOURCE_GROUP --query id -o tsv)
fi

#
# Create AKS cluster
#
aks_query=$(az aks list --query "[?name=='$K8S_NAME']")
if [ "$aks_query" == "[]" ]; then
   echo -e "\nCreating AKS cluster '$K8S_NAME'"
   az aks create -g ${RG} -n ${K8S_NAME} --enable-managed-identity --node-count 2 --node-vm-size ${VM_SIZE} --enable-addons monitoring --generate-ssh-keys --attach-acr ${ACR_NAME}
else
   echo "AKS cluster $K8S_NAME already exists."

   # Attach using acr-name
   #az aks update -g ${RG} -n ${K8S_NAME} --attach-acr ${ACR_NAME}
fi

# Get cluster credentials to local .kube/config
az aks get-credentials -g ${RG} -n ${K8S_NAME}

# Arc enable the cluster
kubectl config use-context ${K8S_NAME}
az connectedk8s connect --name ${K8S_NAME} --resource-group ${RG}

echo "Created site ${SITE_NAME}"

