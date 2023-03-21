#!/usr/bin/bash
# in short, the script will setup the ovn cluster and creates a simple network topology
# with one internal bridge ${BR-INTERNAL} with DHCP enabled
# and another external bridge called ${BR-PROVIDER}. The bridges are joined
# by a router ${ROUTER_PROVIDER} with SNAT enabled
# the router is distributed over controller nodes
#
# execute this script on controller 1
# ensure that root SSH /root/.ssh/id_rsa exists on controller 1 and /root/.ssh/authorized_keys on controller 2 and 3
# OVN man pages:
# https://man7.org/linux/man-pages/man7/ovn-architecture.7.html
# https://github.com/openvswitch/ovs/blob/master/Documentation/topics/integration.rst
# https://man7.org/linux/man-pages/man5/ovn-nb.5.html
# https://man7.org/linux/man-pages/man5/ovn-sb.5.html
# https://man7.org/linux/man-pages/man5/ovs-vswitchd.conf.db.5.html
# https://man7.org/linux/man-pages/man8/ovn-nbctl.8.html
# https://man7.org/linux/man-pages/man8/ovn-sbctl.8.html
# https://man7.org/linux/man-pages/man8/ovs-vsctl.8.html
# https://github.com/openvswitch/ovs/blob/master/Documentation/intro/install/general.rst
# https://docs.openvswitch.org/en/latest/faq/releases/
# https://github.com/openvswitch/ovs/blob/master/Documentation/faq/issues.rst

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log
echo "BR_PROVIDER=${BR_PROVIDER}" 2>&1 | tee -a $0.log
echo "BR_COMPUTE=${BR_COMPUTE}" 2>&1 | tee -a $0.log
echo "ROUTER=${ROUTER_PROVIDER}" 2>&1 | tee -a $0.log
echo "ROUTER_COMPUTE=${ROUTER_COMPUTE}" 2>&1 | tee -a $0.log
echo "OUI=${OUI}" 2>&1 | tee -a $0.log
echo "OUI_MANUAL=${OUI_MANUAL}" 2>&1 | tee -a $0.log
echo "PROVIDER_NETWORK_IFACE=${PROVIDER_NETWORK_IFACE}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_OVS_BRIDGING_IFACE=${COMPUTE_NETWORK_OVS_BRIDGING_IFACE}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_GATEWAY=${INTERNAL_NETWORK_GATEWAY}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_GATEWAY_CIDR=${INTERNAL_NETWORK_GATEWAY_CIDR}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_GATEWAY_MAC=${INTERNAL_NETWORK_GATEWAY_MAC}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_CIDR=${INTERNAL_NETWORK_CIDR}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_MASK=${INTERNAL_NETWORK_MASK}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_DHCP_SERVER_MAC=${INTERNAL_NETWORK_DHCP_SERVER_MAC}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_DHCP_LEASE_TIME=${INTERNAL_NETWORK_DHCP_LEASE_TIME}" 2>&1 | tee -a $0.log
echo "INTERNAL_NETWORK_DHCP_EXCLUDE_IPS=${INTERNAL_NETWORK_DHCP_EXCLUDE_IPS}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_GATEWAY=${COMPUTE_NETWORK_GATEWAY}" 2>&1 | tee -a $0.log
#echo "COMPUTE_NETWORK_GATEWAY_CIDR=${COMPUTE_NETWORK_GATEWAY_CIDR}" 2>&1 | tee -a $0.log
#echo "COMPUTE_NETWORK_GATEWAY_MAC=${COMPUTE_NETWORK_GATEWAY_MAC}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_CIDR=${COMPUTE_NETWORK_CIDR}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_ROUTER_PORT_IP=${COMPUTE_NETWORK_ROUTER_PORT_IP}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_ROUTER_PORT_IP_CIDR=${COMPUTE_NETWORK_ROUTER_PORT_IP_CIDR}" 2>&1 | tee -a $0.log
echo "COMPUTE_NETWORK_ROUTER_PORT_MAC=${COMPUTE_NETWORK_ROUTER_PORT_MAC}" 2>&1 | tee -a $0.log
echo "EXTERNAL_NETWORK_GATEWAY=${EXTERNAL_NETWORK_GATEWAY}" 2>&1 | tee -a $0.log
echo "EXTERNAL_NETWORK_ROUTER_PORT_IP=${EXTERNAL_NETWORK_ROUTER_PORT_IP}" 2>&1 | tee -a $0.log
echo "EXTERNAL_NETWORK_ROUTER_PORT_IP_CIDR=${EXTERNAL_NETWORK_ROUTER_PORT_IP_CIDR}" 2>&1 | tee -a $0.log
echo "EXTERNAL_NETWORK_ROUTER_PORT_MAC=${EXTERNAL_NETWORK_ROUTER_PORT_MAC}" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  read -p "Install ovs and ovn on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    continue
  fi
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_NAME}-${i}"
  else
    SSH=""
  fi
  echo "${SSH} apk add alpine-sdk libcap-ng-dev unbound-dev autoconf automake libtool util-linux iproute2 tcpdump uuidgen" 2>&1 | tee -a $0.log
  ${SSH} apk add alpine-sdk libcap-ng-dev unbound-dev autoconf automake libtool util-linux iproute2 tcpdump uuidgen 2>&1 | tee -a $0.log
  if (( i > 1 )); then
    echo "scp ~/ovs.tar.gz ${CONTROLLER_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp ~/ovs.tar.gz ${CONTROLLER_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "scp ~/ovn.tar.gz ${CONTROLLER_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp ~/ovn.tar.gz ${CONTROLLER_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "${SSH} tar -C / -xzf /root/ovs.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -xzf /root/ovs.tar.gz
    echo "${SSH} 'cd /root/ovs; make install'"
    ${SSH} 'cd /root/ovs; make install'
    echo "${SSH} tar -C / -xzf /root/ovn.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -xzf /root/ovn.tar.gz
    echo "${SSH} 'cd /root/ovn; make install;"
    ${SSH} 'cd /root/ovn; make install'
  else
  # Build ovs and ovn from git repos as supplied alpine packages are not the latest
    read -p "Build OVS on ${CONTROLLER_NAME}-${i}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "cd ~" 2>&1 | tee -a $0.log
      cd ~
      echo "git clone -b ${OVS_VERSION} --depth 1 ${OVS_GIT_REPO}" 2>&1 | tee -a $0.log
      git clone -b ${OVS_VERSION} --depth 1 ${OVS_GIT_REPO} 2>&1 | tee -a $0.log
      echo "cd ~/ovs" 2>&1 | tee -a $0.log
      cd ~/ovs
      echo "~/ovs/boot.sh" 2>&1 | tee -a $0.log
      ~/ovs/boot.sh
      echo "~/ovs/configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc CFLAGS=\"-g -O2 -march=native\"" 2>&1 | tee -a $0.log
      ~/ovs/configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc CFLAGS="-g -O2 -march=native" 2>&1 | tee -a $0.log
      echo "make" 2>&1 | tee -a $0.log
      make 2>&1 | tee -a $0.log
      echo "tar -czf ~/ovs.tar.gz ~/ovs" 2>&1 | tee -a $0.log
      tar -czf ~/ovs.tar.gz ~/ovs
      echo "make install" 2>&1 | tee -a $0.log
      make install 2>&1 | tee -a $0.log
#      echo "tar -czf ~/ovs.tar.gz /usr/bin/ovs* /usr/bin/vtep* /etc/bash_completion.d/ovs* /var/lib/openvswitch /etc/openvswitch /usr/sbin/ovs* /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man5/vtep* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/man/man8/vtep* /usr/share/openvswitch /usr/include/openvswitch /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep*" 2>&1 | tee -a $0.log
#      tar -czf ~/ovs.tar.gz /usr/bin/ovs* /usr/sbin/ovs* /usr/bin/vtep* /etc/bash_completion.d/ovs* /var/lib/openvswitch /etc/openvswitch /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man5/vtep* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/man/man8/vtep* /usr/share/openvswitch /usr/include/openvswitch /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep*
    fi

    read -p "Build OVN on ${CONTROLLER_NAME}-${i}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "cd ~" 2>&1 | tee -a $0.log
      cd ~
      echo "git clone -b ${OVN_VERSION} --depth 1 ${OVN_GIT_REPO}" 2>&1 | tee -a $0.log
      git clone -b ${OVN_VERSION} --depth 1 ${OVN_GIT_REPO} 2>&1 | tee -a $0.log
      echo "cd ~/ovn" 2>&1 | tee -a $0.log
      cd ~/ovn
      echo "~/ovn/boot.sh" 2>&1 | tee -a $0.log
      ~/ovn/boot.sh 2>&1 | tee -a $0.log
      echo "~/ovn/configure --with-ovs-source=/root/ovs --with-ovs-build=/root/ovs --prefix=/usr --localstatedir=/var --sysconfdir=/etc CFLAGS=\"-g -O2 -march=native\"" 2>&1 | tee -a $0.log
      ~/ovn/configure --with-ovs-source=/root/ovs --with-ovs-build=/root/ovs --prefix=/usr --localstatedir=/var --sysconfdir=/etc CFLAGS="-g -O2 -march=native" 2>&1 | tee -a $0.log
      echo "make" 2>&1 | tee -a $0.log
      make 2>&1 | tee -a $0.log
      echo "tar -czf ~/ovn.tar.gz ~/ovn" 2>&1 | tee -a $0.log
      tar -czf ~/ovn.tar.gz ~/ovn
      echo "make install" 2>&1 | tee -a $0.log
      make install 2>&1 | tee -a $0.log
#      echo "tar -czf ~/ovn.tar.gz /usr/bin/ovn* /usr/share/man/man1/ovn* /usr/share/man/man5/ovn* /usr/share/man/man7/ovn* /usr/share/man/man8/ovn* /usr/share/ovn /usr/include/ovn /usr/lib/libovn*" 2>&1 | tee -a $0.log
#      tar -czf ~/ovn.tar.gz /usr/bin/ovn* /usr/share/man/man1/ovn* /usr/share/man/man5/ovn* /usr/share/man/man7/ovn* /usr/share/man/man8/ovn* /usr/share/ovn /usr/include/ovn /usr/lib/libovn*
    fi
  fi

  read -p "Setup OVS/OVN services on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    export IP_ADDR=${CONTROLLER_IP[${i}]}
    echo "IP_ADDR=${IP_ADDR}" 2>&1 | tee -a $0.log

    echo "envsubst '${IP_ADDR}' < ${BASE_DIR}/ovn/alpine/ovn-ovsdb-server-nb.template | ${SSH} dd status=none of=/etc/init.d/ovn-ovsdb-server-nb" 2>&1 | tee -a $0.log
    envsubst '${IP_ADDR}' < ${BASE_DIR}/ovn/alpine/ovn-ovsdb-server-nb.template | ${SSH} dd status=none of=/etc/init.d/ovn-ovsdb-server-nb
    echo "envsubst '${IP_ADDR}' < ${BASE_DIR}/ovn/alpine/ovn-ovsdb-server-sb.template | ${SSH} dd status=none of=/etc/init.d/ovn-ovsdb-server-sb" 2>&1 | tee -a $0.log
    envsubst '${IP_ADDR}' < ${BASE_DIR}/ovn/alpine/ovn-ovsdb-server-sb.template | ${SSH} dd status=none of=/etc/init.d/ovn-ovsdb-server-sb
    echo "envsubst '${OVN_NB_DB}${OVN_SB_DB}' < ${BASE_DIR}/ovn/alpine/ovn-northd.template | ${SSH} dd status=none of=/etc/init.d/ovn-northd" 2>&1 | tee -a $0.log
    envsubst '${OVN_NB_DB}${OVN_SB_DB}' < ${BASE_DIR}/ovn/alpine/ovn-northd.template | ${SSH} dd status=none of=/etc/init.d/ovn-northd

    echo "scp ${BASE_DIR}/ovn/alpine/ovn-controller ${CONTROLLER_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovn-controller ${CONTROLLER_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/ovn/alpine/ovsdb-server ${CONTROLLER_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovsdb-server ${CONTROLLER_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/ovn/alpine/ovs-vswitchd ${CONTROLLER_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovs-vswitchd ${CONTROLLER_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovn-controller" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovn-controller 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovn-northd" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovn-northd 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovsdb-server" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovsdb-server 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovs-vswitchd" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovs-vswitchd 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovn-ovsdb-server-nb" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovn-ovsdb-server-nb 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovn-ovsdb-server-sb" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovn-ovsdb-server-sb 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovn-controller 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovn-northd 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovsdb-server 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovs-vswitchd 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovn-ovsdb-server-nb 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovn-ovsdb-server-sb 2>&1 | tee -a $0.log
  fi

  echo "${SSH} mkdir -p /etc/openvswitch /var/run/openvswitch /var/lib/ovn /var/run/ovn" 2>&1 | tee -a $0.log
  ${SSH} mkdir -p /etc/openvswitch /var/run/openvswitch /var/lib/ovn /var/run/ovn 2>&1 | tee -a $0.log

  if (( i == 1 )); then
      
    if [[ -S /var/run/ovn/ovnnb_db.ctl ]]; then
      SID=`ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/sid OVN_Northbound`
      if [[ -n "${SID}" ]]; then
        read -p "This host is already a member of the OVN_Northbound cluster. Would you like to leave it? [y/N]"
        if [[ "${REPLY}" == "y" ]]; then
          ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/leave OVN_Northbound
          service ovn-ovsdb-server-nb stop
          rm -f /var/lib/ovn/ovnnb_db.db /var/lib/ovn/.ovnnb_db.db.~lock~
        fi
      fi
    fi  
    if [[ -S /var/run/ovn/ovnsb_db.ctl ]]; then
      SID=`ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/sid OVN_Southbound`
      if [[ -n "${SID}" ]]; then
        read -p "This host is already a member of the OVN_Southbound cluster. Would you like to leave it? [y/N]"
        if [[ "${REPLY}" == "y" ]]; then
          ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/leave OVN_Southbound
          service ovn-ovsdb-server-sb stop
          rm -f /var/lib/ovn/ovnsb_db.db /var/lib/ovn/.ovnsb_db.db.~lock~
        fi
      fi
    fi  

    read -p "Initiate OVN cluster on ${CONTROLLER_NAME}-${i}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then  

      echo "ovsdb-tool create-cluster /var/lib/ovn/ovnnb_db.db /usr/share/ovn/ovn-nb.ovsschema tcp:${CONTROLLER_IP[1]}:6643" 2>&1 | tee -a $0.log

      ovsdb-tool create-cluster /var/lib/ovn/ovnnb_db.db /usr/share/ovn/ovn-nb.ovsschema tcp:${CONTROLLER_IP[1]}:6643 2>&1 | tee -a $0.log

      echo "ovsdb-tool create-cluster /var/lib/ovn/ovnsb_db.db /usr/share/ovn/ovn-sb.ovsschema tcp:${CONTROLLER_IP[1]}:6644" 2>&1 | tee -a $0.log

      ovsdb-tool create-cluster /var/lib/ovn/ovnsb_db.db /usr/share/ovn/ovn-sb.ovsschema tcp:${CONTROLLER_IP[1]}:6644 2>&1 | tee -a $0.log
    
    fi

  else

    read -p "Join ${CONTROLLER_NAME}-${i} OVN cluster? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then  
      if [[ -S /var/run/ovn/ovnnb_db.ctl ]]; then
        SID=`ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound | grep ${CONTROLLER_IP[${i}] | awk '{print $1}'`
        if [[ -n "${SID}" ]]; then
          read -p "${CONTROLLER_NAME}-${i} is already a member of the OVN_Northbound cluster. Would you like to kick it off? [y/N]"
          if [[ "${REPLY}" == "y" ]]; then
            ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/kick OVN_Northbound ${SID}
            ${SSH} service ovn-ovsdb-server-nb stop
            ${SSH} "rm -f /var/lib/ovn/ovnnb_db.db /var/lib/ovn/.ovnnb_db.db.~lock~"
          fi
        fi
      fi  
      if [[ -S /var/run/ovn/ovnsb_db.ctl ]]; then
        SID=`ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/status OVN_Southbound | grep ${CONTROLLER_IP[${i}] | awk '{print $1}'`
        if [[ -n "${SID}" ]]; then
          read -p "${CONTROLLER_NAME}-${i} is already a member of the OVN_Southbound cluster. Would you like to kick it off? [y/N]"
          if [[ "${REPLY}" == "y" ]]; then
            ovn-appctl -t /var/run/ovn/ovnsb_db.ctl cluster/kick OVN_Southbound ${SID}
            ${SSH} service ovn-ovsdb-server-sb stop
            ${SSH} rm -f /var/lib/ovn/ovnsb_db.db /var/lib/ovn/.ovnsb_db.db.~lock~
          fi
        fi
      fi  

      SSH_COMMAND="ovsdb-tool join-cluster /var/lib/ovn/ovnnb_db.db OVN_Northbound tcp:${CONTROLLER_IP[${i}]}:6643 tcp:${CONTROLLER_IP[1]}:6643"

      echo "${SSH} ${SSH_COMMAND}" 2>&1 | tee -a $0.log
      ${SSH} ${SSH_COMMAND} 2>&1 | tee -a $0.log

      SSH_COMMAND="ovsdb-tool join-cluster /var/lib/ovn/ovnsb_db.db OVN_Southbound tcp:${CONTROLLER_IP[${i}]}:6644 tcp:${CONTROLLER_IP[1]}:6644"

      echo "${SSH} ${SSH_COMMAND}" 2>&1 | tee -a $0.log
      ${SSH} ${SSH_COMMAND} 2>&1 | tee -a $0.log
    fi
  fi

  echo "sleep 3" 2>&1 | tee -a $0.log
  sleep 3

  FILE_EXISTS=`${SSH} ls /etc/openvswitch/conf.db`
  if [[ -n "${FILE_EXISTS}" ]]; then
    read -p "There is an existing openvswitch database ${CONTROLLER_NAME}-${i}:/etc/openvswitch/conf.db. Would you like to remove it first? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      ${SSH} service ovsdb-server stop
      ${SSH} rm -f /etc/openvswitch/conf.db
    fi
  fi

  echo "${SSH} ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema" 2>&1 | tee -a $0.log
  ${SSH} ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema 2>&1 | tee -a $0.log

  echo "${SSH} service ovsdb-server start" 2>&1 | tee -a $0.log
  ${SSH} service ovsdb-server start 2>&1 | tee -a $0.log
  echo "${SSH} service ovs-vswitchd start" 2>&1 | tee -a $0.log
  ${SSH} service ovs-vswitchd start 2>&1 | tee -a $0.log

  echo "${SSH} service ovn-ovsdb-server-sb start" 2>&1 | tee -a $0.log
  ${SSH} service ovn-ovsdb-server-sb start 2>&1 | tee -a $0.log
  echo "${SSH} service ovn-ovsdb-server-nb start" 2>&1 | tee -a $0.log
  ${SSH} service ovn-ovsdb-server-nb start 2>&1 | tee -a $0.log
  echo "${SSH} service ovn-northd start" 2>&1 | tee -a $0.log
  ${SSH} service ovn-northd start 2>&1 | tee -a $0.log

  echo "${SSH} service ovn-controller start " 2>&1 | tee -a $0.log
  ${SSH} service ovn-controller start 2>&1 | tee -a $0.log

done

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do

  read -p "Configure OVS on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
  
    if (( i > 1 )); then
      SSH="ssh ${CONTROLLER_NAME}-${i}"
    else
      SSH=""
    fi

    SYSTEM_ID=`uuidgen`
    read -p "Set chassis system-id ${SYSTEM_ID}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:system-id=${SYSTEM_ID}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:system-id=${SYSTEM_ID} 2>&1 | tee -a $0.log
    fi

    read -p "Set chassis hostname to ${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:hostname=${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:hostname=${CONTROLLER_NAME}-${i}.${DOMAIN_NAME} 2>&1 | tee -a $0.log
    fi

    read -p "Set connections to ${OVN_SB_DB} for ovn-controller? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-remote=${OVN_SB_DB}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-remote=${OVN_SB_DB} 2>&1 | tee -a $0.log
    fi

    read -p "Set encapsulation type geneve for overlay logical switches? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-type=geneve" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-type=geneve 2>&1 | tee -a $0.log
    fi

    read -p "Configure a geneve tunnel to use IP address ${CONTROLLER_IP[${i}]} (must be assigned to the physical interface on a chassis)? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-ip=${CONTROLLER_IP[${i}]}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-ip=${CONTROLLER_IP[${i}]} 2>&1 | tee -a $0.log
    fi

    read -p "Gateway chassis needs a virtual bridge to the provider network, add ${BR_PROVIDER}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl add-br ${BR_PROVIDER}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl add-br ${BR_PROVIDER} 2>&1 | tee -a $0.log
    fi

    read -p "Plug physical interface ${PROVIDER_NETWORK_IFACE} to the virtual bridge ${BR_PROVIDER}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl add-port ${BR_PROVIDER} ${PROVIDER_NETWORK_IFACE}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl add-port ${BR_PROVIDER} ${PROVIDER_NETWORK_IFACE} 2>&1 | tee -a $0.log
    fi

    read -p "Gateway chassis needs a virtual bridge to the compute network, add ${BR_COMPUTE}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl add-br ${BR_COMPUTE}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl add-br ${BR_COMPUTE} 2>&1 | tee -a $0.log
    fi

    read -p "Plug physical interface ${COMPUTE_NETWORK_OVS_BRIDGING_IFACE} to the virtual bridge ${BR_COMPUTE}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl add-port ${BR_COMPUTE} ${COMPUTE_NETWORK_OVS_BRIDGING_IFACE}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl add-port ${BR_COMPUTE} ${COMPUTE_NETWORK_OVS_BRIDGING_IFACE} 2>&1 | tee -a $0.log
    fi

  # This creates a mapping between the bridge "br-provider" in OVS and a network named "provider" in OVN and
  # "br-compute" in OVS and a nework named "compute" in OVN
  # Network "provider" will have a localnet port connected to a bridged logical switch to bridge traffic to physical interface "eth1"
  # Network "compute" will have a localnet port connected to a bridged logical switch to bridge traffic to physical interface "eth2"         
    read -p "Create a mapping between the virtual bridges [${BR_PROVIDER}, ${BR_COMPUTE}] and networks [provider, compute]? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-bridge-mappings=provider:${BR_PROVIDER},compute:${BR_COMPUTE}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-bridge-mappings=provider:${BR_PROVIDER},compute:${BR_COMPUTE} 2>&1 | tee -a $0.log
    fi
  fi
done

read -p "Configure OVN? [y/N]"
if [[ "${REPLY}" == "y" ]]; then  

  read -p "Configure MAC address prefix ${OUI}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl set nb_global . options:mac_prefix=\"${OUI}\"" 2>&1 | tee -a $0.log
    ovn-nbctl set nb_global . options:mac_prefix="${OUI}" 2>&1 | tee -a $0.log
  fi

  # Create overlay logical switch "br-internal". It won't have a localnet port. 
  # Traffic destined to remote ports (on other chassis) will flow via geneve-encap tunneling
  read -p "Create an overlay logical switch ${BR_INTERNAL} for container network ${INTERNAL_NETWORK_CIDR}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl ls-add ${BR_INTERNAL} -- set logical_switch ${BR_INTERNAL} other-config:exclude_ips=\"${INTERNAL_NETWORK_DHCP_EXCLUDE_IPS}\" other-config:mac_only=\"false\" other-config:subnet=\"${INTERNAL_NETWORK_CIDR}\" other-config:mcast_flood_unregistered=\"false\" other_config:mcast_snoop=\"false\"" 2>&1 | tee -a $0.log
    ovn-nbctl ls-add ${BR_INTERNAL} -- set logical_switch ${BR_INTERNAL} other-config:exclude_ips="${INTERNAL_NETWORK_DHCP_EXCLUDE_IPS}" other-config:mac_only="false" other-config:subnet="${INTERNAL_NETWORK_CIDR}" other-config:mcast_flood_unregistered="false" other_config:mcast_snoop="false" 2>&1 | tee -a $0.log
  fi

  # Create bridged logical switch "br-provider". It will have localnet port to bridge traffic destined to remote ports 
  # (ports that are not on the same chassis) to physical network, i.e. interface "eth1", for example
  read -p "Create a bridged logical switch ${BR_PROVIDER} for the external (provider) network? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl ls-add ${BR_PROVIDER} -- set logical_switch ${BR_PROVIDER} other-config:mcast_flood_unregistered=\"false\" other_config:mcast_snoop=\"false\"" 2>&1 | tee -a $0.log
    ovn-nbctl ls-add ${BR_PROVIDER} -- set logical_switch ${BR_PROVIDER} other-config:mcast_flood_unregistered="false" other_config:mcast_snoop="false" 2>&1 | tee -a $0.log
  fi

  read -p "Create a bridged logical switch ${BR_COMPUTE} for controller and compute nodes network ${COMPUTE_NETWORK_CIDR}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl ls-add ${BR_COMPUTE} -- set logical_switch ${BR_COMPUTE} other-config:mcast_flood_unregistered=\"false\" other_config:mcast_snoop=\"false\"" 2>&1 | tee -a $0.log
    ovn-nbctl ls-add ${BR_COMPUTE} -- set logical_switch ${BR_COMPUTE} other-config:mcast_flood_unregistered="false" other_config:mcast_snoop="false" 2>&1 | tee -a $0.log
  fi

  read -p "Creates a virtual provider router between the overlay logical switch ${BR_INTERNAL} and the bridged logical switch ${BR_PROVIDER}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lr-add ${ROUTER_PROVIDER} -- lr-route-add ${ROUTER_PROVIDER} 0.0.0.0/0 ${EXTERNAL_NETWORK_GATEWAY} -- lr-route-add ${ROUTER_PROVIDER} ${COMPUTE_NETWORK_CIDR} 10.10.10.2 -- set logical_router ${ROUTER_PROVIDER} enabled=true" 2>&1 | tee -a $0.log
    ovn-nbctl lr-add ${ROUTER_PROVIDER} -- lr-route-add ${ROUTER_PROVIDER} 0.0.0.0/0 ${EXTERNAL_NETWORK_GATEWAY} -- lr-route-add ${ROUTER_PROVIDER} ${COMPUTE_NETWORK_CIDR} 10.10.10.2 -- set logical_router ${ROUTER_PROVIDER} enabled=true 2>&1 | tee -a $0.log
  fi

  read -p "Add an internal network interface ${INTERNAL_NETWORK_GATEWAY_CIDR} to the router ${ROUTER_PROVIDER}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-internal-gateway ${INTERNAL_NETWORK_GATEWAY_MAC} ${INTERNAL_NETWORK_GATEWAY_CIDR} -- lrp-set-enabled lrp-internal-gateway enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-internal-gateway ${INTERNAL_NETWORK_GATEWAY_MAC} ${INTERNAL_NETWORK_GATEWAY_CIDR} -- lrp-set-enabled lrp-internal-gateway enabled 2>&1 | tee -a $0.log
  fi

  read -p "Add a provider interface ${EXTERNAL_NETWORK_ROUTER_PORT_IP_CIDR} to the router ${ROUTER_PROVIDER}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-provider-network ${EXTERNAL_NETWORK_ROUTER_PORT_MAC} ${EXTERNAL_NETWORK_ROUTER_PORT_IP_CIDR} -- lrp-set-enabled lrp-provider-network enabled"
    ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-provider-network ${EXTERNAL_NETWORK_ROUTER_PORT_MAC} ${EXTERNAL_NETWORK_ROUTER_PORT_IP_CIDR} -- lrp-set-enabled lrp-provider-network enabled
  fi

  read -p "Add a inter-router interface 10.10.10.1/30 to the router ${ROUTER_PROVIDER} for ${ROUTER_COMPUTE} connection? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-compute-router ${INTER_ROUTER_PROVIDER_MAC} 10.10.10.1/30 -- lrp-set-enabled lrp-compute-router enabled"
    ovn-nbctl lrp-add ${ROUTER_PROVIDER} lrp-compute-router ${INTER_ROUTER_PROVIDER_MAC} 10.10.10.1/30 -- lrp-set-enabled lrp-compute-router enabled
  fi

  read -p "Creates a compute network router between the provider router and the bridged logical switch ${BR_COMPUTE}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lr-add ${ROUTER_COMPUTE} -- lr-route-add ${ROUTER_COMPUTE} ${INTERNAL_NETWORK_CIDR} 10.10.10.1 -- set logical_router ${ROUTER_COMPUTE} enabled=true" 2>&1 | tee -a $0.log
    ovn-nbctl lr-add ${ROUTER_COMPUTE} -- lr-route-add ${ROUTER_COMPUTE} ${INTERNAL_NETWORK_CIDR} 10.10.10.1 -- set logical_router ${ROUTER_COMPUTE} enabled=true 2>&1 | tee -a $0.log
  fi

  read -p "Add an inter-router network interface 10.10.10.2/30 to the router ${ROUTER_COMPUTE}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lrp-add ${ROUTER_COMPUTE} lrp-provider-router ${INTER_ROUTER_COMPUTE_MAC} 10.10.10.2/30 peer=lrp-compute-router -- lrp-set-enabled lrp-provider-router enabled -- set logical_router_port lrp-compute-router peer=lrp-provider-router" 2>&1 | tee -a $0.log
    ovn-nbctl lrp-add ${ROUTER_COMPUTE} lrp-provider-router ${INTER_ROUTER_COMPUTE_MAC} 10.10.10.2/30 peer=lrp-compute-router -- lrp-set-enabled lrp-provider-router enabled -- set logical_router_port lrp-compute-router peer=lrp-provider-router 2>&1 | tee -a $0.log
  fi

  read -p "Add an external interface ${COMPUTE_NETWORK_ROUTER_PORT_IP_CIDR} to the router ${ROUTER_COMPUTE}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lrp-add ${ROUTER_COMPUTE} lrp-compute-network ${COMPUTE_NETWORK_ROUTER_PORT_MAC} ${COMPUTE_NETWORK_ROUTER_PORT_IP_CIDR} -- lrp-set-enabled lrp-compute-network enabled"
    ovn-nbctl lrp-add ${ROUTER_COMPUTE} lrp-compute-network ${COMPUTE_NETWORK_ROUTER_PORT_MAC} ${COMPUTE_NETWORK_ROUTER_PORT_IP_CIDR} -- lrp-set-enabled lrp-compute-network enabled
  fi

  read -p "Create a HA chassis group controller_ha_chassis_group? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl ha-chassis-group-add controller_ha_chassis_group" 2>&1 | tee -a $0.log
    ovn-nbctl ha-chassis-group-add controller_ha_chassis_group 2>&1 | tee -a $0.log
  fi

  for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do

    if (( i > 1 )); then
      SSH="ssh ${CONTROLLER_NAME}-${i}"
    else
      SSH=""
    fi

    GATEWAY_CHASSIS=`${SSH} ovs-vsctl get open_vswitch . external_ids:system-id | tr -d "\""`
    echo "GATEWAY_CHASSIS=${GATEWAY_CHASSIS}" 2>&1 | tee -a $0.log

    read -p "Add ${CONTROLLER_NAME}-${i} chassis with UUID ${GATEWAY_CHASSIS} to the HA chassis group controller_ha_chassis_group? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then  
      echo "ovn-nbctl ha-chassis-group-add-chassis controller_ha_chassis_group ${GATEWAY_CHASSIS} $((MEDIAN_HA_CHASSIS_PRIORITY - ${i}))" 2>&1 | tee -a $0.log
      ovn-nbctl ha-chassis-group-add-chassis controller_ha_chassis_group ${GATEWAY_CHASSIS} $((MEDIAN_HA_CHASSIS_PRIORITY - ${i})) 2>&1 | tee -a $0.log
    fi
  done

  read -p "Assign HA chassis group controller_ha_chassis_group to the router's port for high availability? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "HA_GROUP_UUID=\`ovn-nbctl --columns _uuid find ha_chassis_group name=controller_ha_chassis_group|cut -f2 -d ':'|tr -d ' '\`" 2>&1 | tee -a $0.log
    HA_GROUP_UUID=`ovn-nbctl --columns _uuid find ha_chassis_group name=controller_ha_chassis_group|cut -f2 -d ':'|tr -d ' '`
    echo "HA_GROUP_UUID=${HA_GROUP_UUID}" 2>&1 | tee -a $0.log
    echo "ovn-nbctl set logical_router_port lrp-provider-network ha_chassis_group=${HA_GROUP_UUID}" 2>&1 | tee -a $0.log
    ovn-nbctl set logical_router_port lrp-provider-network ha_chassis_group=${HA_GROUP_UUID} 2>&1 | tee -a $0.log
    echo "ovn-nbctl set logical_router_port lrp-compute-network ha_chassis_group=${HA_GROUP_UUID}" 2>&1 | tee -a $0.log
    ovn-nbctl set logical_router_port lrp-compute-network ha_chassis_group=${HA_GROUP_UUID} 2>&1 | tee -a $0.log
  fi
 
  read -p "Configure SNAT on the router ${ROUTER_PROVIDER}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lr-nat-add ${ROUTER_PROVIDER} snat ${EXTERNAL_NETWORK_ROUTER_PORT_IP} ${INTERNAL_NETWORK_CIDR}" 2>&1 | tee -a $0.log
    ovn-nbctl lr-nat-add ${ROUTER_PROVIDER} snat ${EXTERNAL_NETWORK_ROUTER_PORT_IP} ${INTERNAL_NETWORK_CIDR} 2>&1 | tee -a $0.log
  fi

  if [[ "${OS_PUBLIC_ENDPOINT}" != "${OS_INTERNAL_ENDPOINT}" ]]; then
    read -p "Configure DNAT on the router ${ROUTER_PROVIDER}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then  
      echo "ovn-nbctl lr-nat-add ${ROUTER_PROVIDER} dnat ${OS_PUBLIC_ENDPOINT} ${OS_INTERNAL_ENDPOINT}" 2>&1 | tee -a $0.log
      ovn-nbctl lr-nat-add ${ROUTER_PROVIDER} dnat ${OS_PUBLIC_ENDPOINT} ${OS_INTERNAL_ENDPOINT} 2>&1 | tee -a $0.log
    fi
  fi

  read -p "Configure DNAT IP ${HAPROXY_PROXY_IP} on the router ${ROUTER_COMPUTE} to HAPROXY_IP ${HAPROXY_IP}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lr-nat-add ${ROUTER_COMPUTE} dnat ${HAPROXY_PROXY_IP} ${HAPROXY_IP}" 2>&1 | tee -a $0.log
    ovn-nbctl lr-nat-add ${ROUTER_COMPUTE} dnat ${HAPROXY_PROXY_IP} ${HAPROXY_IP} 2>&1 | tee -a $0.log
  fi

  read -p "Add a port to ${BR_INTERNAL} to connect the provider network router? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lsp-add ${BR_INTERNAL} lsp-internal-gateway-port -- lsp-set-type lsp-internal-gateway-port router -- lsp-set-addresses lsp-internal-gateway-port router -- lsp-set-options lsp-internal-gateway-port router-port=lrp-internal-gateway -- lsp-set-enabled lsp-internal-gateway-port enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lsp-add ${BR_INTERNAL} lsp-internal-gateway-port -- lsp-set-type lsp-internal-gateway-port router -- lsp-set-addresses lsp-internal-gateway-port router -- lsp-set-options lsp-internal-gateway-port router-port=lrp-internal-gateway -- lsp-set-enabled lsp-internal-gateway-port enabled 2>&1 | tee -a $0.log
  fi

  read -p "Add a port to ${BR_PROVIDER} to connect the provider network router? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lsp-add ${BR_PROVIDER} lsp-provider-network-port -- lsp-set-type lsp-provider-network-port router -- lsp-set-addresses lsp-provider-network-port router -- lsp-set-options lsp-provider-network-port router-port=lrp-provider-network nat-addresses=router -- lsp-set-enabled lsp-provider-network-port enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lsp-add ${BR_PROVIDER} lsp-provider-network-port -- lsp-set-type lsp-provider-network-port router -- lsp-set-addresses lsp-provider-network-port router -- lsp-set-options lsp-provider-network-port router-port=lrp-provider-network nat-addresses=router -- lsp-set-enabled lsp-provider-network-port enabled 2>&1 | tee -a $0.log
  fi

  read -p "Bridge the logical switch ${BR_PROVIDER} to the physical network "provider" via localnet port? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lsp-add ${BR_PROVIDER} lsp-provider-localnet-port -- lsp-set-type lsp-provider-localnet-port localnet -- lsp-set-addresses lsp-provider-localnet-port unknown -- lsp-set-options lsp-provider-localnet-port network_name=\"provider\" -- lsp-set-enabled lsp-provider-localnet-port enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lsp-add ${BR_PROVIDER} lsp-provider-localnet-port -- lsp-set-type lsp-provider-localnet-port localnet -- lsp-set-addresses lsp-provider-localnet-port unknown -- lsp-set-options lsp-provider-localnet-port network_name="provider" -- lsp-set-enabled lsp-provider-localnet-port enabled 2>&1 | tee -a $0.log
  fi

  read -p "Add a port to ${BR_COMPUTE} to connect the compute network router? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lsp-add ${BR_COMPUTE} lsp-compute-network-port -- lsp-set-type lsp-compute-network-port router -- lsp-set-addresses lsp-compute-network-port router -- lsp-set-options lsp-compute-network-port router-port=lrp-compute-network nat-addresses=router -- lsp-set-enabled lsp-compute-network-port enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lsp-add ${BR_COMPUTE} lsp-compute-network-port -- lsp-set-type lsp-compute-network-port router -- lsp-set-addresses lsp-compute-network-port router -- lsp-set-options lsp-compute-network-port router-port=lrp-compute-network nat-addresses=router -- lsp-set-enabled lsp-compute-network-port enabled 2>&1 | tee -a $0.log
  fi

  read -p "Bridge the logical switch ${BR_COMPUTE} to the physical network "compute" via localnet port? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl lsp-add ${BR_COMPUTE} lsp-compute-localnet-port -- lsp-set-type lsp-compute-localnet-port localnet -- lsp-set-addresses lsp-compute-localnet-port unknown -- lsp-set-options lsp-compute-localnet-port network_name=\"compute\" -- lsp-set-enabled lsp-compute-localnet-port enabled" 2>&1 | tee -a $0.log
    ovn-nbctl lsp-add ${BR_COMPUTE} lsp-compute-localnet-port -- lsp-set-type lsp-compute-localnet-port localnet -- lsp-set-addresses lsp-compute-localnet-port unknown -- lsp-set-options lsp-compute-localnet-port network_name="compute" -- lsp-set-enabled lsp-compute-localnet-port enabled 2>&1 | tee -a $0.log
  fi

  # domain_name option does not work!!!
  # if specified, DHCP will stop working!!!
  read -p "Create a DHCP server? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl dhcp-options-create ${INTERNAL_NETWORK_CIDR}" 2>&1 | tee -a $0.log
    ovn-nbctl dhcp-options-create ${INTERNAL_NETWORK_CIDR}
  fi

  DHCP_OPTIONS=`ovn-nbctl find dhcp_options cidr="${INTERNAL_NETWORK_CIDR}"|grep _uuid|tr -d " "|cut -f2 -d":"`
  echo "DHCP_OPTIONS=${DHCP_OPTIONS}" 2>&1 | tee -a $0.log

  read -p "Configure DHCP options? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then  
    echo "ovn-nbctl dhcp-options-set-options ${DHCP_OPTIONS} router=${INTERNAL_NETWORK_GATEWAY} server_mac=\"${INTERNAL_NETWORK_DHCP_SERVER_MAC}\" mtu=1442 classless_static_route=\"{${COMPUTE_NETWORK_CIDR},${COMPUTE_NETWORK_GATEWAY}, 0.0.0.0/0,${INTERNAL_NETWORK_GATEWAY}}\" dns_server=\"{${DNS_SERVERS}}\" netmask=${INTERNAL_NETWORK_MASK} server_id=${INTERNAL_NETWORK_GATEWAY} lease_time=${INTERNAL_NETWORK_DHCP_LEASE_TIME}" 2>&1 | tee -a $0.log
    ovn-nbctl dhcp-options-set-options ${DHCP_OPTIONS} router=${INTERNAL_NETWORK_GATEWAY} server_mac="${INTERNAL_NETWORK_DHCP_SERVER_MAC}" mtu=1442 classless_static_route="{0.0.0.0/0,${INTERNAL_NETWORK_GATEWAY}}" dns_server="{${DNS_SERVERS}}" netmask=${INTERNAL_NETWORK_MASK} server_id=${INTERNAL_NETWORK_GATEWAY} lease_time=${INTERNAL_NETWORK_DHCP_LEASE_TIME} 2>&1 | tee -a $0.log
  fi
fi

# This might not be necessary... need to check once the bug related to ha_chassis_group and non-functioning BFD is addressed
for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do

  read -p "Restart ovs-switchd service on ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
  
    if (( i > 1 )); then
      SSH="ssh ${CONTROLLER_NAME}-${i}"
    else
      SSH=""
    fi
    echo "${SSH} service ovs-vswitchd restart" 2>&1 | tee -a $0.log
    ${SSH} service ovs-vswitchd restart 2>&1 | tee -a $0.log
  fi
done
