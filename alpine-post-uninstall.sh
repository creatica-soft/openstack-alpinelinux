#!/usr/bin/bash

# Post uninstall script - undo some alpine-pre-install.sh stuff

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

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

read -p "Delete the base image ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} snapshot? [y/N]"
if [[ "${REPLY}" == "y" ]]; then

  echo "rbd -c ${CEPH_CONF} -k ${CEPH_CLIENT_KEYRING} -p ${RBD_POOL} snap unprotect --snap ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --image ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --id ${CEPH_CLIENT}" 2>&1 | tee -a $0.log
  
  rbd -c ${CEPH_CONF} -k ${CEPH_CLIENT_KEYRING} -p ${RBD_POOL} snap unprotect --snap ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --image ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log
  
  echo "rbd -c ${CEPH_CONF} -k ${CEPH_CLIENT_KEYRING} -p ${RBD_POOL} snap rm --snap ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --id ${CEPH_CLIENT}" 2>&1 | tee -a $0.log
  
  rbd -c ${CEPH_CONF} -k ${CEPH_CLIENT_KEYRING} -p ${RBD_POOL} snap rm --snap ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log

fi

read -p "Destroy the base linux container ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  echo "lxc-destroy -n ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}" 2>&1 | tee -a $0.log
  lxc-destroy -n ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} 2>&1 | tee -a $0.log
fi

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_IP[${i}]}"
  else
    SSH=""
  fi
  
  read -p "Uninstall openstack client version ${PYTHON_OPENSTACK_CLIENT_VERSION} on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    if (( i == 1 )); then
      echo "${SSH} pip uninstall python-openstackclient osc-placement" 2>&1 | tee -a $0.log
      ${SSH} pip uninstall python-openstackclient osc-placement 2>&1 | tee -a $0.log
      echo "${SSH} apk del alpine-sdk python3 python3-dev libffi libffi-dev openssl-dev rust cargo qemu-img curl" 2>&1 | tee -a $0.log
      ${SSH} apk del alpine-sdk python3 python3-dev libffi libffi-dev openssl-dev rust cargo qemu-img curl 2>&1 | tee -a $0.log
      echo "rm -f ~/python-openstackclient.tar.gz" 2>&1 | tee -a $0.log
      rm -f ~/python-openstackclient.tar.gz 2>&1 | tee -a $0.log
    else
      PYTHON3_VERSION=`python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
      echo "PYTHON3_VERSION=${PYTHON3_VERSION}" 2>&1 | tee -a $0.log
      echo "${SSH} rm -rf /root/python-openstackclient.tar.gz /usr/lib/python${PYTHON3_VERSION}/site-packages /usr/bin/openstack" 2>&1 | tee -a $0.log
      ${SSH} rm -rf /root/python-openstackclient.tar.gz /usr/lib/python${PYTHON3_VERSION}/site-packages /usr/bin/openstack 2>&1 | tee -a $0.log
      echo "${SSH} apk del python3 libffi openssl qemu-img curl" 2>&1 | tee -a $0.log
      ${SSH} apk del python3 libffi openssl qemu-img curl 2>&1 | tee -a $0.log
    fi
  fi

  read -p "Uninstall lxc and ceph-common on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} service udev stop" 2>&1 | tee -a $0.log
    ${SSH} service udev stop 2>&1 | tee -a $0.log
    echo "${SSH} rc-update del udev" 2>&1 | tee -a $0.log
    ${SSH} rc-update del udev 2>&1 | tee -a $0.log
    echo "${SSH} service cgroups stop" 2>&1 | tee -a $0.log
    ${SSH} service cgroups stop 2>&1 | tee -a $0.log
    echo "${SSH} rc-update del cgroups" 2>&1 | tee -a $0.log
    ${SSH} rc-update del cgroups 2>&1 | tee -a $0.log
    echo "${SSH} apk del lxc lxc-templates lxc-download xz eudev ceph-common ethtool lxc-bridge bridge jq libcap-ng" 2>&1 | tee -a $0.log
    ${SSH} apk del lxc lxc-templates lxc-download xz eudev ceph-common ethtool lxc-bridge bridge jq libcap-ng 2>&1 | tee -a $0.log
    echo "${SSH} rm -rf /usr/share/lxc /etc/lxc /var/lib/lxc" 2>&1 | tee -a $0.log
    ${SSH} rm -rf /usr/share/lxc /etc/lxc /var/lib/lxc 2>&1 | tee -a $0.log
  fi

  read -p "Delete RC file for admin on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} rm -f /root/admin-openrc" 2>&1 | tee -a $0.log
    ${SSH} rm -f /root/admin-openrc 2>&1 | tee -a $0.log
  fi

  read -p "Delete RC file for user on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} rm -f /root/user-openrc" 2>&1 | tee -a $0.log
    ${SSH} rm -f /root/user-openrc 2>&1 | tee -a $0.log
  fi

  read -p "Delete the static route to the internal network ${INTERNAL_NETWORK_CIDR} via ${INTERNAL_NETWORK_GATEWAY} on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
     echo "rm -f /etc/route.conf" 2>&1 | tee -a $0.log
     rm -f /etc/route.conf 2>&1 | tee -a $0.log
     echo "${SSH} /etc/init.d/staticroute stop" 2>&1 | tee -a $0.log
     ${SSH} /etc/init.d/staticroute stop 2>&1 | tee -a $0.log
     echo "${SSH} rc-update del staticroute" 2>&1 | tee -a $0.log
     ${SSH} rc-update del staticroute 2>&1 | tee -a $0.log
     echo "${SSH} ip route del ${INTERNAL_NETWORK_CIDR}" 2>&1 | tee -a $0.log
     ${SSH} ip route del ${INTERNAL_NETWORK_CIDR} 2>&1 | tee -a $0.log
  fi

  read -p "Uninstall ISC bind DNS on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} service named stop" 2>&1 | tee -a $0.log
    ${SSH} service named stop 2>&1 | tee -a $0.log
    echo "${SSH} rc-update del named" 2>&1 | tee -a $0.log
    ${SSH} rc-update del named 2>&1 | tee -a $0.log
    echo "${SSH} apk del bind" 2>&1 | tee -a $0.log
    ${SSH} apk del bind 2>&1 | tee -a $0.log
    echo "${SSH} rm -rf /etc/bind /var/bind /var/log/bind" 2>&1 | tee -a $0.log
    ${SSH} rm -rf /etc/bind /var/bind /var/log/bind 2>&1 | tee -a $0.log
  fi  

  echo "${SSH} apk del gettext man-db mlocate" 2>&1 | tee -a $0.log
  ${SSH} apk del gettext man-db mlocate 2>&1 | tee -a $0.log

done
