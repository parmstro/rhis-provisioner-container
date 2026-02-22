#!/bin/bash

echo "Using Satellite to deploy satellite capsule hosts defined in list capsule_hosts defined in group_vars/provisioner/capsule_hosts.yml"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ capsule_hosts }}" \
                 -u ansiblerunner \
                 --ask-pass \
                 --ask-vault-password \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
