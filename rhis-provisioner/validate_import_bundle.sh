#!/bin/bash

# validate_import_bundle.sh
# Pre-import sanity check for a RHIS disconnected transfer bundle.
# Confirms the bundle is present and the key elements are there before
# committing to a multi-hour import run.
# Physical security of the drive in transit is the customer's responsibility.
#
# Usage: validate_import_bundle.sh -d <bundle_root>
#   bundle_root: root of the transfer drive (e.g. /mnt/transfer)
#                or the specific bundle directory if multiple bundles exist

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${GREEN}[INFO]${NC}"

DRIVE_MOUNT=""
BUNDLE_ROOT=""

usage() {
    echo "Usage: validate_import_bundle.sh [options]"
    echo ""
    echo "Run on the highside after mounting the transfer drive."
    echo "The drive contains both the Pulp export content and the bundle artifacts."
    echo ""
    echo "Options:"
    echo "    -d | --drive-mount <path>  Mount point of the transfer drive (e.g. /mnt/transfer)"
    echo "    -b | --bundle-dir <path>   Specific bundle directory if multiple exist on the drive"
    echo "    -h | --help                Show this message"
    echo ""
    echo "Examples:"
    echo "    validate_import_bundle.sh -d /mnt/transfer"
    echo "    validate_import_bundle.sh -d /mnt/transfer -b discosatellite1.example.ca_2026-06-07_0338"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--drive-mount) DRIVE_MOUNT="$2"; shift ;;
        -b|--bundle-dir)  BUNDLE_ROOT="$2"; shift ;;
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

# Auto-discover the bundle directory (copy_rhis_to_transfer_media.sh creates rhis_transfer_* directories)
if [[ -z "$BUNDLE_ROOT" ]]; then
    BUNDLE_ROOT=$(sudo find "$DRIVE_MOUNT" -maxdepth 1 -type d -name "rhis_transfer_*" 2>/dev/null | sort | tail -1)
    if [[ -n "$BUNDLE_ROOT" ]]; then
        echo "Auto-discovered bundle: $(basename "$BUNDLE_ROOT")"
    else
        echo "ERROR: No rhis_transfer_* directory found on drive. Has copy_to_transfer_media.yml been run?"
        exit 1
    fi
else
    BUNDLE_ROOT="$DRIVE_MOUNT/$BUNDLE_ROOT"
fi

if [[ ! -d "$BUNDLE_ROOT" ]]; then
    echo "ERROR: Bundle directory not found: $BUNDLE_ROOT"
    exit 1
fi

# Pulp export content is in library_export/ subdirectory within the bundle
LIBRARY_EXPORT_DIR="$BUNDLE_ROOT/library_export"

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
echo " Bundle: $(basename "$BUNDLE_ROOT")"
echo "============================================================"

# ── Manifest ──────────────────────────────────────────────────────────────────
echo
echo "── Manifest ──────────────────────────────────────────────"

MANIFEST="$BUNDLE_ROOT/rhis_disconnected_manifest.yml"
if [[ -f "$MANIFEST" ]]; then
    check PASS "Manifest found: rhis_disconnected_manifest.yml"

    # Parse key fields from manifest (simple grep, no YAML parser needed)
    SOURCE=$(grep "source_satellite:" "$MANIFEST" | awk '{print $2}')
    TIMESTAMP=$(grep "generated:" "$MANIFEST" | awk '{print $2}')
    PULP_PATH=$(grep "pulp_export_path:" "$MANIFEST" | awk '{print $2}')

    [[ -n "$SOURCE" ]]    && check INFO "Source satellite: $SOURCE"
    [[ -n "$TIMESTAMP" ]] && check INFO "Export timestamp: $TIMESTAMP"
    [[ -n "$PULP_PATH" ]] && check INFO "Export path:      $PULP_PATH"
else
    check FAIL "Manifest not found — bundle may be incomplete or corrupted"
fi

# ── Content export chunks ─────────────────────────────────────────────────────
echo
echo "── Content Export ────────────────────────────────────────"

# Check library_export/ first (old pattern), then drive root Default_Organization/ (new pattern)
CHUNK_COUNT=0
METADATA_FILE=""
if [[ -d "$LIBRARY_EXPORT_DIR" ]]; then
    CHUNK_COUNT=$(find "$LIBRARY_EXPORT_DIR" -name "*.tar.*" -type f 2>/dev/null | wc -l)
    METADATA_FILE=$(find "$LIBRARY_EXPORT_DIR" -name "metadata.json" 2>/dev/null | head -1)
    check INFO "Export content found in library_export/ subdirectory"
elif [[ -d "$DRIVE_MOUNT/Default_Organization" ]]; then
    CHUNK_COUNT=$(find "$DRIVE_MOUNT/Default_Organization" -name "*.tar.*" -type f 2>/dev/null | wc -l)
    METADATA_FILE=$(find "$DRIVE_MOUNT/Default_Organization" -name "metadata.json" 2>/dev/null | head -1)
    check INFO "Export content found at drive root (Default_Organization/)"
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

# ── content_imports.yml ────────────────────────────────────────────────────────
echo
echo "── Import Configuration ──────────────────────────────────"

IMPORTS_FILE=$(find "$BUNDLE_ROOT" -name "*content_imports.yml" 2>/dev/null | head -1)
if [[ -n "$IMPORTS_FILE" ]]; then
    check PASS "content_imports.yml found: $(basename "$IMPORTS_FILE")"
    IMPORT_TYPE=$(grep "type:" "$IMPORTS_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    IMPORT_PATH=$(grep "import_path:" "$IMPORTS_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    [[ -n "$IMPORT_TYPE" ]] && check INFO "Export type: $IMPORT_TYPE"
    [[ -n "$IMPORT_PATH" ]] && check INFO "Import path: $IMPORT_PATH"
else
    check FAIL "content_imports.yml not found — highside operator cannot configure the import"
fi

# ── Bundle artifacts ───────────────────────────────────────────────────────────
echo
echo "── Bundle Artifacts ──────────────────────────────────────"

ROLES_COUNT=$(find "$BUNDLE_ROOT/ansible_roles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
if [[ "$ROLES_COUNT" -gt 0 ]]; then
    check PASS "ansible_roles/ present ($ROLES_COUNT roles)"
else
    check WARN "ansible_roles/ is empty or missing — compliance roles will not be available"
fi

if [[ -d "$BUNDLE_ROOT/bootstrap_init" && "$(ls -A "$BUNDLE_ROOT/bootstrap_init" 2>/dev/null)" ]]; then
    check PASS "bootstrap_init/ present — kickstart ISO tooling available"
else
    check WARN "bootstrap_init/ is empty or missing — no kickstart ISO tooling in bundle"
fi

MANIFEST_COUNT=$(find "$BUNDLE_ROOT/manifests" -name "*.zip" 2>/dev/null | wc -l)
if [[ "$MANIFEST_COUNT" -gt 0 ]]; then
    check PASS "manifests/ — $MANIFEST_COUNT subscription manifest(s) found"
    find "$BUNDLE_ROOT/manifests" -name "*.zip" | while read -r f; do
        check INFO "  $(basename "$f")"
    done
else
    check WARN "manifests/ is empty — highside satellite will need subscription manifests"
fi

DISC_COUNT=$(find "$BUNDLE_ROOT/discovery_images" -type f 2>/dev/null | wc -l)
if [[ "$DISC_COUNT" -gt 0 ]]; then
    check PASS "discovery_images/ — $DISC_COUNT file(s) found"
else
    check WARN "discovery_images/ is empty — Foreman discovery will need images from Satellite DVD"
fi

if [[ -d "$BUNDLE_ROOT/container" && "$(ls -A "$BUNDLE_ROOT/container" 2>/dev/null)" ]]; then
    check PASS "container/ — provisioner container image present"
else
    check WARN "container/ is empty — save provisioner container image manually before import"
    check WARN "  podman save <image> -o <bundle>/container/rhis-provisioner.tar"
fi

if [[ -d "$BUNDLE_ROOT/inventory" && "$(ls -A "$BUNDLE_ROOT/inventory" 2>/dev/null)" ]]; then
    check PASS "inventory/ — inventory archive present"
else
    check WARN "inventory/ is empty or missing"
fi

# ── Checksum verification ─────────────────────────────────────────────────────
echo
echo "── Checksum Verification ─────────────────────────────────"
echo "  Verifying bundle file integrity against manifest checksums..."

if [[ -f "$MANIFEST" ]]; then
    TOTAL=0
    PASSED=0
    FAILED_FILES=()

    # Parse manifest checksum entries using Python3 (always available on RHEL)
    while IFS='|' read -r FPATH FHASH; do
        [[ -z "$FPATH" || -z "$FHASH" ]] && continue
        FULL_PATH="$BUNDLE_ROOT/$FPATH"
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
    printf " ${RED}NOT READY FOR IMPORT${NC} — %d failure(s), %d warning(s)\n" "$CHECKS_FAILED" "$CHECKS_WARNED"
    echo " Resolve the failures above before running the import."
    exit 1
elif [[ "$CHECKS_WARNED" -gt 0 ]]; then
    printf " ${YELLOW}READY WITH WARNINGS${NC} — %d warning(s)\n" "$CHECKS_WARNED"
    echo " Review warnings. Import can proceed."
    exit 0
else
    printf " ${GREEN}READY FOR IMPORT${NC}\n"
    echo " Run the import playbook when ready."
    exit 0
fi
