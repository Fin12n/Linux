#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/Fin12n/Linux/refs/heads/main/Antigravity/scripts"

# Detect OS
source /etc/os-release

case "$ID" in

    ubuntu|debian|linuxmint|pop|elementary|zorin)
        SCRIPT_URL="$BASE_URL/install-ubuntu.sh"
        ;;

    fedora|rhel|centos|rocky|almalinux)
        SCRIPT_URL="$BASE_URL/install-fedora.sh"
        ;;

    *)
        if [[ "${ID_LIKE:-}" == *debian* ]]; then
            SCRIPT_URL="$BASE_URL/install-ubuntu.sh"

        elif [[ "${ID_LIKE:-}" == *fedora* ||
                "${ID_LIKE:-}" == *rhel* ]]; then
            SCRIPT_URL="$BASE_URL/install-fedora.sh"

        else
            echo "ERROR: OS chưa được hỗ trợ."
            exit 1
        fi
        ;;
esac

echo "Detected OS: ${PRETTY_NAME:-$ID}"
echo "Downloading installer..."

exec bash <(
    curl -fsSL "$SCRIPT_URL"
)
