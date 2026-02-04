#!/bin/bash

echo "Using rhis-builder-aap to run post configuration using the default inventory"

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=platform_installer \
                 --extra-vars "role_name=platform_post" \
                 run_role.yml