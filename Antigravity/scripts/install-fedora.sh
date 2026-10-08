#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Antigravity IDE"
INSTALL_DIR="/opt/antigravity-ide"
BIN_PATH="/usr/local/bin/antigravity-ide"
DESKTOP_FILE="$HOME/.local/share/applications/antigravity.desktop"
DESKTOP_SHORTCUT="$HOME/Desktop/antigravity.desktop"

RELEASE_URL="https://antigravity.google/releases/"
TMP_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

die() {
    echo "ERROR: $*" >&2
    exit 1
}

log() {
    echo "$*"
}

need_command() {
    command -v "$1" >/dev/null 2>&1
}

install_dependencies() {
    local missing=()

    need_command curl || missing+=("curl")
    need_command tar || missing+=("tar")
    need_command python3 || missing+=("python3")

    if [[ ${#missing[@]} -eq 0 ]]; then
        return
    fi

    echo
    echo "Thiếu dependency: ${missing[*]}"
    echo "Đang cài dependency..."
    echo

    sudo dnf install -y "${missing[@]}"
}

version_from_dir() {
    local dir="$1"
    local version=""

    version="$(
        python3 - "$dir" <<'PY'
import json
import os
import sys

root = sys.argv[1]

files = [
    os.path.join(root, "resources", "app", "package.json"),
    os.path.join(root, "resources", "app", "product.json"),
    os.path.join(root, "resources", "package.json"),
    os.path.join(root, "package.json"),
]

for path in files:
    if not os.path.isfile(path):
        continue

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        for key in ("version", "buildVersion", "productVersion"):
            value = data.get(key)
            if value:
                print(str(value))
                raise SystemExit(0)
    except Exception:
        pass
PY
    )"

    echo "$version"
}

version_from_archive() {
    local archive="$1"
    local temp_dir="$TMP_ROOT/version-check"

    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    tar -xzf "$archive" -C "$temp_dir"

    local root="$temp_dir"

    local dirs=()
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    if [[ ${#dirs[@]} -eq 1 ]]; then
        root="${dirs[0]}"
    fi

    version_from_dir "$root"
}

version_compare() {
    python3 - "$1" "$2" <<'PY'
import re
import sys

a = sys.argv[1].strip()
b = sys.argv[2].strip()

def normalize(v):
    nums = re.findall(r'\d+', v)
    return tuple(int(x) for x in nums)

va = normalize(a)
vb = normalize(b)

if va < vb:
    print("1")
elif va > vb:
    print("2")
else:
    print("0")
PY
}

extract_release_page() {
    local output="$TMP_ROOT/releases.html"

    log "==> Đang lấy trang releases chính thức..." >&2

    curl -fL --retry 3 --retry-delay 1 \
        -A "Mozilla/5.0" \
        "$RELEASE_URL" \
        -o "$output" \
        || die "Không tải được trang releases."

    [[ -s "$output" ]] || die "Trang releases rỗng."

    echo "$output"
}

discover_release() {
    local html="$1"

    python3 - "$html" <<'PY'
import html
import re
import sys
from urllib.parse import urljoin

path = sys.argv[1]

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    raw = f.read()

BASE = "https://antigravity.google/releases/"

def clean_html(s):
    s = re.sub(r'(?is)<script\b.*?</script>', ' ', s)
    s = re.sub(r'(?is)<style\b.*?</style>', ' ', s)
    s = re.sub(r'(?is)<!--.*?-->', ' ', s)
    s = re.sub(r'(?s)<[^>]+>', ' ', s)
    s = html.unescape(s)
    s = re.sub(r'\s+', ' ', s)
    return s.strip()

anchors = []

anchor_re = re.compile(
    r'(?is)<a\b[^>]*href\s*=\s*([\'"])(.*?)\1[^>]*>(.*?)</a>'
)

for m in anchor_re.finditer(raw):
    href = html.unescape(m.group(2)).strip()
    text = clean_html(m.group(3))

    if not href:
        continue

    anchors.append({
        "href": urljoin(BASE, href),
        "text": text,
        "start": m.start(),
        "end": m.end(),
    })

urls = set()

for m in re.finditer(
    r'https?://[^"\'<>\s]+?\.(?:tar\.gz|tgz)(?:\?[^"\'<>\s]*)?',
    raw,
    re.I
):
    urls.add(html.unescape(m.group(0)))

for m in re.finditer(
    r'["\']([^"\']+\.(?:tar\.gz|tgz)(?:\?[^"\']*)?)["\']',
    raw,
    re.I
):
    urls.add(urljoin(BASE, html.unescape(m.group(1))))

for u in urls:
    if not any(a["href"] == u for a in anchors):
        anchors.append({
            "href": u,
            "text": "",
            "start": 0,
            "end": 0,
        })

heading_re = re.compile(
    r'(?is)<(?:h1|h2|h3|h4|h5|h6)\b[^>]*>(.*?)</(?:h1|h2|h3|h4|h5|h6)>'
)

headings = []

for m in heading_re.finditer(raw):
    txt = clean_html(m.group(1))
    if txt:
        headings.append((m.start(), m.end(), txt))

def context_for(pos):
    previous = [h for h in headings if h[0] <= pos]
    if not previous:
        return ""
    return " ".join(h[2] for h in previous[-4:])

def score_candidate(a):
    href = a["href"].lower()
    text = a["text"].lower()
    ctx = context_for(a["start"]).lower()

    blob = f"{href} {text} {ctx}"

    if not re.search(r'\.(?:tar\.gz|tgz)(?:\?|$)', href):
        return -999999

    score = 0

    if "antigravity" in href:
        score += 100

    if "antigravity" in text:
        score += 150

    if "antigravity" in ctx:
        score += 200

    if re.search(r'\bantigravity\s+ide\b', blob):
        score += 300
    elif re.search(r'\bide\b', blob):
        score += 20

    if re.search(r'\blinux\b', blob):
        score += 150

    if re.search(r'\b(x86[_-]?64|amd64|x64)\b', blob):
        score += 150

    if re.search(r'\b(x64|amd64)\b', href):
        score += 100

    if re.search(r'\b(arm64|aarch64|armv7|armhf|arm)\b', blob):
        score -= 1000

    if re.search(r'\b(windows|win32|win64|darwin|macos|mac)\b', blob):
        score -= 1000

    if re.search(r'\b(source|src|debug|symbols)\b', blob):
        score -= 300

    if re.search(r'\d+\.\d+\.\d+', href):
        score += 30

    return score

ranked = []

for a in anchors:
    score = score_candidate(a)

    if score <= -999999:
        continue

    ranked.append((score, a))

ranked.sort(
    key=lambda x: (
        x[0],
        len(x[1]["text"]),
        x[1]["href"],
    ),
    reverse=True
)

if not ranked:
    print(
        "Không tìm thấy archive Linux x64 của Antigravity IDE.",
        file=sys.stderr
    )

    print("", file=sys.stderr)
    print("Các archive tar.gz/tgz tìm được:", file=sys.stderr)

    seen = set()

    for a in anchors:
        u = a["href"]

        if u in seen:
            continue

        seen.add(u)

        if re.search(r'\.(?:tar\.gz|tgz)(?:\?|$)', u, re.I):
            print("  " + u, file=sys.stderr)

    sys.exit(2)

best_score, best = ranked[0]

if best_score < 250:
    print(
        "Không đủ chắc chắn để xác định archive Antigravity IDE.",
        file=sys.stderr
    )

    print("", file=sys.stderr)
    print("Top candidates:", file=sys.stderr)

    for score, a in ranked[:10]:
        print(
            f"  score={score:4d} | "
            f"{a['text'][:80]} | "
            f"{a['href']}",
            file=sys.stderr
        )

    sys.exit(2)

if len(ranked) >= 2:
    second_score = ranked[1][0]

    if best_score == second_score:
        print(
            "Có nhiều archive có cùng độ ưu tiên; không tự đoán.",
            file=sys.stderr
        )

        for score, a in ranked[:10]:
            print(
                f"  score={score:4d} | "
                f"{a['text'][:80]} | "
                f"{a['href']}",
                file=sys.stderr
            )

        sys.exit(2)

# stdout chỉ có URL.
print(best["href"])
PY
}

download_latest() {
    local url="$1"
    local output="$TMP_ROOT/antigravity.tar.gz"

    log "==> Download:"
    log "$url"
    echo

    curl -fL --retry 3 --retry-delay 1 \
        -A "Mozilla/5.0" \
        "$url" \
        -o "$output" \
        || die "Download thất bại."

    [[ -s "$output" ]] || die "File download rỗng."

    echo "$output"
}

installed_version() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo ""
        return
    fi

    version_from_dir "$INSTALL_DIR"
}

confirm() {
    local question="$1"

    read -r -p "$question [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

install_archive() {
    local archive="$1"
    local new_dir="$TMP_ROOT/new-install"

    rm -rf "$new_dir"
    mkdir -p "$new_dir"

    log "==> Giải nén..."

    tar -xzf "$archive" -C "$new_dir"

    local source_dir="$new_dir"

    local dirs=()

    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(
        find "$new_dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0
    )

    if [[ ${#dirs[@]} -eq 1 ]]; then
        source_dir="${dirs[0]}"
    fi

    [[ -x "$source_dir/antigravity-ide" ]] || {
        die "Archive không có executable antigravity-ide."
    }

    local version
    version="$(version_from_dir "$source_dir")"

    [[ -n "$version" ]] || {
        die "Không đọc được version sau khi giải nén."
    }

    log "Archive version: $version"

    local backup="$TMP_ROOT/old-install"

    if [[ -d "$INSTALL_DIR" ]]; then
        log "==> Backup installation hiện tại..."
        sudo mv "$INSTALL_DIR" "$backup"
    fi

    log "==> Cài vào $INSTALL_DIR..."

    sudo mkdir -p "$INSTALL_DIR"
    sudo cp -a "$source_dir"/. "$INSTALL_DIR"/

    if [[ ! -x "$INSTALL_DIR/antigravity-ide" ]]; then
        if [[ -d "$backup" ]]; then
            sudo rm -rf "$INSTALL_DIR"
            sudo mv "$backup" "$INSTALL_DIR"
        fi

        die "Cài đặt thất bại: không tìm thấy executable."
    fi

    if [[ -f "$INSTALL_DIR/chrome-sandbox" ]]; then
        log "==> Fix chrome-sandbox..."

        sudo chown root:root "$INSTALL_DIR/chrome-sandbox"
        sudo chmod 4755 "$INSTALL_DIR/chrome-sandbox"

        # Fedora thường dùng SELinux.
        if command -v restorecon >/dev/null 2>&1; then
            sudo restorecon -v "$INSTALL_DIR/chrome-sandbox" || true
        fi
    else
        echo "WARNING: Không tìm thấy chrome-sandbox." >&2
    fi

    log "==> Tạo command $BIN_PATH..."

    sudo ln -sfn \
        "$INSTALL_DIR/antigravity-ide" \
        "$BIN_PATH"

    create_desktop_entry

    if [[ -d "$backup" ]]; then
        sudo rm -rf "$backup"
    fi

    log
    log "=========================================="
    log "Antigravity IDE đã được cài đặt."
    log "Version: $version"
    log "Command: antigravity-ide"
    log "=========================================="
}

create_desktop_entry() {
    mkdir -p "$(dirname "$DESKTOP_FILE")"

    local icon=""

    for candidate in \
        "$INSTALL_DIR/resources/app/out/media/code-icon.svg" \
        "$INSTALL_DIR/resources/app/resources/linux/code.png" \
        "$INSTALL_DIR/resources/app/resources/linux/code.svg"
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
StartupNotify=true
StartupWMClass=antigravity
EOF

    if [[ -n "$icon" ]]; then
        printf 'Icon=%s\n' "$icon" >> "$DESKTOP_FILE"
    fi

    chmod +x "$DESKTOP_FILE"

    if [[ -d "$HOME/Desktop" ]]; then
        cp -f "$DESKTOP_FILE" "$DESKTOP_SHORTCUT"
        chmod +x "$DESKTOP_SHORTCUT"
    fi
}

main() {
    echo
    echo "=========================================="
    echo "       Antigravity IDE Manager"
    echo "       Fedora / RHEL"
    echo "=========================================="
    echo

    install_dependencies

    local current_version
    current_version="$(installed_version)"

    if [[ -n "$current_version" ]]; then
        echo "Installed version: $current_version"
    else
        echo "Antigravity IDE: CHƯA CÀI"
    fi

    echo

    local html
    html="$(extract_release_page)"

    echo "==> Đang tìm Antigravity IDE Linux x64..."
    local latest_url

    if ! latest_url="$(discover_release "$html")"; then
        echo
        echo "Không thể xác định chính xác file tải Antigravity IDE."
        echo "Script đã dừng để tránh tải nhầm sản phẩm."
        exit 1
    fi

    echo
    echo "Latest artifact:"
    echo "$latest_url"
    echo

    local archive
    archive="$(download_latest "$latest_url")"

    echo "==> Đang xác định version mới nhất..."

    local latest_version
    latest_version="$(version_from_archive "$archive")"

    [[ -n "$latest_version" ]] || {
        die "Không đọc được version từ archive."
    }

    echo "Latest version:    $latest_version"

    if [[ -n "$current_version" ]]; then
        echo

        local comparison
        comparison="$(version_compare "$current_version" "$latest_version")"

        case "$comparison" in
            0)
                echo "Bạn đang dùng phiên bản mới nhất."
                exit 0
                ;;

            2)
                echo "Phiên bản đang cài mới hơn artifact trên releases."
                echo "Không thực hiện downgrade."
                exit 0
                ;;

            1)
                echo "Có phiên bản mới."
                echo
                echo "Installed: $current_version"
                echo "Latest:    $latest_version"
                echo

                if ! confirm "Bạn có muốn update không?"; then
                    echo "Đã hủy."
                    exit 0
                fi
                ;;
        esac
    else
        echo

        if ! confirm "Antigravity IDE chưa được cài. Cài phiên bản $latest_version không?"; then
            echo "Đã hủy."
            exit 0
        fi
    fi

    echo
    install_archive "$archive"
}

main "$@"
