#!/bin/bash

echo "Using Satellite to deploy satellite capsule hosts defined in list capsule_hosts defined in group_vars/provisioner/capsule_hosts.yml"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

sshuser="ansiblerunner"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--sshuser)
            sshuser="$2"
            shift # Shift past the value
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift # Shift past the option
done

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user $sshuser \
                 --ask-pass \
                 --ask-vault-password \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --extra-vars "platform_hosts={{ capsule_hosts }}" \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
