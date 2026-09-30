#!/bin/bash
# scan_base.sh - Run security scanning for rhis-base container build
#
# Abstracts ansible-playbook invocations for the scanning pipeline.
# Called by rhis_build_base.sh or can be used standalone.
#
# Usage:
#   ./scan_base.sh --phase pre-build --os-ver 9 --ansible-config /etc/ansible/ansible.cfg
#   ./scan_base.sh --phase post-build --image rhis-base-9-2.5:1.0.22
#   ./scan_base.sh --phase all --os-ver 9 --ansible-config /etc/ansible/ansible.cfg --image rhis-base-9-2.5:1.0.22

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

phase=""
osver=""
ansiblecfg=""
image_name=""
registry_image=""
config_file=""
reports_dir=""

usage() {
    echo "Usage: $0 --phase <pre-build|post-build|all> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --phase PHASE           Required: pre-build, post-build, or all"
    echo "  --os-ver VER            OS version (9 or 10) — required for pre-build"
    echo "  --ansible-config PATH   Path to ansible.cfg — required for pre-build"
    echo "  --image NAME            Container image name — required for post-build"
    echo "  --registry-image REF   Registry image reference for push/sign (e.g. quay.io/org/image:tag)"
    echo "  --reports-dir DIR       Build reports directory (created by build script)"
    echo "  --config FILE           Path to scan_collections_config.yml (optional)"
    echo "  -h, --help              Show this help"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)         phase="$2"; shift 2 ;;
        --os-ver)        osver="$2"; shift 2 ;;
        --ansible-config) ansiblecfg="$2"; shift 2 ;;
        --image)         image_name="$2"; shift 2 ;;
        --registry-image) registry_image="$2"; shift 2 ;;
        --reports-dir)   reports_dir="$2"; shift 2 ;;
        --config)        config_file="$2"; shift 2 ;;
        -h|--help)       usage ;;
        *)               echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$phase" ]]; then
    echo "ERROR: --phase is required"
    usage
fi

run_pre_build() {
    if [[ -z "$osver" ]]; then
        echo "ERROR: --os-ver is required for pre-build scanning"
        exit 1
    fi
    if [[ -z "$ansiblecfg" ]]; then
        echo "ERROR: --ansible-config is required for pre-build scanning"
        exit 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "  Pre-Build Security Scan — ubi${osver}"
    echo "═══════════════════════════════════════════════════════════"

    ansible-playbook "${SCRIPT_DIR}/scan_base_pre_build.yml" \
        -e "os_ver=${osver}" \
        -e "ansible_cfg=${ansiblecfg}" \
        ${reports_dir:+-e "reports_dir=${reports_dir}"} \
        ${config_file:+-e "config_file=${config_file}"}

    return $?
}

run_post_build() {
    if [[ -z "$image_name" ]]; then
        echo "ERROR: --image is required for post-build scanning"
        exit 1
    fi

    echo "═══════════════════════════════════════════════════════════"
    echo "  Post-Build Security Scan — ${image_name}"
    echo "═══════════════════════════════════════════════════════════"

    ansible-playbook "${SCRIPT_DIR}/scan_base_post_build.yml" \
        -e "image_name=${image_name}" \
        ${registry_image:+-e "registry_image=${registry_image}"} \
        ${reports_dir:+-e "reports_dir=${reports_dir}"} \
        ${config_file:+-e "config_file=${config_file}"}

    return $?
}

case "$phase" in
    pre-build)
        run_pre_build
        exit $?
        ;;
    post-build)
        run_post_build
        exit $?
        ;;
    all)
        run_pre_build
        pre_rc=$?
        if [[ $pre_rc -ne 0 ]]; then
            echo "Pre-build scan failed. Aborting."
            exit $pre_rc
        fi
        run_post_build
        exit $?
        ;;
    *)
        echo "ERROR: Unknown phase '${phase}'. Use pre-build, post-build, or all."
        usage
        ;;
esac
