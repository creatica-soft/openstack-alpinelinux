#!/usr/bin/bash

# The script interactively creates a sample cloud image, a volume, flavors, networks, a router, a floating IP,
# a key pair, a security group, a floating IP and a server

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variable in common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo "source /root/admin_openrc"
if [[ -f /root/admin-openrc ]]; then
  source /root/admin-openrc
else
  echo "/root/admin-openrc file is not found. Unable to continue. Please source your openrc file first"
  exit 1
fi

if [[ ! -v OS_PROJECT_DOMAIN_NAME ]] || [[ ! -v OS_USER_DOMAIN_NAME ]] || [[ ! -v OS_PROJECT_NAME ]] || [[ ! -v OS_USERNAME ]] || [[ ! -v OS_PASSWORD ]] || [[ ! -v OS_AUTH_URL ]] || [[ ! -v OS_IDENTITY_API_VERSION ]] || [[ ! -v OS_IMAGE_API_VERSION ]]; then 
  echo "Please source your admin-openrc file first, then try again" 
  exit 1
fi

# Automated openstack alpine image build
read -p "Build Openstack alpine image ${SAMPLE_IMAGE_FILE} using packer and qemu on ${COMPUTE_NODE_NAME}-1? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  SSH="ssh ${COMPUTE_NODE_NAME}-1"
  echo 'allow virbr0' | ${SSH} tee -a /etc/qemu/bridge.conf
  ${SSH} wget -O /tmp/${PACKER_ARCHIVE} ${PACKER_URL}
  ${SSH} unzip /tmp/${PACKER_ARCHIVE} -d /root/vm/
  ${SSH} rm -f /tmp/${PACKER_ARCHIVE}
  envsubst '${SAMPLE_IMAGE_URL}${SAMPLE_IMAGE_FILE}' < ${BASE_DIR}/vm/alpine-qemu.json.template | ${SSH} dd status=none of=/root/vm/alpine-qemu.json
  ${SSH} mkdir -p /root/vm/http /root/vm/scripts
  scp ${BASE_DIR}/vm/http/answers ${COMPUTE_NODE_NAME}-1:/root/vm/http
  scp ${BASE_DIR}/vm/scripts/provision.sh ${COMPUTE_NODE_NAME}-1:/root/vm/scripts/
  ${SSH} "cd /root/vm; /root/vm/packer build /root/vm/alpine-qemu.json"
  scp ${COMPUTE_NODE_NAME}-1:/root/vm/output_alpine/${SAMPLE_IMAGE_FILE}.raw ${BASE_DIR}/vm/
fi

read -p "Create glance image ${SAMPLE_NAME} from the converted raw sample OS image? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack image create --public --file ${BASE_DIR}/vm/${SAMPLE_IMAGE_FILE}.raw --property hw_scsi_model=virtio-scsi --property hw_disk_bus=scsi --property hw_qemu_guest_agent=yes --property os_require_quiesce=yes ${SAMPLE_IMAGE_FILE}
fi

read -p "Create sample flavors? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack flavor create --public --vcpu 1 --ram 2048 --disk 0 public.1c.2r.0d
  openstack flavor create --public --vcpu 2 --ram 4096 --disk 0 public.2c.4r.0d
  openstack flavor create --public --vcpu 1 --ram 2048 --disk 2 public.1c.2r.2d
  openstack flavor create --public --vcpu 2 --ram 4096 --disk 4 public.2c.4r.4d
  openstack flavor create --public --vcpu 1 --ram 2048 --disk 8 public.1c.2r.8d
  openstack flavor create --public --vcpu 2 --ram 4096 --disk 8 public.2c.4r.8d
fi

read -p "Create a bootable volume from the sample image ${SAMPLE_NAME}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack volume create --bootable --size ${SAMPLE_VOLUME_SIZE} --image ${SAMPLE_IMAGE_FILE} ${SAMPLE_NAME}
fi

read -p "Create a default internal network ${DEFAULT_INTERNAL_NETWORK}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack network create --default ${DEFAULT_INTERNAL_NETWORK}
#  openstack subnet create --network ${DEFAULT_INTERNAL_NETWORK} --subnet-range ${DEFAULT_INTERNAL_NETWORK_CIDR} --gateway ${DEFAULT_INTERNAL_NETWORK_GATEWAY} --dns-nameserver ${DEFAULT_INTERNAL_NETWORK_DNS} --allocation-pool ${DEFAULT_INTERNAL_NETWORK_POOL} --host-route destination=169.254.169.254/32,gateway=${OVN_METADATA_PORT_IP} ${DEFAULT_INTERNAL_NETWORK}
  openstack subnet create --network ${DEFAULT_INTERNAL_NETWORK} --subnet-range ${DEFAULT_INTERNAL_NETWORK_CIDR} --gateway ${DEFAULT_INTERNAL_NETWORK_GATEWAY} --dns-nameserver ${DEFAULT_INTERNAL_NETWORK_DNS} --allocation-pool ${DEFAULT_INTERNAL_NETWORK_POOL} ${DEFAULT_INTERNAL_NETWORK}
  openstack port create --fixed-ip subnet=${DEFAULT_INTERNAL_NETWORK},ip-address=${DEFAULT_INTERNAL_NETWORK_GATEWAY} --disable-port-security --network ${DEFAULT_INTERNAL_NETWORK} internal-gateway
#  openstack port create --network ${DEFAULT_INTERNAL_NETWORK} --device-owner network:distributed --fixed-ip ip-address=${OVN_METADATA_PORT_IP} ovn-metadata
fi

read -p "Create a public network ${DEFAULT_EXTERNAL_NETWORK}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack network create --external --provider-physical-network provider --provider-network-type flat ${DEFAULT_EXTERNAL_NETWORK}
  openstack subnet create --network ${DEFAULT_EXTERNAL_NETWORK} --subnet-range ${DEFAULT_EXTERNAL_NETWORK_CIDR} --gateway ${DEFAULT_EXTERNAL_NETWORK_GATEWAY} --no-dhcp --allocation-pool ${DEFAULT_EXTERNAL_NETWORK_POOL} ${DEFAULT_EXTERNAL_NETWORK}
  #openstack port create --fixed-ip subnet=${DEFAULT_EXTERNAL_NETWORK},ip-address=${DEFAULT_EXTERNAL_NETWORK_GATEWAY} --disable-port-security --network ${DEFAULT_EXTERNAL_NETWORK} external-gateway
fi

read -p "Create a router? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack router create router
  openstack router set --enable-snat --external-gateway ${DEFAULT_EXTERNAL_NETWORK} router
  openstack router add port router internal-gateway
fi

read -p "Create ubuntu rsa keypair? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack keypair create --private-key ~/.ssh/ubuntu ubuntu
fi

read -p "Create a server? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack server create --flavor public.1c.2r.0d --key-name ubuntu --volume ${SAMPLE_NAME} --network ${DEFAULT_INTERNAL_NETWORK} ${SAMPLE_NAME}
fi

read -p "Create a floating IP? [y/N]"
REPLY=`echo ${REPLY}|cut -c1`
if [[ "${REPLY}" == "y" ]]; then
  openstack floating ip create ${DEFAULT_EXTERNAL_NETWORK}
  FLOATING_IP=`openstack floating ip list -f value|cut -f2 -d " "`
fi

read -p "Assign a floating IP to the server? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack server add floating ip ${SAMPLE_NAME} ${FLOATING_IP}
fi

read -p "Update default security group to allow ssh and icmp ingress? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  SGID=`openstack security group list -f value --project admin|grep default|cut -f1 -d" "`
  RULE_LIST=`openstack security group rule list -f value ${SGID}|cut -f1 -d" "`
  for RULE in ${RULE_LIST}; do
    openstack security group rule delete ${RULE}
  done
  openstack security group rule create --egress --ethertype IPv4 ${SGID}
  openstack security group rule create --ingress --protocol tcp --dst-port 22 ${SGID}
  openstack security group rule create --ingress --protocol icmp ${SGID}
fi

echo -e "Once it is booted, your server should be accessible via\n\nssh -i ~/.ssh/ubuntu ubuntu@${FLOATING_IP}\n\n from ${DEFAULT_EXTERNAL_NETWORK_CIDR} network"
