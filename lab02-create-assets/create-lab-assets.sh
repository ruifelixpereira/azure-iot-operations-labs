#!/bin/bash

# Display Help message
Help()
{
   # Display Help
   echo "Create IoT Operations Assets."
   echo
   echo "Syntax: ./create-lab-assets.sh [-h|r|s]"
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
CUSTOM_LOCATION=${K8S_NAME}-cl

#
# Create Asset endpoints
#
ASSET_ENDPOINT="opc-ua-connector-0"

ae_query=$(az iot ops asset endpoint query --custom-location ${CUSTOM_LOCATION} --query "[?name=='$ASSET_ENDPOINT']")
if [ "$ae_query" == "[]" ]; then
   echo -e "\nCreating Asset endpoint '$ASSET_ENDPOINT'"
   az iot ops asset endpoint create --name ${ASSET_ENDPOINT} -g ${RG} --custom-location ${CUSTOM_LOCATION} --target-address "opc.tcp://opcplc-000000:50000"

   # Configure OPC PLC Simulator (that generates sample data)
   kubectl patch AssetEndpointProfile ${ASSET_ENDPOINT} -n azure-iot-operations --type=merge -p '{"spec":{"additionalConfiguration":"{\"applicationName\":\"opc-ua-connector-0\",\"security\":{\"autoAcceptUntrustedServerCertificates\":true}}"}}'

   # Force changes
   pod_name=$(kubectl get pods -n azure-iot-operations | awk '{print $1}' | grep -e "aio-opc-supervisor")
   kubectl delete pod $pod_name -n azure-iot-operations
else
   echo "Asset endpoint $ASSET_ENDPOINT already exists."
fi

#
# Create Assets
#
ASSET_NAME="thermostat"

asset_query=$(az iot ops asset query --custom-location ${CUSTOM_LOCATION} --query "[?name=='$ASSET_NAME']")
if [ "$asset_query" == "[]" ]; then
   echo -e "\nCreating Asset '$ASSET_NAME'"
   az iot ops asset create \
     --name ${ASSET_NAME} \
     -g ${RG} \
     --custom-location ${CUSTOM_LOCATION} \
     --endpoint ${ASSET_ENDPOINT} \
     --description "A simulated thermostat asset" \
     --custom-attribute "batch=102" "customer=Contoso" "equipment=Boiler" "isSpare=true" "location=Seattle" \
     --data-file ./thermostat_tags.csv
else
   echo "Asset $ASSET_NAME already exists."
fi


