#!/bin/bash

echo "Using Satellite to build Host Group test hosts defined in list hostgroup_test_hosts_rhel8 defined in group_vars/provisioner/ directory"
echo "WARNING: This creates a large number of VMs in the default configuration"
echo "CTRL+C to exit"
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

sleep 15

echo "Beginning builds..."

ansible-playbook --inventory /rhis/vars/external_inventory/inventory \
                 --user $sshuser \
                 --ask-pass \
                 --ask-vault-password \
                 --extra-vars "vault_dir=/rhis/vars/vault" \
                 --extra-vars "platform_hosts={{ hostgroup_test_hosts_rhel9 }}" \
                 --limit=provisioner \
                 rhis_build_from_provisioner.yml

echo "Builds Complete."

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration
