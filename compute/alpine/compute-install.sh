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
echo "BR_PROVIDER=${BR_PROVIDER}" 2>&1 | tee -a $0.log
echo "PROVIDER_NETWORK_IFACE=${PROVIDER_NETWORK_IFACE}" 2>&1 | tee -a $0.log
echo "CEPH_CINDER_LOGIN=${CEPH_CINDER_LOGIN}" 2>&1 | tee -a $0.log
echo "CEPH_CINDER_KEY=********" 2>&1 | tee -a $0.log
echo "CEPH_SECRET_CINDER_UUID=${CEPH_SECRET_CINDER_UUID}" 2>&1 | tee -a $0.log
echo "LIBVIRT_TYPE=${LIBVIRT_TYPE}" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_COMPUTE_NODES; i++ )); do
  read -p "Install compute node ${COMPUTE_NODE_NAME}-${i}? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    continue
  fi
  export COMPUTE_NODE_IP_ADDR=${COMPUTE_NODE_IP[${i}]}
  echo "COMPUTE_NODE_IP_ADDR=${COMPUTE_NODE_IP_ADDR}" 2>&1 | tee -a $0.log

  SSH="ssh ${COMPUTE_NODE_NAME}-${i}"
  echo "SSH=${SSH}" 2>&1 | tee -a $0.log

  read -p 'Install nova (compute service)? [y/N]'
  if [[ "${REPLY}" == "y" ]]; then

    echo "scp ${NOVA_CONTAINER_NAME}-1:/root/nova.tar.gz /tmp/" 2>&1 | tee -a $0.log
    scp ${NOVA_CONTAINER_NAME}-1:/root/nova.tar.gz /tmp/ 2>&1 | tee -a $0.log
    echo "scp /tmp/nova.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp /tmp/nova.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "${SSH} tar -C / -zxf /root/nova.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -zxf /root/nova.tar.gz 2>&1 | tee -a $0.log
    echo "rm -f /tmp/nova.tar.gz" 2>&1 | tee -a $0.log
    rm -f /tmp/nova.tar.gz 2>&1 | tee -a $0.log
    echo "${SSH} ln -s /bin/nova-rootwrap /usr/bin/nova-rootwrap" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/nova-rootwrap /usr/bin/nova-rootwrap 2>&1 | tee -a $0.log

    echo "${SSH} apk add alpine-sdk curl python3 python3-dev libffi-dev openssl-dev libxml2-dev libxslt-dev py3-numpy-dev wget libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules dbus polkit-gnome polkit-kde-agent-1 sudo ${PSYCOPG2} py3-libvirt ceph-common" 2>&1 | tee -a $0.log
    ${SSH} apk add alpine-sdk curl python3 python3-dev libffi-dev openssl-dev libxml2-dev libxslt-dev py3-numpy-dev wget libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules dbus polkit-gnome polkit-kde-agent-1 sudo ${PSYCOPG2} py3-libvirt  ceph-common 2>&1 | tee -a $0.log

    TUN=`${SSH} lsmod|grep tun`
    if [[ -z "${TUN}" ]]; then
      echo "${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<\"tun\"" 2>&1 | tee -a $0.log
      ${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<"tun"

      echo "${SSH} modprobe tun" 2>&1 | tee -a $0.log
      ${SSH} modprobe tun 2>&1 | tee -a $0.log
    fi
#    OPENVSWITCH=`${SSH} lsmod|grep openvswitch`
#    if [[ -z "${OPENVSWITCH}" ]]; then
#      echo "${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<\"openvswitch\"" 2>&1 | tee -a $0.log
#      ${SSH} dd status=none oflag=append conv=notrunc of=/etc/modules <<<"openvswitch"

#      echo "${SSH} modprobe openvswitch" 2>&1 | tee -a $0.log
#      ${SSH} modprobe openvswitch 2>&1 | tee -a $0.log
#    fi

# qemu-system-x86_64 comes without rbd support 
    QEMU_RBD_SUPPORT=`${SSH} ldd /usr/bin/qemu-system-x86_64|grep libr`
    echo "QEMU_RBD_SUPPORT=${QEMU_RBD_SUPPORT}" 2>&1 | tee -a $0.log
    if [[ "${QEMU_RBD_SUPPORT}" == "" ]]; then
      if (( i == 1 )); then
        QEMU_VERSION=`${SSH} apk info qemu-system-x86_64|grep -m 1 qemu-system-x86_64|cut -f4 -d"-"`
        echo "QEMU_VERSION=${QEMU_VERSION}" 2>&1 | tee -a $0.log
        echo "${SSH} apk add alpine-sdk ceph-dev samurai gcompat glib-dev pixman-dev perl" 2>&1 | tee -a $0.log
        ${SSH} apk add alpine-sdk ceph-dev samurai gcompat glib-dev pixman-dev perl 2>&1 | tee -a $0.log
        echo "${SSH} git clone -b v${QEMU_VERSION} --depth 1 https://github.com/qemu/qemu.git" 2>&1 | tee -a $0.log
        ${SSH} git clone -b v${QEMU_VERSION} --depth 1 https://github.com/qemu/qemu.git 2>&1 | tee -a $0.log
        echo "${SSH} \"mkdir -p ~/qemu/build; cd ~/qemu/build; ../configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc --target-list=x86_64-softmmu --enable-rbd --disable-werror; make; cp qemu-system-x86_64 /usr/bin/\"" 2>&1 | tee -a $0.log
        ${SSH} "mkdir -p ~/qemu/build; cd ~/qemu/build; ../configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc --target-list=x86_64-softmmu --enable-rbd --disable-werror; make; cp qemu-system-x86_64 /usr/bin/" 2>&1 | tee -a $0.log
        echo "${SSH} apk del alpine-sdk samurai gcompat glib-dev pixman-dev perl" 2>&1 | tee -a $0.log
        ${SSH} apk del alpine-sdk samurai gcompat glib-dev pixman-dev perl 2>&1 | tee -a $0.log
      else
        echo "scp ${COMPUTE_NODE_NAME}-1:/usr/bin/qemu-system-x86_64 /tmp/" 2>&1 | tee -a $0.log
        scp ${COMPUTE_NODE_NAME}-1:/usr/bin/qemu-system-x86_64 /tmp/ 2>&1 | tee -a $0.log
        echo "scp /tmp/qemu-system-x86_64 ${COMPUTE_NODE_NAME}-${i}:/usr/bin/" 2>&1 | tee -a $0.log
        scp /tmp/qemu-system-x86_64 ${COMPUTE_NODE_NAME}-${i}:/usr/bin/ 2>&1 | tee -a $0.log
        echo "rm -f /tmp/qemu-system-x86_64" 2>&1 | tee -a $0.log
        rm -f /tmp/qemu-system-x86_64 2>&1 | tee -a $0.log
      fi
    fi

    echo "${SSH} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
    ${SSH} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

    echo "${SSH} python3 get-pip.py" 2>&1 | tee -a $0.log
    ${SSH} python3 get-pip.py 2>&1 | tee -a $0.log

    echo "${SSH} pip install ${PYMYSQL} python-memcached pynacl etcd3gw" 2>&1 | tee -a $0.log
    ${SSH} pip install ${PYMYSQL} python-memcached pynacl etcd3gw 2>&1 | tee -a $0.log

    PYTHON3_VERSION=`${SSH} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
    echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

    echo "${SSH} dd status=none of=/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
    ${SSH} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

    echo "${SSH} \"addgroup -S nova; adduser -S -D -h /var/lib/nova -G nova -g nova -s /bin/false nova; mkdir -p /var/log/nova; chown nova:adm /var/log/nova; chmod 750 /var/log/nova; mkdir -p /var/lib/nova/instances; chown nova:nova /var/lib/nova/instances\"" 2>&1 | tee -a $0.log
    ${SSH} "addgroup -S nova; adduser -S -D -h /var/lib/nova -G nova -g nova -s /bin/false nova; mkdir -p /var/log/nova; chown nova:adm /var/log/nova; chmod 750 /var/log/nova; mkdir -p /var/lib/nova/instances; chown nova:nova /var/lib/nova/instances" 2>&1 | tee -a $0.log

    echo "${SSH} \"addgroup nova libvirt\"" 2>&1 | tee -a $0.log
    ${SSH} "addgroup nova libvirt" 2>&1 | tee -a $0.log
    echo "${SSH} \"addgroup nova kvm\"" 2>&1 | tee -a $0.log
    ${SSH} "addgroup nova kvm" 2>&1 | tee -a $0.log

    echo "envsubst < ${BASE_DIR}/compute/nova.conf.template > /tmp/nova.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/nova.conf.template > /tmp/nova.conf
    echo "envsubst < ${BASE_DIR}/compute/nova-compute.conf.template > /tmp/nova-compute.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/nova-compute.conf.template > /tmp/nova-compute.conf
    echo "scp /tmp/nova.conf ${COMPUTE_NODE_NAME}-${i}:/etc/nova/" 2>&1 | tee -a $0.log
    scp /tmp/nova.conf ${COMPUTE_NODE_NAME}-${i}:/etc/nova/ 2>&1 | tee -a $0.log
    echo "scp /tmp/nova-compute.conf ${COMPUTE_NODE_NAME}-${i}:/etc/nova/" 2>&1 | tee -a $0.log
    scp /tmp/nova-compute.conf ${COMPUTE_NODE_NAME}-${i}:/etc/nova/ 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/compute/alpine/nova-compute ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/compute/alpine/nova-compute ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/nova-compute" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/nova-compute 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add nova-compute" 2>&1 | tee -a $0.log
    ${SSH} rc-update add nova-compute 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/nova/nova_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/nova/nova_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 440 /etc/sudoers.d/nova_sudoers" 2>&1 | tee -a $0.log
    ${SSH} chmod 440 /etc/sudoers.d/nova_sudoers 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/nova/alpine/nova-compute.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/nova-compute" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/nova/alpine/nova-compute.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/nova-compute 2>&1 | tee -a $0.log

    VMX=`${SSH} egrep -c '(vmx|svm)' /proc/cpuinfo`
    if (( ${VMX} == 0 )); then
      echo "${SSH} \"sed -i 's/#virt_type/virt_type/' /etc/nova/nova-compute.conf\"" 2>&1 | tee -a $0.log
      ${SSH} "sed -i 's/#virt_type/virt_type/' /etc/nova/nova-compute.conf"
    fi

    echo "${SSH} rc-update add dbus" 2>&1 | tee -a $0.log
    ${SSH} rc-update add dbus 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add libvirtd" 2>&1 | tee -a $0.log
    ${SSH} rc-update add libvirtd 2>&1 | tee -a $0.log
    echo "${SSH} service dbus start" 2>&1 | tee -a $0.log
    ${SSH} service dbus start 2>&1 | tee -a $0.log
    echo "${SSH} service libvirtd start" 2>&1 | tee -a $0.log
    ${SSH} service libvirtd start 2>&1 | tee -a $0.log
    echo "rm -f /tmp/nova.conf /tmp/nova-compute.conf" 2>&1 | tee -a $0.log
    rm -f /tmp/nova.conf /tmp/nova-compute.conf 2>&1 | tee -a $0.log

    echo "${SSH} service nova-compute start" 2>&1 | tee -a $0.log
    ${SSH} service nova-compute start 2>&1 | tee -a $0.log
  fi

  read -p "Install cinder-volume? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then

    echo "${SSH} apk add open-iscsi" 2>&1 | tee -a $0.log
    ${SSH} apk add open-iscsi 2>&1 | tee -a $0.log
    echo "scp ${CINDER_CONTAINER_NAME}-1:/root/cinder.tar.gz /tmp/" 2>&1 | tee -a $0.log
    scp ${CINDER_CONTAINER_NAME}-1:/root/cinder.tar.gz /tmp/ 2>&1 | tee -a $0.log
    echo "scp /tmp/cinder.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp /tmp/cinder.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "${SSH} tar -C / -zxf /root/cinder.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -zxf /root/cinder.tar.gz 2>&1 | tee -a $0.log
    echo "rm -rf /tmp/cinder.tar.gz" 2>&1 | tee -a $0.log
    rm -rf /tmp/cinder.tar.gz 2>&1 | tee -a $0.log
    echo "${SSH} ln -s /bin/cinder-rootwrap /usr/bin/cinder-rootwrap" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/cinder-rootwrap /usr/bin/cinder-rootwrap 2>&1 | tee -a $0.log

    echo "${SSH} \"addgroup -S cinder; adduser -S -D -h /var/lib/cinder -G cinder -g cinder -s /bin/false cinder; mkdir -p /var/log/cinder; chown cinder:adm /var/log/cinder; chmod 750 /var/log/cinder\"" 2>&1 | tee -a $0.log
    ${SSH} "addgroup -S cinder; adduser -S -D -h /var/lib/cinder -G cinder -g cinder -s /bin/false cinder; mkdir -p /var/log/cinder; chown cinder:adm /var/log/cinder; chmod 750 /var/log/cinder" 2>&1 | tee -a $0.log

    echo "envsubst < ${BASE_DIR}/compute/cinder.conf.template > /tmp/cinder.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/cinder.conf.template > /tmp/cinder.conf
    echo "scp /tmp/cinder.conf ${COMPUTE_NODE_NAME}-${i}:/etc/cinder/" 2>&1 | tee -a $0.log
    scp /tmp/cinder.conf ${COMPUTE_NODE_NAME}-${i}:/etc/cinder/ 2>&1 | tee -a $0.log
    echo "rm -f /tmp/cinder.conf" 2>&1 | tee -a $0.log
    rm -f /tmp/cinder.conf 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/compute/alpine/cinder-volume ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log"
    scp ${BASE_DIR}/compute/alpine/cinder-volume ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/cinder-volume" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/cinder-volume 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add cinder-volume" 2>&1 | tee -a $0.log
    ${SSH} rc-update add cinder-volume 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/cinder/cinder_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/cinder/cinder_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 440 /etc/sudoers.d/cinder_sudoers" 2>&1 | tee -a $0.log
    ${SSH} chmod 440 /etc/sudoers.d/cinder_sudoers 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/cinder/alpine/cinder-volume.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/cinder-volume" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/cinder/alpine/cinder-volume.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/cinder-volume 2>&1 | tee -a $0.log

    echo "${SSH} service cinder-volume start" 2>&1 | tee -a $0.log
    ${SSH} service cinder-volume start 2>&1 | tee -a $0.log

  fi

  read -p "Configure ceph client for cinder? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} apk add open-iscsi ceph-common py3-rbd" 2>&1 | tee -a $0.log
    ${SSH} apk add open-iscsi ceph-common py3-rbd 2>&1 | tee -a $0.log
    echo "envsubst '\${CEPH_CLUSTER_ID}\${CEPH_NODE_IP1}\${CEPH_NODE_IP2}\${CEPH_NODE_IP3}' < ${BASE_DIR}/compute/ceph.conf.template > /tmp/ceph.conf" 2>&1 | tee -a $0.log
    envsubst '${CEPH_CLUSTER_ID}${CEPH_NODE_IP1}${CEPH_NODE_IP2}${CEPH_NODE_IP3}' < ${BASE_DIR}/compute/ceph.conf.template > /tmp/ceph.conf
    echo "scp /tmp/ceph.conf ${COMPUTE_NODE_NAME}-${i}:/etc/ceph/" 2>&1 | tee -a $0.log
    scp /tmp/ceph.conf ${COMPUTE_NODE_NAME}-${i}:/etc/ceph/ 2>&1 | tee -a $0.log
    echo "rm -f /tmp/ceph.conf" 2>&1 | tee -a $0.log
    rm -f /tmp/ceph.conf 2>&1 | tee -a $0.log
    echo "${SSH} mkdir -p /var/run/ceph/guests/ /var/log/qemu/" 2>&1 | tee -a $0.log
    ${SSH} mkdir -p /var/run/ceph/guests/ /var/log/qemu/ 2>&1 | tee -a $0.log
    echo "${SSH} chown qemu:qemu /var/run/ceph/guests /var/log/qemu/" 2>&1 | tee -a $0.log
    ${SSH} chown qemu:qemu /var/run/ceph/guests /var/log/qemu/ 2>&1 | tee -a $0.log
    echo "envsubst < ${BASE_DIR}/compute/ceph.client.cinder.keyring.template > /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/ceph.client.cinder.keyring.template > /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring
    echo "scp /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring ${COMPUTE_NODE_NAME}-${i}:/etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring" 2>&1 | tee -a $0.log
    scp /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring ${COMPUTE_NODE_NAME}-${i}:/etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring 2>&1 | tee -a $0.log
    echo "rm -f /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring" 2>&1 | tee -a $0.log
    rm -f /tmp/ceph.client.${CEPH_CINDER_LOGIN}.keyring 2>&1 | tee -a $0.log

    echo "${SSH} chown cinder:cinder /etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring" 2>&1 | tee -a $0.log
    ${SSH} chown cinder:cinder /etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring 2>&1 | tee -a $0.log
    echo "${SSH} chmod 640 /etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring" 2>&1 | tee -a $0.log
    ${SSH} chmod 640 /etc/ceph/ceph.client.${CEPH_CINDER_LOGIN}.keyring 2>&1 | tee -a $0.log
    echo "envsubst < ${BASE_DIR}/compute/secret.xml.template > /tmp/secret.xml" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/secret.xml.template > /tmp/secret.xml
    echo "scp /tmp/secret.xml ${COMPUTE_NODE_NAME}-${i}:/tmp/" 2>&1 | tee -a $0.log
    scp /tmp/secret.xml ${COMPUTE_NODE_NAME}-${i}:/tmp/ 2>&1 | tee -a $0.log
    echo "${SSH} virsh secret-define --file /tmp/secret.xml" 2>&1 | tee -a $0.log
    ${SSH} virsh secret-define --file /tmp/secret.xml 2>&1 | tee -a $0.log
    echo "${SSH} virsh secret-set-value --secret ${CEPH_SECRET_CINDER_UUID} --base64 ${CEPH_CINDER_KEY}" 2>&1 | tee -a $0.log
    ${SSH} virsh secret-set-value --secret ${CEPH_SECRET_CINDER_UUID} --base64 ${CEPH_CINDER_KEY} 2>&1 | tee -a $0.log
    echo "rm -f /tmp/secret.xml" 2>&1 | tee -a $0.log
    rm -f /tmp/secret.xml 2>&1 | tee -a $0.log
  fi

  read -p "Install OVN host and neutron OVN metadata agent? [y/N]"
  if [[ "${REPLY}" == "y" ]]; then
    echo "${SSH} apk add sudo alpine-sdk libcap-ng-dev unbound-dev autoconf automake libtool util-linux iproute2 tcpdump haproxy" 2>&1 | tee -a $0.log
    ${SSH} apk add sudo alpine-sdk libcap-ng-dev unbound-dev autoconf automake libtool util-linux iproute2 tcpdump haproxy 2>&1 | tee -a $0.log

    echo "scp ~/ovs.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp ~/ovs.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "scp ~/ovn.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp ~/ovn.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "${SSH} tar -C / -xzf /root/ovs.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -xzf /root/ovs.tar.gz
    echo "${SSH} 'cd /root/ovs; make install'"
    ${SSH} 'cd /root/ovs; make install'
    echo "${SSH} tar -C / -xzf /root/ovn.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -xzf /root/ovn.tar.gz
    echo "${SSH} 'cd /root/ovn; make install;"
    ${SSH} 'cd /root/ovn; make install'

    echo "scp ${NEUTRON_CONTAINER_NAME}-1:/root/neutron.tar.gz /tmp/" 2>&1 | tee -a $0.log
    scp ${NEUTRON_CONTAINER_NAME}-1:/root/neutron.tar.gz /tmp/ 2>&1 | tee -a $0.log
    echo "scp /tmp/neutron.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/" 2>&1 | tee -a $0.log
    scp /tmp/neutron.tar.gz ${COMPUTE_NODE_NAME}-${i}:/root/ 2>&1 | tee -a $0.log
    echo "${SSH} tar -C / -zxf /root/neutron.tar.gz" 2>&1 | tee -a $0.log
    ${SSH} tar -C / -zxf /root/neutron.tar.gz 2>&1 | tee -a $0.log
    echo "rm -rf /tmp/neutron.tar.gz" 2>&1 | tee -a $0.log
    rm -rf /tmp/neutron.tar.gz 2>&1 | tee -a $0.log
    echo "${SSH} ln -s /bin/privsep-helper /usr/sbin/privsep-helper" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/privsep-helper /usr/sbin/privsep-helper 2>&1 | tee -a $0.log
    echo "${SSH} ln -s /bin/neutron-rootwrap /usr/bin/neutron-rootwrap" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/neutron-rootwrap /usr/bin/neutron-rootwrap 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/neutron/neutron_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/neutron/neutron_sudoers ${COMPUTE_NODE_NAME}-${i}:/etc/sudoers.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 440 /etc/sudoers.d/neutron_sudoers" 2>&1 | tee -a $0.log
    ${SSH} chmod 440 /etc/sudoers.d/neutron_sudoers 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/neutron/alpine/neutron-ovn-metadata-agent.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/neutron-ovn-metadata-agent" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/neutron/alpine/neutron-ovn-metadata-agent.logrotate ${COMPUTE_NODE_NAME}-${i}:/etc/logrotate.d/neutron-ovn-metadata-agent 2>&1 | tee -a $0.log

    echo "${SSH} \"addgroup -S neutron; adduser -S -D -h /var/lib/neutron -G neutron -g neutron -s /bin/false neutron; mkdir -p /var/log/neutron; chown neutron:adm /var/log/neutron; chmod 750 /var/log/neutron\"" 2>&1 | tee -a $0.log
    ${SSH} "addgroup -S neutron; adduser -S -D -h /var/lib/neutron -G neutron -g neutron -s /bin/false neutron; mkdir -p /var/log/neutron; chown neutron:adm /var/log/neutron; chmod 750 /var/log/neutron" 2>&1 | tee -a $0.log

    echo "${SSH} ln -s /bin/privsep-helper /usr/sbin/privsep-helper" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/privsep-helper /usr/sbin/privsep-helper 2>&1 | tee -a $0.log
    echo "${SSH} ln -s /bin/neutron-rootwrap /usr/bin/neutron-rootwrap" 2>&1 | tee -a $0.log
    ${SSH} ln -s /bin/neutron-rootwrap /usr/bin/neutron-rootwrap 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/ovn/alpine/ovsdb-server ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovsdb-server ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/ovn/alpine/ovs-vswitchd ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovs-vswitchd ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "scp ${BASE_DIR}/ovn/alpine/ovn-controller ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/" 2>&1 | tee -a $0.log
    scp ${BASE_DIR}/ovn/alpine/ovn-controller ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log

    echo "${SSH} chmod 755 /etc/init.d/ovsdb-server" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovsdb-server 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovs-vswitchd" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovs-vswitchd 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/ovn-controller" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/ovn-controller 2>&1 | tee -a $0.log
   
    echo "${SSH} mkdir -p /var/log/openvswitch /var/log/ovn /var/run/ovn /var/run/openvswitch" 2>&1 | tee -a $0.log
    ${SSH} mkdir -p /var/log/openvswitch /var/log/ovn /var/run/ovn /var/run/openvswitch 2>&1 | tee -a $0.log

    echo "${SSH} rc-update add ovsdb-server" 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovsdb-server 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add ovs-vswitchd" 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovs-vswitchd 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add ovn-controller" 2>&1 | tee -a $0.log
    ${SSH} rc-update add ovn-controller 2>&1 | tee -a $0.log

    echo "${SSH} ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema" 2>&1 | tee -a $0.log
    ${SSH} ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema 2>&1 | tee -a $0.log

    echo "${SSH} service ovsdb-server start" 2>&1 | tee -a $0.log
    ${SSH} service ovsdb-server start 2>&1 | tee -a $0.log
    echo "${SSH} service ovs-vswitchd start" 2>&1 | tee -a $0.log
    ${SSH} service ovs-vswitchd start 2>&1 | tee -a $0.log

    echo "sleep 5" 2>&1 | tee -a $0.log
    sleep 5 2>&1 | tee -a $0.log

    SYSTEM_ID=`uuidgen`
    read -p "Set chassis's ${COMPUTE_NODE_NAME}-${i} system-id ${SYSTEM_ID}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:system-id=${SYSTEM_ID}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:system-id=${SYSTEM_ID} 2>&1 | tee -a $0.log
    fi

    read -p "Set chassis hostname to ${COMPUTE_NODE_NAME}-${i}? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:hostname=${COMPUTE_NODE_NAME}-${i}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:hostname=${COMPUTE_NODE_NAME}-${i} 2>&1 | tee -a $0.log
    fi

    read -p "Set connections to ${OVN_SB_DB} for ovn-controller? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-remote=${OVN_SB_DB}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-remote=${OVN_SB_DB} 2>&1 | tee -a $0.log
    fi

    read -p "Set encapculation type geneve for overlay logical switches? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-type=geneve" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-type=geneve 2>&1 | tee -a $0.log
    fi

    read -p "Configure a geneve tunnel to use IP address ${COMPUTE_NODE_IP_ADDR} (must be assigned to the physical interface on a chassis)? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-ip=${COMPUTE_NODE_IP_ADDR}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-encap-ip=${COMPUTE_NODE_IP_ADDR} 2>&1 | tee -a $0.log
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

  # This creates a mapping between the bridge "br-provider" in OVS and a network named "provider" in OVN
  # Network "provider" will have a localnet port connected to a bridged logical switch to bridge traffic to physical interface "eth1"
    read -p "Create a mapping between the virtual bridge ${BR_PROVIDER} and network provider? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-bridge-mappings=provider:${BR_PROVIDER}" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open_vswitch . external-ids:ovn-bridge-mappings=provider:${BR_PROVIDER} 2>&1 | tee -a $0.log
    fi
  fi

    read -p "Set this chassis as a gateway [ovn-cms-options]? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-vsctl set open . external-ids:ovn-cms-options=enable-chassis-as-gw" 2>&1 | tee -a $0.log
      ${SSH} ovs-vsctl set open . external-ids:ovn-cms-options=enable-chassis-as-gw 2>&1 | tee -a $0.log
    fi

    read -p "Configure OVS DB server to listen on 127.0.0.1:6640? [y/N]"
    if [[ "${REPLY}" == "y" ]]; then
      echo "${SSH} ovs-appctl -t ovsdb-server ovsdb-server/add-remote ptcp:6640:127.0.0.1" 2>&1 | tee -a $0.log
      ${SSH} ovs-appctl -t ovsdb-server ovsdb-server/add-remote ptcp:6640:127.0.0.1 2>&1 | tee -a $0.log
    fi

    echo "${SSH} service ovn-controller start" 2>&1 | tee -a $0.log
    ${SSH} service ovn-controller start 2>&1 | tee -a $0.log

    echo "envsubst < ${BASE_DIR}/compute/neutron.conf.template > /tmp/neutron.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/neutron.conf.template > /tmp/neutron.conf
    echo "envsubst < ${BASE_DIR}/compute/neutron_ovn_metadata_agent.ini.template > /tmp/neutron_ovn_metadata_agent.ini" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/compute/neutron_ovn_metadata_agent.ini.template > /tmp/neutron_ovn_metadata_agent.ini
    echo "scp /tmp/neutron.conf ${COMPUTE_NODE_IP_ADDR}:/etc/neutron/" 2>&1 | tee -a $0.log
    scp /tmp/neutron.conf ${COMPUTE_NODE_IP_ADDR}:/etc/neutron/ 2>&1 | tee -a $0.log
    echo "scp /tmp/neutron_ovn_metadata_agent.ini ${COMPUTE_NODE_IP_ADDR}:/etc/neutron/" 2>&1 | tee -a $0.log
    scp /tmp/neutron_ovn_metadata_agent.ini ${COMPUTE_NODE_IP_ADDR}:/etc/neutron/ 2>&1 | tee -a $0.log
    echo "rm -f /tmp/neutron.conf /tmp/neutron_ovn_metadata_agent.ini" 2>&1 | tee -a $0.log
    rm -f /tmp/neutron.conf /tmp/neutron_ovn_metadata_agent.ini 2>&1 | tee -a $0.log

    echo "scp ${BASE_DIR}/compute/alpine/neutron-ovn-metadata-agent ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log"
    scp ${BASE_DIR}/compute/alpine/neutron-ovn-metadata-agent ${COMPUTE_NODE_NAME}-${i}:/etc/init.d/ 2>&1 | tee -a $0.log
    echo "${SSH} chmod 755 /etc/init.d/neutron-ovn-metadata-agent" 2>&1 | tee -a $0.log
    ${SSH} chmod 755 /etc/init.d/neutron-ovn-metadata-agent 2>&1 | tee -a $0.log
    echo "${SSH} rc-update add neutron-ovn-metadata-agent" 2>&1 | tee -a $0.log
    ${SSH} rc-update add neutron-ovn-metadata-agent 2>&1 | tee -a $0.log

    echo "${SSH} service neutron-ovn-metadata-agent start" 2>&1 | tee -a $0.log
    ${SSH} service neutron-ovn-metadata-agent start 2>&1 | tee -a $0.log
  fi

  echo "Openstack ${OPENSTACK_VERSION} has been installed on the compute node ${COMPUTE_NODE_NAME}-${i}" 2>&1 | tee -a $0.log

done

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc
echo "openstack compute service list" 2>&1 | tee -a $0.log
openstack compute service list 2>&1 | tee -a $0.log
echo "openstack volume service list" 2>&1 | tee -a $0.log
openstack compute volume list 2>&1 | tee -a $0.log
echo "openstack network agent list" 2>&1 | tee -a $0.log
openstack network agent list 2>&1 | tee -a $0.log
