#!/bin/bash

echo "Register IdM server to Satellite"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"

usage() {
            echo "Usage: register_idm_to_satellite.sh [options]"
            echo "This helper script registers the IdM server to Satellite."
            echo "Run this after both IdM and Satellite are built."
            echo "Options:"
            echo "    -u | --sshuser <user> - specify the local or IdM realm user to execute the play"
            echo "    -i | --inventory <fq_inventory_path> - an alternate inventory to use for the play"
            echo "    -h | --help - prints this message"
            echo "The default user is 'ansiblerunner' if not specified."
            echo "The default inventory is '/rhis/vars/external_inventory/inventory' if not specified."
            echo "You will be prompted for the ssh and vault passwords."
            exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--sshuser)
            sshuser="$2"
            shift
            ;;
        -i|--inventory)
            inventory="$2"
            shift
            ;;
        -h|--help)
            usage ;;
        *)
            echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

ansible-playbook --inventory $inventory \
                 --user $sshuser \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 register_idm_to_satellite.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
