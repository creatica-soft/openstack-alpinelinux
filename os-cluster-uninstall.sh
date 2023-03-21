#!/usr/bin/bash

# Openstack cluster uninstall script. It's a wrapper around all component install scripts.

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

${BASE_DIR}/vm/vm-delete.sh

if (( $? != 0 )); then
  read -p "Continue? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi
fi

${BASE_DIR}/compute/${DOWNLOAD_DIST}/compute-uninstall.sh

if (( $? != 0 )); then
  read -p "Continue? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi
fi

for CONTAINER_NAME in horizon cinder neutron nova placement glance keystone haproxy postgres memcached rabbitmq; do
  ${BASE_DIR}/container-uninstall.sh ${CONTAINER_NAME}
  if (( $? != 0 )); then
    read -p "Continue? [y/N]"
    if [[ "${REPLY}" != "y" ]]; then
      exit 1
    fi
  fi
done

${BASE_DIR}/ovn/${DOWNLOAD_DIST}/ovn-uninstall.sh

if (( $? != 0 )); then
  read -p "Continue? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi
fi

${BASE_DIR}/${DOWNLOAD_DIST}-post-uninstall.sh

if (( $? != 0 )); then
  read -p "Continue? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi
fi
