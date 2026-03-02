#!/bin/bash
#
# Standalone script: Import a tool (e.g. Weather_Tool) and its connection into a target WxO environment.
#
# Order of operations (required by orchestrate CLI):
#   1. Import connection definition (orchestrate connections import -f <yaml>)
#   2. Set connection credentials for draft and live (orchestrate connections set-credentials -a <app_id> --env draft|live --api-key <value>)
#   3. Import tool with --app-id (orchestrate tools import -k openapi -f skill_v2.json -a <app_id>) — links tool to connection
#
# Usage:
#   ./import_tool_with_connection.sh [OPTIONS]
#   -t, --tool-dir <path>   Directory containing the tool (e.g. .../tools/Weather_Tool)
#   -e, --env-file <path>   .env_connection file with CONN_<app_id>_API_KEY=...
#   -n, --target-env <name> Target WxO environment (e.g. TZ2)
#   -h, --help              Show help
#
# Example (from WxO ImporterAndExport directory):
#   ./import_tool_with_connection.sh \
#     -t "WxO/Exports/TZ1/20260226_113727/tools/Weather_Tool" \
#     -e "WxO/Systems/TZ1/Connections/.env_connection_TZ1" \
#     -n TZ2
#
# Prerequisites: .env with WXO_API_KEY_<target>; .env_connection with CONN_<app_id>_API_KEY (api_key) or CONN_<app_id>_USERNAME/PASSWORD (basic)
#
set -e

TOOL_DIR=""
ENV_CONN_FILE=""
TARGET_ENV=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../../../.env}"
[[ ! -f "$ENV_FILE" ]] && ENV_FILE="$SCRIPT_DIR/../../.env"
[[ ! -f "$ENV_FILE" ]] && ENV_FILE="$SCRIPT_DIR/.env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tool-dir)     TOOL_DIR="${2:-}"; shift 2 ;;
    -e|--env-file)     ENV_CONN_FILE="${2:-}"; shift 2 ;;
    -n|--target-env)   TARGET_ENV="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 -t <tool-dir> -e <env-connection-file> -n <target-env>"
      echo ""
      echo "Import a tool and its connection into a target WxO environment."
      echo ""
      echo "Options:"
      echo "  -t, --tool-dir <path>   Directory with tool (skill_v2.json, connections/*.yaml)"
      echo "  -e, --env-file <path>   .env_connection with CONN_<app_id>_API_KEY=..."
      echo "  -n, --target-env <name> Target WxO env (e.g. TZ2); API key from WXO_API_KEY_<name> in .env"
      echo ""
      echo "Example:"
      echo "  $0 -t WxO/Exports/TZ1/20260226_113727/tools/Weather_Tool \\"
      echo "      -e WxO/Systems/TZ1/Connections/.env_connection_TZ1 -n TZ2"
      exit 0
      ;;
    *) echo "[ERROR] Unknown option: $1"; exit 1 ;;
  esac
done

[[ -z "$TOOL_DIR" ]] && { echo "[ERROR] -t <tool-dir> required."; exit 1; }
[[ -z "$TARGET_ENV" ]] && { echo "[ERROR] -n <target-env> required."; exit 1; }
[[ ! -d "$TOOL_DIR" ]] && { echo "[ERROR] Tool dir not found: $TOOL_DIR"; exit 1; }

# Resolve tool dir (allow relative paths)
TOOL_DIR="$(cd "$TOOL_DIR" && pwd)"

# Activate target environment
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE" 2>/dev/null; set +a; }
API_KEY_VAR="WXO_API_KEY_${TARGET_ENV}"
API_KEY="${!API_KEY_VAR}"
[[ -z "$API_KEY" ]] && { echo "[ERROR] No API key for $TARGET_ENV. Set WXO_API_KEY_${TARGET_ENV} in .env"; exit 1; }

echo "→ Activating $TARGET_ENV..."
orchestrate env activate "$TARGET_ENV" --api-key "$API_KEY" || { echo "[ERROR] Failed to activate $TARGET_ENV"; exit 1; }
echo ""

# 1. Import connections first (tools need connections to exist before import)
# Use app_id from bundled connections/*.yaml (from source export) to preserve same connection assignment
TOOL_CONN_APP_ID=""
if [[ -d "$TOOL_DIR/connections" ]]; then
  for CONN_YAML in "$TOOL_DIR"/connections/*.yml "$TOOL_DIR"/connections/*.yaml; do
    [[ -f "$CONN_YAML" ]] || continue
    APP_ID=$(grep -E '^[[:space:]]*app_id:' "$CONN_YAML" 2>/dev/null | head -1 | sed 's/.*app_id:[[:space:]]*\([^[:space:]]*\).*/\1/')
    [[ -z "$APP_ID" ]] && { APP_ID=$(basename "$CONN_YAML"); APP_ID="${APP_ID%.yml}"; APP_ID="${APP_ID%.yaml}"; }
    [[ -z "$TOOL_CONN_APP_ID" ]] && TOOL_CONN_APP_ID="$APP_ID"

    echo "→ Importing connection: $APP_ID"
    orchestrate connections import -f "$CONN_YAML" || { echo "[ERROR] Failed to import $APP_ID"; exit 1; }

    # 2. Set credentials (API key, basic auth, etc.) for both draft and live
    if [[ -n "$ENV_CONN_FILE" ]] && [[ -f "$ENV_CONN_FILE" ]]; then
      APP_SAFE="${APP_ID//./_}"
      # Use [[:space:]] not \s — BSD grep (macOS) doesn't support \s
      CONN_KIND=$(grep -A 50 'environments:' "$CONN_YAML" 2>/dev/null | grep -A 20 'live:' | grep -E '^[[:space:]]*kind:' | head -1 | sed 's/.*kind:[[:space:]]*\([a-z_]*\).*/\1/')
      [[ -z "$CONN_KIND" ]] && CONN_KIND=$(grep -A 30 'environments:' "$CONN_YAML" 2>/dev/null | grep -E '^[[:space:]]*kind:' | head -1 | sed 's/.*kind:[[:space:]]*\([a-z_]*\).*/\1/')
      [[ -z "$CONN_KIND" ]] && CONN_KIND="api_key"

      _get_val() { grep -E "^${1}=" "$ENV_CONN_FILE" 2>/dev/null | head -1 | sed "s/^${1}=//" | sed 's/^["'\'']//;s/["'\'']$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

      SET_ARGS=()
      if [[ "$CONN_KIND" == "basic" ]]; then
        U=$( _get_val "CONN_${APP_SAFE}_USERNAME" )
        P=$( _get_val "CONN_${APP_SAFE}_PASSWORD" )
        [[ -n "$U" ]] && SET_ARGS+=(--username "$U")
        [[ -n "$P" ]] && SET_ARGS+=(--password "$P")
      else
        V=$( _get_val "CONN_${APP_SAFE}_API_KEY" )
        [[ -n "$V" ]] && SET_ARGS+=(--api-key "$V")
      fi

      if [[ ${#SET_ARGS[@]} -gt 0 ]]; then
        echo "  → Setting credentials for $APP_ID ($CONN_KIND, draft + live)..."
        orchestrate connections set-credentials -a "$APP_ID" --env draft "${SET_ARGS[@]}" || { echo "[ERROR] Failed to set draft credentials for $APP_ID"; exit 1; }
        orchestrate connections set-credentials -a "$APP_ID" --env live "${SET_ARGS[@]}" || { echo "[ERROR] Failed to set live credentials for $APP_ID"; exit 1; }
        echo "  ✓ Credentials set (draft and live)"
      else
        echo "  [WARN] No CONN_${APP_SAFE}_* in $ENV_CONN_FILE — connection imported but not configured"
      fi
    else
      echo "  [WARN] No env file; connection imported but credentials not set"
    fi
    echo ""
  done
fi

# 3. Import tool with --app-id to associate it with the connection
SPEC=""
[[ -f "$TOOL_DIR/skill_v2.json" ]] && SPEC="skill_v2.json"
[[ -z "$SPEC" ]] && [[ -f "$TOOL_DIR/openapi.json" ]] && SPEC="openapi.json"
[[ -z "$SPEC" ]] && { echo "[ERROR] No skill_v2.json or openapi.json in $TOOL_DIR"; exit 1; }

# Patch spec: use info.title or x-ibm-skill-name for operation summary when single operation (so tool displays with intended name)
SPEC_PATH="$TOOL_DIR/$SPEC"
if jq -e '.paths' "$SPEC_PATH" >/dev/null 2>&1; then
  skill_name=$(jq -r '.info["x-ibm-skill-name"] // .info.title // empty' "$SPEC_PATH" 2>/dev/null)
  if [[ -n "$skill_name" ]]; then
    op_count=$(jq '[.paths[][]? | select(type == "object")] | length' "$SPEC_PATH" 2>/dev/null)
    if [[ "$op_count" == "1" ]]; then
      tmp=$(mktemp)
      jq --arg sn "$skill_name" '.paths |= with_entries(.value |= (if type == "object" then with_entries(.value |= (if type == "object" then . + {summary: $sn} else . end)) else . end))' "$SPEC_PATH" >"$tmp" 2>/dev/null && mv "$tmp" "$SPEC_PATH" || rm -f "$tmp"
    fi
  fi
fi

TOOL_NAME=$(basename "$TOOL_DIR")
echo "→ Importing tool: $TOOL_NAME (openapi)${TOOL_CONN_APP_ID:+ — linked to $TOOL_CONN_APP_ID}"
if [[ -n "$TOOL_CONN_APP_ID" ]]; then
  (cd "$TOOL_DIR" && orchestrate tools import -k openapi -f "$SPEC" -a "$TOOL_CONN_APP_ID") || { echo "[ERROR] Failed to import tool"; exit 1; }
else
  (cd "$TOOL_DIR" && orchestrate tools import -k openapi -f "$SPEC") || { echo "[ERROR] Failed to import tool"; exit 1; }
fi
echo ""
echo "✓ Done. Tool '$TOOL_NAME' and connection(s) imported into $TARGET_ENV."
