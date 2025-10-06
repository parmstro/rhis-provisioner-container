#!/bin/bash

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user ansiblerunner \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --extra-vars "role_name=platform_node_pre" \
                 --limit=aap_controllers \
                 /rhis/rhis-builder-aap/run_role.yml
