#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_FILE="${REPO_ROOT}/action.yml"

if ! command -v yq &>/dev/null; then
  echo "SKIP: yq not installed; install via 'brew install yq' or download from mikefarah/yq"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CONFIG_DIR="$WORK/.skyhook"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/skyhook.yaml"

cat >"$CONFIG_FILE" <<'YAML'
services:
  - name: with-context
    path: java-web-project
    deploymentRepo: KoalaOps/deployment
    deploymentRepoPath: nbjkgj
    buildTool:
      docker:
        buildContext: java-web-project/src
        dockerfilePath: java-web-project/src/Dockerfile
  - name: no-context
    path: java-multi-modules
    deploymentRepo: skyhook-dev/deployment
    deploymentRepoPath: nbjkgj
    buildTool:
      docker:
        dockerfilePath: java-multi-modules/Dockerfile
  - name: explicit-null
    path: svc-null
    buildTool:
      docker:
        buildContext: null
        dockerfilePath: svc-null/Dockerfile
  - name: empty-string
    path: svc-empty
    buildTool:
      docker:
        buildContext: ""
        dockerfilePath: svc-empty/Dockerfile
YAML

# Inline parse logic mirroring action.yml - kept in sync deliberately
parse() {
  local SERVICE_NAME="$1"
  local SERVICE_INDEX
  SERVICE_INDEX=$(SERVICE_NAME="$SERVICE_NAME" yq e '.services | to_entries | .[] | select(.value.name == strenv(SERVICE_NAME)) | .key' "$CONFIG_FILE" 2>/dev/null || echo "")
  [ -z "$SERVICE_INDEX" ] && { echo "MISS"; return; }

  local MATCH_COUNT
  MATCH_COUNT=$(printf '%s\n' "$SERVICE_INDEX" | grep -c .)
  if [ "$MATCH_COUNT" -gt 1 ]; then
    echo "DUPLICATE"
    return
  fi

  local SERVICE_PATH=".services[$SERVICE_INDEX]"
  local BUILD_CONTEXT
  BUILD_CONTEXT=$(yq e "${SERVICE_PATH}.buildTool.docker.buildContext // \"\"" "$CONFIG_FILE")
  [ "$BUILD_CONTEXT" = "null" ] && BUILD_CONTEXT=""
  [ -z "$BUILD_CONTEXT" ] && BUILD_CONTEXT="."

  local DOCKERFILE_PATH
  DOCKERFILE_PATH=$(yq e "${SERVICE_PATH}.buildTool.docker.dockerfilePath // \"\"" "$CONFIG_FILE")
  [ "$DOCKERFILE_PATH" = "null" ] && DOCKERFILE_PATH=""

  echo "${BUILD_CONTEXT}|${DOCKERFILE_PATH}"
}

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL ($label): got '$got' want '$want'"
    exit 1
  fi
  echo "PASS: $label"
}

assert_eq "$(parse with-context)" "java-web-project/src|java-web-project/src/Dockerfile" "buildContext is read"
assert_eq "$(parse no-context)" ".|java-multi-modules/Dockerfile" "buildContext defaults to '.' when absent"
assert_eq "$(parse explicit-null)" ".|svc-null/Dockerfile" "buildContext explicit null defaults to '.'"
assert_eq "$(parse empty-string)" ".|svc-empty/Dockerfile" "buildContext empty string defaults to '.'"
assert_eq "$(parse nonexistent-service)" "MISS" "missing service yields MISS"
assert_eq "$(parse 'name-with-\"-quote')" "MISS" "service_name containing a literal quote is handled (no crash)"

# Duplicate-name detection
DUP_FILE="$WORK/.skyhook/dup.yaml"
cat >"$DUP_FILE" <<'YAML'
services:
  - name: dup
    path: a
  - name: dup
    path: b
YAML
DUP_INDEX=$(SERVICE_NAME="dup" yq e '.services | to_entries | .[] | select(.value.name == strenv(SERVICE_NAME)) | .key' "$DUP_FILE")
DUP_COUNT=$(printf '%s\n' "$DUP_INDEX" | grep -c .)
if [ "$DUP_COUNT" -ne 2 ]; then
  echo "FAIL: expected 2 matches for duplicate name, got $DUP_COUNT"
  exit 1
fi
echo "PASS: duplicate service names produce >1 match (action.yml errors on this)"

# Sanity: action.yml references the renamed field, default, strenv, dup detection, and drops context_path
grep -q "buildTool.docker.buildContext" "$ACTION_FILE" || { echo "FAIL: action.yml does not read buildContext"; exit 1; }
grep -q 'BUILD_CONTEXT="\."' "$ACTION_FILE" || { echo "FAIL: action.yml does not default build_context to '.'"; exit 1; }
grep -q "build_context:" "$ACTION_FILE" || { echo "FAIL: action.yml does not declare build_context output"; exit 1; }
grep -q "strenv(SERVICE_NAME)" "$ACTION_FILE" || { echo "FAIL: action.yml does not use strenv() for service_name"; exit 1; }
grep -q "Multiple services named" "$ACTION_FILE" || { echo "FAIL: action.yml does not detect duplicate service names"; exit 1; }
grep -q "v4.47.1" "$ACTION_FILE" || { echo "FAIL: action.yml does not pin yq to a specific version"; exit 1; }
grep -q "context_path" "$ACTION_FILE" && { echo "FAIL: action.yml still references old context_path"; exit 1; }
echo "PASS: action.yml has expected schema + defaults + strenv + dup-detection + pinned yq + no context_path"
