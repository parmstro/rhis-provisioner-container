#!/bin/bash

echo "Using rhis-builder-aap to build AAP 2.4 hub from standalone hub24 inventory"

cd /rhis/rhis-builder-aap/

ansible-playbook --inventory /rhis/vars/external_inventory/inventory_standalone_hub24 \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=platform_installer \
                 main.yml
