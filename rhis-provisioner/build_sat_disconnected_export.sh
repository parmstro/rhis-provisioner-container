#!/bin/bash
# build_sat_disconnected_export.sh
# Wrapper for export_disconnected.yml.
# Runs the Pulp library export on the lowside satellite and pulls satellite-side
# artifacts (Ansible roles, Foreman discovery images) into the provisioner
# staging directory mounted at /rhis/vars/export_staging.
#
# Normally invoked by export_deployment.sh (Stage 1).  Run this script directly
# when you need to re-run or resume the export step inside the container without
# going through the full export_deployment.sh pipeline.
#
# USAGE:
#   ./build_sat_disconnected_export.sh [options]
#
# OPTIONS:
#   -u | --sshuser <user>        SSH user for satellite connection (default: ansiblerunner)
#   -i | --inventory <path>      Inventory path (default: /rhis/vars/external_inventory/inventory)
#   -d | --downstream <fqdn>     Highside deployment domain FQDN (required, e.g. highside.example.ca)
#        --resume                Skip the Pulp library export; run from Step 2 onward.
#                                Use when the Pulp export completed in a prior run but
#                                artifact collection (roles, images) failed.
#   -h | --help                  Show this help

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"
downstream=""
skip_tags=""

usage() {
    sed -n '/^# USAGE:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--sshuser)    sshuser="$2";     shift ;;
        -i|--inventory)  inventory="$2";   shift ;;
        -d|--downstream) downstream="$2";  shift ;;
        --resume)        skip_tags="--skip-tags tags_content_exports" ;;
        -h|--help)       usage ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1 ;;
    esac
    shift
done

if [[ -z "$downstream" ]]; then
    echo -e "${RED}ERROR: --downstream <fqdn> is required${NC}" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

echo "Using rhis-builder-satellite to run disconnected export against sat_primary"
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

cd /rhis/rhis-builder-satellite || { echo -e "${RED}ERROR: /rhis/rhis-builder-satellite not mounted${NC}" >&2; exit 1; }

ansible-playbook \
    --inventory "$inventory" \
    --user "$sshuser" \
    --private-key /root/.ssh/id_ed25519 \
    --vault-password-file /root/.ssh/vault.txt \
    --extra-vars "vault_dir=/rhis/vars/vault vars_dir=/rhis/vars/host_vars" \
    --extra-vars "active_downstream_deployment=${downstream}" \
    --limit=sat_primary \
    $skip_tags \
    export_disconnected.yml

EXIT_CODE=$?

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

exit $EXIT_CODE
