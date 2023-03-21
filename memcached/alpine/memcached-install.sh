#!/usr/bin/bash

# memcached - free open source, high-performance, distributed memory object caching system
# https://github.com/memcached/memcached/wiki/Install

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

CONTAINER_NAME=${MEMCACHED_CONTAINER_NAME}

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

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install memcached
LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache memcached\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache memcached" 2>&1 | tee -a $0.log

echo "${LXC} sed -i '/^LISTENON=/c\LISTENON=0.0.0.0' /etc/conf.d/memcached" 2>&1 | tee -a $0.log
${LXC} sed -i '/^LISTENON=/c\LISTENON=0.0.0.0' /etc/conf.d/memcached 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"rc-update add memcached\"" 2>&1 | tee -a $0.log
${LXC} sh -c "rc-update add memcached" 2>&1 | tee -a $0.log

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
  create_container "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" "${SSH}"
done
