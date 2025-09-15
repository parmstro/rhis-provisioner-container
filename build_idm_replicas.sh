#!/bin/bash

ansible-playbook -i /rhis/vars/external_inventory/inventory -e "vault_dir=/rhis/vars/vault" -u ansiblerunner --ask-pass --ask-vault-pass --limit=idm_replicas /rhis/rhis-builder-idm/replicas_main.yml