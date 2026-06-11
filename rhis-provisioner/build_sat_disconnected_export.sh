#!/bin/bash
# build_sat_disconnected_export.sh
# Stage 1 of the disconnected satellite export process.
# Assembles all bundle artifacts EXCEPT the Pulp library export chunks,
# which remain in /var/lib/pulp/exports/ where Satellite placed them.
# Computes total transfer size and advises the operator on media requirements.
#
# USAGE:
#   ./build_sat_disconnected_export.sh [options]
#
# OPTIONS:
#   -u | --sshuser <user>       SSH user for satellite connection (default: ansiblerunner)
#   -i | --inventory <path>     Inventory path (default: /rhis/vars/external_inventory/inventory)
#   -e | --export-root <path>   Local path on satellite for bundle staging
#                               (default: /home/ansiblerunner/rhis_export)
#       --media-path <path>     Transfer media mount point — passed to copy script
#                               (default: /mnt/rhis_transfer)
#       --image-tar <path>      Path to the provisioner container image tar (mounted into container
#                               by export_deployment.sh). Passed as provisioner_image_tar extra-var
#                               so the playbook can include the image in the bundle (Step 7).
#   -x | --extra-vars <file>    Extra vars file to override content_exports (e.g. for testing)
#                               Passed as @<file> to ansible-playbook
#   -h | --help                 Show this help

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

sshuser="ansiblerunner"
inventory="/rhis/vars/external_inventory/inventory"
export_root="/home/ansiblerunner/rhis_export"
media_path="/mnt/rhis_transfer"
image_tar=""
extra_vars_file=""

usage() {
    sed -n '/^# USAGE:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--sshuser)       sshuser="$2"; shift ;;
        -i|--inventory)     inventory="$2"; shift ;;
        -e|--export-root)   export_root="$2"; shift ;;
        --media-path)       media_path="$2"; shift ;;
        --image-tar)        image_tar="$2"; shift ;;
        -x|--extra-vars)    extra_vars_file="$2"; shift ;;
        -h|--help)          usage ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1 ;;
    esac
    shift
done

echo -e "${GREEN}Starting RHIS disconnected satellite export (Stage 1 — Prepare)${NC}"
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

EXTRA_VARS_ARGS=""
[[ -n "$extra_vars_file" ]] && EXTRA_VARS_ARGS="--extra-vars @${extra_vars_file}"
IMAGE_TAR_ARGS=""
[[ -n "$image_tar" ]] && IMAGE_TAR_ARGS="--extra-vars provisioner_image_tar=${image_tar}"

ansible-playbook \
    --inventory "$inventory" \
    --user "$sshuser" \
    --private-key /root/.ssh/id_ed25519 \
    --vault-password-file /root/.ssh/vault.txt \
    --extra-vars "vault_dir=/rhis/vars/vault vars_dir=/rhis/vars/host_vars" \
    --extra-vars "rhis_export_root=${export_root}" \
    $IMAGE_TAR_ARGS \
    $EXTRA_VARS_ARGS \
    --limit=sat_primary \
    export_disconnected.yml

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "${RED}Export playbook failed with exit code ${EXIT_CODE}.${NC}" >&2
    exit $EXIT_CODE
fi

# ── Compute transfer size ───────────────────────────────────────────────────
# Bundle directory and Pulp export live on the satellite — query via SSH
SAT_HOST=$(ansible-inventory --inventory "$inventory" --list 2>/dev/null | python3 -c "
import sys, json
inv = json.load(sys.stdin)
hosts = inv.get('sat_primary', {}).get('hosts', [])
print(hosts[0] if hosts else '')
" 2>/dev/null)

if [[ -z "$SAT_HOST" ]]; then
    echo -e "${YELLOW}WARNING: Could not determine satellite hostname — skipping size calculation${NC}" >&2
    SAT_HOST="satellite"
fi

BUNDLE_DIR=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "${sshuser}@${SAT_HOST}" \
    "ls -td ${export_root}/*/ 2>/dev/null | head -1" 2>/dev/null | tr -d '\n')

if [[ -z "$BUNDLE_DIR" ]]; then
    echo -e "${RED}ERROR: Could not locate bundle directory under ${export_root} on ${SAT_HOST}${NC}" >&2
    exit 1
fi

# Find the Pulp export directory (destination_server is the first component under /var/lib/pulp/exports/)
DS_NAME=$(basename "$BUNDLE_DIR" | sed 's/_[0-9]*_[0-9]*$//')
PULP_EXPORT_DIR="/var/lib/pulp/exports/${DS_NAME}"

echo ""
echo "Computing transfer size..."
BUNDLE_BYTES=$(ssh -o BatchMode=yes "${sshuser}@${SAT_HOST}" \
    "du -sb '${BUNDLE_DIR}' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo 0)
PULP_BYTES=$(ssh -o BatchMode=yes "${sshuser}@${SAT_HOST}" \
    "sudo du -sb '${PULP_EXPORT_DIR}' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo 0)
TOTAL_BYTES=$(( BUNDLE_BYTES + PULP_BYTES ))

# Convert to GB (ceiling)
TOTAL_GB=$(( (TOTAL_BYTES + 1073741823) / 1073741824 ))

# Buffer: min(10%, 10GB), minimum 1GB
TEN_PERCENT=$(( TOTAL_GB / 10 ))
BUFFER=$(( TEN_PERCENT < 10 ? TEN_PERCENT : 10 ))
[[ $BUFFER -lt 1 ]] && BUFFER=1

# Round up to nearest 10GB
REQUIRED_GB=$(( ((TOTAL_GB + BUFFER + 9) / 10) * 10 ))

if [[ $REQUIRED_GB -ge 1000 ]]; then
    REQUIRED_DISPLAY="$(awk "BEGIN {printf \"%.1f TB\", ${REQUIRED_GB}/1024}")"
else
    REQUIRED_DISPLAY="${REQUIRED_GB} GB"
fi

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  RHIS Export Bundle Prepared${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Bundle directory:    ${YELLOW}${BUNDLE_DIR}${NC}"
echo -e "  Pulp export dir:     ${YELLOW}${PULP_EXPORT_DIR}${NC}"
echo -e "  Transfer size:       ${YELLOW}${REQUIRED_DISPLAY}${NC}  (${TOTAL_GB} GB data + ${BUFFER} GB buffer)"
echo ""
echo -e "  ${YELLOW}Review the checklist before transfer:${NC}"
echo -e "  $(ssh -o BatchMode=yes "${sshuser}@${SAT_HOST}" "ls '${BUNDLE_DIR}'/RHIS_Export_Checklist_*.md 2>/dev/null | head -1" 2>/dev/null)"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  HIGHSIDE DISK SPACE REQUIREMENT${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  The highside (disconnected) satellite requires ${RED}3x the library size${NC}"
echo -e "  simultaneously on disk during import:"
echo ""
echo -e "    1x  Import tar.gz chunks (transferred from media)"
echo -e "    1x  Temporary extraction directory (Satellite extracts before importing)"
echo -e "    1x  Imported Pulp library (/var/lib/pulp/)"
echo ""
echo -e "  Library size on this satellite: ${YELLOW}$(ssh -o BatchMode=yes "${sshuser}@${SAT_HOST}" "sudo du -sh /var/lib/pulp 2>/dev/null | awk '{print \$1}'" 2>/dev/null)${NC}"
echo -e "  ${YELLOW}Ensure the highside satellite has at least 3x that capacity${NC}"
echo -e "  ${YELLOW}available under /var/lib/pulp before starting the import.${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "  NEXT STEP:"
echo -e "  Mount transfer media with at least ${REQUIRED_DISPLAY} capacity at:"
echo -e "  ${YELLOW}${media_path}${NC}"
echo ""
echo -e "  Then run:"
echo -e "  ${YELLOW}./copy_rhis_to_transfer_media.sh \\"
echo -e "      --bundle-dir ${BUNDLE_DIR} \\"
echo -e "      --pulp-export-dir ${PULP_EXPORT_DIR} \\"
echo -e "      --media-path ${media_path}${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}IMPORTANT: Vault password must travel via a separate trusted channel.${NC}"
echo -e "  ${YELLOW}ISOs are NOT included — see checklist for required installation media.${NC}"
echo ""
