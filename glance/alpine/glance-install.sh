#!/usr/bin/bash

# glance - image services
# https://docs.openstack.org/glance/victoria/contributor/set-up-glance.html
# https://opendev.org/openstack/glance/src/branch/stable/victoria
# https://docs.ceph.com/en/latest/rbd/rbd-openstack/#

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

CONTAINER_NAME=${GLANCE_CONTAINER_NAME}
export NUMBER_OF_API_WORKERS=2

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

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install glance

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev wget ceph-common py3-rbd ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev wget ceph-common py3-rbd ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log
echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/glance.git" 2>&1 | tee -a $0.log
${LXC} git clone -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/glance.git 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"mkdir -p /etc/glance && cd glance && pip install ${PYMYSQL} python-memcached boto3 && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log
${LXC} sh -c "mkdir -p /etc/glance && cd glance && pip install ${PYMYSQL} python-memcached boto3 && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/glance/glance.sql.template > /tmp/glance.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/glance/glance.sql.template > /tmp/glance.sql
  echo "mysql < /tmp/glance.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/glance.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/glance/glance.postgres.template > /tmp/glance.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/glance/glance.postgres.template > /tmp/glance.sql
  echo "${LXC_SQL} dd status=none of=/tmp/glance.sql < /tmp/glance.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/glance.sql < /tmp/glance.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/glance.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/glance.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/glance.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/glance.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/glance.sql" 2>&1 | tee -a $0.log
rm -f /tmp/glance.sql

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack user create --domain default --password ${GLANCE_DBPASS} glance" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${GLANCE_DBPASS} glance 2>&1 | tee -a $0.log

echo "openstack role add --project service --user glance admin" 2>&1 | tee -a $0.log
openstack role add --project service --user glance admin 2>&1 | tee -a $0.log

echo "openstack service create --name glance --description \"OpenStack Image\" image" 2>&1 | tee -a $0.log
openstack service create --name glance --description "OpenStack Image" image 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} image public http://${OS_PUBLIC_ENDPOINT}:9292" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} image public http://${OS_PUBLIC_ENDPOINT}:9292 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} image internal http://${OS_INTERNAL_ENDPOINT}:9292" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} image internal http://${OS_INTERNAL_ENDPOINT}:9292 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} image admin http://${OS_ADMIN_ENDPOINT}:9292" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} image admin http://${OS_ADMIN_ENDPOINT}:9292 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/glance/glance-api.conf.template > /tmp/glance-api.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/glance/glance-api.conf.template > /tmp/glance-api.conf

echo "${LXC} dd status=none of=/etc/glance/glance-api.conf < /tmp/glance-api.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/glance/glance-api.conf < /tmp/glance-api.conf

echo "rm -f /tmp/glance-api.conf" 2>&1 | tee -a $0.log
rm -f /tmp/glance-api.conf 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S glance && adduser -S -D -h /var/lib/glance -G glance -g glance -s /bin/false glance\"" 2>&1 | tee -a $0.log

${LXC} sh -c "addgroup -S glance && adduser -S -D -h /var/lib/glance -G glance -g glance -s /bin/false glance" 2>&1 | tee -a $0.log

echo "${LXC} mkdir -p /etc/ceph" 2>&1 | tee -a $0.log
${LXC} mkdir -p /etc/ceph 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/common/ceph.conf.template > ceph.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/common/ceph.conf.template > ceph.conf

echo "${LXC} dd status=none of=/etc/ceph/ceph.conf < ceph.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/ceph/ceph.conf < ceph.conf

echo "rm -f ceph.conf" 2>&1 | tee -a $0.log
rm -f ceph.conf 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/glance/ceph.client.glance.keyring.template > ceph.client.${CEPH_GLANCE_LOGIN}.keyring" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/glance/ceph.client.glance.keyring.template > ceph.client.${CEPH_GLANCE_LOGIN}.keyring

echo "${LXC} dd status=none of=/etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring < ceph.client.${CEPH_GLANCE_LOGIN}.keyring" 2>&1 | tee -a $0.log

${LXC} dd status=none of=/etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring < ceph.client.${CEPH_GLANCE_LOGIN}.keyring

echo "rm -f ceph.client.${CEPH_GLANCE_LOGIN}.keyring" 2>&1 | tee -a $0.log
rm -f ceph.client.${CEPH_GLANCE_LOGIN}.keyring

echo "${LXC} chown glance:glance /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring" 2>&1 | tee -a $0.log
${LXC} chown glance:glance /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring 2>&1 | tee -a $0.log

echo "${LXC} chmod 640 /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring" 2>&1 | tee -a $0.log
${LXC} chmod 640 /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring 2>&1 | tee -a $0.log

# ensure that ceph cluster is accessible
read -p "Would you like to check if ceph cluster ${CEPH_NODE_ID} ${CEPH_NODE_IP1}, ${CEPH_NODE_IP2}, ${CEPH_NODE_IP3} is accessble? [y/N]"
if [[ "${REPLY}" == "y" ]]; then
  echo "${LXC} rbd -c /etc/ceph/ceph.conf -k /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring  pool stats ${CEPH_GLANCE_POOL} --id ${CEPH_GLANCE_LOGIN}" 2>&1 | tee -a $0.log
  ${LXC} rbd -c /etc/ceph/ceph.conf -k /etc/ceph/ceph.client.${CEPH_GLANCE_LOGIN}.keyring  pool stats ${CEPH_GLANCE_POOL} --id ${CEPH_GLANCE_LOGIN} 2>&1 | tee -a $0.log
  if (( $? != 0 )); then
    echo -e "There is a problem communicating with ceph cluster. Make sure it has the static route\n\"${INTERNAL_NETWORK_CIDR} via ${INTERNAL_NETWORK_GATEWAY} proto static\"" 2>&1 | tee -a $0.log
    read -p "Continue? [y/N]"
    if [[ "${REPLY}" != "y" ]]; then
      exit 1
    fi
  fi
fi

echo "${LXC} su -s /bin/sh -c \"glance-manage db_sync\" glance" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "glance-manage db_sync" glance 2>&1 | tee -a $0.log

echo "${LXC} tee /etc/init.d/glance < ${BASE_DIR}/glance/${DOWNLOAD_DIST}/glance" 2>&1 | tee -a $0.log
${LXC} tee /etc/init.d/glance < ${BASE_DIR}/glance/${DOWNLOAD_DIST}/glance

echo "${LXC} tee /etc/glance/schema-image.json < ${BASE_DIR}/glance/schema-image.json" 2>&1 | tee -a $0.log
${LXC} tee /etc/glance/schema-image.json < ${BASE_DIR}/glance/schema-image.json

echo "${LXC} chmod 755 /etc/init.d/glance" 2>&1 | tee -a $0.log
${LXC} chmod 755 /etc/init.d/glance 2>&1 | tee -a $0.log
echo "${LXC} rc-update add glance" 2>&1 | tee -a $0.log
${LXC} rc-update add glance 2>&1 | tee -a $0.log

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
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "${SSH}"
  create_container "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" "${SSH}"
done

# update haproxy config

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_NAME}-${i}"
  else
    SSH=""
  fi
  
  LXC="lxc-attach --keep-env -n ${HAPROXY_CONTAINER_NAME}-${i} --"
  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME} # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME} # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :9292 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :9292 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:9292 check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

    ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:9292 check # ${CONTAINER_NAME}"

  done

  echo "${SSH} ${LXC} service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done

echo "openstack image list" 2>&1 | tee -a $0.log
openstack image list  2>&1 | tee -a $0.log