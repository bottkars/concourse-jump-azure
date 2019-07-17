#!/usr/bin/env bash
source ~/.env.sh
set -eux
cd ${HOME_DIR}
MYSELF=$(basename $0)
mkdir -p ${LOG_DIR}
exec &> >(tee -a "${LOG_DIR}/${MYSELF}.$(date '+%Y-%m-%d-%H').log")
exec 2>&1
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -n|--NO_DOWNLOAD)
    NO_DOWNLOAD="$2"
    echo $NO_DOWNLOAD
    # shift # past value
    ;;
    -d|--DO_NOT_APPLY_CHANGES)
    NO_APPLY="$2"
    echo $NO_APPLY
    ## shift # past value
    ;;    
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
shift
done

EXPORT_FILE=${HOME_DIR}/$(uuidgen)
om --env "${HOME_DIR}/om_${ENV_NAME}.env"  \
    export-installation --output-file ${EXPORT_FILE}

TOKEN=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -s -H Metadata:true | jq -r .access_token)
AZURE_SUBSCRIPTION_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-08-01" | jq -r .subscriptionId)
AZURE_CLIENT_SECRET=$(curl https://${AZURE_VAULT}.vault.azure.net/secrets/AZURECLIENTSECRET?api-version=2016-10-01 -s -H "Authorization: Bearer ${TOKEN}" | jq -r .value)
AZURE_CLIENT_ID=$(curl https://${AZURE_VAULT}.vault.azure.net/secrets/AZURECLIENTID?api-version=2016-10-01 -s -H "Authorization: Bearer ${TOKEN}" | jq -r .value)
AZURE_TENANT_ID=$(curl https://${AZURE_VAULT}.vault.azure.net/secrets/AZURETENANTID?api-version=2016-10-01 -s -H "Authorization: Bearer ${TOKEN}" | jq -r .value)
PIVNET_UAA_TOKEN=$(curl https://${AZURE_VAULT}.vault.azure.net/secrets/PIVNETUAATOKEN?api-version=2016-10-01 -H "Authorization: Bearer ${TOKEN}" | jq -r .value)

OPS_MANAGER_STORAGE_ACCOUNT=$(terraform output -state ~/pivotal-cf-terraforming-azure-*/terraforming-control-plane/terraform.tfstate ops_manager_storage_account)

export AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
--name ${OPS_MANAGER_STORAGE_ACCOUNT} --resource-group ${ENV_NAME})
export OPSMAN_IMAGE_VERSION=$(grep -A1 'OPSMAN_IMAGE:' ${ENV_DIR}/opsman.yml | tail -n1 | cut -c15- )

export OPSMAN_IMAGE_URI=$(dirname ${OPS_MANAGER_IMAGE_URI})/ops-manager-${OPSMAN_IMAGE_VERSION}.vhd

AZURE_STORAGE_ENDPOINT=$(az storage account show --name ${OPS_MANAGER_STORAGE_ACCOUNT} \
 --resource-group ${ENV_NAME} \
  --query '[primaryEndpoints.blob]' --output tsv)
OPSMAN_LOCAL_IMAGE=${AZURE_STORAGE_ENDPOINT}opsmanagerimage/opsman-image-${OPSMAN_IMAGE_VERSION}.vhd

az storage blob copy start --source-uri $OPSMAN_IMAGE_URI \
 --destination-container opsmanagerimage \
 --destination-blob opsman-image-${OPSMAN_IMAGE_VERSION}.vhd


echo "Querying Blob Copy Status"
while [ $(az storage blob show \
 --name opsman-image-${OPSMAN_IMAGE_VERSION}.vhd\
 --container-name opsmanagerimage \
 --query '[properties.copy.status]' --output tsv) != "success" ]
do
printf '.'
sleep 5
done

az vm delete --name ${ENV_NAME}-ops-manager-vm \
  --resource-group ${ENV_NAME} -y

az image create --resource-group ${ENV_NAME} \
--name ${OPSMAN_IMAGE_VERSION} \
--source ${OPSMAN_LOCAL_IMAGE} \
--location ${LOCATION} \
--os-type Linux


az vm create --name ${ENV_NAME}-ops-manager-vm  --resource-group ${ENV_NAME} \
 --location ${LOCATION} \
 --nics ${ENV_NAME}-ops-manager-nic \
 --image ${OPSMAN_IMAGE_VERSION} \
 --os-disk-name ${OPSMAN_IMAGE_VERSION}-osdisk \
 --admin-username ubuntu \
 --os-disk-size-gb 127 \
 --size Standard_DS2_v2 \
 --storage-sku StandardSSD_LRS \
 --ssh-key-value ${HOME_DIR}/.ssh/authorized_keys

 om --env "${HOME_DIR}/om_${ENV_NAME}.env"  \
    import-installation --installation $EXPORT_FILE

om --env "${HOME_DIR}/om_${ENV_NAME}.env"  \
update-ssl-certificate \
    --certificate-pem "$(cat ${HOME_DIR}/fullchain.cer)" \
    --private-key-pem "$(cat ${HOME_DIR}/${PKS_SUBDOMAIN_NAME}.${PKS_DOMAIN_NAME}.key)"

om --env "${HOME_DIR}/om_${ENV_NAME}.env"  \
    apply-changes --skip-deployed-products    