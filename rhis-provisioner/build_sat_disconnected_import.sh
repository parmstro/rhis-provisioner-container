#!/bin/bash
# build_sat_disconnected_import.sh
# Highside (disconnected) satellite import driver.
# Stages the transfer bundle onto the satellite, then runs the full satellite build.
# Run inside the RHIS provisioner container.
#
# USAGE:
#   ./build_sat_disconnected_import.sh [options]
#
# OPTIONS:
#   -d | --deployment <name>        Deployment name (e.g. highside.example.ca) [required]
#   -m | --delivery-method <method> Bundle delivery method: usb | virtual_disk | rsync [required]
#   -b | --bundle-dir <name>        Bundle directory name (e.g. rhis_transfer_20260601_120000)
#                                   Optional for virtual_disk/rsync (auto-discovered from source-path).
#                                   Provided to bundle_delivery for explicit USB selection.
#   -s | --source-path <path>       Source path on provisioner for virtual_disk/rsync
#                                   (default: /mnt/rhis_transfer)
#   -u | --sshuser <user>           SSH user for satellite connection (default: ansiblerunner)
#   -i | --inventory <path>         Inventory path (default: /rhis/vars/external_inventory/inventory)
#   -h | --help                     Show this help

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

deployment=""
delivery_method=""
bundle_dir=""
source_path="/mnt/rhis_transfer"
sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"

usage() {
    sed -n '/^# USAGE:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--deployment)        deployment="$2";        shift ;;
        -m|--delivery-method)   delivery_method="$2";   shift ;;
        -b|--bundle-dir)        bundle_dir="$2";        shift ;;
        -s|--source-path)       source_path="$2";       shift ;;
        -u|--sshuser)           sshuser="$2";           shift ;;
        -i|--inventory)         inventory="$2";         shift ;;
        -h|--help)              usage ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1 ;;
    esac
    shift
done

# ── Validate required args ──────────────────────────────────────────────────
if [[ -z "$deployment" ]]; then
    echo -e "${RED}ERROR: --deployment is required${NC}" >&2
    exit 1
fi

case "$delivery_method" in
    usb|virtual_disk|rsync) ;;
    "")
        echo -e "${RED}ERROR: --delivery-method is required (usb | virtual_disk | rsync)${NC}" >&2
        exit 1 ;;
    *)
        echo -e "${RED}ERROR: Unknown delivery method '${delivery_method}' — expected usb, virtual_disk, or rsync${NC}" >&2
        exit 1 ;;
esac

echo -e "${GREEN}Starting RHIS disconnected satellite import${NC}"
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

# ── Derive satellite hostname and host_vars directory from inventory ─────────
SAT_HOST=$(ansible-inventory --inventory "$inventory" --list 2>/dev/null | python3 -c "
import sys, json
inv = json.load(sys.stdin)
hosts = inv.get('sat_primary', {}).get('hosts', [])
print(hosts[0] if hosts else '')
" 2>/dev/null)

if [[ -z "$SAT_HOST" ]]; then
    echo -e "${RED}ERROR: Could not determine satellite hostname from sat_primary group in inventory${NC}" >&2
    exit 1
fi

HOST_VARS_DIR="/rhis/vars/host_vars/${SAT_HOST}"
if [[ ! -d "$HOST_VARS_DIR" ]]; then
    echo -e "${RED}ERROR: host_vars directory not found: ${HOST_VARS_DIR}${NC}" >&2
    exit 1
fi

echo -e "  Satellite:         ${YELLOW}${SAT_HOST}${NC}"
echo -e "  Delivery method:   ${YELLOW}${delivery_method}${NC}"
echo -e "  host_vars dir:     ${YELLOW}${HOST_VARS_DIR}${NC}"

# ── For push methods: auto-discover bundle_dir from source_path ─────────────
if [[ "$delivery_method" != "usb" && -z "$bundle_dir" ]]; then
    bundle_dir=$(ls -td "${source_path}"/rhis_transfer_*/ 2>/dev/null | head -1 | xargs -r basename 2>/dev/null)
    if [[ -z "$bundle_dir" ]]; then
        echo -e "${RED}ERROR: No rhis_transfer_* directory found under ${source_path}${NC}" >&2
        echo -e "${RED}       Provide --bundle-dir explicitly or check --source-path.${NC}" >&2
        exit 1
    fi
    echo -e "  Bundle dir:        ${YELLOW}${bundle_dir}${NC} (auto-discovered)"
elif [[ -n "$bundle_dir" ]]; then
    echo -e "  Bundle dir:        ${YELLOW}${bundle_dir}${NC}"
fi

# ── Step 1: bundle_delivery.yml ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}── Step 1/3: Delivering bundle to satellite ────────────────────────────────${NC}"

DELIVERY_EXTRA_VARS="bundle_delivery_method=${delivery_method}"
[[ -n "$bundle_dir" ]]                  && DELIVERY_EXTRA_VARS+=" bundle_delivery_bundle_dir=${bundle_dir}"
[[ "$delivery_method" != "usb" ]]       && DELIVERY_EXTRA_VARS+=" bundle_delivery_source_path=${source_path}"

ansible-playbook \
    --inventory "$inventory" \
    --user "$sshuser" \
    --private-key /root/.ssh/id_ed25519 \
    --vault-password-file /root/.ssh/vault.txt \
    --extra-vars "vault_dir=/rhis/vars/vault vars_dir=/rhis/vars/host_vars" \
    --extra-vars "$DELIVERY_EXTRA_VARS" \
    --limit=sat_primary \
    bundle_delivery.yml

EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "${RED}bundle_delivery.yml failed with exit code ${EXIT_CODE}.${NC}" >&2
    exit $EXIT_CODE
fi

# ── Step 2: Remap content_imports.yml and write disconnected vars ────────────
echo ""
echo -e "${GREEN}── Step 2/3: Preparing host_vars for disconnected build ─────────────────────${NC}"

FETCHED_IMPORTS="/tmp/rhis_content_imports_fetch.yml"
if [[ ! -f "$FETCHED_IMPORTS" ]]; then
    echo -e "${RED}ERROR: bundle_delivery.yml did not produce ${FETCHED_IMPORTS}${NC}" >&2
    echo -e "${RED}       Check that _content_imports.yml exists in the transfer bundle.${NC}" >&2
    exit 1
fi

# Remap lowside export prefix to highside import prefix
sed 's|/var/lib/pulp/exports/|/var/lib/pulp/imports/|g' \
    "$FETCHED_IMPORTS" \
    > "${HOST_VARS_DIR}/content_imports.yml"
echo -e "  content_imports.yml written to: ${YELLOW}${HOST_VARS_DIR}/content_imports.yml${NC}"

# Read bundle path written by bundle_delivery validate tasks
BUNDLE_PATH=$(cat /tmp/rhis_bundle_path.txt 2>/dev/null)
if [[ -z "$BUNDLE_PATH" ]]; then
    echo -e "${RED}ERROR: Could not read bundle path from /tmp/rhis_bundle_path.txt${NC}" >&2
    exit 1
fi
echo -e "  Bundle path on satellite:       ${YELLOW}${BUNDLE_PATH}${NC}"

# Write disconnected extra-vars — passed to main.yml to set all disconnected code paths
EXTRA_VARS_FILE="/tmp/rhis_disconnected_extra_vars.yml"
cat > "$EXTRA_VARS_FILE" <<EOF
satellite_disconnected: true
satellite_disconnected_iso_prestaged: true
satellite_disconnected_root: "${BUNDLE_PATH}"
satellite_import_content: true
satellite_roles_source_path: "${BUNDLE_PATH}/ansible_roles"
satellite_disconnected_discovery_images_src: "${BUNDLE_PATH}/discovery_images"
satellite_bundle_stage_path: "/var/satellite_stage/pulp_stage"
EOF
echo -e "  Disconnected extra-vars written: ${YELLOW}${EXTRA_VARS_FILE}${NC}"

# ── Step 3: main.yml ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}── Step 3/3: Running satellite build (main.yml) ─────────────────────────────${NC}"
echo -e "${YELLOW}  This step installs and configures the satellite — expect 60+ minutes.${NC}"

ansible-playbook \
    --inventory "$inventory" \
    --user "$sshuser" \
    --private-key /root/.ssh/id_ed25519 \
    --vault-password-file /root/.ssh/vault.txt \
    --extra-vars "vault_dir=/rhis/vars/vault vars_dir=/rhis/vars/host_vars" \
    --extra-vars "@${EXTRA_VARS_FILE}" \
    --limit=sat_primary \
    main.yml

EXIT_CODE=$?

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "${RED}main.yml failed with exit code ${EXIT_CODE}.${NC}" >&2
    exit $EXIT_CODE
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  RHIS Disconnected Satellite Build Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Satellite:   ${YELLOW}${SAT_HOST}${NC}"
echo -e "  Deployment:  ${YELLOW}${deployment}${NC}"
echo -e "  Bundle:      ${YELLOW}${BUNDLE_PATH}${NC}"
TZ=UTC0 printf "  Elapsed:     ${YELLOW}%(%T)T${NC}\n" $duration
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
