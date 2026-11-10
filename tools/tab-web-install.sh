# Runs as root on the tablet: web server stack (files pushed to /tmp/archpad-web.tgz by tools/push-web.sh).
#  - Caddy on port 80: the React site from /srv/web/app/client/dist, /api/* to the Node app on 127.0.0.1:3000
#  - SQLite through Node's built-in node:sqlite (data in /srv/web/app/data); no database server: PostgreSQL
#    and MongoDB need System V shared memory, which this kernel lacks
#  - Node/Express app (archpad-web-app.service, user "web"): a starter site in /srv/web/app
#  - cloudflared + cloudflared.service (idle until /etc/cloudflared/tunnel.env has a tunnel token)
#  - OpenAI Codex CLI (codex)
# Safe to rerun; an existing /srv/web/app is kept (the starter is copied only the first time).
set -e
rm -rf /tmp/archpad-web; mkdir -p /tmp/archpad-web; tar -C /tmp/archpad-web -xzf /tmp/archpad-web.tgz
W=/tmp/archpad-web/web

# A first try used MongoDB's own aarch64 build; mongod aborts at startup on this kernel. Remove it if present.
if [ -e /etc/systemd/system/mongod.service ] || [ -e /opt/mongodb ]; then
  systemctl disable --now mongod >/dev/null 2>&1 || true
  rm -rf /etc/systemd/system/mongod.service /etc/mongod.conf /opt/mongodb /opt/mongodb-linux-* /usr/local/bin/mongod \
    /var/lib/mongodb /var/log/mongodb
  userdel mongodb 2>/dev/null || true
  npm uninstall -g mongosh >/dev/null 2>&1 || true
  grep -q '"mongodb"' /srv/web/app/package.json 2>/dev/null && rm -rf /srv/web/app
  echo "removed the earlier MongoDB install"
fi

echo "== packages"
pacman -S --noconfirm --needed caddy cloudflared nodejs npm >/dev/null 2>&1
echo "caddy $(caddy version | cut -d' ' -f1), $(cloudflared --version 2>&1 | head -1 | cut -d' ' -f1-3), node $(node -v)"

# PostgreSQL was tried next; it needs System V shared memory (shmget), which this kernel lacks. Remove it.
if pacman -Q postgresql >/dev/null 2>&1 && [ ! -s /var/lib/postgres/data/PG_VERSION ]; then
  systemctl disable --now postgresql >/dev/null 2>&1 || true; pacman -Rns --noconfirm postgresql >/dev/null 2>&1 || true
  grep -q "\"pg\"" /srv/web/app/package.json 2>/dev/null && rm -rf /srv/web/app
  echo "removed PostgreSQL"
fi
id web >/dev/null 2>&1 || useradd -r -m -d /srv/web -s /usr/bin/nologin web

echo "== web app"
if [ ! -e /srv/web/app/server.js ]; then
  mkdir -p /srv/web/app; cp -r $W/demo/. /srv/web/app/; chown -R web:web /srv/web
fi
cd /srv/web/app
sudo -u web env HOME=/srv/web npm install --omit=dev --no-fund --no-audit >/dev/null 2>&1
sudo -u web env HOME=/srv/web npm run build >/dev/null 2>&1
install -m644 $W/archpad-web-app.service /etc/systemd/system/archpad-web-app.service
chmod 755 /srv/web

echo "== Caddy"
install -m644 $W/Caddyfile /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && echo "Caddyfile ok"

echo "== cloudflared"
install -d -m700 /etc/cloudflared
install -m644 $W/cloudflared.service /etc/systemd/system/cloudflared.service

echo "== Codex CLI"
command -v codex >/dev/null || npm install -g --no-fund --no-audit @openai/codex >/dev/null 2>&1
codex --version

systemctl daemon-reload
systemctl enable archpad-web-app caddy cloudflared >/dev/null 2>&1   # cloudflared starts once a token is present
systemctl restart archpad-web-app caddy
sleep 2
systemctl is-active archpad-web-app caddy | paste -sd' '
curl -fsS http://127.0.0.1/api/health; echo
curl -fsS http://127.0.0.1/ | grep -o '<title>[^<]*</title>'
