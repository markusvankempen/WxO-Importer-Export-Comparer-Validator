#!/bin/bash
#
# Script: compare_wxo_systems.sh
# Version: 1.0.7
# Author: Markus van Kempen <mvankempen@ca.ibm.com>, <markus.van.kempen@gmail.com>
# Date: Feb 25, 2026
#
# Description:
#   Compare agents, tools, and flows between two Watson Orchestrate (WXO) environments.
#   Produces a report table showing what exists in each system (Sys1 only, Sys2 only, both).
#
# Usage:
#   ./compare_wxo_systems.sh [ENV1] [ENV2]
#   ./compare_wxo_systems.sh              # interactive: select from orchestrate env list
#   ./compare_wxo_systems.sh --help
#
# Options:
#   --output, -o <file>   Write report to file
#   --env-file <path>     Path to .env for WXO_API_KEY_<ENV> (e.g. WXO_API_KEY_TZ1)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WXO_ROOT="${WXO_ROOT:-$SCRIPT_DIR/WxO}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../../.env}"
[[ ! -f "$ENV_FILE" ]] && ENV_FILE="$SCRIPT_DIR/.env"
REPORT_FILE=""

command -v orchestrate >/dev/null 2>&1 || { echo "[ERROR] 'orchestrate' CLI not found."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] 'jq' required."; exit 1; }
AUTO_REPORT=true   # when true, save to WxO/Compare/Sys1->Sys2/datetime/ if -o not given

# --- Parse args ---
ENV1=""
ENV2=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)   REPORT_FILE="$2"; AUTO_REPORT=false; [[ $# -ge 2 ]] && shift 2 || shift ;;
    --env-file)    ENV_FILE="$2"; [[ $# -ge 2 ]] && shift 2 || shift ;;
    -v|--version)
      echo "compare_wxo_systems.sh 1.0.7"
      exit 0
      ;;
    -h|--help)
      echo "Usage: $0 [ENV1] [ENV2] [OPTIONS]"
      echo "  WxO Importer/Export/Comparer/Validator — Compare script v1.0.7"
      echo ""
      echo ""
      echo "Compare agents, tools, and flows between two WXO environments."
      echo ""
      echo "Arguments:"
      echo "  ENV1, ENV2   Environment names (from orchestrate env list). If omitted, select interactively."
      echo ""
      echo "Options:"
      echo "  -o, --output <file>   Write report to file"
      echo "  --env-file <path>      .env for API keys (WXO_API_KEY_<ENV>)"
      echo "  -h, --help             Show this help"
      echo ""
      exit 0
      ;;
    *)
      if [[ -z "$ENV1" ]]; then ENV1="$1"
      elif [[ -z "$ENV2" ]]; then ENV2="$1"
      fi
      shift
      ;;
  esac
done

# --- Helpers ---
_print_header() {
  echo ""
  echo "  ═══════════════════════════════════════════════════════════"
  echo "  $1"
  echo "  ═══════════════════════════════════════════════════════════"
  echo ""
}

# Load API key: from env var WXO_API_KEY_<ENV>, .env, or prompt
_get_api_key() {
  local env_name="$1"
  local var_name="WXO_API_KEY_${env_name}"
  local key="${!var_name}"
  if [[ -z "$key" ]] && [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE" 2>/dev/null || true
    set +a
    key="${!var_name}"
  fi
  if [[ -z "$key" ]] && [[ -t 0 ]]; then
    read -p "  API key for $env_name: " key
  fi
  echo "$key"
}

# Fetch agents from active environment (names only, lowercase for comparison)
_fetch_agents() {
  orchestrate agents list -v 2>/dev/null | jq -r '
    (.native // .agents // .data // .items // .) |
    if type == "array" then . else [] end |
    .[] | select(type == "object") | (.name // .id) // empty
  ' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true
}

# Fetch tools with kind: output "name|kind" per line
_fetch_tools() {
  orchestrate tools list -v 2>/dev/null | jq -r '
    (if type == "array" then . else (.tools // .native // .data // .items) end) |
    if type == "array" then . else [] end |
    .[] | select(type == "object") |
    (.name // .id) as $n |
    (if .binding.python then "python"
     elif .binding.openapi then "openapi"
     elif .binding.flow then "flow"
     elif .binding.langflow then "langflow"
     else "other"
     end) as $k |
    "\($n)|\($k)"
  ' 2>/dev/null || true
}

# --- Main ---
main() {
  _print_header "Watson Orchestrate — System Comparison"

  # Get env list
  local env_list
  env_list=$(orchestrate env list 2>&1) || {
    echo "[ERROR] Failed to run 'orchestrate env list'. Ensure orchestrate CLI is installed."
    exit 1
  }

  local envs=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local name
    name=$(echo "$line" | awk '{print $1}')
    [[ -n "$name" ]] && [[ "$name" != "Name" ]] && envs+=("$name")
  done <<< "$env_list"

  if [[ ${#envs[@]} -lt 2 ]]; then
    echo "[ERROR] Need at least 2 environments to compare. Found: ${envs[*]:-none}"
    exit 1
  fi

  # Select ENV1 and ENV2 if not provided
  if [[ -z "$ENV1" ]] || [[ -z "$ENV2" ]]; then
    echo "  Select two environments to compare:"
    local i=1
    for e in "${envs[@]}"; do
      echo "    [$i] $e"
      ((i++))
    done
    echo ""
    if [[ -z "$ENV1" ]]; then
      read -p "  First system (1-$i): " c1
      [[ "$c1" =~ ^[0-9]+$ ]] && [[ "$c1" -ge 1 ]] && [[ "$c1" -le "$i" ]] && ENV1="${envs[$((c1-1))]}"
    fi
    if [[ -z "$ENV2" ]]; then
      read -p "  Second system (1-$i): " c2
      [[ "$c2" =~ ^[0-9]+$ ]] && [[ "$c2" -ge 1 ]] && [[ "$c2" -le "$i" ]] && ENV2="${envs[$((c2-1))]}"
    fi
    [[ -z "$ENV1" ]] || [[ -z "$ENV2" ]] && { echo "[ERROR] Invalid selection."; exit 1; }
    [[ "$ENV1" == "$ENV2" ]] && { echo "[ERROR] Choose two different environments."; exit 1; }
  fi

  echo "  Comparing: $ENV1  vs  $ENV2"
  echo ""

  # Auto-save report to WxO/Compare/Sys1->Sys2/datetime/ when -o not given
  if [[ "$AUTO_REPORT" == "true" ]] && [[ -z "$REPORT_FILE" ]]; then
    local compare_label="${ENV1}->${ENV2}"
    local compare_dir="$WXO_ROOT/Compare/$compare_label/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$compare_dir"
    REPORT_FILE="$compare_dir/compare_report.txt"
  fi

  # Activate and fetch from ENV1
  local key1 key2
  key1=$(_get_api_key "$ENV1")
  [[ -z "$key1" ]] && { echo "[ERROR] API key required for $ENV1."; exit 1; }
  orchestrate env activate "$ENV1" --api-key "$key1" 2>/dev/null || {
    echo "[ERROR] Failed to activate $ENV1."
    exit 1
  }

  local agents1 tools1 flows1
  agents1=$(sort -u <<< "$(_fetch_agents)")
  tools1=$(_fetch_tools)
  flows1=$(echo "$tools1" | grep '|flow$' | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | sort -u)
  tools1=$(echo "$tools1" | grep -v '|flow$' | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | sort -u)

  # Activate and fetch from ENV2
  key2=$(_get_api_key "$ENV2")
  [[ -z "$key2" ]] && { echo "[ERROR] API key required for $ENV2."; exit 1; }
  orchestrate env activate "$ENV2" --api-key "$key2" 2>/dev/null || {
    echo "[ERROR] Failed to activate $ENV2."
    exit 1
  }

  local agents2 tools2 flows2
  agents2=$(sort -u <<< "$(_fetch_agents)")
  tools2=$(_fetch_tools)
  flows2=$(echo "$tools2" | grep '|flow$' | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | sort -u)
  tools2=$(echo "$tools2" | grep -v '|flow$' | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]' | sort -u)

  # Build comparison: all unique names
  local all_agents all_tools all_flows
  all_agents=$(sort -u <<< "$(echo -e "${agents1}\n${agents2}")")
  all_tools=$(sort -u <<< "$(echo -e "${tools1}\n${tools2}")")
  all_flows=$(sort -u <<< "$(echo -e "${flows1}\n${flows2}")")

  _in_s1() { echo "$1" | grep -qFx "$2" 2>/dev/null; }
  _in_s2() { echo "$1" | grep -qFx "$2" 2>/dev/null; }

  # Build report (same format for console and file)
  REPORT_CONTENT=""
  REPORT_CONTENT+=$'\n'
  REPORT_CONTENT+="  ═══════════════════════════════════════════════════════════════════════════════════"$'\n'
  REPORT_CONTENT+="  COMPARISON REPORT: $ENV1  vs  $ENV2"$'\n'
  REPORT_CONTENT+="  ═══════════════════════════════════════════════════════════════════════════════════"$'\n'

  _append_section() {
    local title="$1" list="$2" set1="$3" set2="$4" name1="$5" name2="$6"
    REPORT_CONTENT+=$'\n'
    REPORT_CONTENT+="  $title"$'\n'
    REPORT_CONTENT+="  ─────────────────────────────────────────────────────────────────────────"$'\n'
    REPORT_CONTENT+="  $(printf '%-42s  %-8s  %-8s  %s' "NAME" "$name1" "$name2" "DIFF")"$'\n'
    REPORT_CONTENT+="  ─────────────────────────────────────────────────────────────────────────"$'\n'
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      _in_s1 "$set1" "$name" && in1="✓" || in1="-"
      _in_s2 "$set2" "$name" && in2="✓" || in2="-"
      if [[ "$in1" == "✓" ]] && [[ "$in2" == "✓" ]]; then diff="both"
      elif [[ "$in1" == "✓" ]]; then diff="only $name1"
      else diff="only $name2"; fi
      REPORT_CONTENT+="  $(printf '%-42s  %-8s  %-8s  %s' "${name:0:42}" "$in1" "$in2" "$diff")"$'\n'
    done <<< "$list"
    REPORT_CONTENT+="  ─────────────────────────────────────────────────────────────────────────"$'\n'
  }

  _append_section "AGENTS" "$all_agents" "$agents1" "$agents2" "$ENV1" "$ENV2"
  _append_section "TOOLS" "$all_tools" "$tools1" "$tools2" "$ENV1" "$ENV2"
  _append_section "FLOWS" "$all_flows" "$flows1" "$flows2" "$ENV1" "$ENV2"

  REPORT_CONTENT+=$'\n'
  REPORT_CONTENT+="  Legend: ✓ = present  |  - = absent  |  both = in both  |  only X = only in X"$'\n'
  REPORT_CONTENT+="  ═══════════════════════════════════════════════════════════════════════════════════"$'\n'
  REPORT_CONTENT+=$'\n'

  # Console output
  echo "$REPORT_CONTENT"

  # File: same formatted output + timestamp header
  if [[ -n "$REPORT_FILE" ]]; then
    {
      echo "=== WXO System Comparison $(date '+%Y-%m-%dT%H:%M:%S') ==="
      echo "Systems: $ENV1 vs $ENV2"
      echo "$REPORT_CONTENT"
    } > "$REPORT_FILE"
    echo "  Report saved: $REPORT_FILE"
    echo ""
  fi
}

main "$@"
