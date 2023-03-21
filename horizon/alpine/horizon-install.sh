#!/usr/bin/bash

# horizon - Openstack dashboard
# https://docs.openstack.org/horizon/victoria/
# https://docs.openstack.org/horizon/latest/install/from-source.html
# https://docs.djangoproject.com/en/dev/topics/cache/

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${HORIZON_CONTAINER_NAME}
NUMBER_OF_WORKERS=1

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

# install horizon

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk git python3 python3-dev libev-dev libffi-dev openssl-dev nginx sudo ${PSYCOPG2}\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk git python3 python3-dev libev-dev libffi-dev openssl-dev nginx sudo ${PSYCOPG2}"  2>&1 | tee -a $0.log

echo "${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py" 2>&1 | tee -a $0.log
${LXC} curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} python3 get-pip.py" 2>&1 | tee -a $0.log
${LXC} python3 get-pip.py 2>&1 | tee -a $0.log

echo "${LXC} git clone -b ${HORIZON_VERSION} --depth 1 ${GIT_REPO_URL}/horizon" 2>&1 | tee -a $0.log
${LXC} git clone -b ${HORIZON_VERSION} --depth 1 ${GIT_REPO_URL}/horizon 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"addgroup -S horizon && adduser -S -D -h /var/lib/openstack-dashboard -G horizon -g horizon -s /bin/false horizon && addgroup nginx horizon && mkdir -p /var/run/horizon && chown horizon:nginx /var/run/horizon && chmod g+w /var/run/horizon\"" 2>&1 | tee -a $0.log

${LXC} sh -c "addgroup -S horizon && adduser -S -D -h /var/lib/openstack-dashboard -G horizon -g horizon -s /bin/false horizon && addgroup nginx horizon && mkdir -p /var/run/horizon && chown horizon:nginx /var/run/horizon && chmod g+w /var/run/horizon" 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"pip install ${PYMYSQL} bjoern python-memcached && cd horizon && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / .\"" 2>&1 | tee -a $0.log
${LXC} sh -c "pip install ${PYMYSQL} bjoern python-memcached && cd horizon && pip install -c ${GIT_OS_UPPER_CONSTRAINTS_URL} --upgrade --root / --prefix / ." 2>&1 | tee -a $0.log

PYTHON3_VERSION=`${LXC} python3 --version|cut -f2 -d " "|cut -f1-2 -d"."`
echo "PYTHON3_VERSION=${PYTHON3_VERSION}"  2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<\"../../../../lib/python${PYTHON3_VERSION}/site-packages\"" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/usr/lib/python${PYTHON3_VERSION}/site-packages/site-packages.pth <<<"../../../../lib/python${PYTHON3_VERSION}/site-packages"

echo "${LXC} mv /lib/python${PYTHON3_VERSION}/site-packages/openstack_dashboard /var/lib/openstack-dashboard/" 2>&1 | tee -a $0.log
${LXC} mv /lib/python${PYTHON3_VERSION}/site-packages/openstack_dashboard /var/lib/openstack-dashboard/ 2>&1 | tee -a $0.log

echo "${LXC} cp /horizon/manage.py /var/lib/openstack-dashboard/" 2>&1 | tee -a $0.log
${LXC} cp /horizon/manage.py /var/lib/openstack-dashboard/ 2>&1 | tee -a $0.log

echo "${LXC} cp /var/lib/openstack-dashboard/openstack_dashboard/settings.py /var/lib/openstack-dashboard/" 2>&1 | tee -a $0.log
${LXC} cp /var/lib/openstack-dashboard/openstack_dashboard/settings.py /var/lib/openstack-dashboard/ 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/horizon/alpine/local_settings.py.template > /tmp/local_settings.py" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/horizon/alpine/local_settings.py.template > /tmp/local_settings.py

echo "${LXC} dd status=none of=/var/lib/openstack-dashboard/openstack_dashboard/local/local_settings.py < /tmp/local_settings.py" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/var/lib/openstack-dashboard/openstack_dashboard/local/local_settings.py < /tmp/local_settings.py

echo "rm -f /tmp/local_settings.py" 2>&1 | tee -a $0.log
rm -f /tmp/local_settings.py

echo "${LXC} dd status=none of=/var/lib/openstack-dashboard/openstack_dashboard/wsgi.py < ${BASE_DIR}/horizon/alpine/wsgi.py" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/var/lib/openstack-dashboard/openstack_dashboard/wsgi.py < ${BASE_DIR}/horizon/alpine/wsgi.py 2>&1 | tee -a $0.log

echo "${LXC} chmod 755 /var/lib/openstack-dashboard/openstack_dashboard/wsgi.py" 2>&1 | tee -a $0.log
${LXC} chmod 755 /var/lib/openstack-dashboard/openstack_dashboard/wsgi.py 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"ln -s /usr/bin/python3 /usr/bin/python && cd /var/lib/openstack-dashboard && ./manage.py collectstatic && ./manage.py compress && chown horizon secret_key\"" 2>&1 | tee -a $0.log
${LXC} sh -c "ln -s /usr/bin/python3 /usr/bin/python && cd /var/lib/openstack-dashboard && ./manage.py collectstatic && ./manage.py compress && chown horizon secret_key" 2>&1 | tee -a $0.log

echo "${LXC} dd status=none of=/etc/nginx/nginx.conf < ${BASE_DIR}/horizon/alpine/nginx.conf.template" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/nginx/nginx.conf < ${BASE_DIR}/horizon/alpine/nginx.conf.template

echo "envsubst '\${HORIZON_CONTAINER_NAME}\${DOMAIN_NAME}' < ${BASE_DIR}/horizon/alpine/default.conf.template > /tmp/default.conf" 2>&1 | tee -a $0.log
envsubst '${HORIZON_CONTAINER_NAME}${DOMAIN_NAME}' < ${BASE_DIR}/horizon/alpine/default.conf.template > /tmp/default.conf

echo "${LXC} dd status=none of=/etc/nginx/http.d/default.conf < /tmp/default.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/nginx/http.d/default.conf < /tmp/default.conf

echo "rm -f /tmp/default.conf" 2>&1 | tee -a $0.log
rm -f /tmp/default.conf

for (( i = 1; i <= NUMBER_OF_WORKERS; i++ )); do
  export i
  echo "export PORT=$(( 5000 + i ))"
  export PORT=$(( 5000 + i ))
  echo "envsubst '\${PORT}\${i}' < ${BASE_DIR}/horizon/alpine/horizon.template > /tmp/horizon-${i}" 2>&1 | tee -a $0.log
  envsubst '${PORT}${i}' < ${BASE_DIR}/horizon/alpine/horizon.template > /tmp/horizon-${i}
  echo "${LXC} dd status=none of=/etc/init.d/horizon-${i} < /tmp/horizon-${i}" 2>&1 | tee -a $0.log
  ${LXC} dd status=none of=/etc/init.d/horizon-${i} < /tmp/horizon-${i}
  echo "rm -f /tmp/horizon-${i}" 2>&1 | tee -a $0.log
  rm -f /tmp/horizon-${i} 2>&1 | tee -a $0.log
  echo "${LXC} chmod 755 /etc/init.d/horizon-${i}" 2>&1 | tee -a $0.log
  ${LXC} chmod 755 /etc/init.d/horizon-${i} 2>&1 | tee -a $0.log
  echo "${LXC} rc-update add horizon-${i}" 2>&1 | tee -a $0.log
  ${LXC} rc-update add horizon-${i} 2>&1 | tee -a $0.log
  echo "${LXC} sed -i \"/\ #\ server\ 127.0.0.1:5001;/a\\ \ \ \ server\ 127.0.0.1:${PORT};\" /etc/nginx/nginx.conf" 2>&1 | tee -a $0.log
  ${LXC} sed -i "/\ #\ server\ 127.0.0.1:5001;/a\\ \ \ \ server\ 127.0.0.1:${PORT};" /etc/nginx/nginx.conf 2>&1 | tee -a $0.log
done

echo "${LXC} rc-update add nginx" 2>&1 | tee -a $0.log
${LXC} rc-update add nginx 2>&1 | tee -a $0.log

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

  echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  bind :80 # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

  ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  bind :80 # ${CONTAINER_NAME}"

  for (( j = 1; j <= NUMBER_OF_CONTROLLERS; j++ )); do

    CONTAINER_IP=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-${j} | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

      echo "${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<\"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:80 check # ${CONTAINER_NAME}\"" 2>&1 | tee -a $0.log

      ${SSH} ${LXC} dd status=none oflag=append conv=notrunc of=/etc/haproxy/haproxy.cfg <<<"  server ${CONTAINER_NAME}-${j} ${CONTAINER_IP}:80 check # ${CONTAINER_NAME}"

  done

  echo "${SSH} ${LXC} service haproxy reload" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} service haproxy reload

done
