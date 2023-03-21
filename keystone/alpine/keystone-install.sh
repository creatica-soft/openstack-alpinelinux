#!/usr/bin/bash

# keystone - authentication, authorization and service catalog openstack server
# https://docs.openstack.org/keystone/victoria/contributor/set-up-keystone.html
# https://blog.miguelgrinberg.com/post/running-a-flask-application-as-a-service-with-systemd

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${KEYSTONE_CONTAINER_NAME}
NUMBER_OF_API_WORKERS=1


if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee -a $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install keystone

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk git python3 python3-dev libev-dev libffi-dev openssl-dev ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk git python3 python3-dev libev-dev libffi-dev openssl-dev ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log
echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone --depth 1 -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/keystone.git" 2>&1 | tee -a $0.log
${LXC} git clone --depth 1 -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/keystone.git 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"mkdir -p /etc/keystone && cd keystone && pip install ${PYMYSQL} bjoern python-memcached etcd3gw && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / .\"" 2>&1 | tee -a $0.log
${LXC} sh -c "mkdir -p /etc/keystone && cd keystone && pip install ${PYMYSQL} bjoern python-memcached etcd3gw && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/keystone/keystone.sql.template > /tmp/keystone.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/keystone/keystone.sql.template > /tmp/keystone.sql
  echo "${LXC_SQL} mysql < /tmp/keystone.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/keystone.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/keystone/keystone.postgres.template > /tmp/keystone.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/keystone/keystone.postgres.template > /tmp/keystone.sql
  echo "${LXC_SQL} dd status=none of=/tmp/keystone.sql < /tmp/keystone.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/keystone.sql < /tmp/keystone.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/keystone.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/keystone.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/keystone.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/keystone.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/keystone.sql" 2>&1 | tee -a $0.log
rm -f /tmp/keystone.sql

echo "envsubst < ${BASE_DIR}/keystone/keystone.conf.template > /tmp/keystone.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/keystone/keystone.conf.template > /tmp/keystone.conf

echo "${LXC} dd status=none of=/etc/keystone/keystone.conf < /tmp/keystone.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/keystone/keystone.conf < /tmp/keystone.conf

echo "rm -f /tmp/keystone.conf" 2>&1 | tee -a $0.log
rm -f /tmp/keystone.conf 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S keystone && adduser -S -D -h /var/lib/keystone -G keystone -g keystone -s /bin/false keystone\"" 2>&1 | tee -a $0.log

${LXC} sh -c "addgroup -S keystone && adduser -S -D -h /var/lib/keystone -G keystone -g keystone -s /bin/false keystone" 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh keystone -c 'keystone-manage db_sync'" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh keystone -c 'keystone-manage db_sync' 2>&1 | tee -a $0.log

echo "${LXC} keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone" 2>&1 | tee -a $0.log
${LXC} keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone 2>&1 | tee -a $0.log

echo "${LXC} keystone-manage credential_setup --keystone-user keystone --keystone-group keystone" 2>&1 | tee -a $0.log
${LXC} keystone-manage credential_setup --keystone-user keystone --keystone-group keystone 2>&1 | tee -a $0.log

echo "${LXC} keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} --bootstrap-admin-url http://${OS_ADMIN_ENDPOINT}:5000/v3/ --bootstrap-internal-url http://${OS_INTERNAL_ENDPOINT}:5000/v3/ --bootstrap-public-url http://${OS_PUBLIC_ENDPOINT}:5000/v3/ --bootstrap-region-id ${REGION}" 2>&1 | tee -a $0.log

${LXC} keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} --bootstrap-admin-url http://${OS_ADMIN_ENDPOINT}:5000/v3/ --bootstrap-internal-url http://${OS_INTERNAL_ENDPOINT}:5000/v3/ --bootstrap-public-url http://${OS_PUBLIC_ENDPOINT}:5000/v3/ --bootstrap-region-id ${REGION} 2>&1 | tee -a $0.log

echo "${LXC} tee /bin/keystone-wsgi-admin < ${BASE_DIR}/keystone/keystone-wsgi-admin" 2>&1 | tee -a $0.log
${LXC} tee /bin/keystone-wsgi-admin < ${BASE_DIR}/keystone/keystone-wsgi-admin

echo "${LXC} tee /bin/keystone-wsgi-public < ${BASE_DIR}/keystone/keystone-wsgi-public" 2>&1 | tee -a $0.log
${LXC} tee /bin/keystone-wsgi-public < ${BASE_DIR}/keystone/keystone-wsgi-public

echo "${LXC} sh -c \"chmod 755 /bin/keystone-wsgi-*\"" 2>&1 | tee -a $0.log
${LXC} sh -c "chmod 755 /bin/keystone-wsgi-*" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_API_WORKERS; i++ )); do
  export i
  echo "export PORT=$(( 5000 + i ))"
  export PORT=$(( 5000 + i ))
  echo "envsubst '\${PORT}' < ${BASE_DIR}/keystone/alpine/keystone.template > /tmp/keystone-${i}" 2>&1 | tee -a $0.log
  envsubst '\${PORT}' < ${BASE_DIR}/keystone/alpine/keystone.template > /tmp/keystone-${i}
  echo "${LXC} dd status=none of=/etc/init.d/keystone-${i} < /tmp/keystone-${i}" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/init.d/keystone-${i} < /tmp/keystone-${i}
  echo "rm -f /tmp/keystone-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/keystone-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/keystone-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/keystone-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add keystone-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add keystone-${i} 2>&1 | tee -a $0.log
done

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

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :5000 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :5000 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    for (( k = 1; k <= NUMBER_OF_API_WORKERS; k++ )); do

      echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

      ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}"

    done
  done

  echo "${SSH} ${LXC} service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack project create --domain default --description \"Service Project\" service" 2>&1 | tee -a $0.log
openstack project create --domain default --description "Service Project" service 2>&1 | tee -a $0.log

echo "openstack project create --domain default --description \"Test Project\" ${TEST_PROJECT}" 2>&1 | tee -a $0.log
openstack project create --domain default --description "Test Project" ${TEST_PROJECT} 2>&1 | tee -a $0.log

echo "openstack user create --domain default --password ${TEST_PASS} ${TEST_USER}" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${TEST_PASS} ${TEST_USER} 2>&1 | tee -a $0.log

echo "openstack role create ${TEST_ROLE}" 2>&1 | tee -a $0.log
openstack role create ${TEST_ROLE} 2>&1 | tee -a $0.log

echo "openstack role add --project ${TEST_PROJECT} --user ${TEST_USER} ${TEST_ROLE}" 2>&1 | tee -a $0.log
openstack role add --project ${TEST_PROJECT} --user ${TEST_USER} ${TEST_ROLE} 2>&1 | tee -a $0.log
