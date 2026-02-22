#!/bin/bash

echo "Using Satellite to build Host Group test hosts defined in list hostgroup_test_hosts_rhel8 defined in group_vars/provisioner/ directory"
echo "WARNING: This creates a large number of VMs in the default configuration"
echo "CTRL+C to exit"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

sleep 15

echo "Beginning builds..."
ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ hostgroup_test_hosts_rhel10 }}" \
                 -u ansiblerunner \
                 --ask-pass \
                 --ask-vault-password \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

echo "Builds Complete."

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
