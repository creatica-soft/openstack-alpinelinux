#!/usr/bin/bash

# haproxy - free open source reliable high performance TCP/HTTP load balancer
# keepalived - simple and robust facilities for loadbalancing and high-availability to Linux system and Linux based infrastructures
# http://www.haproxy.org/
# https://keepalived.org/

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export CONTAINER_NAME=${SQL_CONTAINER_NAME}

if [[ "${READY_TO_PROCEED}" != "true" ]]; then
  echo "Please review and update environment variables in ${BASE_DIR}/common/common.env, then set READY_TO_PROCEED=true"
  exit 1
fi

echo `date` 2>&1 | tee $0.log
echo "source ${BASE_DIR}/common/common.env" 2>&1 | tee -a $0.log
echo "CONTAINER_NAME=${CONTAINER_NAME}" 2>&1 | tee -a $0.log

read -p "Install ${CONTAINER_NAME} cluster in linux containers? [y/N]"
if [[ "${REPLY}" != "y" ]]; then
  exit 1
fi

lxc_clone "${DOWNLOAD_DIST}" "${CONTAINER_NAME}-1"

# Create a virtual port for postgres
echo "ovn-nbctl --may-exist lsp-add ${BR_INTERNAL} ${CONTAINER_NAME} -- lsp-set-type ${CONTAINER_NAME} virtual -- lsp-set-enabled ${CONTAINER_NAME} enabled -- lsp-set-options ${CONTAINER_NAME} virtual-ip=${POSTGRES_IP} virtual-parents=\"${CONTAINER_NAME}-1,${CONTAINER_NAME}-2,${CONTAINER_NAME}-3\"" 2>&1 | tee -a $0.log

ovn-nbctl --may-exist lsp-add ${BR_INTERNAL} ${CONTAINER_NAME} -- lsp-set-type ${CONTAINER_NAME} virtual -- lsp-set-enabled ${CONTAINER_NAME} enabled -- lsp-set-options ${CONTAINER_NAME} virtual-ip=${POSTGRES_IP} virtual-parents="${CONTAINER_NAME}-1,${CONTAINER_NAME}-2,${CONTAINER_NAME}-3" 2>&1 | tee -a $0.log

# Create DNS record for this virtual port
dns_update "${CONTAINER_NAME}" "${POSTGRES_IP}"
dns_reload

ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"
ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-2" "${CONTROLLER_NAME}-2.${DOMAIN_NAME}"
ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-3" "${CONTROLLER_NAME}-3.${DOMAIN_NAME}"

export IP_ADDR1=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-1 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
export IP_ADDR2=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-2 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`
export IP_ADDR3=`ovn-nbctl find logical_switch_port name=${CONTAINER_NAME}-3 | egrep "^dynamic_addresses "|cut -f2- -d":"|cut -f3 -d" "|tr -d "\""`

echo "IP_ADDR1=${IP_ADDR1}" 2>&1 | tee -a $0.log
echo "IP_ADDR2=${IP_ADDR2}" 2>&1 | tee -a $0.log
echo "IP_ADDR3=${IP_ADDR3}" 2>&1 | tee -a $0.log

lxc_config "${CONTAINER_NAME}-1"

# This does not work in alpine and doesn't seem to be needed even though it set to 0
# It could be related to the fact that the non-local IP is declared as virtual in OVN, which has local parents.
#echo "lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1" >> /var/lib/lxc/${CONTAINER_NAME}-1/config

echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

lxc_set_hostname "${CONTAINER_NAME}-1"
lxc_set_hosts "${CONTAINER_NAME}-1"

echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
echo "lxc-start -n  ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# install postgres and keepalived

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apk update && apk upgrade && apk add --no-cache alpine-sdk openssl-dev libnl3-dev file-dev ipset-dev musl-locales postgresql\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apk update && apk upgrade && apk add --no-cache alpine-sdk openssl-dev libnl3-dev file-dev ipset-dev musl-locales postgresql" 2>&1 | tee -a $0.log

echo "${LXC} rc-update add postgresql" 2>&1 | tee -a $0.log
${LXC} rc-update add postgresql 2>&1 | tee -a $0.log

echo "${LXC} wget -O /root/keepalived-${KEEPALIVED_VERSION}.tar.gz ${KEEPALIVED_URL}" 2>&1 | tee -a $0.log
${LXC} wget -O /root/keepalived-${KEEPALIVED_VERSION}.tar.gz ${KEEPALIVED_URL} 2>&1 | tee -a $0.log

echo "${LXC} tar -C /root -zxf /root/keepalived-${KEEPALIVED_VERSION}.tar.gz" 2>&1 | tee -a $0.log
${LXC} tar -C /root -zxf /root/keepalived-${KEEPALIVED_VERSION}.tar.gz 2>&1 | tee -a $0.log

echo "${LXC} sh -c \"cd /root/keepalived-${KEEPALIVED_VERSION}; ./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc --with-init=openrc --disable-lvs --disable-vrrp-auth --disable-routes --disable-vmac --disable-iptables --disable-nftables --disable-systemd --disable-track-process; make; make install\"" 2>&1 | tee -a $0.log
${LXC} sh -c "cd /root/keepalived-${KEEPALIVED_VERSION}; ./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc --disable-lvs --disable-routes --disable-vmac --disable-iptables --disable-nftables --disable-systemd --disable-track-process; make; make install" 2>&1 | tee -a $0.log

# keepalived does not work well under supervise-daemon
#echo "${LXC} dd status=none of=/etc/init.d/keepalived < ${BASE_DIR}/postgres/alpine/keepalived" 2>&1 | tee -a $0.log
#${LXC} dd status=none of=/etc/init.d/keepalived < ${BASE_DIR}/postgres/alpine/keepalived

echo "${LXC} sed -i 's/"\/sbin\/\$/"\/usr\/sbin\/\$/' /etc/init.d/keepalived" 2>&1 | tee -a $0.log
${LXC} sed -i 's/"\/sbin\/\$/"\/usr\/sbin\/\$/' /etc/init.d/keepalived

echo "${LXC} chmod 755 /etc/init.d/keepalived" 2>&1 | tee -a $0.log
${LXC} chmod 755 /etc/init.d/keepalived 2>&1 | tee -a $0.log

echo "${LXC} rc-update add keepalived" 2>&1 | tee -a $0.log
${LXC} rc-update add keepalived 2>&1 | tee -a $0.log

echo "${LXC} mkdir -p /etc/keepalived" 2>&1 | tee -a $0.log
${LXC} mkdir -p /etc/keepalived 2>&1 | tee -a $0.log

echo "${LXC} mkdir -p /etc/postgresql" 2>&1 | tee -a $0.log
${LXC} mkdir -p /etc/postgresql 2>&1 | tee -a $0.log

echo "${LXC} mkdir -p /run/postgresql" 2>&1 | tee -a $0.log
${LXC} mkdir -p /run/postgresql 2>&1 | tee -a $0.log

echo "${LXC} chown postgres:postgres /run/postgresql" 2>&1 | tee -a $0.log
${LXC} chown postgres:postgres /run/postgresql 2>&1 | tee -a $0.log


export i=1

echo "envsubst < ${BASE_DIR}/postgres/alpine/postgresql.template > /tmp/postgresql" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/alpine/postgresql.template > /tmp/postgresql
echo "${LXC} dd status=none of=/etc/init.d/postgresql < /tmp/postgresql" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/init.d/postgresql < /tmp/postgresql
echo "${LXC} dd status=none of=/etc/postgresql/postgresql.master < ${BASE_DIR}/postgres/postgresql.master" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/postgresql/postgresql.master < ${BASE_DIR}/postgres/postgresql.master
echo "envsubst < ${BASE_DIR}/postgres/pg_hba.conf.template > /tmp/pg_hba.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/pg_hba.conf.template > /tmp/pg_hba.conf
echo "${LXC} dd status=none of=/etc/postgresql/pg_hba.conf < /tmp/pg_hba.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/postgresql/pg_hba.conf < /tmp/pg_hba.conf
echo "rm -f /tmp/pg_hba.conf" 2>&1 | tee -a $0.log
rm -f /tmp/pg_hba.conf 2>&1 | tee -a $0.log

echo "${LXC} service postgresql initdb" 2>&1 | tee -a $0.log
${LXC} service postgresql initdb 2>&1 | tee -a $0.log

echo "${LXC} rm -f /var/lib/postgresql/13/data/pg_hba.conf" 2>&1 | tee -a $0.log
${LXC} rm -f /var/lib/postgresql/13/data/pg_hba.conf 2>&1 | tee -a $0.log
echo "${LXC} ln -s /etc/postgresql/pg_hba.conf /var/lib/postgresql/13/data/pg_hba.conf" 2>&1 | tee -a $0.log
${LXC} ln -s /etc/postgresql/pg_hba.conf /var/lib/postgresql/13/data/pg_hba.conf 2>&1 | tee -a $0.log
echo "${LXC} rm -f /var/lib/postgresql/13/data/postgresql.conf" 2>&1 | tee -a $0.log
${LXC} rm -f /var/lib/postgresql/13/data/postgresql.conf 2>&1 | tee -a $0.log
echo "${LXC} ln -s /etc/postgresql/postgresql.master /var/lib/postgresql/13/data/postgresql.conf" 2>&1 | tee -a $0.log
${LXC} ln -s /etc/postgresql/postgresql.master /var/lib/postgresql/13/data/postgresql.conf 2>&1 | tee -a $0.log
echo "envsubst < ${BASE_DIR}/postgres/postgresql.slave.template > /tmp/postgresql.slave" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/postgresql.slave.template > /tmp/postgresql.slave
echo "${SSH} ${LXC} dd status=none of=/etc/postgresql/postgresql.slave < /tmp/postgresql.slave" 2>&1 | tee -a $0.log
${SSH} ${LXC} dd status=none of=/etc/postgresql/postgresql.slave < /tmp/postgresql.slave
echo "rm -f /tmp/postgresql.conf /tmp/postgresql.slave /tmp/postgresql" 2>&1 | tee -a $0.log
rm -f /tmp/postgresql.conf /tmp/postgresql.slave /tmp/postgresql 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/postgres/.pgpass.template > /tmp/.pgpass" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/.pgpass.template > /tmp/.pgpass
echo "${LXC} dd status=none of=/var/lib/postgresql/.pgpass < /tmp/.pgpass" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/var/lib/postgresql/.pgpass < /tmp/.pgpass
echo "${LXC} chmod 400 /var/lib/postgresql/.pgpass" 2>&1 | tee -a $0.log
${LXC} chmod 400 /var/lib/postgresql/.pgpass 2>&1 | tee -a $0.log
echo "${LXC} chown postgres:postgres /var/lib/postgresql/.pgpass" 2>&1 | tee -a $0.log
${LXC} chown postgres:postgres /var/lib/postgresql/.pgpass 2>&1 | tee -a $0.log
echo "rm -f /tmp/.pgpass" 2>&1 | tee -a $0.log
rm -f /tmp/.pgpass 2>&1 | tee -a $0.log

echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
echo "lxc-start -n  ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

#lxc_wait "${CONTAINER_NAME}-1" "su -l postgres -s /bin/sh -c \"pg_isready -h 0.0.0.0 -d postgres -U postgres\"" "Is postgres ready? [y/N]"
lxc_wait "${CONTAINER_NAME}-1" "ps" "Is postgres ready? [y/N]"

#read -p "postgres start command does not release the terminal. So please start it from another terminal by running 'lxc-attach -n postgres-1 -- service postgresql start' and then proceed, ok? [y/N]"
#if [[ "${REPLY}" != "y" ]]; then
#  exit 1
#fi

echo "${LXC} su -l postgres -s /bin/sh -c \"psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_1');\"\"" 2>&1 | tee -a $0.log
${LXC} su -l postgres -s /bin/sh -c "psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_1');\"" 2>&1 | tee -a $0.log
echo "${LXC} su -l postgres -s /bin/sh -c \"psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_2');\"\"" 2>&1 | tee -a $0.log
${LXC} su -l postgres -s /bin/sh -c "psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_2');\"" 2>&1 | tee -a $0.log
echo "${LXC} su -l postgres -s /bin/sh -c \"psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_3');\"\"" 2>&1 | tee -a $0.log
${LXC} su -l postgres -s /bin/sh -c "psql -h 0.0.0.0 -d postgres -U postgres -c \"SELECT pg_create_physical_replication_slot('replication_slot_3');\"" 2>&1 | tee -a $0.log

POSTGRES_PASS=\'${POSTGRES_PASS}\'
echo "${LXC} su -l postgres -s /bin/sh -c \"psql -h 0.0.0.0 -U postgres -d postgres -c \"alter user postgres with password *****;\"\"" 2>&1 | tee -a $0.log
${LXC} su -l postgres -s /bin/sh -c "psql -h 0.0.0.0 -U postgres -d postgres -c \"alter user postgres with password ${POSTGRES_PASS};\"" 2>&1 | tee -a $0.log

#echo "${LXC} service postgresql restart " 2>&1 | tee -a $0.log
#${LXC} service postgresql restart 2>&1 | tee -a $0.log

echo "envsubst < ${BASE_DIR}/postgres/keepalived.conf.template > /tmp/keepalived.conf" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/keepalived.conf.template > /tmp/keepalived.conf
echo "${LXC} dd status=none of=/etc/keepalived/keepalived.conf < /tmp/keepalived.conf" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/etc/keepalived/keepalived.conf < /tmp/keepalived.conf
echo "rm -f /tmp/keepalived.conf" 2>&1 | tee -a $0.log
rm -f /tmp/keepalived.conf 2>&1 | tee -a $0.log

# promote, demote and check_postgres scripts
echo "${LXC} dd status=none of=/var/lib/postgresql/check_postgres.sh < ${BASE_DIR}/postgres/alpine/check_postgres.sh" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/var/lib/postgresql/check_postgres.sh < ${BASE_DIR}/postgres/alpine/check_postgres.sh
echo "${LXC} dd status=none of=/var/lib/postgresql/promote.sh < ${BASE_DIR}/postgres/alpine/promote.sh" 2>&1 | tee -a $0.log
${LXC} dd status=none of=/var/lib/postgresql/promote.sh < ${BASE_DIR}/postgres/alpine/promote.sh
echo "envsubst < ${BASE_DIR}/postgres/alpine/demote.sh.template > /tmp/demote.sh" 2>&1 | tee -a $0.log
envsubst < ${BASE_DIR}/postgres/alpine/demote.sh.template > /tmp/demote.sh
${LXC} dd status=none of=/var/lib/postgresql/demote.sh < /tmp/demote.sh
echo "${LXC} chmod 755 /var/lib/postgresql/check_postgres.sh" 2>&1 | tee -a $0.log
${LXC} chmod 755 /var/lib/postgresql/check_postgres.sh 2>&1 | tee -a $0.log
echo "${LXC} chmod 755 /var/lib/postgresql/promote.sh" 2>&1 | tee -a $0.log
${LXC} chmod 755 /var/lib/postgresql/promote.sh 2>&1 | tee -a $0.log
echo "${LXC} chmod 755 /var/lib/postgresql/demote.sh" 2>&1 | tee -a $0.log
${LXC} chmod 755 /var/lib/postgresql/demote.sh 2>&1 | tee -a $0.log
echo "rm -f /tmp/demote.sh" 2>&1 | tee -a $0.log
rm -f /tmp/demote.sh 2>&1 | tee -a $0.log

echo "${LXC} service keepalived start" 2>&1 | tee -a $0.log
${LXC} service keepalived start 2>&1 | tee -a $0.log
echo "${LXC} service keepalived status" 2>&1 | tee -a $0.log
${LXC} service keepalived status 2>&1 | tee -a $0.log

# stop the clone to make snapshot (probably not necessary)
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# create a snapshot of the first clone
lxc_snapshot "${CONTAINER_NAME}-1"

# create more clones from the snapshot
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "ssh ${CONTROLLER_NAME}-${i}"
done

# start the first clone
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"

# configure other clones
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  export i
  SSH="ssh ${CONTROLLER_NAME}-${i}"
  LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-${i} --"

  lxc_config "${CONTAINER_NAME}-${i}" "${SSH}"

#  echo "${SSH} dd status=none of=/var/lib/lxc/${CONTAINER_NAME}-${i}/config oflag=append conv=notrunc <<<\"lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1\""
#  ${SSH} dd status=none of=/var/lib/lxc/${CONTAINER_NAME}-${i}/config oflag=append conv=notrunc <<<"lxc.sysctl.net.ipv4.ip_nonlocal_bind = 1"

  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log

  lxc_set_hostname "${CONTAINER_NAME}-${i}" "${SSH}"
  lxc_set_hosts "${CONTAINER_NAME}-${i}" "${SSH}"

  echo "${SSH} lxc-stop -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-stop -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  lxc_status "${CONTAINER_NAME}-${i}" "${SSH}"

  echo "envsubst < ${BASE_DIR}/postgres/postgresql.slave.template > /tmp/postgresql.conf" 2>&1 | tee -a $0.log
  envsubst < ${BASE_DIR}/postgres/postgresql.slave.template > /tmp/postgresql.conf
  echo "${SSH} ${LXC} dd status=none of=/etc/postgresql/postgresql.slave < /tmp/postgresql.conf" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} dd status=none of=/etc/postgresql/postgresql.slave < /tmp/postgresql.conf

  lxc_wait "${CONTAINER_NAME}-${i}" "service postgresql status" "Is postgresql up? [y/N]" "${SSH}"

  echo "${SSH} \"${LXC} sh -c 'service postgresql stop; rm -rf /var/lib/postgresql/13/data'\"" 2>&1 | tee -a $0.log
  ${SSH} "${LXC} sh -c 'service postgresql stop; rm -rf /var/lib/postgresql/13/data'" 2>&1 | tee -a $0.log

  if (( i == 2 )); then

    echo "${SSH} \"${LXC} su -l postgres -s /bin/sh -c 'pg_basebackup -w -R -X stream -S replication_slot_2 -d \"host=${CONTAINER_NAME} port=5432 user=postgres passfile=/var/lib/postgresql/.pgpass\" -D /var/lib/postgresql/13/data'\"" 2>&1 | tee -a $0.log
    ${SSH} "${LXC} su -l postgres -s /bin/sh -c 'pg_basebackup -w -R -X stream -S replication_slot_2 -d \"host=${CONTAINER_NAME} port=5432 user=postgres passfile=/var/lib/postgresql/.pgpass\" -D /var/lib/postgresql/13/data'" 2>&1 | tee -a $0.log
  
  else

    echo "${SSH} \"${LXC} su -l postgres -s /bin/sh -c 'pg_basebackup -w -R -X stream -S replication_slot_3 -d \"host=${CONTAINER_NAME} port=5432 user=postgres passfile=/var/lib/postgresql/.pgpass\" -D /var/lib/postgresql/13/data'\"" 2>&1 | tee -a $0.log
    ${SSH} "${LXC} su -l postgres -s /bin/sh -c 'pg_basebackup -w -R -X stream -S replication_slot_3 -d \"host=${CONTAINER_NAME} port=5432 user=postgres passfile=/var/lib/postgresql/.pgpass\" -D /var/lib/postgresql/13/data'" 2>&1 | tee -a $0.log

  fi

  echo "${SSH} ${LXC} rm -f /var/lib/postgresql/13/data/pg_hba.conf" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} rm -f /var/lib/postgresql/13/data/pg_hba.conf 2>&1 | tee -a $0.log
  echo "${SSH} ${LXC} ln -s /etc/postgresql/pg_hba.conf /var/lib/postgresql/13/data/pg_hba.conf" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} ln -s /etc/postgresql/pg_hba.conf /var/lib/postgresql/13/data/pg_hba.conf 2>&1 | tee -a $0.log
  echo "${SSH} ${LXC} rm -f /var/lib/postgresql/13/data/postgresql.conf" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} rm -f /var/lib/postgresql/13/data/postgresql.conf 2>&1 | tee -a $0.log
  echo "${SSH} ${LXC} ln -s /etc/postgresql/postgresql.slave /var/lib/postgresql/13/data/postgresql.conf" 2>&1 | tee -a $0.log
  ${SSH} ${LXC} ln -s /etc/postgresql/postgresql.slave /var/lib/postgresql/13/data/postgresql.conf 2>&1 | tee -a $0.log
  echo "rm -f /tmp/postgresql.conf" 2>&1 | tee -a $0.log
  rm -f /tmp/postgresql.conf 2>&1 | tee -a $0.log

  read -p "postgres start command does not release the terminal. So please start it from another terminal on ${CONTAINER_NAME}-${i} by running 'lxc-attach -n postgres-${i} -- service postgresql start' and then proceed, ok? [y/N]"
  if [[ "${REPLY}" != "y" ]]; then
    exit 1
  fi
done
