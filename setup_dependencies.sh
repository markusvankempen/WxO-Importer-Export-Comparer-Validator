#!/bin/bash
#
# setup_dependencies.sh — Check and optionally install WxO ImporterAndExport dependencies
#
# Dependencies: orchestrate CLI, jq, unzip (Python 3.11+ required for orchestrate)
# Run: ./setup_dependencies.sh   (check only)
# Run: ./setup_dependencies.sh --install   (prompt to install missing)
#
set -e

INSTALL_URL="https://developer.watson-orchestrate.ibm.com/getting_started/installing"
INSTALL_ORCHESTRATE="pip install --upgrade ibm-watsonx-orchestrate"

_ok()   { echo "  ✓ $1"; }
_fail() { echo "  ✗ $1"; return 1; }
_warn() { echo "  ⚠ $1"; }

check_python() {
    if command -v python3 >/dev/null 2>&1; then
        local ver
        ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0")
        if [[ "$ver" == "3.11" ]] || [[ "$ver" > "3.11" ]]; then
            _ok "Python $ver"
            return 0
        fi
        _warn "Python $ver (3.11+ recommended for orchestrate CLI)"
    else
        _fail "Python 3 not found. Install from https://www.python.org/downloads/"
        return 1
    fi
}

check_orchestrate() {
    if command -v orchestrate >/dev/null 2>&1; then
        local ver
        ver=$(orchestrate --version 2>/dev/null | head -1 || echo "unknown")
        _ok "orchestrate CLI ($ver)"
        return 0
    fi
    _fail "orchestrate CLI not found"
    echo "    Install: $INSTALL_ORCHESTRATE"
    echo "    Docs: $INSTALL_URL"
    return 1
}

check_jq() {
    if command -v jq >/dev/null 2>&1; then
        _ok "jq $(jq --version 2>/dev/null || echo "")"
        return 0
    fi
    _fail "jq not found"
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "    Install: brew install jq"
    else
        echo "    Install: sudo apt-get install -y jq   (or: dnf install jq)"
    fi
    return 1
}

check_unzip() {
    if command -v unzip >/dev/null 2>&1; then
        _ok "unzip"
        return 0
    fi
    _fail "unzip not found"
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "    macOS: unzip usually preinstalled; try: xcode-select --install"
    else
        echo "    Install: sudo apt-get install -y unzip   (or: dnf install unzip)"
    fi
    return 1
}

run_install() {
    local cmd="$1"
    echo ""
    read -p "Run: $cmd ? [y/N] " yn
    case "$yn" in
        [yY]|[yY][eE][sS])
            eval "$cmd"
            ;;
        *)
            echo "  Skipped."
            ;;
    esac
}

do_install() {
    echo ""
    echo "=== Installing missing dependencies ==="
    echo ""

    if ! command -v orchestrate >/dev/null 2>&1; then
        echo "orchestrate CLI:"
        run_install "$INSTALL_ORCHESTRATE"
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "jq:"
        if [[ "$OSTYPE" == darwin* ]]; then
            run_install "brew install jq"
        else
            run_install "sudo apt-get update -y && sudo apt-get install -y jq"
        fi
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        echo "unzip:"
        if [[ "$OSTYPE" != darwin* ]]; then
            run_install "sudo apt-get install -y unzip"
        fi
    fi

    echo ""
    echo "Re-run this script (without --install) to verify."
}

# --- main ---
echo ""
echo "WxO ImporterAndExport — dependency check"
echo "========================================="
echo ""

if [[ "${1:-}" == "--install" ]]; then
    do_install
    exit 0
fi

all_ok=true
check_python  || all_ok=false
check_orchestrate || all_ok=false
check_jq      || all_ok=false
check_unzip   || all_ok=false

echo ""
if [[ "$all_ok" == "true" ]]; then
    echo "All dependencies OK. Run ./wxo_exporter_importer.sh to start."
else
    echo "Some dependencies are missing."
    echo "  • Run manually with the install commands above, or"
    echo "  • Run: ./setup_dependencies.sh --install"
    echo ""
    echo "Docs: $INSTALL_URL"
fi
echo ""
