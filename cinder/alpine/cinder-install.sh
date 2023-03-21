#!/usr/bin/bash

# cinder - volume services
# https://docs.openstack.org/cinder/victoria/
# https://opendev.org/openstack/cinder/src/branch/stable/victoria
# https://docs.ceph.com/en/latest/rbd/rbd-openstack/#

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${CINDER_CONTAINER_NAME}
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

# cinder takes about 1.4GB, so it's safer to resize to 3GB
image_resize "${CONTAINER_NAME}-1" "3GB"

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install cinder

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev libev-dev libxml2-dev libxslt-dev wget sudo ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libffi-dev openssl-dev libev-dev libxml2-dev libxslt-dev wget sudo ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone --depth 1 -b ${CINDER_VERSION} ${GIT_REPO_URL}/cinder.git" 2>&1 | tee -a $0.log
${LXC} git clone --depth 1 -b ${CINDER_VERSION} ${GIT_REPO_URL}/cinder.git 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"pip install bjoern ${PYMYSQL} python-memcached etcd3gw pynacl && mkdir -p /etc/cinder && cd cinder && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log
${LXC} sh -c "pip install bjoern ${PYMYSQL} python-memcached etcd3gw pynacl && mkdir -p /etc/cinder && cd cinder && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/cinder/cinder.sql.template > /tmp/cinder.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/cinder/cinder.sql.template > /tmp/cinder.sql
  echo "mysql < /tmp/cinder.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/cinder.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/cinder/cinder.postgres.template > /tmp/cinder.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/cinder/cinder.postgres.template > /tmp/cinder.sql
  echo "${LXC_SQL} dd status=none of=/tmp/cinder.sql < /tmp/cinder.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/cinder.sql < /tmp/cinder.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/cinder.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/cinder.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/cinder.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/cinder.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/cinder.sql" 2>&1 | tee -a $0.log
rm -f /tmp/cinder.sql

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack user create --domain default --password ${CINDER_DBPASS} cinder" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${CINDER_DBPASS} cinder 2>&1 | tee -a $0.log

echo "openstack role add --project service --user cinder admin" 2>&1 | tee -a $0.log
openstack role add --project service --user cinder admin 2>&1 | tee -a $0.log

echo "openstack service create --name cinderv3 --description \"OpenStack Block Storage\" volumev3" 2>&1 | tee -a $0.log
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} volumev3 public http://${OS_PUBLIC_ENDPOINT}:8776/v3/%\(project_id\)s" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} volumev3 public http://${OS_PUBLIC_ENDPOINT}:8776/v3/%\(project_id\)s 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} volumev3 internal http://${OS_INTERNAL_ENDPOINT}:8776/v3/%\(project_id\)s" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} volumev3 internal http://${OS_INTERNAL_ENDPOINT}:8776/v3/%\(project_id\)s 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} volumev3 admin http://${OS_ADMIN_ENDPOINT}:8776/v3/%\(project_id\)s" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} volumev3 admin http://${OS_ADMIN_ENDPOINT}:8776/v3/%\(project_id\)s 2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/bin/cinder-wsgi < ${BASE_DIR}/cinder/cinder-wsgi" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/bin/cinder-wsgi < ${BASE_DIR}/cinder/cinder-wsgi

echo "${LXC} chmod 755 /bin/cinder-wsgi" 2>&1 | tee -a $0.log
${LXC} chmod 755 /bin/cinder-wsgi 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_API_WORKERS; i++ )); do
  export i
  echo "export PORT=$(( 5000 + i ))"
  export PORT=$(( 5000 + i ))
  echo "envsubst '\${PORT}' < ${BASE_DIR}/cinder/alpine/cinder.template > /tmp/cinder-${i}" 2>&1 | tee -a $0.log
  envsubst '\${PORT}' < ${BASE_DIR}/cinder/alpine/cinder.template > /tmp/cinder-${i}
  echo "${LXC} dd status=none of=/etc/init.d/cinder-${i} < /tmp/cinder-${i}" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/init.d/cinder-${i} < /tmp/cinder-${i}
  echo "rm -f /tmp/cinder-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/cinder-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/cinder-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/cinder-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add cinder-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add cinder-${i} 2>&1 | tee -a $0.log
done

# cinder-scheduler runs as a daemon
echo "${LXC} dd status=none of=/etc/init.d/cinder-scheduler < ${BASE_DIR}/cinder/alpine/cinder-scheduler" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/cinder-scheduler < ${BASE_DIR}/cinder/alpine/cinder-scheduler

echo "${LXC} chmod 755 /etc/init.d/cinder-scheduler" 2>&1 | tee -a $0.log
${LXC} chmod 755 /etc/init.d/cinder-scheduler 2>&1 | tee -a $0.log

echo "${LXC} rc-update add cinder-scheduler" 2>&1 | tee -a $0.log
${LXC} rc-update add cinder-scheduler 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/cinder/cinder.conf.template > /tmp/cinder.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/cinder/cinder.conf.template > /tmp/cinder.conf
echo "${LXC} dd status=none of=/etc/cinder/cinder.conf < /tmp/cinder.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/cinder/cinder.conf < /tmp/cinder.conf

echo "rm -f /tmp/cinder.conf" 2>&1 | tee -a $0.log
rm -f /tmp/cinder.conf 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S cinder && adduser -S -D -h /var/lib/cinder -G cinder -g cinder -s /bin/false cinder\"" 2>&1 | tee -a $0.log
${LXC} sh -c "addgroup -S cinder && adduser -S -D -h /var/lib/cinder -G cinder -g cinder -s /bin/false cinder" 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"cinder-manage db sync\" cinder" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "cinder-manage db sync" cinder 2>&1 | tee -a $0.log

# create an archive for cinder-volume service in alpine compute node to avoid unnecessary building from the repo again

echo "${LXC} sh -c \"tar -zcf /root/cinder.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/cinder* /bin/privsep-helper /etc/cinder\"" 2>&1 | tee -a $0.log
${LXC} sh -c "tar -zcf /root/cinder.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/cinder* /bin/privsep-helper /etc/cinder"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub" 2>&1 | tee -a $0.log
${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub

echo "Need to unlock root account in order to scp the cinder.tar.gz archive later. Please type new root password" 2>&1 | tee -a $0.log
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
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "${SSH}"
  create_container "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}" "${SSH}"
done

## update haproxy config

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_NAME}-${i}"
  else
    SSH=""
  fi

# cinder api listener

  LXC="lxc-attach --keep-env -n ${HAPROXY_CONTAINER_NAME}-${i} --"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME}-server # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME}-server # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :8776 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :8776 # ${CONTAINER_NAME}"

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

sleep 5

echo "openstack volume list" 2>&1 | tee -a $0.log
openstack volume list 2>&1 | tee -a $0.log