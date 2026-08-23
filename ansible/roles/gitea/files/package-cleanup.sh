#!/bin/sh
# ansible/roles/gitea/files/package-cleanup.sh
# Keeps the newest $KEEP_COUNT container-package versions per app in Gitea's
# registry, always preserving whatever versions are listed in $LIVE_TAGS
# regardless of age/position. Gitea has no cleanup-rules API in this version
# (1.27.0) and the UI-only feature is documented upstream as unreliable for
# container-type packages — see SESSION-HANDOFF.md for the investigation.
#
# Env vars (all required):
#   GITEA_URL    e.g. http://gitea-http.gitea.svc.cluster.local:3000
#   GITEA_TOKEN  PAT with read:package, write:package, admin scopes
#   KEEP_COUNT   how many newest versions to keep per package
#   LIVE_TAGS    space-separated "package:version" pairs, always kept
#   DRY_RUN      "true" to print without deleting
set -eu

PACKAGES="research-forum-app rf-pre-event-app"
OWNER="gitea_admin"

for pkg in $PACKAGES; do
  echo "=== $pkg ==="
  page=1
  : > "/tmp/${pkg}.json"
  while :; do
    resp=$(curl -sf -H "Authorization: token $GITEA_TOKEN" \
      "$GITEA_URL/api/v1/packages/${OWNER}?type=container&q=${pkg}&limit=50&page=${page}")
    count=$(echo "$resp" | jq 'length')
    echo "$resp" | jq -c '.[] | {version, created_at}' >> "/tmp/${pkg}.json"
    [ "$count" -lt 50 ] && break
    page=$((page + 1))
  done

  # newest-first — jq-based sort only; a naive text `sort` on ISO-8601
  # timestamps can silently produce the wrong order without erroring.
  jq -s -c '. | sort_by(.created_at) | reverse | .[]' "/tmp/${pkg}.json" > "/tmp/${pkg}.sorted.json"

  keep_versions=$(jq -r '.version' "/tmp/${pkg}.sorted.json" | head -n "$KEEP_COUNT")
  live_version=$(echo "$LIVE_TAGS" | tr ' ' '\n' | grep "^${pkg}:" | cut -d: -f2 || true)

  total=$(wc -l < "/tmp/${pkg}.sorted.json")
  echo "Total versions: $total, keeping newest $KEEP_COUNT, live tag: ${live_version:-none}"

  deleted=0
  jq -r '.version' "/tmp/${pkg}.sorted.json" | while read -r v; do
    if echo "$keep_versions" | grep -qx "$v"; then continue; fi
    if [ -n "$live_version" ] && [ "$v" = "$live_version" ]; then
      echo "SKIP (live tag): $pkg:$v"
      continue
    fi
    if [ "$DRY_RUN" = "true" ]; then
      echo "WOULD DELETE: $pkg:$v"
    else
      echo "Deleting $pkg:$v"
      curl -sf -X DELETE -H "Authorization: token $GITEA_TOKEN" \
        "$GITEA_URL/api/v1/packages/${OWNER}/container/${pkg}/${v}"
    fi
  done
done
