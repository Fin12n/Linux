#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Antigravity IDE"

APP_DIR="/opt/antigravity-ide"
BIN_PATH="/usr/local/bin/antigravity-ide"

DESKTOP_FILE="$HOME/.local/share/applications/antigravity.desktop"
DESKTOP_LINK="$HOME/Desktop/Antigravity IDE.desktop"

RELEASES_URL="https://antigravity.google/releases/"

TMP_DIR=""
WORK_DIR=""

cleanup() {
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT


die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}


info() {
    echo
    echo "==> $*"
}


warn() {
    echo
    echo "WARNING: $*" >&2
}


install_dependencies() {

    local missing=()

    command -v curl >/dev/null 2>&1 || missing+=(curl)
    command -v tar >/dev/null 2>&1 || missing+=(tar)
    command -v python3 >/dev/null 2>&1 || missing+=(python3)

    if ((${#missing[@]})); then

        info "Cài dependency: ${missing[*]}"

        sudo apt update

        sudo apt install -y "${missing[@]}"
    fi
}


version_from_dir() {

    local dir="$1"
    local f=""

    for f in \
        "$dir/resources/app/package.json" \
        "$dir/resources/app/product.json" \
        "$dir/resources/package.json" \
        "$dir/package.json"
    do

        if [[ -f "$f" ]]; then

            if command -v python3 >/dev/null 2>&1; then

                python3 - "$f" <<'PY'
import json
import sys

path = sys.argv[1]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    for key in ("version", "productVersion"):

        value = data.get(key)

        if isinstance(value, str) and value.strip():
            print(value.strip())
            raise SystemExit(0)

except Exception:
    pass
PY

                return 0
            fi

            sed -n \
                's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                "$f" |
                head -n1

            return 0
        fi
    done

    if [[ -x "$dir/antigravity-ide" ]]; then

        "$dir/antigravity-ide" --version 2>/dev/null |
            head -n1 ||
            true

    fi
}


installed_version() {

    [[ -d "$APP_DIR" ]] || return 0

    version_from_dir "$APP_DIR" || true
}


discover_release() {

    local html="$WORK_DIR/releases.html"

    info "Đang lấy trang releases chính thức..."

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 15 \
        -A "Mozilla/5.0" \
        "$RELEASES_URL" \
        -o "$html" ||
        die "Không tải được $RELEASES_URL"


    if command -v python3 >/dev/null 2>&1; then

        python3 - "$html" <<'PY'

import html as H
import re
import sys

from urllib.parse import urljoin


path = sys.argv[1]

with open(path, encoding="utf-8", errors="ignore") as f:
    data = f.read()

data = H.unescape(data)


anchors = re.findall(
    r'<a\b[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',
    data,
    flags=re.I | re.S
)


candidates = []


for href, text in anchors:

    visible = re.sub(
        r'<[^>]+>',
        ' ',
        text
    )

    visible = ' '.join(
        H.unescape(visible).split()
    )

    blob = (
        href +
        " " +
        visible
    ).lower()


    # Phải liên quan rõ ràng đến Antigravity.
    if "antigravity" not in blob:
        continue


    # Chỉ archive Linux dạng tar.gz/tgz.
    if not re.search(
        r'\.(?:tar\.gz|tgz)(?:[?#].*)?$',
        href,
        re.I
    ):
        continue


    # Phải có dấu hiệu Linux/x64.
    if not any(
        x in blob
        for x in (
            "linux",
            "x64",
            "amd64"
        )
    ):
        continue


    # Không lấy ARM.
    if any(
        x in blob
        for x in (
            "arm64",
            "aarch64",
            "armv7"
        )
    ):
        continue


    url = urljoin(
        "https://antigravity.google/",
        href
    )

    candidates.append(
        (
            url,
            visible
        )
    )


# Kiểm tra URL nằm trong HTML/JSON.
for match in re.finditer(
    r'https?://[^"\'<>\s]+',
    data
):

    url = H.unescape(
        match.group(0)
    )

    blob = url.lower()

    if "antigravity" not in blob:
        continue

    if not re.search(
        r'\.(?:tar\.gz|tgz)(?:[?#].*)?$',
        url,
        re.I
    ):
        continue

    if not any(
        x in blob
        for x in (
            "linux",
            "x64",
            "amd64"
        )
    ):
        continue

    if any(
        x in blob
        for x in (
            "arm64",
            "aarch64",
            "armv7"
        )
    ):
        continue

    candidates.append(
        (
            url,
            "embedded URL"
        )
    )


# Remove duplicates.
seen = set()
unique = []

for url, text in candidates:

    if url not in seen:

        seen.add(url)

        unique.append(
            (
                url,
                text
            )
        )


if len(unique) == 1:

    print(unique[0][0])

    raise SystemExit(0)


if len(unique) > 1:

    ranked = sorted(
        unique,
        key=lambda item: (
            "linux" not in item[1].lower(),

            not bool(
                re.search(
                    r'\b(x64|amd64)\b',
                    item[1],
                    re.I
                )
            )
        )
    )

    # Chỉ tự chọn khi ranking rõ ràng.
    if (
        len(ranked) == 1
        or ranked[0][1] != ranked[1][1]
    ):

        print(ranked[0][0])

        raise SystemExit(0)


print("AMBIGUOUS")

for url, text in unique[:10]:

    print(
        url +
        "\t" +
        text
    )

PY

        return 0
    fi


    # Fallback nếu không có Python.
    grep -Eo \
        'https?://[^"'\'' <>()]+\.tar\.gz' \
        "$html" 2>/dev/null |
        grep -Ei \
            'antigravity.*(linux|x64|amd64)|(linux|x64|amd64).*antigravity' |
        grep -Eiv \
            'arm64|aarch64|armv7' |
        head -n1 ||
        true
}


download_latest() {

    local url="$1"

    local archive="$WORK_DIR/antigravity.tar.gz"


    info "Artifact:"
    echo "$url"
    echo


    curl \
        -fL \
        --retry 3 \
        --connect-timeout 15 \
        -A "Mozilla/5.0" \
        "$url" \
        -o "$archive" ||
        die "Download thất bại."


    [[ -s "$archive" ]] ||
        die "File tải về rỗng."


    echo "$archive"
}


install_archive() {

    local archive="$1"

    local extract_dir="$WORK_DIR/extracted"


    mkdir -p "$extract_dir"


    tar \
        -xzf "$archive" \
        -C "$extract_dir" ||
        die "Không giải nén được archive."


    local source=""


    if [[ -x "$extract_dir/antigravity-ide" ]]; then

        source="$extract_dir"

    else

        source="$(
            find "$extract_dir" \
                -mindepth 1 \
                -maxdepth 2 \
                -type f \
                -name antigravity-ide \
                -printf '%h\n' 2>/dev/null |
            head -n1 ||
            true
        )"

    fi


    [[ -n "$source" ]] ||
        die "Archive không chứa executable antigravity-ide."


    [[ -x "$source/antigravity-ide" ]] ||
        die "Executable antigravity-ide không hợp lệ."


    local stage="$WORK_DIR/stage"


    rm -rf "$stage"

    mkdir -p "$stage"

    cp -a "$source"/. "$stage"/


    local new_version=""

    new_version="$(
        version_from_dir "$stage" ||
        true
    )"


    info "Đang cài vào $APP_DIR..."


    sudo mkdir -p "$APP_DIR"

    sudo rm -rf "$APP_DIR"

    sudo cp -a "$stage"/. "$APP_DIR"/


    [[ -x "$APP_DIR/antigravity-ide" ]] ||
        die "Cài đặt thất bại."


    # Chrome/Electron sandbox.
    if [[ -f "$APP_DIR/chrome-sandbox" ]]; then

        info "Thiết lập Chrome SUID sandbox..."

        sudo chown \
            root:root \
            "$APP_DIR/chrome-sandbox"

        sudo chmod \
            4755 \
            "$APP_DIR/chrome-sandbox"

    else

        warn "Không tìm thấy chrome-sandbox trong package."

    fi


    sudo ln \
        -sfn \
        "$APP_DIR/antigravity-ide" \
        "$BIN_PATH"


    create_desktop_entry


    info "Cài đặt hoàn tất."


    if [[ -n "$new_version" ]]; then

        echo "Version: $new_version"

    fi
}


create_desktop_entry() {

    mkdir -p \
        "$(dirname "$DESKTOP_FILE")"


    local icon=""


    for candidate in \
        "$APP_DIR/resources/app/out/media/code-icon.svg" \
        "$APP_DIR/resources/app/resources/linux/code.png" \
        "$APP_DIR/resources/app/resources/linux/code.svg"
    do

        if [[ -f "$candidate" ]]; then

            icon="$candidate"

            break

        fi

    done


    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Antigravity IDE
Comment=Antigravity IDE
Exec=$BIN_PATH %F
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=antigravity
EOF


    if [[ -n "$icon" ]]; then

        printf \
            'Icon=%s\n' \
            "$icon" \
            >> "$DESKTOP_FILE"

    fi


    chmod +x "$DESKTOP_FILE"


    if [[ -d "$HOME/Desktop" ]]; then

        cp -f \
            "$DESKTOP_FILE" \
            "$DESKTOP_LINK"

        chmod +x \
            "$DESKTOP_LINK"

    fi
}


compare_versions() {

    local a="$1"
    local b="$2"


    [[ -n "$a" && -n "$b" ]] ||
        return 2


    if command -v dpkg >/dev/null 2>&1; then

        dpkg \
            --compare-versions \
            "$a" \
            lt \
            "$b"

        return

    fi


    if command -v python3 >/dev/null 2>&1; then

        python3 - "$a" "$b" <<'PY'

import re
import sys


def version(value):

    return tuple(
        int(x) if x.isdigit() else x
        for x in re.findall(
            r'\d+|[A-Za-z]+',
            value
        )
    )


a, b = map(
    version,
    sys.argv[1:3]
)


raise SystemExit(
    0 if a < b else 1
)

PY

        return

    fi


    return 2
}


run_manager() {

    TMP_DIR="$(
        mktemp -d
    )"


    WORK_DIR="$TMP_DIR/work"


    mkdir -p "$WORK_DIR"


    local current=""

    current="$(
        installed_version ||
        true
    )"


    if [[ -n "$current" ]]; then

        echo
        echo "Installed version: $current"

    else

        echo
        echo "Antigravity IDE: chưa cài."

    fi


    local result=""

    result="$(
        discover_release ||
        true
    )"


    if [[ -z "$result" ]]; then

        die \
            "Không tìm thấy artifact Antigravity IDE Linux x64 trên trang releases."

    fi


    if [[ "$result" == AMBIGUOUS* ]]; then

        echo
        echo "Có nhiều artifact phù hợp."
        echo "Script không thể xác định chắc chắn artifact."
        echo
        echo "$result"

        exit 2

    fi


    local latest_url="$result"


    echo
    echo "Latest artifact:"
    echo "$latest_url"


    local archive=""

    archive="$(
        download_latest "$latest_url"
    )"


    # Extract preview để đọc version.
    local extract_preview="$WORK_DIR/preview"


    mkdir -p "$extract_preview"


    tar \
        -xzf "$archive" \
        -C "$extract_preview" ||
        die "Archive không hợp lệ."


    local preview_root="$extract_preview"


    if [[ ! -x "$preview_root/antigravity-ide" ]]; then

        local found=""

        found="$(
            find "$extract_preview" \
                -mindepth 1 \
                -maxdepth 2 \
                -type f \
                -name antigravity-ide \
                -printf '%h\n' 2>/dev/null |
            head -n1 ||
            true
        )"


        if [[ -n "$found" ]]; then

            preview_root="$found"

        fi

    fi


    local latest_version=""

    latest_version="$(
        version_from_dir "$preview_root" ||
        true
    )"


    if [[ -n "$current" &&
          -n "$latest_version" ]]; then


        echo
        echo "Current version: $current"
        echo "Latest version:  $latest_version"


        if compare_versions \
            "$latest_version" \
            "$current"; then


            echo

            read -r -p \
                "Có bản mới. Update Antigravity IDE? [Y/n] " \
                answer


            answer="${answer:-Y}"


            [[ "$answer" =~ ^[Yy]$ ]] ||
            {
                echo "Đã hủy."
                exit 0
            }


        else

            echo
            echo "Antigravity IDE đã là bản mới nhất."

            exit 0

        fi


    elif [[ -z "$current" ]]; then


        echo

        read -r -p \
            "Cài Antigravity IDE? [Y/n] " \
            answer


        answer="${answer:-Y}"


        [[ "$answer" =~ ^[Yy]$ ]] ||
        {
            echo "Đã hủy."
            exit 0
        }


    else


        warn \
            "Không so sánh được version tự động."


        read -r -p \
            "Tiếp tục cài/update artifact này? [y/N] " \
            answer


        [[ "$answer" =~ ^[Yy]$ ]] ||
        {
            echo "Đã hủy."
            exit 0
        }

    fi


    install_archive "$archive"


    echo
    echo "======================================"
    echo "      Antigravity IDE READY"
    echo "======================================"
    echo
    echo "Chạy bằng:"
    echo
    echo "  antigravity-ide"
    echo
}


install_dependencies

run_manager "$@"
