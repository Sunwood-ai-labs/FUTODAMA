FROM lscr.io/linuxserver/webtop:ubuntu-xfce

COPY assets/renji-onizuka-wallpaper.png /defaults/wallpapers/renji-onizuka-wallpaper.png

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    ffmpeg \
    openssh-server \
    curl \
    make \
    g++ \
    cmake \
    python3 \
    gh \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (for Claude Code and Codex)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list

# Install Antigravity Desktop App
RUN mkdir -p /etc/apt/keyrings \
    && wget -q -O - https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list

RUN apt-get update && apt-get install -y \
    google-chrome-stable \
    antigravity \
    && rm -rf /var/lib/apt/lists/*

# Allow the "Background" extension to patch VS Code/Antigravity workbench assets without sudo.
RUN for f in \
      /usr/share/antigravity/resources/app/out/vs/workbench/workbench.desktop.main.js \
      /usr/share/antigravity/resources/app/out/vs/workbench/workbench.desktop.main.css \
      /usr/share/antigravity/resources/app/out/vs/workbench/workbench.web.main.css; do \
      if [ -f "$f" ]; then chown abc:abc "$f" && chmod u+rw "$f"; fi; \
    done

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install OpenAI Codex CLI
RUN npm install -g @openai/codex

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Install Kimi Code CLI in a shared location (avoid /config bind-mount and /root permission issues)
RUN export HOME=/opt/kimi-home \
    && mkdir -p "$HOME" \
    && curl -fsSL https://code.kimi.com/install.sh | bash \
    && chmod -R a+rX /opt/kimi-home \
    && for bin in kimi kimi-cli; do \
      if [ -x "/opt/kimi-home/.local/bin/$bin" ]; then ln -sf "/opt/kimi-home/.local/bin/$bin" "/usr/local/bin/$bin"; fi; \
    done

# Install OpenClaw CLI
RUN SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest

# Wrapper for container environments where `openclaw gateway restart` may rely on systemd user services.
RUN cat <<'EOF' > /usr/local/bin/openclaw
#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_REAL=/usr/bin/openclaw

fallback_gateway_restart() {
  local log_file="${OPENCLAW_GATEWAY_LOG_FILE:-/config/.openclaw/gateway.log}"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

  # Stop existing foreground/background gateway run processes if present.
  if pgrep -f 'openclaw .*gateway run' >/dev/null 2>&1; then
    pkill -f 'openclaw .*gateway run' >/dev/null 2>&1 || true
    sleep 1
  fi

  nohup "$OPENCLAW_REAL" gateway run --allow-unconfigured >>"$log_file" 2>&1 &
  sleep 2

  if "$OPENCLAW_REAL" gateway health >/dev/null 2>&1; then
    echo "Gateway restarted via container fallback (systemctl --user unavailable)." >&2
    return 0
  fi

  echo "Gateway fallback restart could not confirm health. Check $log_file" >&2
  return 1
}

if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "restart" ]; then
  if "$OPENCLAW_REAL" "$@"; then
    exit 0
  fi
  echo "openclaw gateway restart failed; trying container fallback..." >&2
  fallback_gateway_restart
  exit $?
fi

exec "$OPENCLAW_REAL" "$@"
EOF
RUN chmod +x /usr/local/bin/openclaw

# Install terminal monitoring tools
RUN apt-get update && apt-get install -y \
    nmon \
    && rm -rf /var/lib/apt/lists/*

# Launcher for container environments where Chromium sandbox namespaces are restricted.
RUN printf '#!/usr/bin/env bash\nexport BROWSER=/usr/local/bin/google-chrome-launch\nexport GTK_USE_PORTAL=0\nexec antigravity --no-sandbox "$@"\n' > /usr/local/bin/antigravity-launch \
    && chmod +x /usr/local/bin/antigravity-launch

# Chrome launcher with --no-sandbox for container environments
RUN printf '#!/usr/bin/env bash\nexec /usr/bin/google-chrome-stable --no-sandbox --disable-gpu --download.default_directory=/config/Downloads "$@"\n' > /usr/local/bin/google-chrome-launch \
    && chmod +x /usr/local/bin/google-chrome-launch

# Prefer Chrome directly for URL opens from Electron/desktop helpers in container desktops.
RUN cat <<'EOF' > /usr/local/bin/desktop-url-open
#!/usr/bin/env bash
set -e

LOG_FILE=/tmp/url-open-wrapper.log

log() {
  printf '%s %s %s\n' "$(date -Iseconds)" "$1" "$2" >> "$LOG_FILE" || true
}

if [ "$#" -eq 0 ]; then
  exit 1
fi

case "$1" in
  http://*|https://*)
    log "direct" "$*"
    exec /usr/local/bin/google-chrome-launch --new-window "$@"
    ;;
esac

if [ "$1" = "--launch" ] && [ "${2:-}" = "WebBrowser" ] && [ "${3:-}" != "" ]; then
  case "$3" in
    http://*|https://*)
      log "exo-open" "$*"
      exec /usr/local/bin/google-chrome-launch --new-window "$3"
      ;;
  esac
fi

if [ "$1" = "open" ] && [ "${2:-}" != "" ]; then
  case "$2" in
    http://*|https://*)
      log "gio-open" "$*"
      exec /usr/local/bin/google-chrome-launch --new-window "$2"
      ;;
  esac
fi

exit 2
EOF
RUN chmod +x /usr/local/bin/desktop-url-open

RUN if [ -x /usr/bin/xdg-open ] && [ ! -e /usr/bin/xdg-open.real ]; then mv /usr/bin/xdg-open /usr/bin/xdg-open.real; fi \
    && cat <<'EOF' > /usr/bin/xdg-open
#!/usr/bin/env bash
set -e
/usr/local/bin/desktop-url-open "$@" && exit 0 || rc=$?
if [ "${rc:-0}" -ne 2 ]; then
  exit "${rc:-1}"
fi
exec /usr/bin/xdg-open.real "$@"
EOF
RUN chmod +x /usr/bin/xdg-open

RUN if [ -x /usr/bin/exo-open ] && [ ! -e /usr/bin/exo-open.real ]; then mv /usr/bin/exo-open /usr/bin/exo-open.real; fi \
    && cat <<'EOF' > /usr/bin/exo-open
#!/usr/bin/env bash
set -e
/usr/local/bin/desktop-url-open "$@" && exit 0 || rc=$?
if [ "${rc:-0}" -ne 2 ]; then
  exit "${rc:-1}"
fi
exec /usr/bin/exo-open.real "$@"
EOF
RUN chmod +x /usr/bin/exo-open

RUN if [ -x /usr/bin/gio ] && [ ! -e /usr/bin/gio.real ]; then mv /usr/bin/gio /usr/bin/gio.real; fi \
    && cat <<'EOF' > /usr/bin/gio
#!/usr/bin/env bash
set -e
/usr/local/bin/desktop-url-open "$@" && exit 0 || rc=$?
if [ "${rc:-0}" -ne 2 ]; then
  exit "${rc:-1}"
fi
exec /usr/bin/gio.real "$@"
EOF
RUN chmod +x /usr/bin/gio

# Override /usr/bin/google-chrome to always use --no-sandbox and download directory (for Antigravity)
RUN mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real \
    && printf '#!/usr/bin/env bash\nexec /usr/bin/google-chrome-stable.real --no-sandbox --download.default_directory=/config/Downloads "$@"\n' > /usr/bin/google-chrome-stable \
    && chmod +x /usr/bin/google-chrome-stable \
    && ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome

# Override system google-chrome.desktop to use --no-sandbox (for xdg-open/Antigravity)
RUN sed -i 's|Exec=/usr/bin/google-chrome-stable|Exec=/usr/local/bin/google-chrome-launch|g' /usr/share/applications/google-chrome.desktop

# Override XFCE helper to use the launcher wrapper (exo-open uses this)
RUN sed -i 's|X-XFCE-Binaries=google-chrome;google-chrome-stable;com.google.Chrome;|X-XFCE-Binaries=google-chrome-launch;|g' /usr/share/xfce4/helpers/google-chrome.desktop \
    && sed -i 's|X-XFCE-Commands=%B;|X-XFCE-Commands=/usr/local/bin/google-chrome-launch;|g' /usr/share/xfce4/helpers/google-chrome.desktop \
    && sed -i 's|X-XFCE-CommandsWithParameter=%B "%s";|X-XFCE-CommandsWithParameter=/usr/local/bin/google-chrome-launch "%s";|g' /usr/share/xfce4/helpers/google-chrome.desktop

# Helper to apply a user wallpaper to all XFCE workspaces/monitors.
RUN cat <<'EOF' > /usr/local/bin/apply-user-wallpaper
#!/usr/bin/env bash
set -e

WALLPAPER_PATH="${1:-/config/Desktop/renji-onizuka-wallpaper.png}"

if [ ! -f "$WALLPAPER_PATH" ]; then
  exit 0
fi

export HOME="${HOME:-/config}"
export DISPLAY="${DISPLAY:-:1}"

# Wait for xfconf/xfdesktop to be available after session start.
for _ in $(seq 1 30); do
  if xfconf-query -c xfce4-desktop -lv >/tmp/.xfce4-desktop-query.log 2>&1; then
    break
  fi
  sleep 1
done

xfconf-query -c xfce4-desktop -lv | while IFS= read -r line; do
  p="${line%% *}"
  case "$line" in
    *"/last-image"*) xfconf-query -c xfce4-desktop -p "$p" -s "$WALLPAPER_PATH" ;;
    *"/image-style"*) xfconf-query -c xfce4-desktop -p "$p" -s 5 ;;
    *"/color-style"*) xfconf-query -c xfce4-desktop -p "$p" -s 3 ;;
  esac
done

xfdesktop --reload >/dev/null 2>&1 || true
EOF
RUN chmod +x /usr/local/bin/apply-user-wallpaper

# Ensure /defaults/pid exists so selkies backend can finish initialization.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/05-selkies-touch-pid.sh
#!/usr/bin/with-contenv bash
set -e

echo "Applying selkies init fix: creating /defaults/pid..."
touch /defaults/pid
chown abc:abc /defaults/pid || true
EOF
RUN chmod +x /custom-cont-init.d/05-selkies-touch-pid.sh

# Clean stale Chrome singleton locks in persisted profiles after container recreation.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/25-chrome-profile-cleanup.sh
#!/usr/bin/with-contenv bash
set -e

cleanup_profile() {
  local profile_dir="$1"

  if [ ! -d "$profile_dir" ]; then
    return 0
  fi

  rm -f \
    "$profile_dir/SingletonLock" \
    "$profile_dir/SingletonCookie" \
    "$profile_dir/SingletonSocket"

  find "$profile_dir" -maxdepth 1 -type d -name '.org.chromium.Chromium.*' -exec rm -rf {} + 2>/dev/null || true

  mkdir -p "$profile_dir/Crash Reports/pending"
  find "$profile_dir/Crash Reports/pending" -maxdepth 1 -type f -name '*.lock' -delete 2>/dev/null || true
}

# Default Chrome profile used by desktop launches.
cleanup_profile "/config/.config/google-chrome"

# Antigravity browser-launcher extension profile (remote debugging / onboarding flow).
cleanup_profile "/config/.gemini/antigravity-browser-profile"
EOF
RUN chmod +x /custom-cont-init.d/25-chrome-profile-cleanup.sh

# linuxserver.io remaps the abc user at container start (PUID/PGID), so file ownership
# must be fixed at runtime for extensions that patch app assets (e.g. Background).
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/26-antigravity-workbench-perms.sh
#!/usr/bin/with-contenv bash
set -e

for f in \
  /usr/share/antigravity/resources/app/out/vs/workbench/workbench.desktop.main.js \
  /usr/share/antigravity/resources/app/out/vs/workbench/workbench.desktop.main.css \
  /usr/share/antigravity/resources/app/out/vs/workbench/workbench.web.main.css
do
  if [ -f "$f" ]; then
    chown abc:abc "$f" || true
    chmod u+rw "$f" || true
  fi
done
EOF
RUN chmod +x /custom-cont-init.d/26-antigravity-workbench-perms.sh

# Persist a wallpaper autostart that reapplies the user's chosen image on every session start.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/27-wallpaper-autostart.sh
#!/usr/bin/with-contenv bash
set -e

DESKTOP_DIR="/config/Desktop"
AUTOSTART_DIR="/config/.config/autostart"
LEGACY_WALLPAPER="/config/Desktop/hf_20260223_060813_2111db02-ba1e-4cd0-ad9c-9db0c0129769.png"
WALLPAPER="/config/Desktop/renji-onizuka-wallpaper.png"
DEFAULT_WALLPAPER="/defaults/wallpapers/renji-onizuka-wallpaper.png"

mkdir -p "$DESKTOP_DIR" "$AUTOSTART_DIR"

# Normalize the generated filename to a stable name (one-time migration).
if [ ! -f "$WALLPAPER" ] && [ -f "$LEGACY_WALLPAPER" ]; then
  mv "$LEGACY_WALLPAPER" "$WALLPAPER"
fi

# Seed the configured wallpaper into persisted /config on first start.
if [ ! -f "$WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
  cp "$DEFAULT_WALLPAPER" "$WALLPAPER"
fi

cat > "$AUTOSTART_DIR/renji-wallpaper.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Renji Wallpaper
Comment=Apply Renji Onizuka wallpaper on login
Exec=/bin/bash -lc '/usr/local/bin/apply-user-wallpaper "$WALLPAPER"'
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
Terminal=false
Hidden=false
DESKTOP

chown abc:abc "$AUTOSTART_DIR/renji-wallpaper.desktop" || true
chmod 644 "$AUTOSTART_DIR/renji-wallpaper.desktop" || true
if [ -f "$WALLPAPER" ]; then
  chown abc:abc "$WALLPAPER" || true
  chmod 644 "$WALLPAPER" || true
fi
EOF
RUN chmod +x /custom-cont-init.d/27-wallpaper-autostart.sh

# Repair persisted OpenClaw config ownership after accidental root runs.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/28-openclaw-config-perms.sh
#!/usr/bin/with-contenv bash
set -e

OPENCLAW_DIR="/config/.openclaw"

mkdir -p "$OPENCLAW_DIR"
chown -R abc:abc "$OPENCLAW_DIR" || true
chmod u+rwX "$OPENCLAW_DIR" || true
EOF
RUN chmod +x /custom-cont-init.d/28-openclaw-config-perms.sh

# systemd user services are unavailable in this container, so start OpenClaw
# Gateway via custom init in the background when enabled.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/29-openclaw-gateway-autostart.sh
#!/usr/bin/with-contenv bash
set -e

: "${OPENCLAW_GATEWAY_AUTOSTART:=1}"

if [ "$OPENCLAW_GATEWAY_AUTOSTART" = "0" ]; then
  echo "[openclaw] autostart disabled (OPENCLAW_GATEWAY_AUTOSTART=0)"
  exit 0
fi

mkdir -p /config/.openclaw
chown -R abc:abc /config/.openclaw || true

if s6-setuidgid abc openclaw gateway health >/dev/null 2>&1; then
  echo "[openclaw] gateway already healthy; skipping autostart"
  exit 0
fi

if pgrep -u abc -f 'openclaw .*gateway run' >/dev/null 2>&1; then
  echo "[openclaw] gateway process already running; skipping autostart"
  exit 0
fi

LOG_FILE="/config/.openclaw/gateway.log"
touch "$LOG_FILE"
chown abc:abc "$LOG_FILE" || true

echo "[openclaw] starting gateway in background"
nohup s6-setuidgid abc openclaw gateway run --allow-unconfigured >>"$LOG_FILE" 2>&1 &
EOF
RUN chmod +x /custom-cont-init.d/29-openclaw-gateway-autostart.sh

# Ensure desktop shortcuts appear for existing /config volumes as well.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/30-desktop-shortcuts.sh
#!/usr/bin/with-contenv bash
set -e
DESKTOP_DIR=/config/Desktop
mkdir -p "$DESKTOP_DIR"

if [ ! -f "$DESKTOP_DIR/antigravity.desktop" ]; then
  cp /defaults/Desktop/antigravity.desktop "$DESKTOP_DIR/antigravity.desktop"
fi

if [ ! -f "$DESKTOP_DIR/google-chrome.desktop" ]; then
  cp /defaults/Desktop/google-chrome.desktop "$DESKTOP_DIR/google-chrome.desktop"
fi

if [ ! -f "$DESKTOP_DIR/claude-code.desktop" ]; then
  cp /defaults/Desktop/claude-code.desktop "$DESKTOP_DIR/claude-code.desktop"
fi

if [ ! -f "$DESKTOP_DIR/codex.desktop" ]; then
  cp /defaults/Desktop/codex.desktop "$DESKTOP_DIR/codex.desktop"
fi

if [ ! -f "$DESKTOP_DIR/openclaw.desktop" ]; then
  cp /defaults/Desktop/openclaw.desktop "$DESKTOP_DIR/openclaw.desktop"
fi

for launcher in "$DESKTOP_DIR/antigravity.desktop" "$DESKTOP_DIR/google-chrome.desktop" "$DESKTOP_DIR/claude-code.desktop" "$DESKTOP_DIR/codex.desktop" "$DESKTOP_DIR/openclaw.desktop"; do
  if [ -f "$launcher" ]; then
    chown abc:abc "$launcher"
    chmod 755 "$launcher"
    if command -v s6-setuidgid >/dev/null 2>&1 && command -v gio >/dev/null 2>&1; then
      s6-setuidgid abc gio set "$launcher" metadata::trusted true >/dev/null 2>&1 || true
    fi
  fi
done
EOF
RUN chmod +x /custom-cont-init.d/30-desktop-shortcuts.sh

# Autostart a user-provided Python script from the persisted /config volume.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/31-python-autostart.sh
#!/usr/bin/with-contenv bash
set -euo pipefail

: "${PYTHON_AUTOSTART_ENABLE:=0}"
: "${PYTHON_AUTOSTART_SCRIPT:=}"
: "${PYTHON_AUTOSTART_PYTHON:=python3}"
: "${PYTHON_AUTOSTART_CWD:=/config}"
: "${PYTHON_AUTOSTART_DELAY_SEC:=0}"
: "${PYTHON_AUTOSTART_LOG:=/config/.local/state/futodama/python-autostart.log}"
: "${PYTHON_AUTOSTART_PID_FILE:=/config/.local/state/futodama/python-autostart.pid}"

if [ "$PYTHON_AUTOSTART_ENABLE" = "0" ] || [ -z "$PYTHON_AUTOSTART_SCRIPT" ]; then
  exit 0
fi

if [ ! -f "$PYTHON_AUTOSTART_SCRIPT" ]; then
  echo "[python-autostart] script not found: $PYTHON_AUTOSTART_SCRIPT"
  exit 0
fi

if [ ! -d "$PYTHON_AUTOSTART_CWD" ]; then
  echo "[python-autostart] cwd not found: $PYTHON_AUTOSTART_CWD"
  exit 0
fi

mkdir -p "$(dirname "$PYTHON_AUTOSTART_LOG")" "$(dirname "$PYTHON_AUTOSTART_PID_FILE")" || true
touch "$PYTHON_AUTOSTART_LOG"
chown -R abc:abc "$(dirname "$PYTHON_AUTOSTART_LOG")" "$(dirname "$PYTHON_AUTOSTART_PID_FILE")" || true

if [ -f "$PYTHON_AUTOSTART_PID_FILE" ]; then
  pid="$(cat "$PYTHON_AUTOSTART_PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
    echo "[python-autostart] already running (pid=$pid); skipping"
    exit 0
  fi
fi

if ! command -v s6-setuidgid >/dev/null 2>&1; then
  echo "[python-autostart] s6-setuidgid not available; skipping"
  exit 0
fi

if [ "$PYTHON_AUTOSTART_DELAY_SEC" != "0" ]; then
  echo "[python-autostart] waiting ${PYTHON_AUTOSTART_DELAY_SEC}s before start"
  sleep "$PYTHON_AUTOSTART_DELAY_SEC"
fi

echo "[python-autostart] starting: $PYTHON_AUTOSTART_PYTHON $PYTHON_AUTOSTART_SCRIPT"
nohup s6-setuidgid abc bash -lc "cd \"\$1\" && exec env HOME=/config \"\$2\" \"\$3\"" -- \
  "$PYTHON_AUTOSTART_CWD" "$PYTHON_AUTOSTART_PYTHON" "$PYTHON_AUTOSTART_SCRIPT" >>"$PYTHON_AUTOSTART_LOG" 2>&1 &
echo "$!" > "$PYTHON_AUTOSTART_PID_FILE"
chown abc:abc "$PYTHON_AUTOSTART_PID_FILE" || true
EOF
RUN chmod +x /custom-cont-init.d/31-python-autostart.sh

# Enable persisted user-defined s6 services from /config/s6-services.
RUN mkdir -p /custom-cont-init.d \
    && cat <<'EOF' > /custom-cont-init.d/32-s6-user-services.sh
#!/usr/bin/with-contenv bash
set -euo pipefail

: "${S6_USER_SERVICES_ENABLE:=1}"
: "${S6_USER_SERVICES_DIR:=/config/s6-services}"
: "${S6_SCAN_DIR:=/run/service}"

if [ "$S6_USER_SERVICES_ENABLE" = "0" ]; then
  echo "[s6-user-services] disabled (S6_USER_SERVICES_ENABLE=0)"
  exit 0
fi

mkdir -p "$S6_USER_SERVICES_DIR"
chown -R abc:abc "$S6_USER_SERVICES_DIR" || true

if [ ! -d "$S6_SCAN_DIR" ]; then
  echo "[s6-user-services] scan dir not found: $S6_SCAN_DIR"
  exit 0
fi

added=0

for svc_dir in "$S6_USER_SERVICES_DIR"/*; do
  if [ ! -d "$svc_dir" ]; then
    continue
  fi

  name="$(basename "$svc_dir")"
  run_file="$svc_dir/run"
  target="$S6_SCAN_DIR/$name"

  if [ ! -f "$run_file" ]; then
    echo "[s6-user-services] skipping $name (missing run file)"
    continue
  fi

  chmod +x "$run_file" 2>/dev/null || true

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ] && [ "$(readlink -f "$target" 2>/dev/null || true)" = "$(readlink -f "$svc_dir" 2>/dev/null || true)" ]; then
      continue
    fi
    echo "[s6-user-services] skipping $name (target exists: $target)"
    continue
  fi

  ln -s "$svc_dir" "$target"
  echo "[s6-user-services] enabled $name -> $svc_dir"
  added=1
done

if [ "$added" = "1" ] && command -v s6-svscanctl >/dev/null 2>&1; then
  s6-svscanctl -a "$S6_SCAN_DIR" >/dev/null 2>&1 || true
fi
EOF
RUN chmod +x /custom-cont-init.d/32-s6-user-services.sh

# Set Google Chrome as default browser for abc user in the persisted /config profile.
RUN cat <<'EOF' > /custom-cont-init.d/40-default-browser-chrome.sh
#!/usr/bin/with-contenv bash
set -e

if ! command -v s6-setuidgid >/dev/null 2>&1; then
  exit 0
fi

s6-setuidgid abc bash -lc '
  export HOME=/config
  xdg-settings set default-web-browser google-chrome.desktop
  xdg-mime default google-chrome.desktop x-scheme-handler/http
  xdg-mime default google-chrome.desktop x-scheme-handler/https
  xdg-mime default google-chrome.desktop text/html
'
EOF
RUN chmod +x /custom-cont-init.d/40-default-browser-chrome.sh

# Prepare Desktop Shortcuts templates
RUN mkdir -p /defaults/Desktop \
    && echo '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Antigravity\nComment=Google Antigravity\nExec=/usr/local/bin/antigravity-launch\nIcon=antigravity\nCategories=Development;IDE;' > /defaults/Desktop/antigravity.desktop \
    && echo '[Desktop Entry]\nVersion=1.0\nName=Google Chrome\nGenericName=Web Browser\nComment=Access the Internet\nExec=/usr/local/bin/google-chrome-launch %U\nStartupNotify=true\nTerminal=false\nIcon=google-chrome\nType=Application\nCategories=Network;WebBrowser;\nMimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;' > /defaults/Desktop/google-chrome.desktop \
    && echo '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Claude Code\nComment=Anthropic Claude Code CLI\nExec=xfce4-terminal -e "claude"\nIcon=utilities-terminal\nCategories=Development;ConsoleOnly;' > /defaults/Desktop/claude-code.desktop \
    && echo '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Codex\nComment=OpenAI Codex CLI\nExec=xfce4-terminal -e "codex"\nIcon=utilities-terminal\nCategories=Development;ConsoleOnly;' > /defaults/Desktop/codex.desktop \
    && echo '[Desktop Entry]\nVersion=1.0\nType=Application\nName=OpenClaw\nComment=OpenClaw CLI\nExec=xfce4-terminal -e "openclaw"\nIcon=utilities-terminal\nCategories=Development;ConsoleOnly;' > /defaults/Desktop/openclaw.desktop

# SSH server setup
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SSH init script for s6-overlay
RUN cat <<'EOF' > /custom-cont-init.d/10-sshd-setup.sh
#!/usr/bin/with-contenv bash
set -e

SSH_DIR="/config/ssh"
USER_SSH_DIR="/config/.ssh"

# Setup persistent host keys
mkdir -p "$SSH_DIR"
if [ ! -f "$SSH_DIR/ssh_host_rsa_key" ]; then
  ssh-keygen -A
  cp /etc/ssh/ssh_host_* "$SSH_DIR/"
  echo "Generated new SSH host keys in $SSH_DIR"
else
  cp "$SSH_DIR"/ssh_host_* /etc/ssh/
  echo "Restored SSH host keys from $SSH_DIR"
fi

# Ensure SSH run directory exists
mkdir -p /var/run/sshd

# Set password for abc user (same as CUSTOM_USER password)
if [ -n "$PASSWORD" ]; then
  echo "abc:$PASSWORD" | chpasswd
fi

# Setup user SSH directory
mkdir -p "$USER_SSH_DIR"
chown abc:abc "$USER_SSH_DIR"
chmod 700 "$USER_SSH_DIR"

# Generate keypair if not exists
if [ ! -f "$USER_SSH_DIR/id_ed25519" ]; then
  echo "Generating new SSH keypair for abc user..."
  s6-setuidgid abc ssh-keygen -t ed25519 -f "$USER_SSH_DIR/id_ed25519" -N "" -C "abc@webtop"
  echo "Generated: $USER_SSH_DIR/id_ed25519"
fi

# Setup authorized_keys (append generated pubkey if missing)
if [ ! -f "$USER_SSH_DIR/authorized_keys" ]; then
  s6-setuidgid abc touch "$USER_SSH_DIR/authorized_keys"
fi

PUBKEY=$(cat "$USER_SSH_DIR/id_ed25519.pub")
if ! grep -q "$PUBKEY" "$USER_SSH_DIR/authorized_keys" 2>/dev/null; then
  echo "$PUBKEY" >> "$USER_SSH_DIR/authorized_keys"
  s6-setuidgid abc chmod 600 "$USER_SSH_DIR/authorized_keys"
  echo "Added generated pubkey to authorized_keys"
fi

# Ensure correct permissions
s6-setuidgid abc chmod 700 "$USER_SSH_DIR"
s6-setuidgid abc chmod 600 "$USER_SSH_DIR/id_ed25519" "$USER_SSH_DIR/authorized_keys"
s6-setuidgid abc chmod 644 "$USER_SSH_DIR/id_ed25519.pub"

echo "SSH server configured successfully"
echo "Private key: $USER_SSH_DIR/id_ed25519"
echo "Public key:  $USER_SSH_DIR/id_ed25519.pub"

# Setup colorful bashrc for SSH sessions
BASHRC_FILE="/config/.bashrc"
if ! grep -q "# FUTODAMA Color Settings" "$BASHRC_FILE" 2>/dev/null; then
  cat >> "$BASHRC_FILE" << 'BASHRC'
# FUTODAMA Color Settings
export TERM=xterm-256color

# Colorful PS1 prompt
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Enable ls colors
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Enable grep colors
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# dircolors
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi
BASHRC
  echo "Added color settings to $BASHRC_FILE"
fi

# Ensure .profile sources .bashrc for SSH login shells
PROFILE_FILE="/config/.profile"
if ! grep -q "\. ~/.bashrc" "$PROFILE_FILE" 2>/dev/null; then
  echo 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' >> "$PROFILE_FILE"
  echo "Added bashrc source to $PROFILE_FILE"
fi
EOF
RUN chmod +x /custom-cont-init.d/10-sshd-setup.sh

# SSH service definition for s6-overlay
RUN mkdir -p /etc/s6-overlay/s6-rc.d/sshd \
    && echo "longrun" > /etc/s6-overlay/s6-rc.d/sshd/type \
    && cat <<'EOF' > /etc/s6-overlay/s6-rc.d/sshd/run
#!/usr/bin/with-contenv bash
exec /usr/sbin/sshd -D -e
EOF
RUN chmod +x /etc/s6-overlay/s6-rc.d/sshd/run \
    && mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd

# Finalize labels
LABEL maintainer="FUTODAMA"
LABEL description="Fully Unified Tooling and Orchestration for Desktop Agent Machine Architecture"
