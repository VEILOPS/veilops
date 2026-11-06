#!/usr/bin/env bash
# ============================================================================
#  VEILOPS 官方安装脚本（Linux / macOS，无需 Docker）
#  用法：
#     curl -fsSL https://<你的地址>/install.sh | bash
#  可选环境变量：
#     VEILOPS_DIR     安装目录（默认 /opt/veilops，非 root 时默认 ~/veilops）
#     VEILOPS_PORT    服务端口（默认 8080）
#     VEILOPS_BASE    下载源地址（默认见下方 BASE_URL）
# ============================================================================
set -euo pipefail

VERSION="v1.0.0"
BASE_URL="${VEILOPS_BASE:-https://github.com/VEILOPS/veilops/releases/download/v1.0.0}"
PORT="${VEILOPS_PORT:-8080}"

c_info() { printf '\033[36m[veilops]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[32m[  ok  ]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m[ fail ]\033[0m %s\n' "$*" >&2; }

# ---------- 1. 环境判断 ----------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux)  PKG="linux-amd64" ;;
  darwin) PKG="darwin-amd64" ;;
  *) c_err "暂不支持的系统：$OS（Windows 请用 install.ps1）"; exit 1 ;;
esac

if [ "$(id -u)" = "0" ]; then
  APP_DIR="${VEILOPS_DIR:-/opt/veilops}"
  ROOT_INSTALL=1
else
  APP_DIR="${VEILOPS_DIR:-$HOME/veilops}"
  ROOT_INSTALL=0
fi

ARCHIVE="veilops-${VERSION}-${PKG}.tar.gz"
URL="${BASE_URL%/}/${ARCHIVE}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- 2. 下载 ----------
c_info "下载 ${ARCHIVE}"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$TMP/$ARCHIVE" "$URL"
else
  wget -O "$TMP/$ARCHIVE" "$URL"
fi
c_ok "下载完成（$(du -h "$TMP/$ARCHIVE" | cut -f1)）"

# ---------- 3. 校验（有 SHA256SUMS 才校验）----------
if command -v curl >/dev/null 2>&1; then
  if curl -fsL -o "$TMP/SHA256SUMS" "${BASE_URL%/}/SHA256SUMS" 2>/dev/null; then
    ( cd "$TMP" && grep " $ARCHIVE\$" SHA256SUMS | sha256sum -c - ) && c_ok "校验和通过"
  fi
fi

# ---------- 4. 解压 ----------
c_info "安装到 $APP_DIR"
mkdir -p "$APP_DIR"
tar xzf "$TMP/$ARCHIVE" -C "$APP_DIR" --strip-components=1
chmod +x "$APP_DIR/veilops"

# ---------- 5. 首次配置 ----------
if [ ! -s "$APP_DIR/config.yaml" ]; then
  cp "$APP_DIR/config.example.yaml" "$APP_DIR/config.yaml"
  sed -i.bak -E "s/^([[:space:]]*)tls_enabled:[[:space:]]*true/\1tls_enabled: false/" "$APP_DIR/config.yaml"
  sed -i.bak -E "s/^([[:space:]]*)host:[[:space:]]*.*/\1host: 0.0.0.0/" "$APP_DIR/config.yaml"
  sed -i.bak -E "s/^([[:space:]]*)port:[[:space:]]*8080/\1port: ${PORT}/" "$APP_DIR/config.yaml"
  rm -f "$APP_DIR/config.yaml.bak"
  chmod 600 "$APP_DIR/config.yaml"
  c_ok "已生成默认配置 config.yaml"
fi
mkdir -p "$APP_DIR/data" "$APP_DIR/log" "$APP_DIR/tmp" "$APP_DIR/chat_uploads"

# ---------- 6. 启动 ----------
if [ "$ROOT_INSTALL" = "1" ] && command -v systemctl >/dev/null 2>&1; then
  cat > /etc/systemd/system/veilops.service <<EOF
[Unit]
Description=VEILOPS AI Security Console
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/veilops -config $APP_DIR/config.yaml --http
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable veilops >/dev/null 2>&1 || true
  systemctl restart veilops
  sleep 3
  if systemctl is-active --quiet veilops; then
    c_ok "systemd 服务已启动：veilops"
    PW="$(journalctl -u veilops --no-pager | grep -A2 'ADMIN SETUP' | grep -i password | head -1 | awk '{print $2}')"
    LOGCMD="journalctl -u veilops --no-pager | grep -A3 'ADMIN SETUP'"
    MGMT="systemctl status veilops / systemctl restart veilops"
  else
    c_err "服务启动失败，执行 journalctl -u veilops -n 80 查看"
    exit 1
  fi
else
  cd "$APP_DIR"
  nohup ./veilops -config "$APP_DIR/config.yaml" --http > "$APP_DIR/log/veilops.out" 2>&1 &
  echo $! > "$APP_DIR/veilops.pid"
  sleep 5
  PW="$(grep -A2 'ADMIN SETUP' "$APP_DIR/log/veilops.out" | grep -i password | head -1 | awk '{print $2}')"
  LOGCMD="tail -f $APP_DIR/log/veilops.out"
  MGMT="kill \$(cat $APP_DIR/veilops.pid) 然后重新执行 nohup 命令"
  c_ok "已在后台启动（pid $(cat "$APP_DIR/veilops.pid")）"
fi

# ---------- 7. 输出 ----------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "${IP:-}" ] && IP="127.0.0.1"

echo
c_ok "VEILOPS ${VERSION} 安装完成"
echo "   访问地址 : http://${IP}:${PORT}/"
echo "   安装目录 : ${APP_DIR}"
echo "   用户名   : admin"
if [ -n "${PW:-}" ]; then
  echo "   初始密码 : ${PW}   ← 只显示这一次，请立即保存并修改"
else
  echo "   初始密码 : 见日志  $LOGCMD"
fi
echo
echo "   查看日志 : $LOGCMD"
echo "   服务管理 : $MGMT"
echo
echo "   ⚠ 首次登录后请立刻改密码，并在「设置 → 基本设置」里填写你自己的模型 API Key。"
