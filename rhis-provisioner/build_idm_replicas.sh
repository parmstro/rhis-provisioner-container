#!/bin/bash

echo "Using rhis-builder-idm to build idm_replicas from default inventory"

ansible-playbook -i /rhis/vars/external_inventory/inventory \
                 -e "vault_dir=/rhis/vars/vault" \
                 -u ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --limit=idm_replicas \
                 replicas_main.yml
