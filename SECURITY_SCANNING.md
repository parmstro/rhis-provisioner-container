# Security Scanning and Signing Design

This document describes the security scanning pipeline, CVE risk management, and container signing architecture for the rhis-provisioner-container build system.

## Overview

The build pipeline integrates security checks at three points:

1. **Pre-build** — lint and validate source content before building
2. **Post-build** — scan the built container image for vulnerabilities, generate SBOMs, reconcile CVE risks, push, sign, and attest
3. **Pull-time verification** — verify cosign signatures on base images before consuming them in downstream builds

Both the base layer (`rhis-base`) and provisioner layer (`rhis-provisioner`) implement this pipeline. Scanning is enabled by default and can be disabled with `--no-scan` for quick dev iterations.

## Build Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        rhis-base build                              │
│                                                                     │
│  1. Pre-build scan (lint, yamllint, collection validation)          │
│  2. podman build (UBI base + ansible collections + dependencies)    │
│  3. Post-build scan:                                                │
│     a. Trivy image scan (OS + app deps + secrets)                   │
│     b. Syft SBOM generation (SPDX JSON)                             │
│     c. Grype SBOM scan (second-opinion vulnerability scan)          │
│     d. CVE risk reconciliation (auto-update accepted risks)         │
│     e. Policy enforcement (fail on actionable findings)             │
│     f. Push to registry                                             │
│     g. Cosign sign (keyless / Sigstore)                             │
│     h. Cosign attest SBOM + vulnerability scan                      │
│  4. Update version file                                             │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     rhis-provisioner build                           │
│                                                                     │
│  1. Pre-build scan (ansible-lint, yamllint)                         │
│  2. Cosign verify base image signature ◄── NEW                     │
│  3. podman build (base image + rhis-builder projects)               │
│  4. Post-build scan (same pipeline as base: Trivy, Syft,           │
│     Grype, CVE reconciliation, policy, push, sign, attest)          │
│  5. Update version file                                             │
└─────────────────────────────────────────────────────────────────────┘
```

## Pre-build Scanning

### Base layer (`scan_base_pre_build.yml`)

- **ansible-lint** with `safety` profile against all playbooks and roles
- **yamllint** for YAML syntax validation
- **Collection compatibility validation** (`validate_collection_compatibility.yml`) — verifies installed collections work against the target ansible-core version (2.14 for UBI 9, 2.16 for UBI 10)
- **ClamAV malware scan** on source files

### Provisioner layer (`scan_provisioner_pre_build.yml`)

- **ansible-lint** with `safety` profile
- **yamllint** for YAML syntax validation

### Configuration

Pre-build scan configuration is in:
- `rhis-base/scan_collections_config.yml` — tool paths, versions, scan policy
- `rhis-provisioner/scan_provisioner_config.yml` — tool paths, severity cutoffs

## Post-build Scanning

Both layers run the same post-build pipeline. The scan playbooks are:
- `rhis-base/scan_base_post_build.yml`
- `rhis-provisioner/scan_provisioner_post_build.yml`

### Tools

| Tool | Purpose | Output |
|------|---------|--------|
| **Trivy** | Container image vulnerability scan (OS packages, app dependencies, embedded secrets) | `trivy-image.json` |
| **Syft** | SBOM generation from container image | `sbom.spdx.json` |
| **Grype** | Vulnerability scan against SBOM (second-opinion, different database than Trivy) | `grype-sbom.json` |
| **Cosign** | Container signing (keyless via Sigstore) and attestation | Signatures stored in registry |

### Scan Reports

Reports are written to a timestamped directory under `scan-reports/` (gitignored):

```
scan-reports/build-ubi9-20260930-163709/
├── ansible-lint.txt           # Pre-build lint results
├── cosign-verify-base.log     # Base image signature verification (provisioner only)
├── trivy-image.json           # Trivy vulnerability scan
├── sbom.spdx.json             # Software Bill of Materials
├── grype-sbom.json            # Grype vulnerability scan
├── risk-reconciliation.txt    # CVE reconciliation report (what changed)
└── scan-summary.txt           # Exit codes for each scan phase
```

## CVE Risk Reconciliation

### Problem

Container images built on UBI inherit upstream RPM vulnerabilities. These change between builds as Red Hat publishes errata. Manually maintaining an accepted risks list is error-prone — patched CVEs linger, new CVEs go undocumented.

### Solution

The `reconcile_accepted_risks.py` script automatically maintains the accepted risks file (`scan_accepted_risks.yml`) as a living audit document:

```
                    Grype scan results
                          │
                          ▼
              ┌───────────────────────┐
              │   reconcile_accepted  │
              │      _risks.py       │
              └───────────────────────┘
                     │         │
        ┌────────────┘         └────────────┐
        ▼                                   ▼
  scan_accepted_risks.yml          risk-reconciliation.txt
  (updated in place)               (build report)
```

### Reconciliation Logic

On each scan, the script compares Grype findings against the existing accepted risks file:

| Scenario | Action | Build Impact |
|----------|--------|--------------|
| CVE in scan, in accepted, no fix | Update `last_scanned` | No block |
| CVE in scan, in accepted, fix now available | Update `fix_available`, flag for review | No block (already accepted) |
| CVE in scan, NOT in accepted, no fix | **Auto-accept** with reason | No block |
| CVE in scan, NOT in accepted, fix available | **Flag as actionable** | **Build blocked** |
| CVE in accepted, NOT in scan | **Remove** (patched) | Accepted list shrinks |

### Key Design Decisions

- **Full transparency**: The accepted risks file documents ALL known vulnerabilities at or above the severity cutoff, not just the ones without fixes. This is the audit document for what ships.
- **Triage optimization**: The reconciliation report separates what's actionable (fix available) from what's not, so you know what you *can* patch during active development.
- **Auto-cleanup**: When a CVE is patched in a new build, it drops off the accepted list automatically. No manual cleanup.
- **Policy gate**: The build only fails when a fix IS available and hasn't been applied. No fix available = auto-accepted. This prevents builds from blocking on upstream issues you can't resolve.

### Accepted Risks File Format

```yaml
accepted_cves:
  CVE-2026-80274:
    severity: High
    packages: ["bind-libs", "bind-license", "bind-utils"]
    fix_available: false
    reason: "Auto-accepted — no fix available from vendor"
    accepted_by: "parmstro"
    accepted_date: "2026-09-30"
    last_scanned: "2026-09-30"
    review_by: "2026-10-14"
```

Fields:
- `fix_available` — updated each scan; triggers review when it flips to `true`
- `fix_versions` — populated when a fix is available, showing target versions per package
- `last_scanned` — updated each scan for audit trail
- `review_by` — set to 14 days from acceptance; signals when to re-evaluate

### Reconciliation Report

Each build produces a `risk-reconciliation.txt` showing what changed:

```
PATCHED — removed from accepted risks (18):
  ✓ High      CVE-2023-4408         bind-libs, bind-license, bind-utils

NEW — auto-accepted, no fix available (2):
  + High      CVE-2026-75804        openssl, openssl-libs

CHANGED — fix now available, review required (7):
  ! Critical  CVE-2026-76578        ipa-common, python3-ipalib
           fix: ipa-common → 0:4.13.4-1.el9_8

Full accepted list (22 CVEs):
  ...
```

## Container Signature Verification

### Signing (Post-build)

After a successful build and scan, images are signed using **cosign keyless signing** via Sigstore:

1. `cosign sign` — signs the image digest (requires OIDC browser authentication)
2. `cosign attest --type spdxjson` — attaches the SBOM as a signed attestation
3. `cosign attest --type vuln` — attaches the vulnerability scan as a signed attestation

Signatures are stored in the registry alongside the image. The signer's identity (OIDC subject) and issuer are recorded in the Sigstore transparency log.

### Verification (Pre-build, provisioner only)

Before building the provisioner layer, the build script verifies the cosign signature on the base image pulled from the registry:

```
verify_base_signature()
  │
  ├── Skip if --skip-verify or pull_registry=localhost
  ├── Skip with warning if cosign not installed
  │
  └── cosign verify
        --certificate-identity <signer-email>
        --certificate-oidc-issuer <oidc-provider>
        <registry>/<repo>/rhis-base-<os>-<aap>:<version>
```

This ensures:
- The base image was signed by the expected identity
- The signature is in the Sigstore transparency log
- The image has not been tampered with since signing

**Failure aborts the build** (exit code 4) before the expensive `podman build` step.

### Configuration

Cosign identity and OIDC issuer are configured in `build.local.conf` (gitignored):

```bash
# Local build configuration — NOT committed to git.
cosign_identity="5768297+parmstro@users.noreply.github.com"
cosign_oidc_issuer="https://github.com/login/oauth"
```

Note: GitHub's OIDC tokens use the `{id}+{username}@users.noreply.github.com` format, not your profile email. Check your signed images with `cosign verify --certificate-identity-regexp ".*" --certificate-oidc-issuer-regexp ".*" <image>` to find the correct identity.

CLI flags `--cosign-identity`, `--cosign-oidc-issuer`, and `--skip-verify` are also available and override the config file.

## KICS IaC Scanning

[KICS](https://kics.io/) (Keeping Infrastructure as Code Secure) scans Ansible playbooks and Dockerfiles for security misconfigurations.

### Standalone Playbook

`rhis-provisioner/scan_kics_iac.yml` is a standalone, callable playbook for running KICS against a built container image:

```bash
ansible-playbook scan_kics_iac.yml \
  -e image_name=localhost/rhis-provisioner-9-2.5:1.0.134 \
  -e reports_dir=./scan-reports/kics-run
```

The playbook:
1. Creates a temporary container from the image
2. Exports the filesystem via `podman export | tar`
3. Runs KICS against `/rhis` within the exported filesystem
4. Parses results and filters by severity
5. Enforces policy: fails on any CRITICAL or HIGH findings not in accepted risks
6. Cleans up the exported filesystem (requires `become: true` for root-owned files)

### Accepted Risks

KICS accepted risks are in `rhis-provisioner/kics_accepted_risks.yml` using query IDs:

```yaml
accepted_queries:
  - query_id: "a88baa34-e2ad-44ea-ad6f-8cac87bc7c71"
    query_name: "Generic Password"
    severity: HIGH
    reason: "Variable references flagged as false positive"
    accepted_by: "parmstro"
    accepted_date: "2026-09-30"
    review_by: "2026-10-14"
```

### KICS Installation

KICS v2.1.20 is installed at `~/.local/bin/kics` with query assets at `~/.local/share/kics/assets/`. The `install_scan_tools.yml` playbook manages installation of KICS and other scan tools.

## Build Script Exit Codes

### `rhis_build_provisioner.sh`

| Code | Stage |
|------|-------|
| 1 | Usage / argument validation |
| 2 | Invalid OS version |
| 3 | Pre-build scan failed |
| 4 | Base image signature verification failed |
| 5 | Container build failed |
| 6 | Registry login failed |
| 7 | Post-build scan failed (policy violation) |
| 8 | Registry push failed |

### `rhis_build_base.sh`

| Code | Stage |
|------|-------|
| 1 | Usage / argument validation |
| 3 | Pre-build scan failed |
| 4 | Container build failed |
| 5 | Registry login failed |
| 6 | Post-build scan failed (policy violation) |
| 7 | Registry push failed |

## Local Configuration

`build.local.conf` at the repository root is sourced by both build scripts. It is gitignored and holds local settings:

```bash
# Cosign signature verification
cosign_identity="5768297+parmstro@users.noreply.github.com"
cosign_oidc_issuer="https://github.com/login/oauth"

# Registry credentials (optional)
# push_registry_login="mybot"
# push_registry_token="<token>"
```

This file is loaded before argument parsing, so CLI flags override any values set here.

## OS-versioned Requirements

Requirements files are split by OS version to handle differing ansible-core versions:

| File | Target | ansible-core |
|------|--------|-------------|
| `requirements.9.yml` | UBI 9 | 2.14.x |
| `requirements.9.txt` | UBI 9 | Python deps |
| `requirements.10.yml` | UBI 10 | 2.16.x |
| `requirements.10.txt` | UBI 10 | Python deps |

The `stage_sources()` function in each build script copies the appropriate requirements files into `sources/` based on `$osver`. The `sources/` directory is a build artifact (gitignored) and is cleaned after each build.

## Scan Tool Installation

The `install_scan_tools.sh` / `install_scan_tools.yml` playbook installs and manages:

- **Trivy** — container vulnerability scanner
- **Grype** — SBOM-based vulnerability scanner
- **Syft** — SBOM generator
- **Cosign** — container signing and verification
- **ClamAV** — malware scanner
- **ansible-lint** — Ansible best practices linter
- **KICS** — IaC security scanner (installed separately at `~/.local/bin/kics`)

Tool versions are pinned in the scan configuration files and can be upgraded with `--upgrade`.
