#!/bin/bash

echo "Capsules Step 1: Using rhis-builder-satellite to run Satellite pre-configuration for Capsules from inventory"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"

usage() {
            echo "Usage: build_sat_1_capsules_satellite_pre.sh [options]"
            echo "This helper script launches the phase 1 play to pre-configure the Satellite for the capsules"
            echo "Options:"
            echo "    -u | --sshuser <user> - specify the local or IdM realm user to execute the play"
            echo "    -i | --inventory <fq_inventory_path> - an alternate inventory to use for the play"
            echo "    -h | --help - prints this message"
            echo "The default user is 'ansiblerunner' if not specified."
            echo "The default inventory is '/rhis/vars/external_inventory/inventory' if not specified."
            echo "NOTE: All Capsule helper scripts need to be run using the same inventory"
            echo "You will be prompted for the ssh and vault passwords."
            exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--sshuser)
            sshuser="$2"
            shift # Shift past the value
            ;;
        -i|--inventory)
            inventory="$2"
            shift # Shift past the value
            ;;
        -h|--help)
            echo "Unknown option: $1" >&2; usage ;;

        *)
            echo "Unknown option: $1" >&2; usage ;;
    esac
    shift # Shift past the option
done

ansible-playbook --inventory $inventory \
                 --user $sshuser \
                 --ask-pass \
                 --ask-vault-pass \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --limit=sat_primary \
                 --extra-vars "role_name=capsule_satellite_pre" \
                 run_role.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

