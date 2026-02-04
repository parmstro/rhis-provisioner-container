#!/bin/bash

echo "Using rhis-builder-aap to build AAP 2.4 controller from default inventory"

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=platform_installer \
                 main.yml
