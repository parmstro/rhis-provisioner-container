#!/bin/bash
# copy_rhis_to_transfer_media.sh
# Stage 2 of the disconnected satellite export process.
# Copies the prepared bundle AND the Pulp library export to mounted transfer media.
# Uses rsync for reliability and resumability.
#
# USAGE:
#   ./copy_rhis_to_transfer_media.sh [options]
#
# OPTIONS:
#   -b | --bundle-dir <path>       Bundle staging directory (from Stage 1 output)
#   -p | --pulp-export-dir <path>  Pulp export directory (from Stage 1 output)
#   -m | --media-path <path>       Transfer media mount point
#   -h | --help                    Show this help

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

bundle_dir=""
pulp_export_dir=""
media_path=""

usage() {
    sed -n '/^# USAGE:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -b|--bundle-dir)        bundle_dir="$2"; shift ;;
        -p|--pulp-export-dir)   pulp_export_dir="$2"; shift ;;
        -m|--media-path)        media_path="$2"; shift ;;
        -h|--help)              usage ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1 ;;
    esac
    shift
done

MISSING=()
[[ -z "$bundle_dir" ]]      && MISSING+=("--bundle-dir")
[[ -z "$pulp_export_dir" ]] && MISSING+=("--pulp-export-dir")
[[ -z "$media_path" ]]      && MISSING+=("--media-path")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}ERROR: Missing required arguments: ${MISSING[*]}${NC}" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

# ── Validate inputs ─────────────────────────────────────────────────────────

if [[ ! -d "$bundle_dir" ]]; then
    echo -e "${RED}ERROR: Bundle directory not found: ${bundle_dir}${NC}" >&2
    exit 1
fi

if ! sudo test -d "$pulp_export_dir" 2>/dev/null; then
    echo -e "${RED}ERROR: Pulp export directory not found: ${pulp_export_dir}${NC}" >&2
    exit 1
fi

if ! mountpoint -q "$media_path" 2>/dev/null; then
    echo -e "${RED}ERROR: No media mounted at ${media_path}${NC}" >&2
    echo "Mount transfer media with sufficient capacity and re-run." >&2
    exit 1
fi

# ── Check available space ───────────────────────────────────────────────────

BUNDLE_BYTES=$(du -sb "$bundle_dir" 2>/dev/null | awk '{print $1}')
PULP_BYTES=$(du -sb "$pulp_export_dir" 2>/dev/null | awk '{print $1}')
TOTAL_BYTES=$(( BUNDLE_BYTES + PULP_BYTES ))
AVAIL_BYTES=$(df -B1 --output=avail "$media_path" 2>/dev/null | tail -1)

if [[ $AVAIL_BYTES -lt $TOTAL_BYTES ]]; then
    NEED_GB=$(( (TOTAL_BYTES + 1073741823) / 1073741824 ))
    AVAIL_GB=$(( AVAIL_BYTES / 1073741824 ))
    echo -e "${RED}ERROR: Insufficient space on ${media_path}${NC}" >&2
    echo -e "  Required: ${NEED_GB} GB" >&2
    echo -e "  Available: ${AVAIL_GB} GB" >&2
    exit 1
fi

# ── Create destination directory on media ───────────────────────────────────

TRANSFER_NAME="rhis_transfer_$(basename "$bundle_dir")"
DEST="${media_path}/${TRANSFER_NAME}"
sudo mkdir -p "${DEST}/library_export" && sudo chown -R ansiblerunner:ansiblerunner "${DEST}" || {
    echo -e "${RED}ERROR: Cannot create destination directory on transfer media.${NC}" >&2
    exit 1
}

echo -e "${GREEN}Starting RHIS export copy to transfer media (Stage 2 — Copy)${NC}"
printf "${GREEN}Start Time: %(%T)T${NC}\n" -1
SECONDS=0

# ── Copy bundle artifacts ───────────────────────────────────────────────────

echo ""
echo "Copying bundle artifacts..."
rsync -av --progress \
    --exclude="library_export" \
    "${bundle_dir}/" "${DEST}/" || {
    echo -e "${RED}ERROR: rsync of bundle directory failed.${NC}" >&2
    exit 1
}

# ── Copy content_imports.yml from Pulp export area ─────────────────────────
# The export playbook writes content_imports.yml to rhis_import_export_data/
# on the satellite. Include the latest one in the bundle so the highside
# operator has it available without needing to locate it separately.

IMPORTS_DIR="$(dirname "$pulp_export_dir")/rhis_import_export_data"
LATEST_IMPORTS=$(find "$IMPORTS_DIR" -name "*content_imports.yml" 2>/dev/null | sort | tail -1)
if [[ -n "$LATEST_IMPORTS" ]]; then
    echo ""
    echo "Copying content_imports.yml..."
    sudo cp "$LATEST_IMPORTS" "${DEST}/content_imports.yml" || {
        echo -e "${YELLOW}WARNING: Could not copy content_imports.yml${NC}" >&2
    }
else
    echo -e "${YELLOW}WARNING: content_imports.yml not found in ${IMPORTS_DIR}${NC}" >&2
fi

# ── Copy Pulp library export ────────────────────────────────────────────────

echo ""
echo "Copying Pulp library export (this may take a while)..."
sudo rsync -av --progress \
    "${pulp_export_dir}/" "${DEST}/library_export/" || {
    echo -e "${RED}ERROR: rsync of Pulp export directory failed.${NC}" >&2
    exit 1
}

# ── Verify manifest checksums ───────────────────────────────────────────────

MANIFEST="${DEST}/rhis_disconnected_manifest.yml"
if [[ -f "$MANIFEST" ]]; then
    echo ""
    echo "Verifying bundle integrity against manifest..."
    ERRORS=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+path:[[:space:]]*(.+)$ ]]; then
            FILE="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]+sha256:[[:space:]]*([a-f0-9]+)$ ]]; then
            EXPECTED="${BASH_REMATCH[1]}"
            FULL_PATH="${DEST}/${FILE}"
            if [[ -f "$FULL_PATH" ]]; then
                ACTUAL=$(sha256sum "$FULL_PATH" 2>/dev/null | awk '{print $1}')
                if [[ "$ACTUAL" != "$EXPECTED" ]]; then
                    echo -e "  ${RED}CHECKSUM MISMATCH: ${FILE}${NC}"
                    ERRORS=$(( ERRORS + 1 ))
                fi
            fi
        fi
    done < "$MANIFEST"
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "  ${GREEN}All checksums verified.${NC}"
    else
        echo -e "  ${RED}${ERRORS} checksum failure(s) detected. Transfer may be corrupt.${NC}"
    fi
else
    echo -e "${YELLOW}WARNING: rhis_disconnected_manifest.yml not found — skipping verification.${NC}"
fi

duration=$SECONDS
printf "\n${GREEN}End Time: %(%T)T${NC}\n" -1
TZ=UTC0 printf "${GREEN}Elapsed Time: %(%T)T${NC}\n" $duration

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  RHIS Export Copy Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Transfer bundle at: ${YELLOW}${DEST}${NC}"
echo ""
echo -e "  Transport this media to the highside satellite and run:"
echo -e "  ${YELLOW}./build_sat_disconnected_import.sh \\"
echo -e "      --bundle-path <media_mount>/${TRANSFER_NAME}${NC}"
echo ""
echo -e "  ${YELLOW}REMINDER: Vault password must travel via a separate trusted channel.${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
