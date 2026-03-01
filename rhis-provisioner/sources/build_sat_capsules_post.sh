#!/bin/bash

echo "Using rhis-builder-satellite to run Satellite Capsule pre configuration using the default inventory"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=sat_primary \
                 --extra-vars "role_name=capsule_post" \
                 run_role.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

