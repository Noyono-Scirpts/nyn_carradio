# Shared by nyn_lib and nyn_template release.sh / release.bat.
# Writes fxmanifest version into public Noyono-Scirpts/nyn_versions,
# then commits, tags, pushes, and creates a GitHub Release.
#
# Expects: ROOT RESOURCE NEW
# Optional env: NYN_VERSIONS_REPO  GH_TOKEN  GITHUB_TOKEN  SKIP_PUSH=1  SKIP_VERSIONS=1

export PATH="${HOME}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

NYN_VERSIONS_REPO="${NYN_VERSIONS_REPO:-Noyono-Scirpts/nyn_versions}"
NYN_VERSIONS_FILE="${NYN_VERSIONS_FILE:-versions.json}"

nyn_python() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  elif command -v python >/dev/null 2>&1; then
    python "$@"
  else
    echo "error: python3 or python is required" >&2
    return 1
  fi
}

nyn_github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s' "$GITHUB_TOKEN"
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    gh auth token 2>/dev/null && return 0
  fi
  return 1
}

nyn_origin_repo() {
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  url="${url%.git}"
  url="${url#git@github.com:}"
  url="${url#https://github.com/}"
  url="${url#http://github.com/}"
  url="${url#ssh://git@github.com/}"
  printf '%s' "$url"
}

nyn_github_api() {
  local method="$1" path="$2"
  local token="$3"
  local data="${4:-}"
  local args=(
    -sS
    -X "$method"
    -H "Authorization: Bearer $token"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: nyn-release"
  )
  if [[ -n "$data" ]]; then
    args+=(-H "Content-Type: application/json" --data "$data")
  fi
  curl "${args[@]}" "https://api.github.com${path}"
}

nyn_publish_versions() {
  if [[ "${SKIP_VERSIONS:-}" == "1" ]]; then
    echo "skip versions catalog (SKIP_VERSIONS=1)"
    return 0
  fi

  if [[ "$RESOURCE" == "nyn_template" ]]; then
    echo "skip versions catalog (nyn_template is a scaffold, not a product)"
    return 0
  fi

  local token
  if ! token="$(nyn_github_token)"; then
    echo "error: need gh (gh auth login) or GH_TOKEN to publish versions" >&2
    echo "       catalog: https://github.com/${NYN_VERSIONS_REPO}" >&2
    return 1
  fi

  local catalog_path meta_path
  catalog_path="$(mktemp)"
  meta_path="$(mktemp)"
  printf '%s\n' '{}' > "$catalog_path"

  nyn_github_api GET "/repos/${NYN_VERSIONS_REPO}/contents/${NYN_VERSIONS_FILE}" "$token" > "$meta_path" || true

  local sha
  sha="$(nyn_python - "$catalog_path" "$meta_path" <<'PY'
import base64, json, pathlib, sys
catalog_path = pathlib.Path(sys.argv[1])
raw = pathlib.Path(sys.argv[2]).read_text(encoding='utf-8').strip() or '{}'
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit('error: invalid versions repo response')
if data.get('message') == 'Not Found':
    catalog_path.write_text('{}\n', encoding='utf-8')
    print('')
    raise SystemExit(0)
if data.get('message') and not data.get('content'):
    sys.exit('error: versions repo: ' + data.get('message', 'unknown'))
content = base64.b64decode(data.get('content') or '').decode('utf-8') or '{}'
try:
    catalog = json.loads(content)
except json.JSONDecodeError:
    catalog = {}
if not isinstance(catalog, dict):
    catalog = {}
catalog_path.write_text(json.dumps(catalog) + '\n', encoding='utf-8')
print(data.get('sha') or '')
PY
)"

  nyn_python - "$catalog_path" "$RESOURCE" "$NEW" <<'PY'
import json, sys
path, name, version = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
if not isinstance(data, dict):
    data = {}
data[name] = version
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write('\n')
PY

  local payload_path
  payload_path="$(mktemp)"
  nyn_python - "$catalog_path" "$RESOURCE" "$NEW" "$sha" "$payload_path" <<'PY'
import base64, json, pathlib, sys
src, name, version, sha, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
content = pathlib.Path(src).read_text(encoding='utf-8')
body = {
    "message": f"Release {name} {version}",
    "content": base64.b64encode(content.encode('utf-8')).decode('ascii'),
}
if sha:
    body["sha"] = sha
pathlib.Path(out).write_text(json.dumps(body), encoding='utf-8')
PY

  local response
  response="$(nyn_github_api PUT "/repos/${NYN_VERSIONS_REPO}/contents/${NYN_VERSIONS_FILE}" "$token" "$(cat "$payload_path")")"
  nyn_python -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if d.get("content") or d.get("commit") else "error: failed to update versions catalog")' <<< "$response"
  echo "catalog https://github.com/${NYN_VERSIONS_REPO}  ${RESOURCE}=${NEW}"

  if [[ -f "$ROOT/server/version.lua" || "$(basename "$ROOT")" == "nyn_lib" ]]; then
    cp "$catalog_path" "$ROOT/versions.json"
  fi
  rm -f "$catalog_path" "$meta_path" "$payload_path"
}

nyn_bump_readme_version() {
  local readme="$ROOT/README.md"
  [[ -f "$readme" ]] || return 0
  nyn_python - "$readme" "$NEW" <<'PY'
import pathlib, re, sys
path, version = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text(encoding='utf-8')
updated, n = re.subn(r'\*\*\d+\.\d+\.\d+\*\*', f'**{version}**', text, count=1)
if n:
    path.write_text(updated, encoding='utf-8')
PY
}

nyn_make_zip() {
  local zip_path="$1"
  nyn_python - "$ROOT/releases" "$RESOURCE" "$zip_path" <<'PY'
import pathlib, shutil, sys
releases, resource, zip_path = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
if zip_path.exists():
    zip_path.unlink()
archive = shutil.make_archive(str(zip_path.with_suffix('')), 'zip', root_dir=str(releases), base_dir=resource)
print(archive)
PY
}

nyn_git_release() {
  local zip_path="$1"
  if [[ ! -d "$ROOT/.git" ]]; then
    echo "skip git: not a git repository"
    return 0
  fi

  git -C "$ROOT" add -- fxmanifest.lua
  [[ -f "$ROOT/README.md" ]] && git -C "$ROOT" add -- README.md
  [[ -f "$ROOT/versions.json" ]] && git -C "$ROOT" add -- versions.json
  [[ -f "$ROOT/server/version.lua" ]] && git -C "$ROOT" add -- server/version.lua

  if git -C "$ROOT" diff --cached --quiet; then
    echo "git: nothing to commit"
  else
    git -C "$ROOT" commit -m "$(cat <<EOF
Release ${RESOURCE} ${NEW}

EOF
)"
  fi

  local tag="v${NEW}"
  if git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1; then
    echo "error: tag $tag already exists" >&2
    return 1
  fi
  git -C "$ROOT" tag -a "$tag" -m "${RESOURCE} ${NEW}"
  echo "tagged $tag"

  if [[ "${SKIP_PUSH:-}" == "1" ]]; then
    echo "skip push / GitHub release (SKIP_PUSH=1)"
    return 0
  fi

  git -C "$ROOT" push -u origin HEAD
  git -C "$ROOT" push origin "$tag"

  local repo
  repo="$(nyn_origin_repo)"

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh release create "$tag" "$zip_path" --title "${RESOURCE} ${NEW}" --generate-notes
    echo "GitHub Release ${tag}  https://github.com/${repo}/releases/tag/${tag}"
    return 0
  fi

  local token
  if ! token="$(nyn_github_token)"; then
    echo "pushed git tag, but no gh/GH_TOKEN — skip GitHub Release upload" >&2
    echo "zip is at $zip_path"
    return 0
  fi

  if [[ "$repo" != */* ]]; then
    echo "skip GitHub Release: origin is not a GitHub repo ($repo)"
    return 0
  fi

  local payload response
  payload="$(nyn_python - "$RESOURCE" "$NEW" "$tag" <<'PY'
import json, sys
resource, version, tag = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "tag_name": tag,
    "name": f"{resource} {version}",
    "generate_release_notes": True,
}))
PY
)"
  response="$(nyn_github_api POST "/repos/${repo}/releases" "$token" "$payload")"
  local upload_url
  upload_url="$(nyn_python -c 'import json,sys; d=json.load(sys.stdin); print((d.get("upload_url") or "").split("{")[0])' <<< "$response")"
  if [[ -z "$upload_url" ]]; then
    echo "error: failed to create GitHub Release:" >&2
    echo "$response" >&2
    return 1
  fi

  local zip_name
  zip_name="$(basename "$zip_path")"
  curl -sS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/zip" \
    -H "User-Agent: nyn-release" \
    --data-binary @"$zip_path" \
    "${upload_url}?name=${zip_name}" >/dev/null
  echo "GitHub Release ${tag}  https://github.com/${repo}/releases/tag/${tag}"
}
