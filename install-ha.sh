#!/bin/bash 

. functions.sh

validate_config masters "provide hosts onto which to install masters"
validate_config target "host onto which to run installation"
validate_config etcds "provide at least one host to use for etcd, can't be a master"
optional_config lb "provide host for external load balancer"
validate_config nodes "provide hosts to be configured as nodes"

function get_hosts
{
   ret=$(for h in $1 ; do echo $h; done)
   echo "$ret"
}

function get_masters
{
   ret=$(get_hosts "$masters")
   echo "$ret"
}
function get_etcds
{
   ret=$(get_hosts "$etcds")
   echo "$ret"
}

function get_nodes
{
   echo "$(for m in $masters; do echo "$m openshift_node_labels='{"region":"infra"}' openshift_schedulable=false"; done)
$(for n in $nodes; do echo "$n openshift_node_labels='{"region":"primary"}' "; done)"

}

function generate_config
{
echo "# Create an OSEv3 group that contains the master, nodes, etcd, and lb groups.
# The lb group lets Ansible configure HAProxy as the load balancing solution.
# Comment lb out if your load balancer is pre-configured.
[OSEv3:children]
masters
nodes
etcd
$([[ ! "$lb" == "" ]] && echo 'lb')

# Set variables common for all OSEv3 hosts
[OSEv3:vars]
ansible_ssh_user=root
deployment_type=openshift-enterprise
# openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/htpasswd'}]

# Native high availbility cluster method with optional load balancer.
# If no lb group is defined installer assumes that a load balancer has
# been preconfigured. For installation the value of
# openshift_master_cluster_hostname must resolve to the load balancer
# or to one or all of the masters defined in the inventory if no load
# balancer is present.
openshift_master_cluster_method=native
openshift_master_cluster_hostname=$master
openshift_master_cluster_public_hostname=$master

# override the default controller lease ttl
#osm_controller_lease_ttl=30

# host group for masters
[masters]
$(get_masters)

[etcd]
$(get_etcds)

$([[ ! "$lb" == "" ]] && echo '[lb]' && echo '$lb')

[nodes]
$(get_nodes)
"
}

master=$(if [[ "$lb" == "" ]]; then echo $masters | cut -d ' ' -f 1 ; else echo $lb ; fi) 

config=$(generate_config)
echo "$config

sending to $target..."

scmd $ssh_user@$target "echo '${config}' > ansible-hosts ; sudo cp ansible-hosts /etc/ansible/hosts "


echo "***************************************************************
*** Ready to install, only proceed if above content looks correct
"
read -p "press any key to continue"

scmd $ssh_user@$target "sudo ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml"