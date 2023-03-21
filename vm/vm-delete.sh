#!/usr/bin/bash

# The script interactively deletes a sample image, a volume, flavors, networks, a router, a floating IP,
# a key pair and a server, and restores the default security group

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

read -p "Delete the server ${SAMPLE_NAME}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack server delete ${SAMPLE_NAME}
fi

FLOATING_IPS=`openstack floating ip list -f value -c "Floating IP Address"`

for FLOATING_IP in ${FLOATING_IPS}; do
  read -p "Delete the floating IP ${FLOATING_IP}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    openstack floating ip delete ${FLOATING_IP}
  fi
done

read -p "Delete ubuntu rsa keypair? [y/N]"
REPLY=`echo ${REPLY}|cut -c1`
if [[ "${REPLY}" == "y" ]]; then
  openstack keypair delete ubuntu
fi

read -p "Restore the default security group? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  SGID=`openstack security group list -f value --project admin|grep default|cut -f1 -d" "`
  RULE_LIST=`openstack security group rule list -f value ${SGID}|cut -f1 -d" "`
  for RULE in ${RULE_LIST}; do
    openstack security group rule delete ${RULE}
  done
  openstack security group rule create --egress --ethertype IPv4 ${SGID}
  openstack security group rule create --egress --ethertype IPv6 ${SGID}
  openstack security group rule create --ingress --ethertype IPv4 --remote-group ${SGID} ${SGID}
  openstack security group rule create --ingress --ethertype IPv6 --remote-group ${SGID} ${SGID}
fi

read -p "Delete the router? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack router remove port router internal-gateway
  openstack router delete router
fi

read -p "Delete the public network ${DEFAULT_EXTERNAL_NETWORK}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack subnet delete ${DEFAULT_EXTERNAL_NETWORK}
  openstack network delete ${DEFAULT_EXTERNAL_NETWORK}
fi

read -p "Delete the default internal network ${DEFAULT_INTERNAL_NETWORK}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack subnet delete ${DEFAULT_INTERNAL_NETWORK}
  openstack network delete ${DEFAULT_INTERNAL_NETWORK}
fi

read -p "Delete sample flavors? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack flavor delete public.1c.2r.0d
  openstack flavor delete public.2c.4r.0d
  openstack flavor delete public.1c.2r.2d
  openstack flavor delete public.2c.4r.4d
  openstack flavor delete public.1c.2r.8d
  openstack flavor delete public.2c.4r.8d
fi

read -p "Delete the bootable volume created from the sample image ${SAMPLE_NAME}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack volume delete ${SAMPLE_NAME}
fi

read -p "Delete glance image ${SAMPLE_IMAGE_FILE}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  openstack image delete ${SAMPLE_IMAGE_FILE}
fi

read -p "Delete raw image ${SAMPLE_IMAGE_FILE}.raw? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  rm -f ${BASE_DIR}/vm/${SAMPLE_IMAGE_FILE}.raw
fi
