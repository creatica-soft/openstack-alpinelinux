#!/usr/bin/bash

# Automation of openstack compute node (install script)
# (nova-compute, neutron-ovn-metadata-agent, cinder-volume)
# with OVN network driver (distributed floating IPs) as described in 
# https://docs.openstack.org/neutron/victoria/admin/ovn/refarch/refarch.html
# and ceph storage 
# https://docs.ceph.com/en/latest/rbd/rbd-openstack/#
# accroding to  the following guides:
# https://docs.openstack.org/nova/victoria/install
# https://docs.openstack.org/cinder/victoria/install

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_COMPUTE_NODES; i++ )); do
  read -p "Pre-install compute node ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    continue
  fi
  export COMPUTE_NODE_IP_ADDR=${COMPUTE_NODE_IP[${i}]}
  echo "COMPUTE_NODE_IP_ADDR=${COMPUTE_NODE_IP_ADDR}" 2>&1 | tee -a $0.log

  SSH="ssh ${COMPUTE_NODE_NAME}-${i}"
  echo "SSH=${SSH}" 2>&1 | tee -a $0.log

  echo "envsubst < ${BASE_DIR}/common/resolv.conf.template | ${SSH} dd status=none of=/etc/resolv.conf" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/common/resolv.conf.template | ${SSH} dd status=none of=/etc/resolv.conf

  read -p "Update DNS forward A and reverse PTR records for ${COMPUTE_NODE_NAME}-${i} with IP ${COMPUTE_NODE_IP_ADDR}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then

    A=`grep ^${COMPUTE_NODE_NAME}-${i} /var/bind/pri/compute.zone`
    echo "A=${A}" 2>&1 | tee -a $0.log
    if [[ -n "${A}" ]]; then
      echo "sed -i \"/^${COMPUTE_NODE_NAME}-${i}/c\\${COMPUTE_NODE_NAME}-${i}\ A\ ${COMPUTE_NODE_IP_ADDR}\" /var/bind/pri/compute.zone" 2>&1 | tee -a $0.log
      sed -i "/^${COMPUTE_NODE_NAME}-${i}/c\\${COMPUTE_NODE_NAME}-${i}\ A\ ${COMPUTE_NODE_IP_ADDR}" /var/bind/pri/compute.zone 2>&1 | tee -a $0.log
    else
      echo "sed -i \"\$a\\${COMPUTE_NODE_NAME}-${i}\ A\ ${COMPUTE_NODE_IP_ADDR}\" /var/bind/pri/compute.zone" 2>&1 | tee -a $0.log
      sed -i "\$a\\${COMPUTE_NODE_NAME}-${i}\ A\ ${COMPUTE_NODE_IP_ADDR}" /var/bind/pri/compute.zone 2>&1 | tee -a $0.log
    fi
    PTR=`grep ${COMPUTE_NODE_NAME}-${i} /var/bind/pri/compute-reverse.zone`
    echo "PTR=${PTR}" 2>&1 | tee -a $0.log
    IP=`echo ${COMPUTE_NODE_IP_ADDR}|cut -f4 -d"."`
    echo "IP=${IP}" 2>&1 | tee -a $0.log
    if [[ -n "${PTR}" ]]; then
      echo "sed -i \"/${COMPUTE_NODE_NAME}-${i}/c\\${IP}\ PTR\ ${COMPUTE_NODE_NAME}-${i}.${DOMAIN_NAME}.\" /var/bind/pri/compute-reverse.zone" 2>&1 | tee -a $0.log
      sed -i "/${COMPUTE_NODE_NAME}-${i}/c\\${IP}\ PTR\ ${COMPUTE_NODE_NAME}-${i}.${DOMAIN_NAME}." /var/bind/pri/compute-reverse.zone 2>&1 | tee -a $0.log
    else
      echo "sed -i \"\$a\\${IP}\ PTR\ ${COMPUTE_NODE_NAME}-${i}.${DOMAIN_NAME}.\" /var/bind/pri/compute-reverse.zone" 2>&1 | tee -a $0.log
      sed -i "\$a\\${IP}\ PTR\ ${COMPUTE_NODE_NAME}-${i}.${DOMAIN_NAME}." /var/bind/pri/compute-reverse.zone 2>&1 | tee -a $0.log
    fi

    DATE=`date -I|tr -d "-"`
    DATE="${DATE}01"
    echo "DATE=${DATE}" 2>&1 | tee -a $0.log
    SERIAL=`grep "; Serial" /var/bind/pri/compute.zone |tr -d " "|cut -f1 -d";"`
    echo "SERIAL=${SERIAL}" 2>&1 | tee -a $0.log
    if (( SERIAL >= DATE )); then
       SERIAL=$(( SERIAL + 1 ))
       echo "sed -i \"/;\ Serial/c\\ \ ${SERIAL}\ ;\ Serial\" /var/bind/pri/compute.zone" 2>&1 | tee -a $0.log
       sed -i "/;\ Serial/c\\ \ ${SERIAL}\ ;\ Serial" /var/bind/pri/compute.zone 2>&1 | tee -a $0.log
    else
       echo "sed -i \"/;\ Serial/c\\ \ ${DATE}\ ;\ Serial\" /var/bind/pri/compute.zone" 2>&1 | tee -a $0.log
       sed -i "/;\ Serial/c\\ \ ${DATE}\ ;\ Serial" /var/bind/pri/compute.zone 2>&1 | tee -a $0.log
    fi
    SERIAL=`grep "; Serial" /var/bind/pri/compute-reverse.zone |tr -d " "|cut -f1 -d";"`
    echo "SERIAL=${SERIAL}" 2>&1 | tee -a $0.log
    if (( SERIAL >= DATE )); then
       SERIAL=$(( SERIAL + 1 ))
       echo "sed -i \"/;\ Serial/c\\ \ ${SERIAL}\ ;\ Serial\" /var/bind/pri/compute-reverse.zone" 2>&1 | tee -a $0.log
       sed -i "/;\ Serial/c\\ \ ${SERIAL}\ ;\ Serial" /var/bind/pri/compute-reverse.zone 2>&1 | tee -a $0.log
    else
       echo \"sed -i "/;\ Serial/c\\ \ ${DATE}\ ;\ Serial\" /var/bind/pri/compute-reverse.zone" 2>&1 | tee -a $0.log
       sed -i "/;\ Serial/c\\ \ ${DATE}\ ;\ Serial" /var/bind/pri/compute-reverse.zone 2>&1 | tee -a $0.log
    fi

    echo "rndc reload" 2>&1 | tee -a $0.log
    rndc reload 2>&1 | tee -a $0.log
  fi

  read -p "Remove getty on ttyS0 from /etc/inittab on node ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} sed -i '/^ttyS0/d' /etc/inittab" 2>&1 | tee -a $0.log
    ${SSH} sed -i '/^ttyS0/d' /etc/inittab
  fi

  read -p "Install prerequisites on controller node ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "scp /etc/apk/repositories ${COMPUTE_NODE_NAME}-${i}:/etc/apk/" 2>&1 | tee -a $0.log
    scp /etc/apk/repositories ${COMPUTE_NODE_NAME}-${i}:/etc/apk/ 2>&1 | tee -a $0.log
    echo "${SSH} \"apk update; apk upgrade; apk add gettext man-db mlocate e2fsprogs-extra logrotate\"" 2>&1 | tee -a $0.log
    ${SSH} "apk update; apk upgrade; apk add gettext man-db mlocate e2fsprogs-extra logrotate" 2>&1 | tee -a $0.log
  fi

  read -p "Configure /etc/network/interfaces file on ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    export IP_ADDR=${COMPUTE_NODE_IP_ADDR}
    export NETMASK=${COMPUTE_NETWORK_MASK}
    export GW=${COMPUTE_NETWORK_DEFAULT_GATEWAY}

    echo "envsubst < ${BASE_DIR}/common/compute-interfaces.template | ${SSH} dd status=none of=/etc/network/interfaces" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/compute-interfaces.template | ${SSH} dd status=none of=/etc/network/interfaces
  fi
  
  read -p "Configure compute node IP in hosts file on ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
     export IP_ADDR=${COMPUTE_NODE_IP_ADDR}
     export NAME=${COMPUTE_NODE_NAME}-${i}
     export DOMAIN=${DOMAIN_NAME}
     echo "IP_ADDR=${IP_ADDR}" 2>&1 | tee -a $0.log
     echo "NAME=${NAME}" 2>&1 | tee -a $0.log
     echo "DOMAIN=${DOMAIN}" 2>&1 | tee -a $0.log
     echo "envsubst < ${BASE_DIR}/common/hosts.template | ${SSH} tee /etc/hosts" 2>&1 | tee -a $0.log
     envsubst < ${BASE_DIR}/common/hosts.template | ${SSH} tee /etc/hosts
  fi

  read -p "Configure a static route to the internal network ${INTERNAL_NETWORK_CIDR} via ${COMPUTE_NETWORK_GATEWAY} on ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
     echo "envsubst < ${BASE_DIR}/common/controller-route.conf > /tmp/route.conf" 2>&1 | tee -a $0.log
     envsubst < ${BASE_DIR}/common/controller-route.conf > /tmp/route.conf
     echo "scp /tmp/route.conf ${COMPUTE_NODE_NAME}-${i}:/etc/" 2>&1 | tee -a $0.log
     scp /tmp/route.conf ${COMPUTE_NODE_NAME}-${i}:/etc/ 2>&1 | tee -a $0.log
     echo "rm -f /tmp/route.conf" 2>&1 | tee -a $0.log
     rm -f /tmp/route.conf 2>&1 | tee -a $0.log
     echo "${SSH} rc-update add staticroute" 2>&1 | tee -a $0.log
     ${SSH} rc-update add staticroute 2>&1 | tee -a $0.log
     echo "${SSH} /etc/init.d/staticroute start" 2>&1 | tee -a $0.log
     ${SSH} /etc/init.d/staticroute start 2>&1 | tee -a $0.log
  fi

  read -p "Configure /etc/sysctl.conf file on ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "scp ${BASE_DIR}/sysctl.conf ${COMPUTE_NODE_NAME}-${i}:/etc/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/sysctl.conf ${COMPUTE_NODE_NAME}-${i}:/etc/ 2>&1 | tee -a $0.log
  fi

done

read -p 'Reboot (required if IPv6 was disabled via sysctl.conf). After reboot run os-cluster-install.sh. [y/N]'
if [[ "${REPLY}" == "y" ]]; then
  for (( i = 1; i <= NUMBER_OF_COMPUTE_NODES; i++ )); do
    SSH="ssh ${COMPUTE_NODE_NAME}-${i}"
    echo "${SSH} reboot" 2>&1 | tee -a $0.log
    ${SSH} reboot
    echo "sleep 10" 2>&1 | tee -a $0.log
    sleep 10
    echo "ping -c 1 ${COMPUTE_NODE_NAME}-${i}" 2>&1 | tee -a $0.log
    ping -c 1 ${COMPUTE_NODE_NAME}-${i} 2>&1 | tee -a $0.log
    while (( $? != 0 )); do
      sleep 3
      echo "ping -c 1 ${COMPUTE_NODE_NAME}-${i}" 2>&1 | tee -a $0.log
      ping -c 1 ${COMPUTE_NODE_NAME}-${i} 2>&1 | tee -a $0.log
    done
  done
fi
