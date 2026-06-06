#!/bin/bash

# configure_export.sh
# Prepare and validate a transfer drive for Satellite content export.
# This script handles ONLY the drive side — export type, organization,
# chunk size, and content validation are defined in content_exports.yml
# and handled by the export Ansible playbook's preflight checks.
#
# Run this script ON the Satellite server before launching the export playbook.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${GREEN}[INFO]${NC}"

EXPORT_MOUNT="/var/lib/pulp/exports"
PULP_CONTENT="/var/lib/pulp"
DEVICE=""
DRY_RUN=false

usage() {
    echo "Usage: configure_export.sh [options]"
    echo ""
    echo "Prepare a transfer drive for Satellite content export."
    echo "Export type and content configuration are read from content_exports.yml"
    echo "by the Ansible export playbook — this script handles drive preparation only."
    echo ""
    echo "Options:"
    echo "    -d | --device <device>   Block device for the transfer drive (e.g. /dev/sdb)"
    echo "                             If omitted, the drive is auto-discovered by label TRANSFER_DRV"
    echo "    -n | --dry-run           Validate and report only — do not mount"
    echo "    -h | --help              Show this message"
    echo ""
    echo "Examples:"
    echo "    configure_export.sh                    # auto-discover TRANSFER_DRV"
    echo "    configure_export.sh -d /dev/sdb        # explicit device"
    echo "    configure_export.sh --dry-run          # validate only, no mount"
    echo ""
    echo "Drive preparation (one-time, on any Linux system):"
    echo "    mkfs.ext4 -L TRANSFER_DRV /dev/<device>"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--device)  DEVICE="$2"; shift ;;
        -n|--dry-run) DRY_RUN=true ;;
        -h|--help)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

# Auto-discover by label if no device specified
if [[ -z "$DEVICE" ]]; then
    DISCOVERED=$(sudo blkid -L TRANSFER_DRV 2>/dev/null)
    if [[ -n "$DISCOVERED" ]]; then
        DEVICE="$DISCOVERED"
        echo "Auto-discovered TRANSFER_DRV at $DEVICE"
    else
        echo "ERROR: No device specified and no drive labelled TRANSFER_DRV found."
        echo "       Attach the transfer drive and retry, or specify with: -d /dev/sdX"
        echo "       To label an existing drive: e2label /dev/sdX TRANSFER_DRV"
        exit 1
    fi
fi

echo
echo "============================================================"
echo " RHIS Export Drive Configuration"
echo "============================================================"
echo " Device:       $DEVICE"
echo " Mount target: $EXPORT_MOUNT"
[[ "$DRY_RUN" == true ]] && echo " Mode:         DRY RUN (validate only, no mount)"
echo "============================================================"
echo

CHECKS_FAILED=0
CHECKS_WARNED=0

check() {
    local status="$1"
    local message="$2"
    case "$status" in
        PASS) printf "  ${PASS} %s\n" "$message" ;;
        WARN) printf "  ${WARN} %s\n" "$message"; ((CHECKS_WARNED++)) ;;
        FAIL) printf "  ${FAIL} %s\n" "$message"; ((CHECKS_FAILED++)) ;;
        INFO) printf "  ${INFO} %s\n" "$message" ;;
    esac
}

# ─── Section 1: Device validation ─────────────────────────────────────────
echo "── Device ────────────────────────────────────────────────"

[[ -b "$DEVICE" ]] && check PASS "Device $DEVICE exists" || { check FAIL "Device $DEVICE not found"; exit 1; }

FS_TYPE=$(sudo blkid -o value -s TYPE "$DEVICE" 2>/dev/null)
[[ "$FS_TYPE" == "ext4" ]] \
    && check PASS "Filesystem: ext4" \
    || check FAIL "Filesystem is '${FS_TYPE:-unknown}' — expected ext4. Format with: mkfs.ext4 -L TRANSFER_DRV $DEVICE"

DRIVE_LABEL=$(sudo blkid -o value -s LABEL "$DEVICE" 2>/dev/null)
[[ "$DRIVE_LABEL" == "TRANSFER_DRV" ]] \
    && check PASS "Drive label: TRANSFER_DRV" \
    || check WARN "Label is '${DRIVE_LABEL:-unset}' — expected TRANSFER_DRV (set with: e2label $DEVICE TRANSFER_DRV)"

DRIVE_UUID=$(sudo blkid -o value -s UUID "$DEVICE" 2>/dev/null)
[[ -n "$DRIVE_UUID" ]] \
    && check PASS "UUID: $DRIVE_UUID" \
    || check FAIL "Could not determine drive UUID"

# ─── Section 2: Size validation ────────────────────────────────────────────
echo
echo "── Size ──────────────────────────────────────────────────"

echo "  Calculating Pulp content size..."
PULP_USED_KB=$(sudo du -sk "$PULP_CONTENT" 2>/dev/null | awk '{print $1}')
PULP_USED_HUMAN=$(sudo du -sh "$PULP_CONTENT" 2>/dev/null | awk '{print $1}')
DRIVE_SIZE_BYTES=$(sudo blockdev --getsize64 "$DEVICE" 2>/dev/null)
DRIVE_SIZE_KB=$(( ${DRIVE_SIZE_BYTES:-0} / 1024 ))
DRIVE_SIZE_HUMAN=$(numfmt --to=iec "${DRIVE_SIZE_BYTES:-0}" 2>/dev/null || echo "unknown")

check INFO "Pulp content ($PULP_CONTENT): ${PULP_USED_HUMAN} used (conservative export size estimate)"
check INFO "Drive capacity: ${DRIVE_SIZE_HUMAN}"

if [[ "${PULP_USED_KB:-0}" -gt 0 && "${DRIVE_SIZE_KB:-0}" -gt 0 ]]; then
    if [[ "$DRIVE_SIZE_KB" -ge "$PULP_USED_KB" ]]; then
        check PASS "Drive capacity is sufficient for estimated export size"
    else
        check FAIL "Drive too small — drive (${DRIVE_SIZE_HUMAN}) < estimated export (${PULP_USED_HUMAN})"
    fi
fi

# ─── Section 3: Mount point ────────────────────────────────────────────────
echo
echo "── Mount Point ───────────────────────────────────────────"

[[ -d "$EXPORT_MOUNT" ]] \
    && check PASS "Mount point $EXPORT_MOUNT exists" \
    || check FAIL "Mount point $EXPORT_MOUNT missing — run: mkdir -p $EXPORT_MOUNT"

ALREADY_MOUNTED=false
if mountpoint -q "$EXPORT_MOUNT" 2>/dev/null; then
    MOUNTED_DEV=$(findmnt -n -o SOURCE "$EXPORT_MOUNT" 2>/dev/null)
    if [[ "$MOUNTED_DEV" == "$DEVICE"* ]]; then
        check PASS "Already mounted from $DEVICE"
        ALREADY_MOUNTED=true
    else
        check WARN "Mounted from $MOUNTED_DEV — expected $DEVICE (unmount first if wrong drive)"
        ALREADY_MOUNTED=true
    fi
else
    check INFO "Not currently mounted"
fi

grep -q "$DRIVE_UUID" /etc/fstab 2>/dev/null \
    && check PASS "fstab entry present for UUID $DRIVE_UUID" \
    || check WARN "No fstab entry — add for persistence across reboots"

# ─── Section 4: Mount ──────────────────────────────────────────────────────
if [[ "$DRY_RUN" == false && "$ALREADY_MOUNTED" == false && "$CHECKS_FAILED" -eq 0 ]]; then
    echo
    echo "── Mounting ──────────────────────────────────────────────"

    if ! grep -q "$DRIVE_UUID" /etc/fstab 2>/dev/null; then
        echo "UUID=${DRIVE_UUID} ${EXPORT_MOUNT} ext4 defaults,fscontext=system_u:object_r:pulpcore_var_lib_t:s0 0 2" \
            | sudo tee -a /etc/fstab > /dev/null
        check PASS "fstab entry added"
    fi

    sudo mount "$EXPORT_MOUNT" \
        && check PASS "Mounted at $EXPORT_MOUNT" \
        || { check FAIL "Mount failed — check: dmesg | tail"; }

    sudo chown pulp:pulp "$EXPORT_MOUNT" && sudo chmod 750 "$EXPORT_MOUNT" \
        && check PASS "Ownership set to pulp:pulp, mode 750" \
        || check FAIL "Could not set ownership on $EXPORT_MOUNT"
fi

# ─── Section 5: Post-mount validation ──────────────────────────────────────
if mountpoint -q "$EXPORT_MOUNT" 2>/dev/null; then
    echo
    echo "── Post-Mount ────────────────────────────────────────────"

    SECONTEXT=$(ls -dZ "$EXPORT_MOUNT" 2>/dev/null | awk '{print $1}')
    echo "$SECONTEXT" | grep -q "pulpcore_var_lib_t" \
        && check PASS "SELinux context: $SECONTEXT" \
        || check FAIL "SELinux context '$SECONTEXT' — expected pulpcore_var_lib_t"

    OWNER=$(stat -c '%U:%G' "$EXPORT_MOUNT" 2>/dev/null)
    [[ "$OWNER" == "pulp:pulp" ]] \
        && check PASS "Ownership: pulp:pulp" \
        || check WARN "Ownership is '$OWNER' — fix with: chown pulp:pulp $EXPORT_MOUNT"

    if sudo -u pulp touch "${EXPORT_MOUNT}/.write_test" 2>/dev/null; then
        sudo rm -f "${EXPORT_MOUNT}/.write_test"
        check PASS "pulp user write access confirmed"
    else
        check FAIL "pulp user cannot write to $EXPORT_MOUNT"
    fi

    AVAIL=$(df -h "$EXPORT_MOUNT" | awk 'NR==2 {print $4}')
    check INFO "Available on drive: $AVAIL"
fi

# ─── Summary ───────────────────────────────────────────────────────────────
echo
echo "============================================================"
if [[ "$CHECKS_FAILED" -gt 0 ]]; then
    printf " ${RED}NOT READY${NC} — %d failure(s), %d warning(s)\n" "$CHECKS_FAILED" "$CHECKS_WARNED"
    echo " Resolve failures before running the export playbook."
    exit 1
elif [[ "$CHECKS_WARNED" -gt 0 ]]; then
    printf " ${YELLOW}READY WITH WARNINGS${NC} — %d warning(s)\n" "$CHECKS_WARNED"
    echo " Review warnings. You may proceed with the export playbook."
    exit 0
else
    printf " ${GREEN}READY FOR EXPORT${NC}\n"
    echo " Run: build_sat_disconnected_export.sh"
    exit 0
fi
