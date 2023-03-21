#!/usr/bin/bash

# Automation of openstack compute node (uninstall script)
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
echo "BR_PROVIDER=${BR_PROVIDER}" 2>&1 | tee -a $0.log
echo "PROVIDER_NETWORK_IFACE=${PROVIDER_NETWORK_IFACE}" 2>&1 | tee -a $0.log
echo "CEPH_CINDER_LOGIN=${CEPH_CINDER_LOGIN}" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_COMPUTE_NODES; i++ )); do
  read -p "Uninstall compute node ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi

  SSH="ssh ${COMPUTE_NODE_NAME}-${i}"

  read -p "Delete ceph-common and librbd python bindings? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} apk del open-iscsi ceph-common py3-rbd" 2>&1 | tee -a $0.log
    ${SSH} apt del open-iscsi ceph-common py3-rbd 2>&1 | tee -a $0.log
    echo "${SSH} rm -rf /etc/ceph" 2>&1 | tee -a $0.log
    ${SSH} rm -rf /etc/ceph 2>&1 | tee -a $0.log
    echo "${SSH} userdel ceph" 2>&1 | tee -a $0.log
    ${SSH} userdel ceph 2>&1 | tee -a $0.log
  fi

  read -p "Delete cinder ceph secret from libvirt? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    UUID=`${SSH} virsh secret-list|grep client.${CEPH_CINDER_LOGIN}|awk '{print $1}'`
    echo "UUID=${UUID}" 2>&1 | tee -a $0.log
    for uuid in ${UUID}; do
      if [[ "${uuid}" != "" ]]; then
        echo "${SSH} virsh secret-undefine ${uuid}" 2>&1 | tee -a $0.log
        ${SSH} virsh secret-undefine ${uuid} 2>&1 | tee -a $0.log
      fi
    done
  fi

  read -p "Delete cinder-volume? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} sh -c \"rm -rf /bin/cinder* /usr/bin/cinder* /etc/cinder /var/log/cinder /var/lib/cinder\"" 2>&1 | tee -a $0.log
    ${SSH} sh -c "rm -rf /bin/cinder* /usr/bin/cinder* /etc/cinder /var/log/cinder /var/lib/cinder" 2>&1 | tee -a $0.log
    echo "${SSH} deluser cinder" 2>&1 | tee -a $0.log
    ${SSH} deluser cinder 2>&1 | tee -a $0.log
    echo "${SSH} delgroup cinder" 2>&1 | tee -a $0.log
    ${SSH} delgroup cinder 2>&1 | tee -a $0.log
  fi

  read -p "Delete OVN host and neutron OVN metadata agent? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then

    echo "${SSH} service ovn-controller stop" 2>&1 | tee -a $0.log
    ${SSH} service ovn-controller stop 2>&1 | tee -a $0.log
    echo "${SSH} service ovs-vswitchd stop" 2>&1 | tee -a $0.log
    ${SSH} service ovs-vswitchd stop 2>&1 | tee -a $0.log
    echo "${SSH} service ovsdb-server stop" 2>&1 | tee -a $0.log
    ${SSH} service ovsdb-server stop 2>&1 | tee -a $0.log

    echo "${SSH} rm -f /etc/init.d/ovsdb-server /etc/init.d/ovs-vswitchd /etc/init.d/ovn-controller" 2>&1 | tee -a $0.log
    ${SSH} rm -f /etc/init.d/ovsdb-server /etc/init.d/ovs-vswitchd /etc/init.d/ovn-controller 2>&1 | tee -a $0.log

    echo "${SSH} apk del openvswitch openvswitch-ovn iproute2 haproxy" 2>&1 | tee -a $0.log
    ${SSH} apk del openvswitch openvswitch-ovn iproute2 haproxy 2>&1 | tee -a $0.log
    echo "${SSH} sh -c \"rm -rf /etc/neutron /bin/neutron* /usr/bin/neutron /var/log/ovn /var/lib/openvswitch /var/log/openvswitch /var/log/neutron /var/lib/neutron\"" 2>&1 | tee -a $0.log
    ${SSH} sh -c "rm -rf /etc/neutron /bin/neutron* /usr/bin/neutron /var/log/ovn /var/lib/openvswitch /var/log/openvswitch /var/log/neutron /var/lib/neutron" 2>&1 | tee -a $0.log
    echo "${SSH} deluser neutron" 2>&1 | tee -a $0.log
    ${SSH} deluser neutorn 2>&1 | tee -a $0.log
    echo "${SSH} delgroup neutron" 2>&1 | tee -a $0.log
    ${SSH} delgroup neutron 2>&1 | tee -a $0.log
  fi

  read -p "Delete nova-compute? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} service libvirtd stop" 2>&1 | tee -a $0.log
    ${SSH} service libvirtd stop 2>&1 | tee -a $0.log
    echo "${SSH} apk del python3 libffi openssl libxml2 libxslt py3-numpy wget libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules dbus polkit-gnome polkit-kde-agent-1" 2>&1 | tee -a $0.log
    ${SSH} apk del python3 libffi openssl libxml2 libxslt py3-numpy wget libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules dbus polkit-gnome polkit-kde-agent-1 2>&1 | tee -a $0.log
    echo "${SSH} sh -c \"rm -rf /bin/nova* /usr/bin/nova* /etc/nova /var/log/nova /var/lib/nova /var/log/libvirt /var/log/qemu\"" 2>&1 | tee -a $0.log
    ${SSH} sh -c "rm -rf /bin/nova* /usr/bin/nova* /etc/nova /var/log/nova /var/lib/nova /var/log/libvirt /var/log/qemu" 2>&1 | tee -a $0.log
    echo "${SSH} deluser nova" 2>&1 | tee -a $0.log
    ${SSH} deluser nova 2>&1 | tee -a $0.log
    echo "${SSH} delgroup nova" 2>&1 | tee -a $0.log
    ${SSH} delgroup nova 2>&1 | tee -a $0.log
  fi

  read -p "Delete DNS forward A and reverse PTR records for ${COMPUTE_NODE_NAME}-${i} with IP ${COMPUTE_NODE_IP_ADDR}? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    dns_delete "${COMPUTE_NODE_NAME}-${i}"
    dns_reload
  fi
  
  echo "Openstack ${OPENSTACK_VERSION} has been uninstalled from the compute node ${COMPUTE_NODE_NAME}-${i}" 2>&1 | tee -a $0.log

done