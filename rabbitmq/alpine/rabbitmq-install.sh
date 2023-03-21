#!/usr/bin/bash

# Documentation https://www.rabbitmq.com/clustering.html

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

CONTAINER_NAME=${RABBITMQ_CONTAINER_NAME}
export RABBITMQ="rabbitmq_server"

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log
echo "CONTAINER_NAME=${CONTAINER_NAME}" 2>&1 | tee -a $0.log
echo "RABBITMQ_URL=${RABBITMQ_URL}" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

# clone the base image
lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# rabbitmq installation on the first clone

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache erlang xz wget\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache erlang xz wget" 2>&1 | tee -a $0.log

echo "${LXC} wget ${RABBITMQ_URL}" 2>&1 | tee -a $0.log
${LXC} wget ${RABBITMQ_URL} 2>&1 | tee -a $0.log

echo "${LXC} xz -d ${RABBITMQ_ARCHIVE}.tar.xz" 2>&1 | tee -a $0.log
${LXC} xz -d ${RABBITMQ_ARCHIVE}.tar.xz 2>&1 | tee -a $0.log

echo "${LXC} tar -xf -d ${RABBITMQ_ARCHIVE}.tar" 2>&1 | tee -a $0.log
${LXC} tar -xf ${RABBITMQ_ARCHIVE}.tar 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S rabbitmq && adduser -S -D -h /var/lib/rabbitmq -G rabbitmq -g rabbitmq -s /sbin/nologin rabbitmq && mkdir -p /var/lib/rabbitmq/mnesia && chown rabbitmq:rabbitmq /var/lib/rabbitmq/mnesia && cp -r /${RABBITMQ}-${RABBITMQ_VERSION}/plugins /var/lib/rabbitmq/ && mkdir -p /${RABBITMQ}-${RABBITMQ_VERSION}/var/log/rabbitmq && chown rabbitmq:rabbitmq /${RABBITMQ}-${RABBITMQ_VERSION}/var/log/rabbitmq\"" 2>&1 | tee -a $0.log

${LXC} sh -c "addgroup -S rabbitmq && adduser -S -D -h /var/lib/rabbitmq -G rabbitmq -g rabbitmq -s /sbin/nologin rabbitmq && mkdir -p /var/lib/rabbitmq/mnesia && chown rabbitmq:rabbitmq /var/lib/rabbitmq/mnesia && cp -r /${RABBITMQ}-${RABBITMQ_VERSION}/plugins /var/lib/rabbitmq/ && mkdir -p /${RABBITMQ}-${RABBITMQ_VERSION}/var/log/rabbitmq && chown rabbitmq:rabbitmq /${RABBITMQ}-${RABBITMQ_VERSION}/var/log/rabbitmq" 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/rabbitmq/alpine/rabbitmq.conf.template > /tmp/rabbitmq.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/rabbitmq/alpine/rabbitmq.conf.template > /tmp/rabbitmq.conf
echo "${LXC} dd status=none of=/${RABBITMQ}-${RABBITMQ_VERSION}/etc/rabbitmq/rabbitmq.conf < /tmp/rabbitmq.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/${RABBITMQ}-${RABBITMQ_VERSION}/etc/rabbitmq/rabbitmq.conf < /tmp/rabbitmq.conf 2>&1 | tee -a $0.log
echo "rm -r /tmp/rabbitmq.conf" 2>&1 | tee -a $0.log
rm -r /tmp/rabbitmq.conf 2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/${RABBITMQ}-${RABBITMQ_VERSION}/etc/rabbitmq/rabbitmq-env.conf < ${BASE_DIR}/rabbitmq/alpine/rabbitmq-env.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/${RABBITMQ}-${RABBITMQ_VERSION}/etc/rabbitmq/rabbitmq-env.conf < ${BASE_DIR}/rabbitmq/alpine/rabbitmq-env.conf 2>&1 | tee -a $0.log

echo "envsubst '\${RABBITMQ} \${RABBITMQ_VERSION}' < ${BASE_DIR}/rabbitmq/alpine/rabbitmq-server.template > /tmp/rabbitmq-server" 2>&1 | tee -a $0.log
envsubst '\${RABBITMQ} \${RABBITMQ_VERSION}' < ${BASE_DIR}/rabbitmq/alpine/rabbitmq-server.template > /tmp/rabbitmq-server

echo "${LXC} dd status=none of=/etc/init.d/rabbitmq-server < /tmp/rabbitmq-server" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/rabbitmq-server < /tmp/rabbitmq-server 2>&1 | tee -a $0.log

echo "rm -f /tmp/rabbitmq-server" 2>&1 | tee -a $0.log
rm -f /tmp/rabbitmq-server 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/rabbitmq/alpine/.profile.template > /tmp/.profile" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/rabbitmq/alpine/.profile.template > /tmp/.profile

echo "${LXC} dd status=none of=/root/.profile < /tmp/.profile" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/root/.profile < /tmp/.profile 2>&1 | tee -a $0.log

echo "rm -f /tmp/.profile" 2>&1 | tee -a $0.log
rm -f /tmp/.profile 2>&1 | tee -a $0.log

echo "${LXC} chmod 755 /etc/init.d/rabbitmq-server" 2>&1 | tee -a $0.log
${LXC} chmod 755 /etc/init.d/rabbitmq-server 2>&1 | tee -a $0.log

echo "${LXC} rc-update add rabbitmq-server" 2>&1 | tee -a $0.log
${LXC} rc-update add rabbitmq-server 2>&1 | tee -a $0.log

echo "${LXC} service rabbitmq-server start" 2>&1 | tee -a $0.log
${LXC} service rabbitmq-server start 2>&1 | tee -a $0.log

lxc_wait "${CONTAINER_NAME}-1" "service rabbitmq-server status" "Is ${CONTAINER_NAME} up? [y/N]"

echo "${LXC} service rabbitmq-server stop" 2>&1 | tee -a $0.log
${LXC} service rabbitmq-server stop 2>&1 | tee -a $0.log

lxc_wait "${CONTAINER_NAME}-1" "ps -ef" "Is ${CONTAINER_NAME} down? [y/N]"

echo "${LXC} cp /var/lib/rabbitmq/.erlang.cookie /root/" 2>&1 | tee -a $0.log
${LXC} cp /var/lib/rabbitmq/.erlang.cookie /root/ 2>&1 | tee -a $0.log

echo "${LXC} rm -rf /var/lib/rabbitmq/mnesia" 2>&1 | tee -a $0.log
${LXC} rm -rf /var/lib/rabbitmq/mnesia 2>&1 | tee -a $0.log

# stopping the container for making more clones (perhaps, it's not really necessary)
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# cloning rabbitmq container to run on other controllers
lxc_snapshot "${CONTAINER_NAME}-1"
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "ssh ${CONTROLLER_NAME}-${i}"
done

# starting the container after cloning is done
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# configuring clones
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"
 
  create_container "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" "${SSH}"

  lxc_wait "${CONTAINER_NAME}-${i}" "ps -ef" "Is ${CONTAINER_NAME} up? [y/N]" "${SSH}"

  LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-${i} --"

  echo "${SSH} ${LXC} service rabbitmq-server stop_app" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service rabbitmq-server stop_app 2>&1 | tee -a $0.log

  echo "${SSH} ${LXC} service rabbitmq-server reset" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service rabbitmq-server reset 2>&1 | tee -a $0.log

  echo "${SSH} ${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl join_cluster rabbit@${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl join_cluster rabbit@${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

  echo "${SSH} ${LXC} service rabbitmq-server start_app" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service rabbitmq-server start_app 2>&1 | tee -a $0.log

# checking the cluster status
  lxc_wait "${CONTAINER_NAME}-${i}" "service rabbitmq-server cluster_status" "Is ${CONTAINER_NAME} cluster up? [y/N]" "${SSH}"
done

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

# rabbitmq configuration
echo "${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl add_user openstack ${RABBITMQ_PASS}" 2>&1 | tee -a $0.log
${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl add_user openstack ${RABBITMQ_PASS} 2>&1 | tee -a $0.log

echo "${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl set_permissions openstack \".*\" \".*\" \".*\"" 2>&1 | tee -a $0.log
${LXC} /${RABBITMQ}-${RABBITMQ_VERSION}/sbin/rabbitmqctl set_permissions openstack ".*" ".*" ".*" 2>&1 | tee -a $0.log
