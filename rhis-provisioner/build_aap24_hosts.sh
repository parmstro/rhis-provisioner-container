#!/bin/bash

echo "Using Satellite to build AAP hosts defined in list aap24_hosts defined in group_vars/provisioner/aap24_hosts.yml"

cd /rhis/rhis-builder-pipelines/

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ aap24_hosts }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml
