#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

UBUNTU_SCRIPT="$SCRIPT_DIR/install-ubuntu.sh"
FEDORA_SCRIPT="$SCRIPT_DIR/install-fedora.sh"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -f /etc/os-release ]] || die "Không tìm thấy /etc/os-release."

# shellcheck disable=SC1091
source /etc/os-release

ID_LIKE="${ID_LIKE:-}"
ID="${ID:-}"

echo
echo "======================================"
echo "      Antigravity IDE Installers"
echo "======================================"
echo
echo "Detected OS: ${PRETTY_NAME:-$ID}"
echo

case "$ID" in
    ubuntu|debian|linuxmint|pop|elementary|zorin)
        exec bash "$UBUNTU_SCRIPT" "$@"
        ;;

    fedora)
        exec bash "$FEDORA_SCRIPT" "$@"
        ;;

    rhel|centos|rocky|almalinux)
        if [[ "$ID_LIKE" == *fedora* ||
              "$ID_LIKE" == *rhel* ||
              "$ID_LIKE" == *centos* ]]; then
            exec bash "$FEDORA_SCRIPT" "$@"
        fi
        ;;

esac

if [[ "$ID_LIKE" == *debian* ]]; then
    exec bash "$UBUNTU_SCRIPT" "$@"

elif [[ "$ID_LIKE" == *fedora* ||
        "$ID_LIKE" == *rhel* ]]; then
    exec bash "$FEDORA_SCRIPT" "$@"
fi

die "Distro chưa được hỗ trợ: ID=$ID, ID_LIKE=$ID_LIKE"
