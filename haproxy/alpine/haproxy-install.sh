#!/usr/bin/bash

# haproxy - free open source reliable high performance TCP/HTTP load balancer
# keepalived - simple and robust facilities for loadbalancing and high-availability to Linux system and Linux based infrastructures
# http://www.haproxy.org/
# https://keepalived.org/

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${HAPROXY_CONTAINER_NAME}

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log
echo "CONTAINER_NAME=${CONTAINER_NAME}" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

# Create a virtual port for haproxy
ovn-nbctl --may-exist lsp-add ${BR_INTERNAL} ${CONTAINER_NAME} -- lsp-set-type ${CONTAINER_NAME} virtual -- lsp-set-enabled ${CONTAINER_NAME} enabled -- lsp-set-options ${CONTAINER_NAME} virtual-ip=${HAPROXY_IP} virtual-parents="${CONTAINER_NAME}-1,${CONTAINER_NAME}-2,${CONTAINER_NAME}-3" 2>&1 | tee -a $0.log

# Create DNS record for this virtual port
dns_update "${CONTAINER_NAME}" "${HAPROXY_IP}"
dns_reload

ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"
ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-2" "${CONTROLLER_NAME}-2.${DOMAIN_NAME}"
ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-3" "${CONTROLLER_NAME}-3.${DOMAIN_NAME}"

export IP_ADDR1=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-1 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
export IP_ADDR2=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-2 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
export IP_ADDR3=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-3 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

echo "IP_ADDR1=${IP_ADDR1}" 2>&1 | tee -a $0.log
echo "IP_ADDR2=${IP_ADDR2}" 2>&1 | tee -a $0.log
echo "IP_ADDR3=${IP_ADDR3}" 2>&1 | tee -a $0.log

lxc_config "${CONTAINER_NAME}-1"

# This does not work in alpine and doesn't seem to be needed even though it set to 0
# It could be related to the fact that the non-local IP is declared as virtual in OVN, which has local parents.
#echo "lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1" >> /var/lib/lxc/${CONTAINER_NAME}-1/config

echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

lxc_set_hostname "${CONTAINER_NAME}-1"
lxc_set_hosts "${CONTAINER_NAME}-1"

echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
echo "lxc-start -n  ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# install haproxy and keepalived

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache haproxy keepalived\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache haproxy keepalived" 2>&1 | tee -a $0.log

echo "${LXC} rc-update add haproxy" 2>&1 | tee -a $0.log
${LXC} rc-update add haproxy 2>&1 | tee -a $0.log

echo "${LXC} rc-update add keepalived" 2>&1 | tee -a $0.log
${LXC} rc-update add keepalived 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/haproxy/haproxy.cfg.template > /tmp/haproxy.cfg" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/haproxy/haproxy.cfg.template > /tmp/haproxy.cfg
echo "${LXC} dd status=none of=/etc/haproxy/haproxy.cfg < /tmp/haproxy.cfg" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/haproxy/haproxy.cfg < /tmp/haproxy.cfg
echo "rm -f /tmp/haproxy.cfg" 2>&1 | tee -a $0.log
rm -f /tmp/haproxy.cfg 2>&1 | tee -a $0.log

echo "${LXC} service haproxy start" 2>&1 | tee -a $0.log
${LXC} service haproxy start 2>&1 | tee -a $0.log
echo "${LXC} service haproxy status" 2>&1 | tee -a $0.log
${LXC} service haproxy status 2>&1 | tee -a $0.log

echo "${LXC} mkdir -p /etc/keepalived" 2>&1 | tee -a $0.log
${LXC} mkdir -p /etc/keepalived 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/haproxy/keepalived.conf.template > /tmp/keepalived.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/haproxy/keepalived.conf.template > /tmp/keepalived.conf
echo "${LXC} dd status=none of=/etc/keepalived/keepalived.conf < /tmp/keepalived.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/keepalived/keepalived.conf < /tmp/keepalived.conf
echo "rm -f /tmp/keepalived.conf" 2>&1 | tee -a $0.log
rm -f /tmp/keepalived.conf 2>&1 | tee -a $0.log

#echo "${LXC} service keepalived start" 2>&1 | tee -a $0.log
#${LXC} service keepalived start 2>&1 | tee -a $0.log
#echo "${LXC} service keepalived status" 2>&1 | tee -a $0.log
#${LXC} service keepalived status 2>&1 | tee -a $0.log

# stop the clone to make snapshot (probably not necessary)
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# create a snapshot of the first clone
lxc_snapshot "${CONTAINER_NAME}-1"

# create more clones from the snapshot
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "ssh ${CONTROLLER_NAME}-${i}"
done

# start the first clone
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# configure other clones
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"
  lxc_config "${CONTAINER_NAME}-${i}" "${SSH}"

#  echo "${SSH} dd status=none of=/var/lib/lxc/${CONTAINER_NAME}-${i}/config oflag=append conv=notrunc <<<\"lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1\""
#  ${SSH} dd status=none of=/var/lib/lxc/${CONTAINER_NAME}-${i}/config oflag=append conv=notrunc <<<"lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1"

  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log

  lxc_set_hostname "${CONTAINER_NAME}-${i}" "${SSH}"
  lxc_set_hosts "${CONTAINER_NAME}-${i}" "${SSH}"

  echo "${SSH} lxc-stop -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-stop -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  lxc_status "${CONTAINER_NAME}-${i}" "${SSH}"
done
