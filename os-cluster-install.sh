#!/usr/bin/bash

# Openstack cluster install script. It's a wrapper for all the component scripts.

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

for SCRIPT in ovn rabbitmq memcached postgres haproxy keystone glance placement nova neutron cinder horizon compute-pre compute; do
  ${BASE_DIR}/${SCRIPT}/${DOWNLOAD_DIST}/${SCRIPT}-install.sh
  if (( $? != 0 )); then
    read -p "Continue? [y/N]"
    if [[ "${REPLY}" != "y" ]]; then
      exit 1
    fi
  fi
done

${BASE_DIR}/vm/vm-create.sh