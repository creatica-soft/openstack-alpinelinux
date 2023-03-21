#!/usr/bin/bash

# nova - compute services
# https://docs.openstack.org/nova/victoria/
# https://opendev.org/openstack/nova/src/branch/stable/victoria
# https://releases.openstack.org/victoria/index.html

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${NOVA_CONTAINER_NAME}
NUMBER_OF_API_WORKERS=1
NOVNC_VERSION="1.2.0"
NOVNC_URL="https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz"

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.enva/$0, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

# nova takes about 1.5GB of disk space, so it's safer to resize the base image (1GB) to 3GB
image_resize "${CONTAINER_NAME}-1" "3GB"

create_container "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"

# install nova

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libev-dev libffi-dev openssl-dev libxml2-dev libxslt-dev py3-numpy-dev wget sudo ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk gnupg git python3 python3-dev libev-dev libffi-dev openssl-dev libxml2-dev libxslt-dev py3-numpy-dev wget sudo ${PSYCOPG2}" 2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} wget ${NOVNC_URL}" 2>&1 | tee -a $0.log
${LXC} wget ${NOVNC_URL} 2>&1 | tee -a $0.log

# install novnc from git
echo "${LXC} sh -c \"tar -zxf v${NOVNC_VERSION}.tar.gz && mkdir -p /usr/share/novnc /usr/share/doc/novnc && cd noVNC-${NOVNC_VERSION} && cp  -r app core utils vendor vnc.html vnc_lite.html /usr/share/novnc && cp -r docs/* /usr/share/doc/novnc && cd .. && rm -rf cd noVNC-${NOVNC_VERSION}\""

${LXC} sh -c "tar -zxf v${NOVNC_VERSION}.tar.gz && mkdir -p /usr/share/novnc /usr/share/doc/novnc && cd noVNC-${NOVNC_VERSION} && cp  -r app core utils vendor vnc.html vnc_lite.html /usr/share/novnc && cp -r docs/* /usr/share/doc/novnc && cd .. && rm -rf cd noVNC-${NOVNC_VERSION}"

echo "${LXC} git clone --depth 1 -b ${NOVA_VERSIOIN} ${GIT_REPO_URL}/nova.git" 2>&1 | tee -a $0.log
${LXC} git clone --depth 1 -b ${NOVA_VERSION} ${GIT_REPO_URL}/nova.git 2>&1 | tee -a $0.log

# a hack around alpine's numpy package being higher than in upper-requirements 
# and inability to build due to missing mkl_rt and blis libraries

echo "${LXC} sh -c \"cd nova && wget ${GIT_OS_UPPER_CONSTRAINTS_URL}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "cd nova && wget ${GIT_OS_UPPER_CONSTRAINTS_URL}" 2>&1 | tee -a $0.log

echo "${LXC} sed -i -c /numpy/c\numpy>=1.19.5 nova/upper-constraints.txt" 2>&1 | tee -a $0.log
${LXC} sed -i '/^numpy===/c\numpy>=1.19.5' nova/upper-constraints.txt 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"mkdir -p /etc/nova && cd nova && pip install bjoern ${PYMYSQL} python-memcached pynacl etcd3gw && pip install -c upper-constraints.txt --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log
${LXC} sh -c "mkdir -p /etc/nova && cd nova && pip install bjoern ${PYMYSQL} python-memcached pynacl etcd3gw && pip install -c upper-constraints.txt --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`lxc-attach -n ${CONTAINER_NAME}-1 -- python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

LXC_SQL="lxc-attach --keep-env -n ${SQL_CONTAINER_NAME}-1 --"

case "${SQL_CONTAINER_NAME}" in
"mariadb")
  echo "envsubst < ${BASE_DIR}/nova/nova.sql.template > /tmp/nova.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/nova/nova.sql.template > /tmp/nova.sql
  echo "mysql < /tmp/nova.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} mysql < /tmp/nova.sql
;;
"postgres")
  echo "envsubst < ${BASE_DIR}/nova/nova.postgres.template > /tmp/nova.sql" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/nova/nova.postgres.template > /tmp/nova.sql
  echo "${LXC_SQL} dd status=none of=/tmp/nova.sql < /tmp/nova.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} dd status=none of=/tmp/nova.sql < /tmp/nova.sql
  echo "${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/nova.sql'" 2>&1 | tee -a $0.log
  ${LXC_SQL} su - postgres -s /bin/sh -c 'psql -U postgres -d postgres -h 0.0.0.0 -f /tmp/nova.sql' 2>&1 | tee -a $0.log
  echo "${LXC_SQL} rm -f /tmp/nova.sql" 2>&1 | tee -a $0.log
  ${LXC_SQL} rm -f /tmp/nova.sql 2>&1 | tee -a $0.log
;;
esac

echo "rm -f /tmp/nova.sql" 2>&1 | tee -a $0.log
rm -f /tmp/nova.sql

echo "source /root/admin-openrc" 2>&1 | tee -a $0.log
source /root/admin-openrc

echo "openstack user create --domain default --password ${NOVA_DBPASS} nova" 2>&1 | tee -a $0.log
openstack user create --domain default --password ${NOVA_DBPASS} nova 2>&1 | tee -a $0.log

echo "openstack role add --project service --user nova admin" 2>&1 | tee -a $0.log
openstack role add --project service --user nova admin 2>&1 | tee -a $0.log

echo "openstack service create --name nova --description \"OpenStack Compute\" compute" 2>&1 | tee -a $0.log
openstack service create --name nova --description "OpenStack Compute" compute 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} compute public http://${OS_PUBLIC_ENDPOINT}:8774/v2.1" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} compute public http://${OS_PUBLIC_ENDPOINT}:8774/v2.1 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} compute internal http://${OS_INTERNAL_ENDPOINT}:8774/v2.1" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} compute internal http://${OS_INTERNAL_ENDPOINT}:8774/v2.1 2>&1 | tee -a $0.log

echo "openstack endpoint create --region ${REGION} compute admin http://${OS_ADMIN_ENDPOINT}:8774/v2.1" 2>&1 | tee -a $0.log
openstack endpoint create --region ${REGION} compute admin http://${OS_ADMIN_ENDPOINT}:8774/v2.1 2>&1 | tee -a $0.log

export IP_ADDR=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-1 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
echo "IP=${IP_ADDR}" 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/nova/nova.conf.template > /tmp/nova.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/nova/nova.conf.template > /tmp/nova.conf

echo "${LXC} dd status=none of=/etc/nova/nova.conf < /tmp/nova.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/nova/nova.conf < /tmp/nova.conf

echo "rm -f /tmp/nova.conf" 2>&1 | tee -a $0.log
rm -f /tmp/nova.conf 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S nova && adduser -S -D -h /var/lib/nova -G nova -g nova -s /bin/false nova\"" 2>&1 | tee -a $0.log
${LXC} sh -c "addgroup -S nova && adduser -S -D -h /var/lib/nova -G nova -g nova -s /bin/false nova" 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"nova-manage api_db sync\" nova" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "nova-manage api_db sync" nova 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"nova-manage cell_v2 map_cell0\" nova" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"nova-manage cell_v2 create_cell --name=cell1 --verbose\" nova" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"nova-manage db sync\" nova" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "nova-manage db sync" nova 2>&1 | tee -a $0.log

echo "${LXC} su -s /bin/sh -c \"nova-manage cell_v2 list_cells\" nova" 2>&1 | tee -a $0.log
${LXC} su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova 2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/bin/nova-api-wsgi < ${BASE_DIR}/nova/nova-api-wsgi" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/bin/nova-api-wsgi < ${BASE_DIR}/nova/nova-api-wsgi

echo "${LXC} dd status=none of=/bin/nova-metadata-wsgi < ${BASE_DIR}/nova/nova-metadata-wsgi" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/bin/nova-metadata-wsgi < ${BASE_DIR}/nova/nova-metadata-wsgi

echo "${LXC} sh -c \"chmod 755 /bin/nova-api-wsgi\"" 2>&1 | tee -a $0.log
${LXC} sh -c "chmod 755 /bin/nova-api-wsgi" 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"chmod 755 /bin/nova-metadata-wsgi\"" 2>&1 | tee -a $0.log
${LXC} sh -c "chmod 755 /bin/nova-metadata-wsgi" 2>&1 | tee -a $0.log

for (( i = 1; i <= NUMBER_OF_API_WORKERS; i++ )); do
  export i
  echo "export PORT=$(( 4000 + i ))"
  export PORT=$(( 4000 + i ))
  echo "envsubst '\${PORT}' < ${BASE_DIR}/nova/alpine/nova-api.template > /tmp/nova-api-${i}" 2>&1 | tee -a $0.log
  envsubst '\${PORT}' < ${BASE_DIR}/nova/alpine/nova-api.template > /tmp/nova-api-${i}
  echo "${LXC} dd status=none of=/etc/init.d/nova-api-${i} < /tmp/nova-api-${i}" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/init.d/nova-api-${i} < /tmp/nova-api-${i}
  echo "rm -f /tmp/nova-api-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/nova-api-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/nova-api-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/nova-api-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add nova-api-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add nova-api-${i} 2>&1 | tee -a $0.log

  echo "export PORT=$(( 5000 + i ))"
  export PORT=$(( 5000 + i ))
  echo "envsubst '\${PORT}' < ${BASE_DIR}/nova/alpine/nova-metadata.template > /tmp/nova-metadata-${i}" 2>&1 | tee -a $0.log
  envsubst '\${PORT}' < ${BASE_DIR}/nova/alpine/nova-metadata.template > /tmp/nova-metadata-${i}
  echo "${LXC} dd status=none of=/etc/init.d/nova-metadata-${i} < /tmp/nova-metadata-${i}" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/init.d/nova-metadata-${i} < /tmp/nova-metadata-${i}
  echo "rm -f /tmp/nova-metadata-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/nova-metadata-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/nova-metadata-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/nova-metadata-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add nova-metadata-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add nova-metadata-${i} 2>&1 | tee -a $0.log
done

echo "${LXC} dd status=none of=/etc/init.d/nova-conductor < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-conductor" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/nova-conductor < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-conductor

echo "${LXC} dd status=none of=/etc/init.d/nova-novncproxy < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-novncproxy" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/nova-novncproxy < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-novncproxy

echo "${LXC} dd status=none of=/etc/init.d/nova-scheduler < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-scheduler" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/nova-scheduler < ${BASE_DIR}/nova/${DOWNLOAD_DIST}/nova-scheduler

for DAEMON in conductor scheduler novncproxy; do
  echo "${LXC} chmod 755 /etc/init.d/nova-${DAEMON}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/nova-${DAEMON} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add nova-${DAEMON}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add nova-${DAEMON} 2>&1 | tee -a $0.log
done

echo "${LXC} sh -c \"tar -zcf /root/nova.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/nova* /bin/privsep-helper /etc/nova\"" 2>&1 | tee -a $0.log
${LXC} sh -c "tar -zcf /root/nova.tar.gz /lib/python${PYTHON3_VERSION}/site-packages /bin/nova* /bin/privsep-helper /etc/nova" 2>&1 | tee -a $0.log

echo "${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub" 2>&1 | tee -a $0.log
${LXC} dd status=none oflag=append conv=notrunc of=/root/.ssh/authorized_keys < /root/.ssh/id_rsa.pub

echo "Need to unlock root account in order to scp the nova.tar.gz archive later. Please type new root password" 2>&1 | tee -a $0.log
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

  export IP_ADDR=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${i} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
  echo "IP_ADDR=${IP_ADDR}" 2>&1 | tee -a $0.log

  echo "envsubst < ${BASE_DIR}/nova/nova.conf.template | ${SSH} dd status=none of=/tmp/nova.conf" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/nova/nova.conf.template | ${SSH} dd status=none of=/tmp/nova.conf

  echo "${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} -- dd status=none of=/etc/nova/nova.conf < /tmp/nova.conf" 2>&1 | tee -a $0.log
  ${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} -- dd status=none of=/etc/nova/nova.conf < /tmp/nova.conf

  echo "${SSH} rm -f /tmp/nova.tmp" 2>&1 | tee -a $0.log
  ${SSH} rm -f /tmp/nova.tmp 2>&1 | tee -a $0.log

done

## update haproxy config

for (( i = 1; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  if (( i > 1 )); then
    SSH="ssh ${CONTROLLER_NAME}-${i}"
  else
    SSH=""
  fi
LXC="lxc-attach --keep-env -n ${HAPROXY_CONTAINER_NAME}-${i} --"
# nova api listener
  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME}-api # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME}-api # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :8774 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :8774 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    for (( k = 1; k <= NUMBER_OF_API_WORKERS; k++ )); do

      echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:400${k} check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

      ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:400${k} check # ${CONTAINER_NAME}"

    done
  
  done

# nova metadata service
  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME}-metadata # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME}-metadata # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :8775 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :8775 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    for (( k = 1; k <= NUMBER_OF_API_WORKERS; k++ )); do

      echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

      ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j}-${k} ${CONTAINER_IP}:500${k} check # ${CONTAINER_NAME}"

    done

  done

# nova novpcproxy service, it uses websockets
  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"listen ${CONTAINER_NAME}-novncproxy # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"listen ${CONTAINER_NAME}-novncproxy # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  timeout client 3600000 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  timeout client 3600000 # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  timeout server 3600000 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  timeout server 3600000 # ${CONTAINER_NAME}"

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :6080 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :6080 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

    echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:6080 check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

    ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:6080 check # ${CONTAINER_NAME}"
  done

  echo "${SSH} ${LXC} service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done

sleep 5

echo "openstack compute service list" 2>&1 | tee -a $0.log
openstack compute service list 2>&1 | tee -a $0.log
