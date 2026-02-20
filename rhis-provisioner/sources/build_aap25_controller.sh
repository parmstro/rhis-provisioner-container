#!/bin/bash

echo "Using rhis-builder-aap to build AAP 2.5 controller from standalone controller 2.5 inventory"

ansible-playbook --inventory /rhis/vars/external_inventory/inventory_standalone_controller25 \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=platform_installer \
                 main.yml
