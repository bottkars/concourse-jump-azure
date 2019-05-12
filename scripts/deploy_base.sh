#!/usr/bin/env bash
function retryop()
{
  retry=0
  max_retries=$2
  interval=$3
  while [ ${retry} -lt ${max_retries} ]; do
    echo "Operation: $1, Retry #${retry}"
    eval $1
    if [ $? -eq 0 ]; then
      echo "Successful"
      break
    else
      let retry=retry+1
      echo "Sleep $interval seconds, then retry..."
      sleep $interval
    fi
  done
  if [ ${retry} -eq ${max_retries} ]; then
    echo "Operation failed: $1"
    exit 1
  fi
}

START_BASE_DEPLOY_TIME=$(date)
echo ${START_BASE_DEPLOY_TIME} starting base deployment
echo "Installing jq"
retryop "apt update && apt install -y jq" 10 30

function get_setting() {
  key=$1
  local value=$(echo $settings | jq ".$key" -r)
  echo $value
}

METADATA=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-08-01")
custom_data_file="/var/lib/cloud/instance/user-data.txt"
settings=$(cat ${custom_data_file})
AZURE_VAULT=$(get_setting AZURE_VAULT)
ADMIN_USERNAME=$(get_setting ADMIN_USERNAME)
ENV_NAME=$(get_setting ENV_NAME)
ENV_SHORT_NAME=$(get_setting ENV_SHORT_NAME)
OPS_MANAGER_IMAGE_URI=$(get_setting OPS_MANAGER_IMAGE_URI)
LOCATION=$(echo $METADATA | jq -r .location)
CONCOURSE_DOMAIN_NAME=$(get_setting CONCOURSE_DOMAIN_NAME)
CONCOURSE_SUBDOMAIN_NAME=$(get_setting CONCOURSE_SUBDOMAIN_NAME)
OPSMAN_USERNAME=$(get_setting OPSMAN_USERNAME)
CONCOURSE_NOTIFICATIONS_EMAIL=$(get_setting CONCOURSE_NOTIFICATIONS_EMAIL)
CONCOURSE_AUTOPILOT=$(get_setting CONCOURSE_AUTOPILOT)
NET_16_BIT_MASK=$(get_setting NET_16_BIT_MASK)
DOWNLOAD_DIR="/datadisks/disk1"
USE_SELF_CERTS=$(get_setting USE_SELF_CERTS)
JUMP_RG=$(echo $METADATA  | jq -r .resourceGroupName)
JUMP_VNET=$(get_setting JUMP_VNET)
HOME_DIR="/home/${ADMIN_USERNAME}"
LOG_DIR="${HOME_DIR}/conductor/logs"
SCRIPT_DIR="${HOME_DIR}/conductor/scripts"
ENV_DIR="${HOME_DIR}/conductor/env"
TEMPLATE_DIR="${HOME_DIR}/conductor/templates"
AZURE_SUBSCRIPTION_ID=$(echo $METADATA | jq -r .subscriptionId)

sudo -S -u ${ADMIN_USERNAME} mkdir -p ${TEMPLATE_DIR}
sudo -S -u ${ADMIN_USERNAME} mkdir -p ${SCRIPT_DIR}
sudo -S -u ${ADMIN_USERNAME} mkdir -p ${ENV_DIR}
sudo -S -u ${ADMIN_USERNAME} mkdir -p ${LOG_DIR}

cp *.sh ${SCRIPT_DIR}
chown ${ADMIN_USERNAME}.${ADMIN_USERNAME} ${SCRIPT_DIR}/*.sh
chmod 755 ${SCRIPT_DIR}/*.sh
chmod +X ${SCRIPT_DIR}/*.sh

cp *.yaml ${TEMPLATE_DIR}
chown ${ADMIN_USERNAME}.${ADMIN_USERNAME} ${TEMPLATE_DIR}/*.yaml
chmod 755 ${TEMPLATE_DIR}/*.yaml

cp *.env ${ENV_DIR}
chown ${ADMIN_USERNAME}.${ADMIN_USERNAME} ${ENV_DIR}/*.env
chmod 755 ${ENV_DIR}/*.env

${SCRIPT_DIR}/vm-disk-utils-0.1.sh

chown ${ADMIN_USERNAME}.${ADMIN_USERNAME} ${DOWNLOAD_DIR}
chmod -R 755 ${DOWNLOAD_DIR}



$(cat <<-EOF > ${HOME_DIR}/.env.sh
#!/usr/bin/env bash
AZURE_VAULT=${AZURE_VAULT}
ENV_NAME="${ENV_NAME}"
ENV_SHORT_NAME="${ENV_SHORT_NAME}"
OPS_MANAGER_IMAGE_URI="${OPS_MANAGER_IMAGE_URI}"
LOCATION="${LOCATION}"
CONCOURSE_DOMAIN_NAME="${CONCOURSE_DOMAIN_NAME}"
CONCOURSE_SUBDOMAIN_NAME="${CONCOURSE_SUBDOMAIN_NAME}"
HOME_DIR="${HOME_DIR}"
OPSMAN_USERNAME="${OPSMAN_USERNAME}"
CONCOURSE_NOTIFICATIONS_EMAIL="${CONCOURSE_NOTIFICATIONS_EMAIL}"
CONCOURSE_AUTOPILOT="${CONCOURSE_AUTOPILOT}"
NET_16_BIT_MASK="${NET_16_BIT_MASK}"
START_BASE_DEPLOY_TIME="${START_BASE_DEPLOY_TIME}"
DOWNLOAD_DIR="${DOWNLOAD_DIR}"
JUMP_VNET="${JUMP_VNET}"
JUMP_RG="${JUMP_RG}"
USE_SELF_CERTS=${USE_SELF_CERTS}
LOG_DIR=${LOG_DIR}
ENV_DIR=${ENV_DIR}
SCRIPT_DIR=${SCRIPT_DIR}
TEMPLATE_DIR=${TEMPLATE_DIR}
EOF
)

chmod 600 ${HOME_DIR}/.env.sh
chown ${ADMIN_USERNAME}.${ADMIN_USERNAME} ${HOME_DIR}/.env.sh

retryop "sudo apt -y install apt-transport-https lsb-release software-properties-common" 10 30
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
     --keyserver packages.microsoft.com \
     --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF

sudo apt-get update

retryop "sudo apt -y install azure-cli unzip" 10 30

retryop "sudo apt -y install ruby ruby-dev gcc build-essential g++" 10 30
sudo gem install cf-uaac

wget -O terraform.zip https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_linux_amd64.zip && \
  unzip terraform.zip && \
  mv terraform /usr/local/bin

wget -O bosh https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-5.4.0-linux-amd64 && \
  chmod +x bosh && \
  mv bosh /usr/local/bin/

wget -O /tmp/bbr.tar https://github.com/cloudfoundry-incubator/bosh-backup-and-restore/releases/download/v1.2.8/bbr-1.2.8.tar && \
  tar xvC /tmp/ -f /tmp/bbr.tar && \
  mv /tmp/releases/bbr /usr/local/bin/


wget -O texplate https://github.com/pivotal-cf/texplate/releases/download/v0.3.0/texplate_linux_amd64  && \
  chmod +x texplate && \
  mv texplate /usr/local/bin/


END_BASE_DEPLOY_TIME=$(date)
echo ${END_BASE_DEPLOY_TIME} end base deployment

echo "Base install finished, now initializing opsman
for install status information, run 'tail -f ${LOG_DIR}/om_init.sh.*.log'"

su ${ADMIN_USERNAME}  -c "nohup ${SCRIPT_DIR}/om_init.sh -h ${HOME_DIR} >/dev/null 2>&1 &"
