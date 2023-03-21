#!/usr/bin/bash

# placement - REST API and data model to track resource provider inventories and usages, along with different classes of resources
# https://docs.openstack.org/placement/victoria/

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

CONTAINER_NAME=${PLACEMENT_CONTAINER_NAME}
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

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install placement

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libev-dev libffi-dev openssl-dev wget ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libev-dev libffi-dev openssl-dev wget ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone --depth 1 -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/placement.git" 2>&1 | tee -a $0.log
${LXC} git clone --depth 1 -b ${OS_GIT_BRANCH} ${GIT_REPO_URL}/placement.git 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"mkdir -p /etc/placement && cd placement && pip install bjoern ${PYMYSQL} python-memcached && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / .\"" 2>&1 | tee -a $0.log
${LXC} sh -c "mkdir -p /etc/placement && cd placement && pip install bjoern ${PYMYSQL} python-memcached && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/placement/placement.sql.template > /tmp/placement.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/placement/placement.sql.template > /tmp/placement.sql
  echo "mysql < /tmp/placement.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/placement.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/placement/placement.postgres.template > /tmp/placement.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/placement/placement.postgres.template > /tmp/placement.sql
  echo "${LXC_SQL} dd status=none of=/tmp/placement.sql < /tmp/placement.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/placement.sql < /tmp/placement.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/placement.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/placement.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/placement.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/placement.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/placement.sql" 2>&1 | tee -a $0.log
rm -f /tmp/placement.sql

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack user create --domain default --password ${PLACEMENT_DBPASS} placement" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${PLACEMENT_DBPASS} placement 2>&1 | tee -a $0.log

echo "openstack role add --project service --user placement admin" 2>&1 | tee -a $0.log
openstack role add --project service --user placement admin 2>&1 | tee -a $0.log

echo "openstack service create --name placement --description \"Placement API\" placement" 2>&1 | tee -a $0.log
openstack service create --name placement --description "Placement API" placement 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} placement public http://${OS_PUBLIC_ENDPOINT}:8778" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} placement public http://${OS_PUBLIC_ENDPOINT}:8778 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} placement internal http://${OS_INTERNAL_ENDPOINT}:8778" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} placement internal http://${OS_INTERNAL_ENDPOINT}:8778 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} placement admin http://${OS_ADMIN_ENDPOINT}:8778" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} placement admin http://${OS_ADMIN_ENDPOINT}:8778 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/placement/placement.conf.template > /tmp/placement.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/placement/placement.conf.template > /tmp/placement.conf

echo "${LXC} dd status=none of=/etc/placement/placement.conf < /tmp/placement.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/placement/placement.conf < /tmp/placement.conf

echo "rm -f /tmp/placement.conf" 2>&1 | tee -a $0.log
rm -f /tmp/placement.conf 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S placement && adduser -S -D -h /var/lib/placement -G placement -g placement -s /bin/false placement\"" 2>&1 | tee -a $0.log

${LXC} sh -c "addgroup -S placement && adduser -S -D -h /var/lib/placement -G placement -g placement -s /bin/false placement" 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"placement-manage db sync\" placement" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "placement-manage db sync" placement 2>&1 | tee -a $0.log

echo "${LXC} tee /bin/placement-api < ${BASE_DIR}/placement/placement-api" 2>&1 | tee -a $0.log
${LXC} tee /bin/placement-api < ${BASE_DIR}/placement/placement-api

echo "${LXC} chmod 755 /bin/placement-api" 2>&1 | tee -a $0.log
${LXC} chmod 755 /bin/placement-api 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_API_WORKERS; i++ )); do
  export i
  echo "export PORT=$(( 5000 + i ))"
  export PORT=$(( 5000 + i ))
  echo "envsubst '\${PORT}' < ${BASE_DIR}/placement/alpine/placement.template > /tmp/placement-${i}" 2>&1 | tee -a $0.log
  envsubst '\${PORT}' < ${BASE_DIR}/placement/alpine/placement.template > /tmp/placement-${i}
  echo "${LXC} tee /etc/init.d/placement-${i} < /tmp/placement-${i}" 2>&1 | tee -a $0.log
  ${LXC} tee /etc/init.d/placement-${i} < /tmp/placement-${i}
  echo "rm -f /tmp/placement-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/placement-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/placement-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/placement-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add placement-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add placement-${i} 2>&1 | tee -a $0.log
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

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :8778 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :8778 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    for (( k = 1; k <= NUMBER_OF_API_WORKERS; k++ )); do

      echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

      ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}"

    done
  done

  echo "${SSH} ${LXC} -- service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done

# just a quick test
echo "openstack --os-placement-api-version 1.2 resource class list --sort-column name" 2>&1 | tee -a $0.log
openstack --os-placement-api-version 1.2 resource class list --sort-column name 2>&1 | tee -a $0.log

echo "openstack --os-placement-api-version 1.6 trait list --sort-column name" 2>&1 | tee -a $0.log
openstack --os-placement-api-version 1.6 trait list --sort-column name 2>&1 | tee -a $0.log
