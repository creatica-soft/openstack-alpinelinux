#!/usr/bin/bash

# Containers uninstall script - undo *-install.sh 

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

CONTAINER_NAME=$1
if [[ ! -v CONTAINER_NAME ]]; then
  echo 'container-uninstall.sh usage: container-uninstall.sh <CONTAINER_NAME>'
  exit 1
fi

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log
echo "CONTAINER_NAME=${CONTAINER_NAME}" 2>&1 | tee -a $0.log

read -p "Uninstall ${CONTAINER_NAME} cluster? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

RBD="rbd -c ${CEPH_CONF} -k ${CEPH_CLIENT_KEYRING} -p ${RBD_POOL}"

for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"

  echo "${SSH} lxc-stop -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-stop -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
 
  echo "${SSH} lxc-destroy -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-destroy -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log

  echo "${SSH} ${RBD} device unmap /dev/rbd/${RBD_POOL}/${CONTAINER_NAME}-${i} --id ${CEPH_CLIENT}" 2>&1 | tee -a $0.log
  ${SSH} ${RBD} device unmap /dev/rbd/${RBD_POOL}/${CONTAINER_NAME}-${i} --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log

  echo "${RBD} rm ${CONTAINER_NAME}-${i} --id ${CEPH_CLIENT}" 2>&1 | tee -a $0.log
  ${RBD} rm ${CONTAINER_NAME}-${i} --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log
done

echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

echo "${RBD} snap unprotect --snap ${CONTAINER_NAME}-1 --image ${CONTAINER_NAME}-1 --id ${CEPH_CLIENT}" 2>&1 | tee -a $0.log
${RBD} snap unprotect --snap ${CONTAINER_NAME}-1 --image ${CONTAINER_NAME}-1 --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log

echo "${RBD} snap rm --snap ${CONTAINER_NAME}-1 ${CONTAINER_NAME}-1 --id ${CEPH_CLIENT} " 2>&1 | tee -a $0.log
${RBD} snap rm --snap ${CONTAINER_NAME}-1 ${CONTAINER_NAME}-1 --id ${CEPH_CLIENT} 2>&1 | tee -a $0.log

echo "lxc-destroy -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-destroy -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++)); do
  # delete DNS records
  dns_delete "${CONTAINER_NAME}-${i}"

  # delete port
  echo "ovn-nbctl --if-exists lsp-del ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ovn-nbctl --if-exists lsp-del ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
done

dns_reload

# post-uninstall for some containers

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc


LXC="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${CONTAINER_NAME}" in

"keystone")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE keystone;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE keystone;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE keystone;\"\"" 2>&1 | tee -a $0.log
  ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE keystone;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER keystone;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER keystone;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"
;;

"glance")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE glance;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE glance;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE glance;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE glance;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER glance;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER glance;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"

  echo "openstack role remove --project service --user glance admin" 2>&1 | tee -a $0.log
  openstack role remove --project service --user glance admin 2>&1 | tee -a $0.log

  echo "openstack user delete glance" 2>&1 | tee -a $0.log
  openstack user delete glance 2>&1 | tee -a $0.log

  echo "ENDPOINTS=\`openstack endpoint list -f value -c ID -c \"Service Name\"|grep glance\`" 2>&1 | tee -a $0.log
  ENDPOINTS=`openstack endpoint list -f value -c ID -c "Service Name"|grep glance|cut -f1 -d " "`

  for ENDPOINT in ${ENDPOINTS}; do
    echo "openstack endpoint delete ${ENDPOINT}" 2>&1 | tee -a $0.log
    openstack endpoint delete ${ENDPOINT} 2>&1 | tee -a $0.log
  done

  echo "openstack service delete image" 2>&1 | tee -a $0.log
  openstack service delete image 2>&1 | tee -a $0.log
;;

"placement")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE placement;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE placement;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE placement;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE placement;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER placement;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER placement;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"

  echo "openstack role remove --project service --user placement admin" 2>&1 | tee -a $0.log
  openstack role remove --project service --user placement admin 2>&1 | tee -a $0.log

  echo "openstack user delete placement" 2>&1 | tee -a $0.log
  openstack user delete placement 2>&1 | tee -a $0.log

  echo "ENDPOINTS=\`openstack endpoint list -f value -c ID -c \"Service Name\"|grep placement\`" 2>&1 | tee -a $0.log
  ENDPOINTS=`openstack endpoint list -f value -c ID -c "Service Name"|grep placement|cut -f1 -d " "`

  for ENDPOINT in ${ENDPOINTS}; do
    echo "openstack endpoint delete ${ENDPOINT}" 2>&1 | tee -a $0.log
    openstack endpoint delete ${ENDPOINT} 2>&1 | tee -a $0.log
  done

  echo "openstack service delete placement" 2>&1 | tee -a $0.log
  openstack service delete placement 2>&1 | tee -a $0.log

;;

"nova")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE nova_cell0; DROP DATABASE nova; DROP DATABASE nova_api;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE nova_cell0; DROP DATABASE nova; DROP DATABASE nova_api;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova_cell0;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova_cell0;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova_api;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE nova_api;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER nova;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER nova;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"

  echo "openstack role remove --project service --user nova admin" 2>&1 | tee -a $0.log
  openstack role remove --project service --user nova admin 2>&1 | tee -a $0.log

  echo "openstack user delete nova" 2>&1 | tee -a $0.log
  openstack user delete nova 2>&1 | tee -a $0.log

  echo "ENDPOINTS=\`openstack endpoint list -f value -c ID -c \"Service Name\"|grep compute\`" 2>&1 | tee -a $0.log
  ENDPOINTS=`openstack endpoint list -f value -c ID -c "Service Name"|grep compute|cut -f1 -d " "`

  for ENDPOINT in ${ENDPOINTS}; do
    echo "openstack endpoint delete ${ENDPOINT}" 2>&1 | tee -a $0.log
    openstack endpoint delete ${ENDPOINT} 2>&1 | tee -a $0.log
  done

  echo "openstack service list -f value -c ID -c Name|grep nova\`"
  SERVICES=`openstack service list -f value -c ID -c Name|grep nova`

  if [[ "${SERVICES}" != "" ]]; then
    SERVICES=`echo ${SERVICES}|cut -f1 -d " "`
    for SERVICE in ${SERVICES}; do
      echo "openstack service delete ${SERVICE}" 2>&1 | tee -a $0.log
      openstack service delete ${SERVICE} 2>&1 | tee -a $0.log
    done
  fi
;;

"neutron")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE neutron;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE neutron;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE neutron;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE neutron;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER neutron;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER neutron;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"

  echo "openstack role remove --project service --user neutron admin" 2>&1 | tee -a $0.log
  openstack role remove --project service --user neutron admin 2>&1 | tee -a $0.log

  echo "openstack user delete neutron" 2>&1 | tee -a $0.log
  openstack user delete neutron 2>&1 | tee -a $0.log

  echo "ENDPOINTS=\`openstack endpoint list -f value -c ID -c \"Service Name\"|grep network\`" 2>&1 | tee -a $0.log
  ENDPOINTS=`openstack endpoint list -f value -c ID -c "Service Name"|grep network|cut -f1 -d " "`

  for ENDPOINT in ${ENDPOINTS}; do
    echo "openstack endpoint delete ${ENDPOINT}" 2>&1 | tee -a $0.log
    openstack endpoint delete ${ENDPOINT} 2>&1 | tee -a $0.log
  done

  echo "openstack service list -f value -c ID -c Name|grep neutron\`"
  SERVICES=`openstack service list -f value -c ID -c Name|grep neutron|cut -f1 -d " "`

  for SERVICE in ${SERVICES}; do
    echo "openstack service delete ${SERVICE}" 2>&1 | tee -a $0.log
    openstack service delete ${SERVICE} 2>&1 | tee -a $0.log
  done
;;

"cinder")
  case "${SQL_CONTAINER_NAME}" in
  "mariadb")
    echo "${LXC} mysql -e \"DROP DATABASE cinder;\"" 2>&1 | tee -a $0.log
    ${LXC} mysql -e "DROP DATABASE cinder;" 2>&1 | tee -a $0.log
  ;;
  "postgres")
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE cinder;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP DATABASE cinder;\"" 2>&1 | tee -a $0.log
    echo "${LXC} su - postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER cinder;\"\"" 2>&1 | tee -a $0.log
    ${LXC} su - postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"DROP USER cinder;\"" 2>&1 | tee -a $0.log
  ;;
  esac
  haproxy_delete_rules "${CONTAINER_NAME}"

  echo "openstack role remove --project service --user cinder admin" 2>&1 | tee -a $0.log
  openstack role remove --project service --user cinder admin 2>&1 | tee -a $0.log

  echo "openstack user delete cinder" 2>&1 | tee -a $0.log
  openstack user delete cinder 2>&1 | tee -a $0.log

  echo "ENDPOINTS=\`openstack endpoint list -f value -c ID -c \"Service Name\"|grep volumev\`" 2>&1 | tee -a $0.log
  ENDPOINTS=`openstack endpoint list -f value -c ID -c "Service Name"|grep volumev|cut -f1 -d " "`

  for ENDPOINT in ${ENDPOINTS}; do
    echo "openstack endpoint delete ${ENDPOINT}" 2>&1 | tee -a $0.log
    openstack endpoint delete ${ENDPOINT} 2>&1 | tee -a $0.log
  done

  echo "openstack service list -f value -c ID -c Name|grep cinder\`"
  SERVICES=`openstack service list -f value -c ID -c Name|grep cinder|cut -f1 -d " "`

  for SERVICE in ${SERVICES}; do
    echo "openstack service delete ${SERVICE}" 2>&1 | tee -a $0.log
    openstack service delete ${SERVICE} 2>&1 | tee -a $0.log
  done
;;

"horizon")
  haproxy_delete_rules "${CONTAINER_NAME}"
;;

"bind")
  DHCP_OPTIONS=`ovn-nbctl find dhcp_options cidr="${INTERNAL_NETWORK_CIDR}"|grep _uuid|tr -d " "|cut -f2 -d":"`
  echo "DHCP_OPTIONS=${DHCP_OPTIONS}" 2>&1 | tee -a $0.log

  echo "ovn-nbctl set dhcp_options ${DHCP_OPTIONS} options:dns_server=\"{${${DNS_FORWARDER1},${DNS_FORWARDER2}}\"" 2>&1 | tee -a $0.log
  ovn-nbctl set dhcp_options ${DHCP_OPTIONS} options:dns_server="{${DNS_FORWARDER1},${DNS_FORWARDER2}}" 2>&1 | tee -a $0.log
;;

"postgres")
  echo "ovn-nbctl --if-exist lsp-del ${CONTAINER_NAME}" 2>&1 | tee -a $0.log
  ovn-nbctl --if-exist lsp-del ${CONTAINER_NAME}
  dns_delete "${CONTAINER_NAME}"
;;

"haproxy")
  echo "ovn-nbctl --if-exist lsp-del ${CONTAINER_NAME}" 2>&1 | tee -a $0.log
  ovn-nbctl --if-exist lsp-del ${CONTAINER_NAME}
;;

esac
