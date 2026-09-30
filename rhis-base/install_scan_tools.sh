#!/bin/bash
# install_scan_tools.sh - Install security scanning prerequisites
#
# Reads pinned versions from scan_collections_config.yml. Introspects
# installed tools, queries GitHub for latest releases, and installs or
# upgrades as needed.
#
# Usage:
#   ./install_scan_tools.sh
#   ./install_scan_tools.sh --upgrade
#   ./install_scan_tools.sh --offline
#   ./install_scan_tools.sh --trivy-version 0.60.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extra_args=()

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --upgrade          Upgrade tools to latest available version"
    echo "  --offline          Verify tools only, do not download or update DBs"
    echo "  --config FILE      Path to scan_collections_config.yml (default: auto)"
    echo "  --trivy-version    Override pinned Trivy version"
    echo "  --grype-version    Override pinned Grype version"
    echo "  --syft-version     Override pinned Syft version"
    echo "  --cosign-version   Override pinned Cosign version"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upgrade)
            extra_args+=(-e "upgrade=true")
            shift
            ;;
        --offline)
            extra_args+=(-e "offline_mode=true")
            shift
            ;;
        --config)
            extra_args+=(-e "config_file=$2")
            shift 2
            ;;
        --trivy-version)
            extra_args+=(-e "trivy_version=$2")
            shift 2
            ;;
        --grype-version)
            extra_args+=(-e "grype_version=$2")
            shift 2
            ;;
        --syft-version)
            extra_args+=(-e "syft_version=$2")
            shift 2
            ;;
        --cosign-version)
            extra_args+=(-e "cosign_version=$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

ansible-playbook "${SCRIPT_DIR}/install_scan_tools.yml" \
    "${extra_args[@]}"
