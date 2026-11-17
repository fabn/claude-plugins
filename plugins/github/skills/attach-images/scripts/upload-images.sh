#!/usr/bin/env bash
# Upload images as GitHub attachments and print one Markdown-ready <img> tag per file.
# Uses the endpoint behind drag-and-drop in the web UI: undocumented, so it may change.
set -euo pipefail

usage() {
  echo "usage: $0 [-R owner/repo] [-w width] <image>..." >&2
  exit 1
}

repo=""
width=""
while getopts "R:w:h" opt; do
  case "$opt" in
    R) repo="$OPTARG" ;;
    w) width="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage

[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
repo_id=$(gh api "repos/${repo}" --jq .id)
token=$(gh auth token)

for file in "$@"; do
  [ -f "$file" ] || { echo "not a file: $file" >&2; exit 1; }
  name=$(basename "$file")
  case "$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')" in
    png) type=image/png ;;
    jpg | jpeg) type=image/jpeg ;;
    gif) type=image/gif ;;
    webp) type=image/webp ;;
    *) echo "unsupported image type: $file" >&2; exit 1 ;;
  esac
  encoded=$(jq -rn --arg v "$name" '$v|@uri')
  url=$(curl -fsS -X POST \
    "https://uploads.github.com/user-attachments/assets?name=${encoded}&content_type=${type}&repository_id=${repo_id}" \
    -H "Authorization: Bearer ${token}" -H "Accept: application/json" -H "Content-Type: ${type}" \
    --data-binary "@${file}" | jq -r '.url // empty')
  [ -n "$url" ] || { echo "upload returned no url: $file" >&2; exit 1; }
  echo "<img src=\"${url}\" alt=\"${name%.*}\"${width:+ width=\"${width}\"}>"
done
