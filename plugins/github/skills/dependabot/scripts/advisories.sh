#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# Open security advisories affecting the default branch, one JSON object per line.
#
# Usage:
#   advisories.sh [<owner/repo>]
#
# Output (stdout), one line per vulnerable package and advisory:
#   { "source": "dependabot" | "osv", "package", "ecosystem", "manifest",
#     "scope": "runtime" | "development" | null, "relationship": "direct" | "transitive" | null,
#     "severity", "ghsa", "cve", "summary", "vulnerable", "patched" }
#
# Source order: Dependabot alerts (the same data Dependabot's security PRs come
# from), then `osv-scanner` on the current checkout. When neither answers, exit
# 3 with the reason on stderr: "no advisories" and "advisories unknown" must
# never look the same.
#
# Requires: gh (authenticated), jq; osv-scanner optional

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed" >&2; exit 69; }

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
err=$(mktemp)
trap 'rm -f "$err"' EXIT

if alerts=$(gh api --paginate "repos/$repo/dependabot/alerts?state=open&per_page=100" --jq '.[] | {
      source: "dependabot",
      package: .dependency.package.name,
      ecosystem: .dependency.package.ecosystem,
      manifest: .dependency.manifest_path,
      scope: .dependency.scope,
      relationship: .dependency.relationship,
      severity: .security_advisory.severity,
      ghsa: .security_advisory.ghsa_id,
      cve: .security_advisory.cve_id,
      summary: .security_advisory.summary,
      vulnerable: .security_vulnerability.vulnerable_version_range,
      patched: .security_vulnerability.first_patched_version.identifier
    }' 2>"$err"); then
  [ -z "$alerts" ] || jq -c . <<<"$alerts"
  exit 0
fi
reason="Dependabot alerts: $(head -1 "$err")"

if command -v osv-scanner >/dev/null 2>&1; then
  # osv-scanner exits 1 when it finds vulnerabilities, which is the normal case here.
  out=$(osv-scanner scan source -r . --format json 2>"$err") || [ $? -eq 1 ] || {
    echo "advisories unknown: $reason; osv-scanner: $(head -1 "$err")" >&2
    exit 3
  }
  jq -c '.results[] | .source.path as $manifest | .packages[]
    | .package as $p
    | (.groups // []) as $groups
    | .vulnerabilities[]
    | .id as $id
    | {
        source: "osv",
        package: $p.name,
        ecosystem: $p.ecosystem,
        manifest: $manifest,
        scope: null,
        relationship: null,
        severity: ([ $groups[] | select(.ids | index($id)) | .max_severity ] | first // .database_specific.severity // null),
        ghsa: ([ $id, (.aliases // [])[] ] | map(select(startswith("GHSA-"))) | first),
        cve: ((.aliases // []) | map(select(startswith("CVE-"))) | first),
        summary,
        vulnerable: null,
        patched: ([ .affected[]? | select(.package.name == $p.name) | .ranges[]?.events[]? | .fixed // empty ] | unique | join(", "))
      }' <<<"$out"
  exit 0
fi

echo "advisories unknown: $reason; osv-scanner not installed" >&2
exit 3
