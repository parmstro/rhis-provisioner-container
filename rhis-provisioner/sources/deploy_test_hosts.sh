#!/bin/bash

echo "Using Satellite to build Host Group test hosts defined in list hostgroup_test_hosts_rhel8 defined in group_vars/provisioner/ directory"
echo "WARNING: This creates a large number of VMs in the default configuration"
echo "CTRL+C to exit"

sleep 15

echo "Beginning builds..."
ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ hostgroup_test_hosts_rhel8 }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

echo "Using Satellite to build Host Group test hosts defined in list hostgroup_test_hosts_rhel9 defined in group_vars/provisioner/ directory"
echo "WARNING: This creates a large number of VMs in the default configuration"
echo "CTRL+C to exit"

sleep 15

echo "Beginning builds..."
ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ hostgroup_test_hosts_rhel9 }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

echo "Using Satellite to build Host Group test hosts defined in list hostgroup_test_hosts_rhel10 defined in group_vars/provisioner/ directory"
echo "WARNING: This creates a large number of VMs in the default configuration"
echo "CTRL+C to exit"

sleep 15

echo "Beginning builds..."
ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ hostgroup_test_hosts_rhel10 }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

echo "Builds Complete."
