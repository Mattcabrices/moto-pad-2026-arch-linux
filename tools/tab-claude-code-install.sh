# Runs as root on the tablet: Claude Code for matt (official npm package, installed in ~/.local, no root npm).
pacman -Sy >/dev/null 2>&1
pacman -S --noconfirm --needed nodejs npm git ripgrep 2>&1 | tail -1
node --version; npm --version
sudo -u matt -H bash -lc '
  npm config set prefix "$HOME/.local"
  npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
  grep -q "/.local/bin" ~/.bashrc 2>/dev/null || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
  ~/.local/bin/claude --version
'
# The npm postinstall that fetches the native linux-arm64 binary did not run on the first install; run it explicitly.
sudo -u matt -H bash -lc 'cd ~/.local/lib/node_modules/@anthropic-ai/claude-code && node install.cjs >/dev/null 2>&1; ~/.local/bin/claude --version'
# Menu entry (Applications > Development): opens Claude Code in xfce4-terminal.
install -D -m644 -o matt -g matt /tmp/claude-code.desktop /home/matt/.local/share/applications/claude-code.desktop
