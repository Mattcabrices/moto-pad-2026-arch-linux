# Runs as root on the tablet: finish the Claude Code install for matt (native binary for linux-arm64).
sudo -u matt -H bash -lc '
  D=$HOME/.local/lib/node_modules/@anthropic-ai/claude-code
  ls $D | head; ls $HOME/.local/lib/node_modules/@anthropic-ai/ 2>&1
  npm config get omit; npm config get ignore-scripts
  cd $D && node install.cjs 2>&1 | tail -8
  ~/.local/bin/claude --version 2>&1 | tail -2
'
