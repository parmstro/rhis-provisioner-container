#!/bin/bash

echo "Using Satellite to build AAP hosts defined in list aap24_hosts defined in group_vars/provisioner/aap24_hosts.yml"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ sat_capsule_hosts }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 -e "role_name=capsule_build"
                 run_role.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
