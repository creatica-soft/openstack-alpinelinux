#!/usr/bin/bash

# neutron - network services
# https://docs.openstack.org/neutron/victoria/
# https://opendev.org/openstack/neutron/src/branch/stable/victoria

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${NEUTRON_CONTAINER_NAME}
NUMBER_OF_API_WORKERS=1

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

# neutron takes about 1.2GB, so it's safer to resize it to 3GB
image_resize "${CONTAINER_NAME}-1" "3GB"

ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"
lxc_config "${CONTAINER_NAME}-1"

echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

lxc_set_hostname "${CONTAINER_NAME}-1"
lxc_set_hosts "${CONTAINER_NAME}-1"

echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
echo "lxc-start -n  ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"
static_route_check "${CONTAINER_NAME}-1" "${COMPUTE_NETWORK_CIDR}" "${INTERNAL_NETWORK_GATEWAY}"

# install neutron

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev wget sudo ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev wget sudo ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone --depth 1 -b ${NEUTRON_VERSION} ${GIT_REPO_URL}/neutron.git" 2>&1 | tee -a $0.log
${LXC} git clone --depth 1 -b ${NEUTRON_VERSION} ${GIT_REPO_URL}/neutron.git 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"mkdir -p /etc/neutron/plugins/ml2 && cd neutron && pip install ${PYMYSQL} python-memcached etcd3gw pynacl && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log
${LXC} sh -c "mkdir -p /etc/neutron/plugins/ml2 && cd neutron && pip install ${PYMYSQL} python-memcached etcd3gw pynacl && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/neutron/neutron.sql.template > /tmp/neutron.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/neutron/neutron.sql.template > /tmp/neutron.sql
  echo "mysql < /tmp/neutron.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/neutron.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/neutron/neutron.postgres.template > /tmp/neutron.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/neutron/neutron.postgres.template > /tmp/neutron.sql
  echo "${LXC_SQL} dd status=none of=/tmp/neutron.sql < /tmp/neutron.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/neutron.sql < /tmp/neutron.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/neutron.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/neutron.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/neutron.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/neutron.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/neutron.sql" 2>&1 | tee -a $0.log
rm -f /tmp/neutron.sql

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack user create --domain default --password ${NEUTRON_DBPASS} neutron" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${NEUTRON_DBPASS} neutron 2>&1 | tee -a $0.log

echo "openstack role add --project service --user neutron admin" 2>&1 | tee -a $0.log
openstack role add --project service --user neutron admin 2>&1 | tee -a $0.log

echo "openstack service create --name neutron --description \"OpenStack Networking\" network" 2>&1 | tee -a $0.log
openstack service create --name neutron --description "OpenStack Networking" network 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} network public http://${OS_PUBLIC_ENDPOINT}:9696" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} network public http://${OS_PUBLIC_ENDPOINT}:9696 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} network internal http://${OS_INTERNAL_ENDPOINT}:9696" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} network internal http://${OS_INTERNAL_ENDPOINT}:9696 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} network admin http://${OS_ADMIN_ENDPOINT}:9696" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} network admin http://${OS_ADMIN_ENDPOINT}:9696 2>&1 | tee -a $0.log

echo "export i=1" 2>&1 | tee -a $0.log
export i=1

echo "envsubst < ${BASE_DIR}/neutron/neutron.conf.template > /tmp/neutron.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/neutron/neutron.conf.template > /tmp/neutron.conf
echo "${LXC} dd status=none of=/etc/neutron/neutron.conf < /tmp/neutron.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/neutron/neutron.conf < /tmp/neutron.conf

echo "envsubst < ${BASE_DIR}/neutron/ml2_conf.ini.template > /tmp/ml2_conf.ini" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/neutron/ml2_conf.ini.template > /tmp/ml2_conf.ini
echo "${LXC} dd status=none of=/etc/neutron/plugins/ml2/ml2_conf.ini < /tmp/ml2_conf.ini" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/neutron/plugins/ml2/ml2_conf.ini < /tmp/ml2_conf.ini

echo "envsubst < ${BASE_DIR}/neutron/ovn.ini.template > /tmp/ovn.ini" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/neutron/ovn.ini.template > /tmp/ovn.ini
echo "${LXC} dd status=none of=/etc/neutron/ovn.ini < /tmp/ovn.ini" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/neutron/ovn.ini < /tmp/ovn.ini

echo "rm -f /tmp/neutron.conf" 2>&1 | tee -a $0.log
rm -f /tmp/neutron.conf 2>&1 | tee -a $0.log
echo "rm -f /tmp/ml2_conf.ini" 2>&1 | tee -a $0.log
rm -f /tmp/ml2_conf.ini 2>&1 | tee -a $0.log
echo "rm -f /tmp/ovn.ini" 2>&1 | tee -a $0.log
rm -f /tmp/ovn.ini 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S neutron && adduser -S -D -h /var/lib/neutron -G neutron -g neutron -s /bin/false neutron\"" 2>&1 | tee -a $0.log
${LXC} sh -c "addgroup -S neutron && adduser -S -D -h /var/lib/neutron -G neutron -g neutron -s /bin/false neutron" 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head\" neutron" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron 2>&1 | tee -a $0.log

echo "${LXC} tee /etc/init.d/neutron-server < ${BASE_DIR}/neutron/${DOWNLOAD_DIST}/neutron-server" 2>&1 | tee -a $0.log
${LXC} tee /etc/init.d/neutron-server < ${BASE_DIR}/neutron/${DOWNLOAD_DIST}/neutron-server

echo "${LXC} chmod 755 /etc/init.d/neutron-server" 2>&1 | tee -a $0.log
${LXC} chmod 755 /etc/init.d/neutron-server 2>&1 | tee -a $0.log
echo "${LXC} rc-update add neutron-server" 2>&1 | tee -a $0.log
${LXC} rc-update add neutron-server 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"tar -zcf /root/neutron.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/neutron* /bin/privsep-helper /etc/neutron\"" 2>&1 | tee -a $0.log
${LXC} sh -c "tar -zcf /root/neutron.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/neutron* /bin/privsep-helper /etc/neutron"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub" 2>&1 | tee -a $0.log
${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub

echo "Need to unlock root account in order to scp the neutron.tar.gz archive later. Please type new root password" 2>&1 | tee -a $0.log
${LXC} passwd

# stop the clone to make snapshot (probably not necessary)
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# create a snapshot of the first clone
lxc_snapshot "${CONTAINER_NAME}-1"

# start the first clone
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# configure other clones
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "ssh ${CONTROLLER_NAME}-${i}"
  create_container "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" "${SSH}"
done

## update haproxy config

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_NAME}-${i}"
  else
    SSH=""
  fi

# neutron api listener
  LXC="lxc-attach -v CONTAINER_NAME -n ${HAPROXY_CONTAINER_NAME}-${i} --"
  
  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME}-server # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME}-server # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :9696 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :9696 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:9696 check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

    ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:9696 check # ${CONTAINER_NAME}"

  done

  echo "${SSH} ${LXC} service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done

sleep 5

echo "openstack network agent list" 2>&1 | tee -a $0.log
openstack network agent list 2>&1 | tee -a $0.log