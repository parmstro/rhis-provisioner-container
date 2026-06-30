#!/bin/bash

# validate_import_bundle.sh
# Pre-import sanity check for a RHIS disconnected transfer bundle.
# Confirms the bundle is present and the key elements are there before
# committing to a multi-hour import run.
# Physical security of the drive in transit is the customer's responsibility.
#
# Drive layout (C3): workflow-stage directories at drive root.
#   TRANSFER_DRV/
#     rhis_export_manifest.yml
#     README_FIRST.md
#     import_bundle.sh
#     <Pulp_org_dir>/              ← Pulp export chunks (org-named directory)
#     bootstrap/
#       rhis-builder-bootstrap-init/
#       bootstrap_isos/
#       infra_isos/
#     provisioner/
#       inventory/
#         deployments/<highside>/
#           host_vars/satellite1/
#             content_imports.yml
#           files/
#             *.zip                ← subscription manifests
#       containers/
#     satellite/
#       ansible_roles/
#       discovery_images/
#
# Usage: validate_import_bundle.sh -d <drive_mount>

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${GREEN}[INFO]${NC}"

DRIVE_MOUNT=""

usage() {
    echo "Usage: validate_import_bundle.sh [options]"
    echo ""
    echo "Run on the highside after mounting the transfer drive."
    echo ""
    echo "Options:"
    echo "    -d | --drive-mount <path>  Mount point of the transfer drive (e.g. /mnt/transfer)"
    echo "    -h | --help                Show this message"
    echo ""
    echo "Examples:"
    echo "    validate_import_bundle.sh -d /mnt/transfer"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--drive-mount) DRIVE_MOUNT="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

if [[ -z "$DRIVE_MOUNT" ]]; then
    echo "ERROR: Drive mount point is required. Use -d /mnt/transfer"
    usage
fi

if [[ ! -d "$DRIVE_MOUNT" ]]; then
    echo "ERROR: Drive mount point not found: $DRIVE_MOUNT"
    exit 1
fi

CHECKS_FAILED=0
CHECKS_WARNED=0

check() {
    case "$1" in
        PASS) printf "  ${PASS} %s\n" "$2" ;;
        WARN) printf "  ${WARN} %s\n" "$2"; ((CHECKS_WARNED++)) ;;
        FAIL) printf "  ${FAIL} %s\n" "$2"; ((CHECKS_FAILED++)) ;;
        INFO) printf "  ${INFO} %s\n" "$2" ;;
    esac
}

echo
echo "============================================================"
echo " RHIS Import Bundle Validation"
echo " Drive:  $DRIVE_MOUNT"
echo "============================================================"

# ── Manifest ──────────────────────────────────────────────────────────────────
echo
echo "── Manifest ──────────────────────────────────────────────"

MANIFEST="$DRIVE_MOUNT/rhis_export_manifest.yml"
if [[ -f "$MANIFEST" ]]; then
    check PASS "Manifest found: rhis_export_manifest.yml"

    SOURCE=$(grep "source_satellite:" "$MANIFEST" | awk '{print $2}')
    TIMESTAMP=$(grep "generated:" "$MANIFEST" | awk '{print $2}')
    PULP_PATH=$(grep "pulp_export_path:" "$MANIFEST" | awk '{print $2}')

    [[ -n "$SOURCE" ]]    && check INFO "Source satellite: $SOURCE"
    [[ -n "$TIMESTAMP" ]] && check INFO "Export timestamp: $TIMESTAMP"
    [[ -n "$PULP_PATH" ]] && check INFO "Export path:      $PULP_PATH"
else
    check FAIL "Manifest not found — bundle may be incomplete or corrupted"
fi

# ── Content export chunks (Pulp — org directory at drive root) ─────────────────
echo
echo "── Content Export ────────────────────────────────────────"

CHUNK_COUNT=0
METADATA_FILE=""
PULP_DIR=$(find "$DRIVE_MOUNT" -maxdepth 1 -mindepth 1 -type d \
    ! -name bootstrap ! -name provisioner ! -name satellite 2>/dev/null | head -1)

if [[ -n "$PULP_DIR" ]]; then
    CHUNK_COUNT=$(find "$PULP_DIR" -name "*.tar.*" -type f 2>/dev/null | wc -l)
    METADATA_FILE=$(find "$PULP_DIR" -name "metadata.json" 2>/dev/null | head -1)
    check INFO "Pulp export directory: $(basename "$PULP_DIR")"
fi

if [[ "$CHUNK_COUNT" -gt 0 ]]; then
    check PASS "$CHUNK_COUNT export chunk(s) found"
else
    check FAIL "No export chunks found — has the export run successfully?"
fi

if [[ -n "$METADATA_FILE" && -f "$METADATA_FILE" ]]; then
    check PASS "metadata.json present"
else
    check FAIL "metadata.json missing — import will fail without it"
fi

# ── Import configuration ───────────────────────────────────────────────────────
echo
echo "── Import Configuration ──────────────────────────────────"

IMPORTS_FILE=$(find "$DRIVE_MOUNT/provisioner/inventory" \
    -path "*/host_vars/*/content_imports.yml" 2>/dev/null | head -1)
if [[ -n "$IMPORTS_FILE" ]]; then
    check PASS "content_imports.yml found: ${IMPORTS_FILE#$DRIVE_MOUNT/}"
    IMPORT_TYPE=$(grep "type:" "$IMPORTS_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    IMPORT_PATH=$(grep "import_path:" "$IMPORTS_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    [[ -n "$IMPORT_TYPE" ]] && check INFO "Export type: $IMPORT_TYPE"
    [[ -n "$IMPORT_PATH" ]] && check INFO "Import path: $IMPORT_PATH"
else
    check FAIL "content_imports.yml not found under provisioner/inventory/ — highside operator cannot configure the import"
fi

# ── Subscription manifests (inside provisioner inventory) ──────────────────────
MANIFEST_COUNT=$(find "$DRIVE_MOUNT/provisioner/inventory" \
    -path "*/files/*.zip" 2>/dev/null | wc -l)
if [[ "$MANIFEST_COUNT" -gt 0 ]]; then
    check PASS "Subscription manifest(s): $MANIFEST_COUNT zip file(s) found in provisioner/inventory/"
    find "$DRIVE_MOUNT/provisioner/inventory" -path "*/files/*.zip" | while read -r f; do
        check INFO "  $(basename "$f")"
    done
else
    check WARN "No subscription manifest zips found in provisioner/inventory/ — highside satellite will need one"
fi

# ── Bundle artifacts ───────────────────────────────────────────────────────────
echo
echo "── Bundle Artifacts ──────────────────────────────────────"

# Provisioner inventory
if [[ -d "$DRIVE_MOUNT/provisioner/inventory" && \
      "$(ls -A "$DRIVE_MOUNT/provisioner/inventory" 2>/dev/null)" ]]; then
    check PASS "provisioner/inventory/ present"
else
    check WARN "provisioner/inventory/ is empty or missing"
fi

# Provisioner containers
if [[ -d "$DRIVE_MOUNT/provisioner/containers" && \
      "$(ls -A "$DRIVE_MOUNT/provisioner/containers" 2>/dev/null)" ]]; then
    check PASS "provisioner/containers/ — provisioner container image present"
else
    check WARN "provisioner/containers/ is empty — provisioner container image missing"
fi

# Ansible roles
ROLES_COUNT=$(find "$DRIVE_MOUNT/satellite/ansible_roles" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
if [[ "$ROLES_COUNT" -gt 0 ]]; then
    check PASS "satellite/ansible_roles/ present ($ROLES_COUNT roles)"
else
    check WARN "satellite/ansible_roles/ is empty or missing — compliance roles will not be available"
fi

# Discovery images
DISC_COUNT=$(find "$DRIVE_MOUNT/satellite/discovery_images" \
    -type f 2>/dev/null | wc -l)
if [[ "$DISC_COUNT" -gt 0 ]]; then
    check PASS "satellite/discovery_images/ — $DISC_COUNT file(s) found"
else
    check WARN "satellite/discovery_images/ is empty — Foreman discovery will need images from Satellite DVD"
fi

# Bootstrap tooling
if [[ -d "$DRIVE_MOUNT/bootstrap/rhis-builder-bootstrap-init" && \
      "$(ls -A "$DRIVE_MOUNT/bootstrap/rhis-builder-bootstrap-init" 2>/dev/null)" ]]; then
    check PASS "bootstrap/rhis-builder-bootstrap-init/ present — kickstart ISO tooling available"
else
    check WARN "bootstrap/rhis-builder-bootstrap-init/ is empty or missing"
fi

# Bootstrap ISOs
BISO_COUNT=$(find "$DRIVE_MOUNT/bootstrap/bootstrap_isos" \
    -name "*.iso" -type f 2>/dev/null | wc -l)
if [[ "$BISO_COUNT" -gt 0 ]]; then
    check PASS "bootstrap/bootstrap_isos/ — $BISO_COUNT ISO(s) found"
else
    check WARN "bootstrap/bootstrap_isos/ is empty — OEMDRV kickstart ISOs missing"
fi

# Infra ISOs
IISO_COUNT=$(find "$DRIVE_MOUNT/bootstrap/infra_isos" \
    -name "*.iso" -type f 2>/dev/null | wc -l)
if [[ "$IISO_COUNT" -gt 0 ]]; then
    check PASS "bootstrap/infra_isos/ — $IISO_COUNT ISO(s) found"
else
    check WARN "bootstrap/infra_isos/ is empty — RHEL and Satellite DVD ISOs missing"
fi

# ── Checksum verification ─────────────────────────────────────────────────────
echo
echo "── Checksum Verification ─────────────────────────────────"
echo "  Verifying bundle file integrity against manifest checksums..."

if [[ -f "$MANIFEST" ]]; then
    TOTAL=0
    PASSED=0
    FAILED_FILES=()

    while IFS='|' read -r FPATH FHASH; do
        [[ -z "$FPATH" || -z "$FHASH" ]] && continue
        FULL_PATH="$DRIVE_MOUNT/$FPATH"
        ((TOTAL++))
        if [[ -f "$FULL_PATH" ]]; then
            ACTUAL=$(sha256sum "$FULL_PATH" 2>/dev/null | awk '{print $1}')
            if [[ "$ACTUAL" == "$FHASH" ]]; then
                ((PASSED++))
            else
                FAILED_FILES+=("$FPATH")
            fi
        else
            FAILED_FILES+=("$FPATH (missing)")
        fi
    done < <(python3 -c "
import sys, re
manifest = open('$MANIFEST').read()
entries = re.findall(r'- path: \"([^\"]+)\"\s+sha256: \"([^\"]+)\"', manifest)
for path, sha in entries:
    print(path + '|' + sha)
" 2>/dev/null)

    if [[ "$TOTAL" -eq 0 ]]; then
        check WARN "No checksums found in manifest — skipping verification"
    elif [[ "${#FAILED_FILES[@]}" -eq 0 ]]; then
        check PASS "All $PASSED/$TOTAL files verified"
    else
        for f in "${FAILED_FILES[@]}"; do
            check FAIL "Checksum mismatch: $f"
        done
        check FAIL "$((TOTAL - PASSED))/$TOTAL files failed verification"
    fi
else
    check WARN "Skipping checksum verification — manifest not found"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "============================================================"
if [[ "$CHECKS_FAILED" -gt 0 ]]; then
    printf " ${RED}DRIVE INVALID${NC} — %d failure(s), %d warning(s)\n" "$CHECKS_FAILED" "$CHECKS_WARNED"
    echo " Resolve the failures above before transporting or importing this drive."
    exit 1
elif [[ "$CHECKS_WARNED" -gt 0 ]]; then
    printf " ${YELLOW}DRIVE VALID WITH WARNINGS${NC} — %d warning(s)\n" "$CHECKS_WARNED"
    echo " Review warnings above. Drive is safe to transport and import can proceed."
    exit 0
else
    printf " ${GREEN}DRIVE VALID${NC} — bundle is complete\n"
    echo " Safe to transport. Run ./import_bundle.sh on the highside when ready."
    exit 0
fi
