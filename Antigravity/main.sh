#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/Fin12n/Linux/refs/heads/main/Antigravity/scripts"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "Không tìm thấy curl."

detect_os() {
    [[ -f /etc/os-release ]] || die "Không tìm thấy /etc/os-release."

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in
        ubuntu)
            echo "ubuntu"
            ;;
        debian)
            echo "ubuntu"
            ;;
        linuxmint)
            echo "ubuntu"
            ;;
        pop)
            echo "ubuntu"
            ;;
        fedora)
            echo "fedora"
            ;;
        rhel)
            echo "fedora"
            ;;
        rocky)
            echo "fedora"
            ;;
        almalinux)
            echo "fedora"
            ;;
        *)
            case "${ID_LIKE:-}" in
                *debian*)
                    echo "ubuntu"
                    ;;
                *fedora*|*rhel*)
                    echo "fedora"
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
}

OS="$(detect_os)" || die "Hệ điều hành chưa được hỗ trợ."

echo "Detected OS: ${PRETTY_NAME:-$OS}"

case "$OS" in
    ubuntu)
        SCRIPT_URL="${REPO_RAW_BASE}/install-ubuntu.sh"
        ;;
    fedora)
        SCRIPT_URL="${REPO_RAW_BASE}/install-fedora.sh"
        ;;
esac

echo "Downloading installer..."
echo

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

curl -fL --retry 3 --retry-delay 1 \
    "$SCRIPT_URL" \
    -o "$TMP_SCRIPT" \
    || die "Không tải được installer: $SCRIPT_URL"

chmod +x "$TMP_SCRIPT"

exec bash "$TMP_SCRIPT" "$@"
