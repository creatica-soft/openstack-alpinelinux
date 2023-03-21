#!/usr/bin/bash

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  read -p "Uninstall ovn and ovs from ${CONTROLLER_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    continue
  fi

  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_IP[${i}]}"
  else
    SSH=""
  fi

  echo "${SSH} service ovn-northd stop" 2>&1 | tee -a $0.log
  ${SSH} service ovn-northd stop 2>&1 | tee -a $0.log
  echo "${SSH} service ovn-ovsdb-server-nb stop" 2>&1 | tee -a $0.log
  ${SSH} service ovn-ovsdb-server-nb stop 2>&1 | tee -a $0.log

  echo "${SSH} service ovn-controller stop " 2>&1 | tee -a $0.log
  ${SSH} service ovn-controller stop 2>&1 | tee -a $0.log

  echo "${SSH} service ovn-ovsdb-server-sb stop" 2>&1 | tee -a $0.log
  ${SSH} service ovn-ovsdb-server-sb stop 2>&1 | tee -a $0.log

  echo "${SSH} service ovs-vswitchd stop" 2>&1 | tee -a $0.log
  ${SSH} service ovs-vswitchd stop 2>&1 | tee -a $0.log
  echo "${SSH} service ovsdb-server stop" 2>&1 | tee -a $0.log
  ${SSH} service ovsdb-server stop 2>&1 | tee -a $0.log

  echo "${SSH} rc-update del ovn-northd" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovn-northd 2>&1 | tee -a $0.log
  echo "${SSH} rc-update del ovn-ovsdb-server-nb" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovn-ovsdb-server-nb 2>&1 | tee -a $0.log
  echo "${SSH} rc-update del ovn-controller" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovn-controller 2>&1 | tee -a $0.log
  echo "${SSH} rc-update del ovn-ovsdb-server-sb" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovn-ovsdb-server-sb 2>&1 | tee -a $0.log
  echo "${SSH} rc-update ovs-vswitchd" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovs-vswitchd 2>&1 | tee -a $0.log
  echo "${SSH} rc-update del ovsdb-server" 2>&1 | tee -a $0.log
  ${SSH} rc-update del ovsdb-server 2>&1 | tee -a $0.log

  echo "${SSH} apk del libcap-ng libcap-ng-dev unbound unbound-dev autoconf automake libtool util-linux iproute2 tcpdump" 2>&1 | tee -a $0.log
  ${SSH} apk del libcap-ng libcap-ng-dev unbound unbound-dev autoconf automake libtool util-linux iproute2 tcpdump 2>&1 | tee -a $0.log

  if (( i > 1 )); then
    echo "${SSH} rm -rf ~/ovs ~/ovn ~/ovn.tar.gz ~/ovs.tar.gz /etc/openvswitch /etc/bash_completion.d/ovs* /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep* /usr/lib/libovn* /usr/include/ovn /usr/include/openvswitch /usr/include/openflow /usr/bin/ovs* /usr/bin/vtep* /usr/sbin/ovs* /etc/openvswitch /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/openvswitch /usr/bin/ovn-* /usr/share/man/man1/ovn-* /usr/share/man/man5/ovn-* /usr/share/man/man7/ovn-* /usr/share/man/man8/ovn-* /usr/share/ovn /var/log/ovn /var/lib/ovn /var/log/openvswitch /var/lib/openvswitch" 2>&1 | tee -a $0.log
    ${SSH} rm -rf ~/ovs ~/ovn ~/ovn.tar.gz ~/ovs.tar.gz /etc/openvswitch /etc/bash_completion.d/ovs* /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep* /usr/lib/libovn* /usr/include/ovn /usr/include/openvswitch /usr/include/openflow /usr/bin/ovs* /usr/bin/vtep* /usr/sbin/ovs* /etc/openvswitch /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/openvswitch /usr/bin/ovn-* /usr/share/man/man1/ovn-* /usr/share/man/man5/ovn-* /usr/share/man/man7/ovn-* /usr/share/man/man8/ovn-* /usr/share/ovn /var/log/ovn /var/lib/ovn /var/log/openvswitch /var/lib/openvswitch 2>&1 | tee -a $0.log
  else
    echo "rm -rf ~/ovs ~/ovn ~/ovn.tar.gz ~/ovs.tar.gz /etc/openvswitch /etc/bash_completion.d/ovs* /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep* /usr/lib/libovn* /usr/include/ovn /usr/include/openvswitch /usr/include/openflow /usr/bin/ovs* /usr/bin/vtep* /usr/sbin/ovs* /etc/openvswitch /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/openvswitch /usr/bin/ovn-* /usr/share/man/man1/ovn-* /usr/share/man/man5/ovn-* /usr/share/man/man7/ovn-* /usr/share/man/man8/ovn-* /usr/share/ovn /var/log/ovn /var/lib/ovn /var/log/openvswitch /var/lib/openvswitch" 2>&1 | tee -a $0.log
    rm -rf ~/ovs ~/ovn ~/ovn.tar.gz ~/ovs.tar.gz /etc/openvswitch /etc/bash_completion.d/ovs* /usr/lib/libopenvswitch* /usr/lib/libsflow* /usr/lib/libofproto* /usr/lib/libofproto* /usr/lib/libvtep* /usr/lib/libovn* /usr/include/ovn /usr/include/openvswitch /usr/include/openflow /usr/bin/ovs* /usr/bin/vtep* /usr/sbin/ovs* /etc/openvswitch /usr/share/man/man1/ovs* /usr/share/man/man5/ovs* /usr/share/man/man7/ovs* /usr/share/man/man8/ovs* /usr/share/openvswitch /usr/bin/ovn-* /usr/share/man/man1/ovn-* /usr/share/man/man5/ovn-* /usr/share/man/man7/ovn-* /usr/share/man/man8/ovn-* /usr/share/ovn /var/log/ovn /var/lib/ovn /var/log/openvswitch /var/lib/openvswitch 2>&1 | tee -a $0.log
  fi
done
