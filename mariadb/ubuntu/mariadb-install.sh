#!/usr/bin/bash

# Mariadb Galera - synchronous multi-master database cluster
# https://galeracluster.com/2014/11/galera-as-central-building-block-for-openstack-high-availability/
# https://downloads.mariadb.org/mariadb/repositories/#distro=Ubuntu&distro_release=focal--ubuntu_focal&mirror=digital-pacific&version=10.5
# https://mariadb.com/kb/en/getting-started-with-mariadb-galera-cluster/
# https://galeracluster.com/library/documentation/quorum-reset.html (basically, shut all members, then
# safe_to_bootstrap: 1 in /var/lib/mysql/grastate.dat on the most advanced member and run galera_new_cluster
# then systemctl start mariadb on other members)

if [[ ! -v BASE_DIR ]]; then
  BASE_DIR=`find / -type d -name openstack-prod-install -print -quit`
  read -e -i ${BASE_DIR} -p "BASE_DIR env var is not set. Please enter it: "
  export BASE_DIR=${REPLY}
fi

source ${BASE_DIR}/common/common.env
source ${BASE_DIR}/common/functions

export DOWNLOAD_DIST="ubuntu"
export DOWNLOAD_RELEASE="focal"
export RBD_FSSIZE="3G"

CONTAINER_NAME=${SQL_CONTAINER_NAME}

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

# clone base image
lxc_clone "${DOWNLOAD_DIST}-${DOWNLOAD_RELEASE}" "${CONTAINER_NAME}-1"

# mariadb takes about 1.4GB, so it's safer to resize it to 3GB
image_resize "${CONTAINER_NAME}-1" "3GB"

# create network port
ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-1" "${CONTROLLER_NAME}-1.${DOMAIN_NAME}"
lxc_config "${CONTAINER_NAME}-1"

# start the clone
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# set hostname, /etc/hosts and LLMNR
lxc_set_hostname "${CONTAINER_NAME}-1"
lxc_set_hosts "${CONTAINER_NAME}-1"
lxc_set_llmnr "${CONTAINER_NAME}-1"

# restart the clone
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
echo "lxc-start -n  ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n  ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log
lxc_status "${CONTAINER_NAME}-1"
static_route_check "${CONTAINER_NAME}-1" "${COMPUTE_NETWORK_CIDR}" "${INTERNAL_NETWORK_GATEWAY}"

# install mariadb galera cluster

LXC="lxc-attach --keep-env -n ${CONTAINER_NAME}-1 --"

echo "${LXC} sh -c \"apt update -y && apt upgrade -y && apt install -y curl gnupg\"" 2>&1 | tee -a $0.log
${LXC} sh -c "apt update -y && apt upgrade -y && apt install -y curl gnupg" 2>&1 | tee -a $0.log
echo "${LXC} sh -c \"curl -fsSL ${MARIADB_KEY_URL} | apt-key add -\"" 2>&1 | tee -a $0.log
${LXC} sh -c "curl -fsSL ${MARIADB_KEY_URL} | apt-key add -" 2>&1 | tee -a $0.log
echo "${LXC} sh -c \"echo ${MARIADB_REPO} > /etc/apt/sources.list.d/mariadb.repo.list\"" 2>&1 | tee -a $0.log
${LXC} sh -c "echo ${MARIADB_REPO} > /etc/apt/sources.list.d/mariadb.repo.list"
echo "${LXC} apt update -y" 2>&1 | tee -a $0.log
${LXC} apt update -y 2>&1 | tee -a $0.log
echo "${LXC} apt install -y mariadb-server mariadb-backup mariadb-client galera-4" 2>&1 | tee -a $0.log
${LXC} apt install -y mariadb-server mariadb-backup mariadb-client galera-4 2>&1 | tee -a $0.log

# configure mariadb
${LXC} sh -c "cat <<'EOF'> /etc/mysql/mariadb.conf.d/60-galera.cnf
[galera]
wsrep_provider           = /usr/lib/libgalera_smm.so
wsrep_on                 = ON
wsrep_cluster_name       = \"MariaDB Galera Cluster\"
wsrep_cluster_address    = gcomm://${CONTAINER_NAME}-1,${CONTAINER_NAME}-2,${CONTAINER_NAME}-3?pc.wait_prim=no
binlog_format            = row
default_storage_engine   = InnoDB
innodb_autoinc_lock_mode = 2
bind-address = 0.0.0.0
wsrep_slave_threads = 1
innodb_flush_log_at_trx_commit = 0
EOF
"

echo "${LXC} sed -i \"/^bind-address/c\\bind-address\ =\ 0.0.0.0\" /etc/mysql/mariadb.conf.d/50-server.cnf" 2>&1 | tee -a $0.log
${LXC} sed -i "/^bind-address/c\\bind-address\ =\ 0.0.0.0" /etc/mysql/mariadb.conf.d/50-server.cnf 2>&1 | tee -a $0.log

echo "${LXC} systemctl disable mariadb" 2>&1 | tee -a $0.log
${LXC} systemctl disable mariadb 2>&1 | tee -a $0.log

# stop mariadb to take a snapshot (probably not necessary)
echo "lxc-stop -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-stop -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# take the snaphost of this clone
lxc_snapshot "${CONTAINER_NAME}-1"

# create more clones from the snapshot
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++ )); do
  lxc_clone "${CONTAINER_NAME}-1" "${CONTAINER_NAME}-${i}" "ssh ${CONTROLLER_NAME}-${i}"
done

# start the first clone after snapshotting
echo "lxc-start -n ${CONTAINER_NAME}-1" 2>&1 | tee -a $0.log
lxc-start -n ${CONTAINER_NAME}-1 2>&1 | tee -a $0.log

# configure other clones in a similar way
for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"
  ovn_nbctl_add_port "${BR_INTERNAL}" "${CONTAINER_NAME}-${i}" "${CONTROLLER_NAME}-${i}.${DOMAIN_NAME}"
  lxc_config "${CONTAINER_NAME}-${i}" "${SSH}"
  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log

  lxc_set_hostname "${CONTAINER_NAME}-${i}" "${SSH}"
  lxc_set_hosts "${CONTAINER_NAME}-${i}" "${SSH}"
  lxc_set_llmnr "${CONTAINER_NAME}-${i}" "${SSH}"

  echo "${SSH} lxc-stop -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-stop -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  echo "${SSH} lxc-start -n ${CONTAINER_NAME}-${i}" 2>&1 | tee -a $0.log
  ${SSH} lxc-start -n ${CONTAINER_NAME}-${i} 2>&1 | tee -a $0.log
  lxc_status "${CONTAINER_NAME}-${i}" "${SSH}"
done

# bootstrap the mariadb galera cluster
echo "${LXC} galera_new_cluster" 2>&1 | tee -a $0.log
${LXC} galera_new_cluster 2>&1 | tee -a $0.log

echo "${LXC} systemctl enable mariadb" 2>&1 | tee -a $0.log
${LXC} systemctl enable mariadb 2>&1 | tee -a $0.log

for (( i = 2; i <= NUMBER_OF_CONTROLLERS; i++)); do
  SSH="ssh ${CONTROLLER_NAME}-${i}"
  echo "${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} systemctl enable mariadb" 2>&1 | tee -a $0.log
  ${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} systemctl enable mariadb 2>&1 | tee -a $0.log
  echo "${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} systemctl start mariadb" 2>&1 | tee -a $0.log
  ${SSH} lxc-attach -n ${CONTAINER_NAME}-${i} systemctl start mariadb 2>&1 | tee -a $0.log
done

# check the mariadb cluster status
echo "${LXC} mysql -e \"SHOW GLOBAL STATUS LIKE 'wsrep_%';\"" 2>&1 | tee -a $0.log
${LXC} mysql -e "SHOW GLOBAL STATUS LIKE 'wsrep_%';"
read -p "Is mariadb galera cluster formed? [y/N]"
while [[ "${REPLY}" != "y" ]]; do
  echo "${LXC} mysql -e \"SHOW GLOBAL STATUS LIKE 'wsrep_%';\"" 2>&1 | tee -a $0.log
  ${LXC} mysql -e "SHOW GLOBAL STATUS LIKE 'wsrep_%';"
  read -p "Is mariadb galera cluster formed? [y/N]"
done



