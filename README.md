# Openstack production installation scripts

This is work in progress. 

The proof of concept is done though. All control plane openstack components run in linux containers backed by ceph cluster (built separately) connected to ovn cluster. The same ovn cluster is used for compute nodes by neutron. The installation of the following components is automated via bash scripts with detailed logs for each component stored in [component-folder]/[component-name]-[un]install.sh.log.

- ISC bind DNS servers (one master and two slaves)
- ovn cluster
- rabbitmq cluster
- mariadb galera cluster (the only software that runs in ubuntu containers - actually, it does not run at all in alpine!)
-- so postgresql synchronous master-slave-slave with keepalived is used instead and SQLAlchemy is configured accordingly. 
- memcached servers
- haproxy containers with keepalived
- keystone cluster
- glance cluster
- placement cluster
- nova cluster
- neutron cluster
- cinder cluster
- horizon cluster
- compute nodes
- sample alpine-based VM with all dependent openstack objects 

The openstack components and its prerequisites (except ovn and python openstack client, which are installed on each controller node) are built in linux containers based on alpine-3.xx (default) distributions. Ubuntu containers were initially used but their automation is no longer maintained, except for mariadb galera cluster.

Linux containers rely on ceph cluster as a backing storage and connect to OVN network cluster.

Containers are connected to an overlay logical switch. 

Container external connections go via a logical router that interconnects the overlay logical switch and the provider bridged logical switch. The provider logical switch is bridged to the provider physical network.

Container compute network connections go via another logical router and a compute network bridged logical switch. The compute network logical switch is bridged to the compute physical network. 

The connections between containers and compute and ceph nodes rely on a static route, which is configured automatically on the router and on compute nodes via staticroute rc file but must also be configured on ceph nodes.

ISC bind services run on controller nodes: master on controller-1 and slaves on controller 2 and 3. A and PTR RR records are created in compute.zone and internal-reverse.zone respectively after OVN port is. The records are also deleted when the port is. When compute nodes are added or deleted, the DNS records can also be managed automatically in compute.zone and compute-reverse.zone. Bind servers are authoritative for openstack controller, compute nodes and containers but also provide forwarding (recursion).

Containers are built from the base image "alpine" and stored in ceph cluster by cloning its protected snapshot. So initially they won't take much room. The size of linux file system in "ubuntu" is limited to 3GB for mariadb galera cluster, in "alpine" it can be much smaller: haproxy with keepalived takes just 17MB as an example, default is 1GB. It can be resized if necessary. "ubuntu-focal" has a cronjob running every day to rotate and vacuum archived log files if they exceed 100MB. In "alpine" logrotate runs as a daily job.

Logging is centralized and fault-tolerant. Rsyslog is used for the solution. Controller-1 is the primary log collector, 2 and 3 - are standby. TCP on port 10514 is used. Containers run rsyslog on the unix socket (/dev/log) and forward logs over tcp to controller-1 and if it fails, then to controller-2 and then if it fails again, to controller-3. Facilities are used to group messages to log files; for example, local0 is used for OVS/OVN and local1 - for rabbitmq, etc.

In ubuntu services run under systemd. In alpine under openrc supervise-daemon.

Alpine containers are available and the default ones for rabbitmq, memcached, haproxy and all openstack control plane components. Compute and controller nodes also run alpine. The only server that runs ubuntu by default is mariadb galera cluster because galera cluster provider library is not portable.

It is assumed that every redundant openstack control plane component runs on each controller node. So we build the first container, then snapshot it and clone others from the protected snapshot. This again will help to keep the size of container images to a minimum. If necessary, containers may be detached from their snapshot via a standard ceph procedure called image flattening.

All openstack controller containers are built directly from git repo. In ubuntu it helps to avoid badly dependencies in distro packages. 

Compute nodes are installed either by using ubuntu packages or alpine python packages tarballed from nova, neutron and cinder containers (default) plus apk packages for dependencies such as KVM, QEMU (qemu-system-x86_64 is built from git repo to enable rbd support), etc.

The structure is as follows: os-cluster-install.sh and os-cluster-uninstall.sh are the main wrappers around individual component scripts such as ovn-install.sh, rabbitmq-install.sh, etc and some "uninstall" counterparts. Containers uninstall is done using a single script called container-uninstall.sh. 

Common environment variables are placed in common.env, which is sourced by individual scripts. common/functions file has some useful functions that avoid cluttering the installation scripts.

The scripts are meant to be run on controller-1. On other controllers and compute nodes, the components are installed over ssh from controller-1. Therefore, valid /root/.ssh/id_rsa is needed on controller-1 and /root/.ssh/authorized_keys on other controllers and compute nodes. Luckily, it's semi-automated in pre-install.sh scripts.

Any container install script may be used as a template for building linux containers for new openstack components.

All REST API openstack wsgi flask apps (except glance and neutron-server) are run in bjoern workers (instead of apache+uwsgi) and load balanced by haproxy. Horizon dashboard additionally runs nginx to serve static contents and load-balanced bjoern workers. There is a noticable performance improvement in horizon dashboard when it is run in nginx+bjoern rather than apache+uswgi.

Canonical MAAS server does not allow custom images without a license. So alpine nodes may not be installed from MAAS. MAAS is an overkill in any case.

Alpine linux can be easily bootstrapped from the network using iPXE-boot, much faster than from MAAS. All is needed are a DHCP and TFTP servers on the same network as controller and compute nodes. DHCP server should have an option filename="ipxe.pxe" (or similar) and TFTP server should be able to provide this file. By default, it will attempt to boot from https://boot.alpinelinux.org/boot.ipxe but this can be changed to any other mirror, even to a local one by adjusting boot.ipxe file and pointing to it via iPXE shell "chain" command. 

In vCenter, iPXE does not work for some reason, so alpine VMs can be booted from a datastore alpine-virt iso and running setup-alpine. Do reboot first once setup-alpine is finished before attempting any configuration changes, otherwise they will be lost after reboot!

## Installation

Running bash scripts in alpine needs bash, of course. So run 

```
apk add bash git
ln -s /bin/bash /usr/bin/bash
```

first. Then clone this repo (use .ssh/git_id_rsa for ssh key if you want)

```
vi .ssh/config
Host git.corp-apps.com
 HostName git.corp-apps.com
 IdentityFile ~/.ssh/git_id_rsa

git clone ssh://git@git.corp-apps.com:7999/ea/openstack-prod-install.git
cd openstack-prod-install
chmod 755 *.sh */*.sh */*/*.sh
```

then review and update common/common.env file setting READY_TO_PROCEED=true. 

```
vi common/common.env
...
READY_TO_PROCEED=true
```

Then run ./alpine-pre-install.sh (it will require reboot of controller nodes)

```
./alpine-pre-install.sh
```

and finally continue with ./os-cluster-install.sh.

```
./os-cluster-install.sh
```