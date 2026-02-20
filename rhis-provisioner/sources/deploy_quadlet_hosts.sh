#!/bin/bash

echo "Beginning builds for quadlet hosts"
ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -e "platform_hosts={{ quadlet_hosts }}" \
                 -u ansiblerunner \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml