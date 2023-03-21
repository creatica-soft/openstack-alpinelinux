#!/usr/bin/bash

# This script will create a base image used to clone linux container from

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

#source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

LXC="lxc-attach --keep-env -n ${DOWNLOAD_DIST} --"

read -p "Download distribution \"${DOWNLOAD_DIST}\" release \"${DOWNLOAD_RELEASE}\" architecture \"${DOWNLOAD_ARCH}\" as a base image for openstack containers? [y/N]"

if [[ "${REPLY}" == "y" ]]; then

  case "${DOWNLOAD_DIST}" in
  "ubuntu")
  
    echo "lxc-create -n ${DOWNLOAD_DIST} -t download -B rbd --rbdpool=${RBD_POOL} --fssize=${RBD_FSSIZE} -- -d ${DOWNLOAD_DIST} -r ${DOWNLOAD_RELEASE} -a ${DOWNLOAD_ARCH}" 2>&1 | tee -a $0.log
  
    lxc-create -n ${DOWNLOAD_DIST} -t download -B rbd --rbdpool=${RBD_POOL} --fssize=${RBD_FSSIZE} -- -d ${DOWNLOAD_DIST} -r ${DOWNLOAD_RELEASE} -a ${DOWNLOAD_ARCH} 2>&1 | tee -a $0.log
  ;;
  "alpine")
    echo "lxc-create -n ${DOWNLOAD_DIST} -t download -B rbd --rbdpool=${RBD_POOL} --fssize=${RBD_FSSIZE} -- -d ${DOWNLOAD_DIST} -r ${DOWNLOAD_RELEASE} -a ${DOWNLOAD_ARCH}" 2>&1 | tee -a $0.log
  
    lxc-create -n ${DOWNLOAD_DIST} -t download -B rbd --rbdpool=${RBD_POOL} --fssize=${RBD_FSSIZE} -- -d ${DOWNLOAD_DIST} -r ${DOWNLOAD_RELEASE} -a ${DOWNLOAD_ARCH} 2>&1 | tee -a $0.log
  ;;
  esac
fi

read -p "Run apt or apk update and upgrade in a base image ${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE} downloaded in the previous step? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  ovn_nbctl_add_port "${BR_INTERNAL}" "${DOWNLOAD_DIST}" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

  lxc_config "${DOWNLOAD_DIST}"

  echo "lxc-start -n ${DOWNLOAD_DIST}" 2>&1 | tee -a $0.log
  lxc-start -n ${DOWNLOAD_DIST} 2>&1 | tee -a $0.log

  lxc_status ${DOWNLOAD_DIST}

  echo "envsubst < ${BASE_DIR}/common/resolv.conf.template > /tmp/resolv.conf"
  envsubst < ${BASE_DIR}/common/resolv.conf.template > /tmp/resolv.conf
  echo "${LXC} dd status=none of=/etc/resolv.conf < /tmp/resolv.conf" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/resolv.conf < /tmp/resolv.conf
  echo "rm -f /tmp/resolv.conf" 2>&1 | tee -a $0.log
  rm -f /tmp/resolv.conf 2>&1 | tee -a $0.log

  case "${DOWNLOAD_DIST}" in
  "ubuntu")
    echo "${LXC} sh -c \"apt update -y && apt upgrade -y && apt install -y ssh logrotate\"" 2>&1 | tee -a $0.log
    ${LXC} sh -c "apt update -y && apt upgrade -y && apt install -y ssh logrotate" 2>&1 | tee -a $0.log
    echo "${LXC} systemctl enable ssh" 2>&1 | tee -a $0.log
    ${LXC} systemctl enable ssh 2>&1 | tee -a $0.log
    echo "${LXC} ssh-keygen -q -f /root/.ssh/id_rsa -t rsa" 2>&1 | tee -a $0.log
    ${LXC} ssh-keygen -q -f /root/.ssh/id_rsa -t rsa 2>&1 | tee -a $0.log
    echo "${LXC} cp /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys" 2>&1 | tee -a $0.log
    ${LXC} cp /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
  ;;
  "alpine")
    echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache rsyslog logrotate openssh\"" 2>&1 | tee -a $0.log
    ${LXC} sh -c "apk update && apk upgrade && apk add --no-cache rsyslog logrotate openssh" 2>&1 | tee -a $0.log
    echo "${LXC} rc-update add sshd" 2>&1 | tee -a $0.log
    ${LXC} rc-update add sshd 2>&1 | tee -a $0.log
    echo "${LXC} ssh-keygen -q -f /root/.ssh/id_rsa -t rsa" 2>&1 | tee -a $0.log
    ${LXC} ssh-keygen -q -f /root/.ssh/id_rsa -t rsa 2>&1 | tee -a $0.log
    echo "${LXC} cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys" 2>&1 | tee -a $0.log
    ${LXC} cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    echo "${LXC} dd status=none of=/usr/share/udhcpc/default.script < ${BASE_DIR}/common/udhcpc.script" 2>&1 | tee -a $0.log
    ${LXC} dd status=none of=/usr/share/udhcpc/default.script < ${BASE_DIR}/common/udhcpc.script
    echo "envsubst < ${BASE_DIR}/common/rsyslog.conf-container.template > /tmp/rsyslog.conf" 2>&1 | tee -a $0.log
    envsubst < ${BASE_DIR}/common/rsyslog.conf-container.template > /tmp/rsyslog.conf
    echo "${LXC} dd status=none of=/etc/rsyslog.conf < /tmp/rsyslog.conf" 2>&1 | tee -a $0.log
    ${LXC} dd status=none of=/etc/rsyslog.conf < /tmp/rsyslog.conf
    echo "rm -f /tmp/rsyslog.conf" 2>&1 | tee -a $0.log
    rm -f /tmp/rsyslog.conf
    echo "${LXC} rc-update del syslog boot" 2>&1 | tee -a $0.log
    ${LXC} rc-update del syslog boot 2>&1 | tee -a $0.log
    echo "${LXC} rc-update add rsyslog boot" 2>&1 | tee -a $0.log
    ${LXC} rc-update add rsyslog boot 2>&1 | tee -a $0.log
    echo "${LXC} service syslog stop" 2>&1 | tee -a $0.log
    ${LXC} service syslog stop 2>&1 | tee -a $0.log
    echo "${SSH} service rsyslog start" 2>&1 | tee -a $0.log
    ${LXC} service rsyslog start 2>&1 | tee -a $0.log
  ;;
  esac
fi

lxc_set_hosts "${DOWNLOAD_DIST}"

read -p "Configure journal or syslog logfile rotation and vacuum [max_size ${JOURNALCTL_VACUUM_SIZE}] in the base image ${DOWNLOAD_DIST}? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  case "${DOWNLOAD_DIST}" in
  "ubuntu")
    CRONLINE=`echo "0 0 * * * journalctl --rotate --vacuum-size=${JOURNALCTL_VACUUM_SIZE}"`
    echo "${LXC} sh -c \"echo \"${CRONLINE}\" | crontab - \"" 2>&1 | tee -a $0.log
    ${LXC} sh -c "echo \"${CRONLINE}\" | crontab - " 2>&1 | tee -a $0.log
    ;;
  "alpine")
    echo "${LXC} sed -i \"/SYSLOGD_OPTS/c\SYSLOGD_OPTS=\"-t -s ${SYSLOG_SIZE} -b ${SYSLOG_FILES} -D\"\" /etc/conf.d/syslog" 2>&1 | tee -a $0.log
    ${LXC} sed -i "/SYSLOGD_OPTS/c\SYSLOGD_OPTS=\"-t\ -s\ ${SYSLOG_SIZE}\ -b\ ${SYSLOG_FILES}\ -D\"" /etc/conf.d/syslog 2>&1 | tee -a $0.log
    ;;
  esac
fi

echo "lxc-stop -n ${DOWNLOAD_DIST}" 2>&1 | tee -a $0.log
lxc-stop -n ${DOWNLOAD_DIST} 2>&1 | tee -a $0.log
lxc_snapshot "${DOWNLOAD_DIST}"
