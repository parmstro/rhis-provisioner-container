#!/bin/bash

echo "Using rhis-builder-aap to build AAP 2.5 hub from standalone hub24 inventory"

ansible-playbook --inventory /rhis/vars/external_inventory/inventory_standalone_hub25 \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=platform_installer \
                 main.yml
