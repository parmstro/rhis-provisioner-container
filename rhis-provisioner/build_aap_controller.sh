#!/bin/bash

echo "Using rhis-builder-aap to build AAP controller from inventory"
GREEN='\033[0;32m'
NC='\033[0m' # No Color/Normal
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"

usage() {
            echo "Usage: build_aap_controller.sh [options]"
            echo "This helper script launches the play to install the AAP controllers"
            echo "Run configure_aap_controllers.sh after this script succeeds to configure the system"
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
                 --limit=platform_installer \
                 main.yml

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration