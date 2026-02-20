#!/bin/bash

echo "Using Satellite to build AAP hosts defined in list aap24_hosts defined in group_vars/provisioner/aap24_hosts.yml"

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ sat_capsule_hosts }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 -e "role_name=capsule_build"
                 run_role.yml
