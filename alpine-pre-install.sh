#!/usr/bin/bash

# Pre-install script to be run first
# It IPv6, configures /etc/hosts file, static route, installs lxc, openstack client and rc files and reboots the controllers
# https://github.com/lxc/lxd/blob/master/doc/production-setup.md

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

read -p "Generate RSA key for SSH? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  echo "ssh-keygen" 2>&1 | tee -a $0.log
  ssh-keygen
  echo "cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys" 2>&1 | tee -a $0.log
  cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys 2>&1 | tee -a $0.log
#  echo "cat ~/.ssh/id_rsa.pub" 2>&1 | tee -a $0.log
#  cat ~/.ssh/id_rsa.pub 2>&1 | tee -a $0.log
#  read -p "Copy the above public key into /root/.ssh/authorized_keys file on all other controller and compute nodes, continue? [y/N]"
#  if [[ "${REPLY}" != "y" ]]; then
#    exit 1
#  fi
fi

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_IP[${i}]}"
    read -p "Copy /root/.ssh/id_rsa.pub to /root/.ssh/authorized_keys to node ${CONTROLLER_NAME}-${i}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "\"mkdir -p /root/.ssh && chmod 500 /root/.ssh\"" 2>&1 | tee -a $0.log
      ${SSH} "mkdir -p /root/.ssh && chmod 500 /root/.ssh" 2>&1 | tee -a $0.log
      echo "/root/.ssh/id_rsa.pub ${CONTROLLER_NAME}-${i}:/root/.ssh/authorized_keys" 2>&1 | tee -a $0.log
      scp  /root/.ssh/id_rsa.pub ${CONTROLLER_NAME}-${i}:/root/.ssh/authorized_keys
    fi
  else
    SSH=""
  fi


  read -p "Remove getty on ttyS0 from /etc/inittab on node ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} sed -i '/^ttyS0/d' /etc/inittab" 2>&1 | tee -a $0.log
    ${SSH} sed -i '/^ttyS0/d' /etc/inittab
  fi

  read -p "Install prerequisites on controller node ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    continue
  fi

  if (( i == 1 )); then
    echo "sed -i \"/v${DOWNLOAD_RELEASE}\/community/s/^#//\" /etc/apk/repositories" 2>&1 | tee -a $0.log
    sed -i "/v${DOWNLOAD_RELEASE}\/community/s/^#//" /etc/apk/repositories 2>&1 | tee -a $0.log
  else
    echo "scp /etc/apk/repositories ${CONTROLLER_IP[${i}]}:/etc/apk/" 2>&1 | tee -a $0.log
    scp /etc/apk/repositories ${CONTROLLER_IP[${i}]}:/etc/apk/ 2>&1 | tee -a $0.log
  fi

  echo "${SSH} \"apk update && apk upgrade && apk add gettext man-db mlocate e2fsprogs-extra rsyslog logrotate bash linux-tools\"" 2>&1 | tee -a $0.log
  ${SSH} "apk update && apk upgrade && apk add gettext man-db mlocate e2fsprogs-extra rsyslog logrotate bash linux-tools" 2>&1 | tee -a $0.log

  echo "${SSH} ln -s /bin/bash /usr/bin/bash" 2>&1 | tee -a $0.log
  ${SSH} ln -s /bin/bash /usr/bin/bash 2>&1 | tee -a $0.log

  if (( i == 1 )); then
    echo "scp ${BASE_DIR}/common/rsyslog.conf-master ${CONTROLLER_NAME}-${i}:/etc/rsyslog.conf" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/common/rsyslog.conf-master ${CONTROLLER_NAME}-${i}:/etc/rsyslog.conf 2>&1 | tee -a $0.log
  else
    echo "envsubst '${CONTROLLER_NAME}' < ${BASE_DIR}/common/rsyslog.conf-slave.template | ${SSH} dd status=none of=/etc/rsyslog.conf" 2>&1 | tee -a $0.log
    envsubst '${CONTROLLER_NAME}' < ${BASE_DIR}/common/rsyslog.conf-slave.template | ${SSH} dd status=none of=/etc/rsyslog.conf
  fi

  echo "scp ${BASE_DIR}/common/rsyslog.logrotate ${CONTROLLER_NAME}-${i}:/etc/logrotate.d/rsyslog" 2>&1 | tee -a $0.log
  scp ${BASE_DIR}/common/rsyslog.logrotate ${CONTROLLER_NAME}-${i}:/etc/logrotate.d/rsyslog 2>&1 | tee -a $0.log

  echo "${SSH} rc-update del syslog boot" 2>&1 | tee -a $0.log
  ${SSH} rc-update del syslog boot 2>&1 | tee -a $0.log
  echo "${SSH} rc-update add rsyslog boot" 2>&1 | tee -a $0.log
  ${SSH} rc-update add rsyslog boot 2>&1 | tee -a $0.log
  echo "${SSH} service syslog stop" 2>&1 | tee -a $0.log
  ${SSH} service syslog stop 2>&1 | tee -a $0.log
  echo "${SSH} service rsyslog start" 2>&1 | tee -a $0.log
  ${SSH} service rsyslog start 2>&1 | tee -a $0.log
  
  read -p "Configure controller IP in hosts file on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
     export IP_ADDR=${CONTROLLER_IP[${i}]}
     export NAME=${CONTROLLER_NAME}-${i}
     export DOMAIN=${DOMAIN_NAME}
     echo "IP_ADDR=${IP_ADDR}" 2>&1 | tee -a $0.log
     echo "NAME=${NAME}" 2>&1 | tee -a $0.log
     echo "DOMAIN=${DOMAIN}" 2>&1 | tee -a $0.log
     echo "envsubst < ${BASE_DIR}/common/hosts.template | ${SSH} tee /etc/hosts" 2>&1 | tee -a $0.log
     envsubst < ${BASE_DIR}/common/hosts.template | ${SSH} tee /etc/hosts
  fi

  read -p "Configure a static route to the internal network ${INTERNAL_NETWORK_CIDR} via ${COMPUTE_NETWORK_GATEWAY} on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
     echo "envsubst < ${BASE_DIR}/common/controller-route.conf > /tmp/route.conf" 2>&1 | tee -a $0.log
     envsubst < ${BASE_DIR}/common/controller-route.conf > /tmp/route.conf
     echo "scp /tmp/route.conf ${CONTROLLER_IP[${i}]}:/etc/" 2>&1 | tee -a $0.log
     scp /tmp/route.conf ${CONTROLLER_IP[${i}]}:/etc/ 2>&1 | tee -a $0.log
     echo "rm -f /tmp/route.conf" 2>&1 | tee -a $0.log
     rm -f /tmp/route.conf 2>&1 | tee -a $0.log
     echo "${SSH} rc-update add staticroute" 2>&1 | tee -a $0.log
     ${SSH} rc-update add staticroute 2>&1 | tee -a $0.log
     echo "${SSH} /etc/init.d/staticroute start" 2>&1 | tee -a $0.log
     ${SSH} /etc/init.d/staticroute start 2>&1 | tee -a $0.log
  fi

  read -p "Install ISC bind dns service on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} apk add bind" 2>&1 | tee -a $0.log
    ${SSH} apk add bind 2>&1 | tee -a $0.log

    echo "${SSH} rc-update add named" 2>&1 | tee -a $0.log
    ${SSH} rc-update add named 2>&1 | tee -a $0.log

    export CONTR_IP1=`echo ${CONTROLLER_IP[1]}|cut -f4 -d"."`
    export CONTR_IP2=`echo ${CONTROLLER_IP[2]}|cut -f4 -d"."`
    export CONTR_IP3=`echo ${CONTROLLER_IP[3]}|cut -f4 -d"."`
    export COMP_NODE_IP1=`echo ${COMPUTE_NODE_IP[1]}|cut -f4 -d"."`
    export COMP_NODE_IP2=`echo ${COMPUTE_NODE_IP[2]}|cut -f4 -d"."`
    export COMP_NODE_IP3=`echo ${COMPUTE_NODE_IP[3]}|cut -f4 -d"."`

    export TTL='$TTL'

    case "${i}" in
    "1")
      export CONTROLLER_IPADDR=${CONTROLLER_IP1}
    ;;
    "2")
      export CONTROLLER_IPADDR=${CONTROLLER_IP2}
    ;;
    "3")
      export CONTROLLER_IPADDR=${CONTROLLER_IP3}
    ;;
    esac

    echo "CONTR_IP1=${CONTR_IP1}" 2>&1 | tee -a $0.log
    echo "CONTR_IP2=${CONTR_IP2}" 2>&1 | tee -a $0.log
    echo "CONTR_IP3=${CONTR_IP3}" 2>&1 | tee -a $0.log
    echo "COMP_NODE_IP1=${COMP_NODE_IP1}" 2>&1 | tee -a $0.log
    echo "COMP_NODE_IP2=${COMP_NODE_IP2}" 2>&1 | tee -a $0.log
    echo "COMP_NODE_IP3=${COMP_NODE_IP3}" 2>&1 | tee -a $0.log
    echo "CONTROLLER_IP1=${CONTROLLER_IP1}" 2>&1 | tee -a $0.log
    echo "CONTROLLER_IP2=${CONTROLLER_IP2}" 2>&1 | tee -a $0.log
    echo "CONTROLLER_IP3=${CONTROLLER_IP3}" 2>&1 | tee -a $0.log
    echo "COMPUTE_NODE_IP1=${COMPUTE_NODE_IP1}" 2>&1 | tee -a $0.log
    echo "COMPUTE_NODE_IP2=${COMPUTE_NODE_IP2}" 2>&1 | tee -a $0.log
    echo "COMPUTE_NODE_IP3=${COMPUTE_NODE_IP3}" 2>&1 | tee -a $0.log
    echo "CONTROLLER_IPADDR=${CONTROLLER_IPADDR}" 2>&1 | tee -a $0.log
    
    if (( i > 1 )); then

      echo "envsubst < ${BASE_DIR}/bind/named-sec.conf.template | ${SSH} dd status=none of=/etc/bind/named.conf" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/bind/named-sec.conf.template | ${SSH} dd status=none of=/etc/bind/named.conf

    else

      echo "envsubst < ${BASE_DIR}/bind/named.conf.template > /etc/bind/named.conf" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/bind/named.conf.template > /etc/bind/named.conf
      echo "envsubst < ${BASE_DIR}/bind/compute.zone.template > /var/bind/pri/compute.zone" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/bind/compute.zone.template > /var/bind/pri/compute.zone
      echo "envsubst < ${BASE_DIR}/bind/compute-reverse.zone.template > /var/bind/pri/compute-reverse.zone" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/bind/compute-reverse.zone.template > /var/bind/pri/compute-reverse.zone
      echo "envsubst < ${BASE_DIR}/bind/internal-reverse.zone.template > /var/bind/pri/internal-reverse.zone" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/bind/internal-reverse.zone.template > /var/bind/pri/internal-reverse.zone
      echo "envsubst < ${BASE_DIR}/common/resolv.conf.template > /etc/resolv.conf" 2>&1 | tee -a $0.log
      envsubst < ${BASE_DIR}/common/resolv.conf.template > /etc/resolv.conf
    fi
    echo "${SSH} service named start" 2>&1 | tee -a $0.log
    ${SSH} service named start 2>&1 | tee -a $0.log
  fi

  read -p "Install lxc and ceph-common on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} apk add lxc lxc-templates lxc-download xz eudev ethtool lxc-bridge bridge jq ceph-common" 2>&1 | tee -a $0.log
    ${SSH} apk add lxc lxc-templates lxc-download xz eudev ethtool lxc-bridge bridge jq ceph-common 2>&1 | tee -a $0.log

    export IP_ADDR=${CONTROLLER_IP[${i}]}
    export NETMASK=${COMPUTE_NETWORK_MASK}
    export GW=${COMPUTE_NETWORK_DEFAULT_GATEWAY}

    echo "envsubst '${CEPH_CONF}${CEPH_CLIENT_KEYRING}${RBD_POOL}${CEPH_CLIENT}' < ${BASE_DIR}/common/rbd-device-map.template | ${SSH} dd status=none of=/usr/share/lxc/hooks/rbd-device-map" 2>&1 | tee -a $0.log
    envsubst '${CEPH_CONF}${CEPH_CLIENT_KEYRING}${RBD_POOL}${CEPH_CLIENT}' < ${BASE_DIR}/common/rbd-device-map.template | ${SSH} dd status=none of=/usr/share/lxc/hooks/rbd-device-map
    echo "envsubst '${CEPH_CONF}${CEPH_CLIENT_KEYRING}${RBD_POOL}${CEPH_CLIENT}' < ${BASE_DIR}/common/rbd-device-unmap.template | ${SSH} dd status=none of=/usr/share/lxc/hooks/rbd-device-unmap" 2>&1 | tee -a $0.log
    envsubst '${CEPH_CONF}${CEPH_CLIENT_KEYRING}${RBD_POOL}${CEPH_CLIENT}' < ${BASE_DIR}/common/rbd-device-unmap.template | ${SSH} dd status=none of=/usr/share/lxc/hooks/rbd-device-unmap
    echo "envsubst < ${BASE_DIR}/common/interfaces.template | ${SSH} dd status=none of=/etc/network/interfaces" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/interfaces.template | ${SSH} dd status=none of=/etc/network/interfaces
    echo "envsubst < ${BASE_DIR}/common/ceph.conf.template | ${SSH} dd status=none of=/etc/ceph/ceph.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/ceph.conf.template | ${SSH} dd status=none of=/etc/ceph/ceph.conf
    echo "envsubst < ${BASE_DIR}/common/ceph.client.keyring.template | ${SSH} dd status=none of=/etc/ceph/ceph.client.${CEPH_CLIENT}.keyring" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/ceph.client.keyring.template | ${SSH} dd status=none of=/etc/ceph/ceph.client.${CEPH_CLIENT}.keyring
    echo "envsubst < ${BASE_DIR}/common/ceph.client.admin.keyring.template | ${SSH} dd status=none of=/etc/ceph/ceph.client.admin.keyring" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/ceph.client.admin.keyring.template | ${SSH} dd status=none of=/etc/ceph/ceph.client.admin.keyring

    echo "scp ${BASE_DIR}/common/ovs_up_down ${CONTROLLER_IP[${i}]}:/etc/lxc/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/common/ovs_up_down ${CONTROLLER_IP[${i}]}:/etc/lxc/ 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/common/lxc-00-custom.conf ${CONTROLLER_IP[${i}]}:/usr/share/lxc/config/common.conf.d/00-custom.conf" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/common/lxc-00-custom.conf ${CONTROLLER_IP[${i}]}:/usr/share/lxc/config/common.conf.d/00-custom.conf 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/sysctl.conf ${CONTROLLER_IP[${i}]}:/etc/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/sysctl.conf ${CONTROLLER_IP[${i}]}:/etc/ 2>&1 | tee -a $0.log
#    echo "scp ${BASE_DIR}/limits.conf ${CONTROLLER_IP[${i}]}:/etc/security/" 2>&1 | tee -a $0.log
#    scp ${BASE_DIR}/limits.conf ${CONTROLLER_IP[${i}]}:/etc/security/ 2>&1 | tee -a $0.log

    echo "${SSH} chmod 400 /etc/ceph/ceph.client.${CEPH_CLIENT}.keyring" 2>&1 | tee -a $0.log
    ${SSH} chmod 400 /etc/ceph/ceph.client.${CEPH_CLIENT}.keyring 2>&1 | tee -a $0.log
    echo "${SSH} chmod 400 /etc/ceph/ceph.client.admin.keyring" 2>&1 | tee -a $0.log
    ${SSH} chmod 400 /etc/ceph/ceph.client.admin.keyring 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /usr/share/lxc/hooks/rbd-device-map" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /usr/share/lxc/hooks/rbd-device-map 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /usr/share/lxc/hooks/rbd-device-unmap" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /usr/share/lxc/hooks/rbd-device-unmap 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/lxc/ovs_up_down" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/lxc/ovs_up_down 2>&1 | tee -a $0.log

    echo "rm -f /tmp/ceph.client.${CEPH_CLIENT}.keyring /tmp/ceph.client.admin.keyring /tmp/ceph.conf /tmp/rbd-device-map /tmp/rbd-device-unmap /tmp/interfaces" 2>&1 | tee -a $0.log
    rm -f /tmp/ceph.client.${CEPH_CLIENT}.keyring /tmp/ceph.client.admin.keyring /tmp/ceph.conf /tmp/rbd-device-map /tmp/rbd-device-unmap /tmp/interfaces 2>&1 | tee -a $0.log

    echo "${SSH} rc-update add udev" 2>&1 | tee -a $0.log
    ${SSH} rc-update add udev 2>&1 | tee -a $0.log
    echo "${SSH} service udev start" 2>&1 | tee -a $0.log
    ${SSH} service udev start 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add cgroups" 2>&1 | tee -a $0.log
    ${SSH} rc-update add cgroups 2>&1 | tee -a $0.log
    echo "${SSH} service cgroups start" 2>&1 | tee -a $0.log
    ${SSH} service cgroups start 2>&1 | tee -a $0.log
    echo "${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<\"tun\"" 2>&1 | tee -a $0.log
    ${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<"tun"
    echo "${SSH} modprobe tun" 2>&1 | tee -a $0.log
    ${SSH} modprobe tun 2>&1 | tee -a $0.log
  fi

  read -p "Install openstack client version ${PYTHON_OPENSTACK_CLIENT_VERSION} and osc-placement version ${OSC_PLACEMENT_VERSION}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    if (( i == 1 )); then
      echo "${SSH} apk add --no-cache alpine-sdk python3 python3-dev libffi-dev openssl-dev rust cargo qemu-img curl" 2>&1 | tee -a $0.log
      ${SSH} apk add --no-cache alpine-sdk python3 python3-dev libffi-dev openssl-dev rust cargo qemu-img curl 2>&1 | tee -a $0.log
      echo "${SSH} curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py" 2>&1 | tee -a $0.log
      ${SSH} curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py 2>&1 | tee -a $0.log
      echo "${SSH} python3 /tmp/get-pip.py" 2>&1 | tee -a $0.log
      ${SSH} python3 /tmp/get-pip.py 2>&1 | tee -a $0.log
      echo "${SSH} pip install python-openstackclient==${PYTHON_OPENSTACK_CLIENT_VERSION}" 2>&1 | tee -a $0.log
      ${SSH} pip install python-openstackclient==${PYTHON_OPENSTACK_CLIENT_VERSION} 2>&1 | tee -a $0.log
      echo "${SSH} pip install osc-placement==${OSC_PLACEMENT_VERSION}" 2>&1 | tee -a $0.log
      ${SSH} pip install osc-placement==${OSC_PLACEMENT_VERSION} 2>&1 | tee -a $0.log
      echo "rm -f /tmp/get-pip.py" 2>&1 | tee -a $0.log
      rm -f /tmp/get-pip.py 2>&1 | tee -a $0.log
      PYTHON3_VERSION=`python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
      echo "PYTHON3_VERSION=${PYTHON3_VERSION}" 2>&1 | tee -a $0.log
      echo "tar -zcf ~/python-openstackclient.tar.gz /usr/lib/python${PYTHON3_VERSION}/site-packages /usr/bin/openstack" 2>&1 | tee -a $0.log
      tar -zcf ~/python-openstackclient.tar.gz /usr/lib/python${PYTHON3_VERSION}/site-packages /usr/bin/openstack
    else
      echo "${SSH} apk add --no-cache python3 libffi openssl qemu-img curl" 2>&1 | tee -a $0.log
      ${SSH} apk add --no-cache python3 libffi openssl qemu-img curl 2>&1 | tee -a $0.log
      echo "scp ~/python-openstackclient.tar.gz ${CONTROLLER_IP[${i}]}:/root" 2>&1 | tee -a $0.log
      scp ~/python-openstackclient.tar.gz ${CONTROLLER_IP[${i}]}:/root  2>&1 | tee -a $0.log
      echo "${SSH} tar -C / -zxf /root/python-openstackclient.tar.gz" 2>&1 | tee -a $0.log
      ${SSH} tar -C / -zxf /root/python-openstackclient.tar.gz
    fi
  fi

  read -p "Create RC file for admin? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "envsubst < ${BASE_DIR}/admin-openrc.template > /root/admin-openrc" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/admin-openrc.template > /root/admin-openrc
    if (( i > 1 )); then
      echo "scp /root/admin-openrc ${CONTROLLER_IP[${i}]}:/root/" 2>&1 | tee -a $0.log
      scp /root/admin-openrc ${CONTROLLER_IP[${i}]}:/root/ 2>&1 | tee -a $0.log
    fi
  fi

  read -p "Create RC file for user? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "envsubst < ${BASE_DIR}/user-openrc.template> /root/user-openrc" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/user-openrc.template > /root/user-openrc
    if (( i > 1 )); then
      echo "scp /root/user-openrc ${CONTROLLER_IP[${i}]}:/root/" 2>&1 | tee -a $0.log
      scp /root/user-openrc ${CONTROLLER_IP[${i}]}:/root/ 2>&1 | tee -a $0.log
    fi
  fi

done

read -p 'Reboot (required if IPv6 was disabled via sysctl.conf). After reboot run compute-pre-install.sh. [y/N]'
if [[ "${REPLY}" == "y" ]]; then
  for (( i = NUMBER_OF_CONTROLLERS; i >= 1 ; i-- )); do
    if (( i > 1 )); then
      SSH="ssh ${CONTROLLER_IP[${i}]}"
    else
      SSH=""
    fi  
    echo "${SSH} reboot" 2>&1 | tee -a $0.log
    ${SSH} reboot
    echo "sleep 10" 2>&1 | tee -a $0.log
    sleep 10
    echo "ping -c 1 ${CONTROLLER_IP[${i}]}" 2>&1 | tee -a $0.log
    ping -c 1 ${CONTROLLER_IP[${i}]} 2>&1 | tee -a $0.log
    while (( $? != 0 )); do
      sleep 3
      echo "ping -c 1 ${CONTROLLER_IP[${i}]}" 2>&1 | tee -a $0.log
      ping -c 1 ${CONTROLLER_IP[${i}]} 2>&1 | tee -a $0.log
    done
  done
fi
