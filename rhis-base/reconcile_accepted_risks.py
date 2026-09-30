#!/usr/bin/env python3
"""Reconcile Grype scan results against the accepted risks file.

Reads a Grype JSON report and the current accepted_risks YAML file,
then produces an updated YAML reflecting the current scan state:
  - CVEs no longer in scan results are REMOVED (patched)
  - New CVEs with no fix are AUTO-ACCEPTED
  - New CVEs with a fix available are FLAGGED (actionable)
  - Existing entries get fix_available and last_scanned updated

The updated file is the audit document for what ships in this build.

Usage:
  python3 reconcile_accepted_risks.py \
    --grype-report grype-sbom.json \
    --accepted-risks scan_accepted_risks.yml \
    --output scan_accepted_risks.yml \
    --severity-cutoff high \
    --accepted-by parmstro \
    --reconcile-report report.txt

Exit codes:
  0 - All findings accepted or no findings
  1 - Actionable findings exist (fix available, not accepted)
  2 - Error
"""

import argparse
import json
import sys
from collections import OrderedDict
from datetime import date, timedelta


def load_grype(path):
    """Parse Grype JSON into {cve: {severity, packages: {pkg: {version, fix_versions}}}}."""
    with open(path) as f:
        data = json.load(f)

    sev_order = {'negligible': 0, 'low': 1, 'medium': 2, 'high': 3, 'critical': 4}
    findings = {}

    for m in data.get('matches', []):
        v = m.get('vulnerability', {})
        cve = v.get('id', '')
        sev = v.get('severity', 'Unknown')
        pkg = m.get('artifact', {}).get('name', '?')
        ver = m.get('artifact', {}).get('version', '?')
        fix_versions = v.get('fix', {}).get('versions', [])

        if cve not in findings:
            findings[cve] = {
                'severity': sev,
                'packages': {},
                'fix_available': False,
            }
        findings[cve]['packages'][pkg] = {
            'version': ver,
            'fix_versions': fix_versions,
        }
        if fix_versions:
            findings[cve]['fix_available'] = True

    return findings, sev_order


def load_accepted(path):
    """Load existing accepted risks YAML. Returns dict keyed by CVE ID."""
    try:
        import yaml
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        return data.get('accepted_cves', {}) or {}
    except FileNotFoundError:
        return {}


def write_accepted(path, accepted, header_comment=""):
    """Write accepted risks as YAML, preserving human-readable structure."""
    import yaml

    output = {
        'accepted_cves': accepted if accepted else {}
    }

    with open(path, 'w') as f:
        f.write("---\n")
        f.write("# Accepted security risks — auto-reconciled from Grype scan results.\n")
        f.write("#\n")
        f.write("# This file is the audit document for what ships in the current build.\n")
        f.write("# It is automatically updated by the scan pipeline:\n")
        f.write("#   - Patched CVEs are removed when no longer in scan results\n")
        f.write("#   - New CVEs with no fix are auto-accepted\n")
        f.write("#   - New CVEs with a fix are flagged as actionable\n")
        f.write("#   - fix_available status is updated each scan\n")
        f.write("#\n")
        f.write(f"# Last reconciled: {date.today().isoformat()}\n")
        f.write(f"# Review by: {(date.today() + timedelta(days=14)).isoformat()}\n")
        f.write("#\n")
        f.write("# Read by: scan_base_post_build.yml, scan_provisioner_post_build.yml\n")
        f.write("\n")

        if not accepted:
            f.write("accepted_cves: {}\n")
            return

        f.write("accepted_cves:\n")

        current_group = None
        for cve_id, entry in accepted.items():
            pkgs = entry.get('packages', [])
            group = pkgs[0] if pkgs else 'other'
            group = group.split('-')[0] if '-' in group else group

            if group != current_group:
                current_group = group
                f.write(f"\n  # ── {', '.join(pkgs)} {'─' * max(1, 56 - len(', '.join(pkgs)))}\n")

            f.write(f"\n  {cve_id}:\n")
            f.write(f"    severity: {entry.get('severity', 'Unknown')}\n")

            pkg_list = entry.get('packages', [])
            if pkg_list:
                f.write(f"    packages: {json.dumps(pkg_list)}\n")

            fix = entry.get('fix_available', False)
            f.write(f"    fix_available: {'true' if fix else 'false'}\n")

            if fix:
                fix_vers = entry.get('fix_versions', {})
                if fix_vers:
                    f.write(f"    fix_versions:\n")
                    for pkg_name, ver in fix_vers.items():
                        f.write(f"      {pkg_name}: \"{ver}\"\n")

            f.write(f"    reason: \"{entry.get('reason', 'Auto-accepted — no fix available')}\"\n")
            f.write(f"    accepted_by: \"{entry.get('accepted_by', 'auto')}\"\n")
            f.write(f"    accepted_date: \"{entry.get('accepted_date', date.today().isoformat())}\"\n")
            f.write(f"    last_scanned: \"{entry.get('last_scanned', date.today().isoformat())}\"\n")
            f.write(f"    review_by: \"{entry.get('review_by', (date.today() + timedelta(days=14)).isoformat())}\"\n")


def reconcile(grype_findings, accepted, severity_cutoff, sev_order, accepted_by):
    """Reconcile scan findings against accepted risks.

    Returns: (updated_accepted, added, removed, changed, actionable)
    """
    cutoff_val = sev_order.get(severity_cutoff.lower(), 3)
    today = date.today().isoformat()
    review_by = (date.today() + timedelta(days=14)).isoformat()

    updated = OrderedDict()
    added = []
    removed = []
    changed = []
    actionable = []

    # Walk current scan findings at or above severity cutoff
    for cve_id, finding in sorted(grype_findings.items()):
        sev = finding['severity']
        if sev_order.get(sev.lower(), 0) < cutoff_val:
            continue

        pkg_names = sorted(finding['packages'].keys())
        fix = finding['fix_available']

        # Build fix_versions map: {pkg: "ver1, ver2"}
        fix_versions = {}
        for pkg, info in finding['packages'].items():
            if info['fix_versions']:
                fix_versions[pkg] = ', '.join(info['fix_versions'])

        if cve_id in accepted:
            # Existing accepted entry — update it
            existing = accepted[cve_id]
            entry = dict(existing)
            entry['last_scanned'] = today
            entry['packages'] = pkg_names

            old_fix = existing.get('fix_available', False)
            entry['fix_available'] = fix
            entry['fix_versions'] = fix_versions if fix else {}

            if fix and not old_fix:
                changed.append({
                    'cve': cve_id,
                    'severity': sev,
                    'packages': pkg_names,
                    'change': 'fix_now_available',
                    'fix_versions': fix_versions,
                })
                entry['reason'] = f"Fix now available — was: {existing.get('reason', 'N/A')}"

            updated[cve_id] = entry
        else:
            # New finding
            entry = {
                'severity': sev,
                'packages': pkg_names,
                'fix_available': fix,
                'fix_versions': fix_versions if fix else {},
                'reason': 'Auto-accepted — no fix available from vendor' if not fix
                          else 'NEW — fix available, action required',
                'accepted_by': accepted_by if not fix else 'UNACCEPTED',
                'accepted_date': today,
                'last_scanned': today,
                'review_by': review_by,
            }

            if fix:
                actionable.append({
                    'cve': cve_id,
                    'severity': sev,
                    'packages': pkg_names,
                    'fix_versions': fix_versions,
                })
            else:
                added.append({
                    'cve': cve_id,
                    'severity': sev,
                    'packages': pkg_names,
                })
                updated[cve_id] = entry

    # Find removed (patched) CVEs — in accepted but not in scan at cutoff level
    for cve_id, entry in accepted.items():
        if cve_id not in updated:
            sev = entry.get('severity', 'Unknown')
            if sev_order.get(sev.lower(), 0) >= cutoff_val:
                removed.append({
                    'cve': cve_id,
                    'severity': sev,
                    'packages': entry.get('packages', []),
                })

    return updated, added, removed, changed, actionable


def write_report(path, image_name, added, removed, changed, actionable, updated):
    """Write a human-readable reconciliation report."""
    with open(path, 'w') as f:
        f.write("═" * 70 + "\n")
        f.write("  CVE Risk Reconciliation Report\n")
        f.write("═" * 70 + "\n")
        f.write(f"  Image:  {image_name}\n")
        f.write(f"  Date:   {date.today().isoformat()}\n")
        f.write(f"  Total accepted: {len(updated)}\n")
        f.write("═" * 70 + "\n\n")

        if removed:
            f.write(f"PATCHED — removed from accepted risks ({len(removed)}):\n")
            for r in removed:
                f.write(f"  ✓ {r['severity']:8s}  {r['cve']:20s}  {', '.join(r['packages'])}\n")
            f.write("\n")

        if added:
            f.write(f"NEW — auto-accepted, no fix available ({len(added)}):\n")
            for a in added:
                f.write(f"  + {a['severity']:8s}  {a['cve']:20s}  {', '.join(a['packages'])}\n")
            f.write("\n")

        if changed:
            f.write(f"CHANGED — fix now available, review required ({len(changed)}):\n")
            for c in changed:
                f.write(f"  ! {c['severity']:8s}  {c['cve']:20s}  {', '.join(c['packages'])}\n")
                for pkg, ver in c.get('fix_versions', {}).items():
                    f.write(f"           fix: {pkg} → {ver}\n")
            f.write("\n")

        if actionable:
            f.write(f"ACTIONABLE — fix available, build blocked ({len(actionable)}):\n")
            for a in actionable:
                f.write(f"  ✗ {a['severity']:8s}  {a['cve']:20s}  {', '.join(a['packages'])}\n")
                for pkg, ver in a.get('fix_versions', {}).items():
                    f.write(f"           fix: {pkg} → {ver}\n")
            f.write("\n")

        if not removed and not added and not changed and not actionable:
            f.write("No changes — accepted risks unchanged from previous scan.\n\n")

        f.write("─" * 70 + "\n")
        f.write(f"Full accepted list ({len(updated)} CVEs):\n")
        for cve_id, entry in updated.items():
            fix_flag = " [FIX AVAILABLE]" if entry.get('fix_available') else ""
            f.write(f"  {entry.get('severity', '?'):8s}  {cve_id:20s}  "
                    f"{', '.join(entry.get('packages', []))}{fix_flag}\n")
        f.write("─" * 70 + "\n")


def main():
    parser = argparse.ArgumentParser(description='Reconcile Grype results with accepted risks')
    parser.add_argument('--grype-report', required=True, help='Path to Grype JSON report')
    parser.add_argument('--accepted-risks', required=True, help='Path to accepted risks YAML')
    parser.add_argument('--output', required=True, help='Path to write updated accepted risks YAML')
    parser.add_argument('--severity-cutoff', default='high', help='Minimum severity to consider')
    parser.add_argument('--accepted-by', default='auto', help='Name for auto-accepted entries')
    parser.add_argument('--reconcile-report', default='', help='Path to write reconciliation report')
    parser.add_argument('--image-name', default='', help='Image name for report header')
    args = parser.parse_args()

    try:
        grype_findings, sev_order = load_grype(args.grype_report)
    except Exception as e:
        print(f"ERROR: Failed to load Grype report: {e}", file=sys.stderr)
        sys.exit(2)

    accepted = load_accepted(args.accepted_risks)

    updated, added, removed, changed, actionable = reconcile(
        grype_findings, accepted, args.severity_cutoff, sev_order, args.accepted_by
    )

    write_accepted(args.output, updated)

    if args.reconcile_report:
        write_report(args.reconcile_report, args.image_name,
                     added, removed, changed, actionable, updated)

    # Summary to stdout for Ansible to capture
    summary = {
        'total_accepted': len(updated),
        'added': len(added),
        'removed': len(removed),
        'changed': len(changed),
        'actionable': len(actionable),
        'added_cves': [a['cve'] for a in added],
        'removed_cves': [r['cve'] for r in removed],
        'changed_cves': [c['cve'] for c in changed],
        'actionable_cves': [a['cve'] for a in actionable],
    }
    print(json.dumps(summary))

    if actionable:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
