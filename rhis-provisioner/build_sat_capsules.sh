#!/bin/bash

echo "Using rhis-builder-satellite to build sat_primary from default inventory"

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -u ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --limit=sat_capsules \
                 capsules_main.yml