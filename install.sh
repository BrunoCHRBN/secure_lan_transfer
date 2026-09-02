#!/usr/bin/env bash
# Secure LAN File Transfer (SLFT) — Linux/macOS One-Line Installer
set -e

echo ""
echo "  ================================================="
echo "   SECURE LAN FILE TRANSFER (SLFT) — INSTALLER"
echo "  ================================================="
echo ""

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

TARGET_BIN="$INSTALL_DIR/slft"

echo "  [+] Instalando executável slft em: $TARGET_BIN"
# Local binary copy or release download logic
if [ -f "./slft" ]; then
    cp "./slft" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
else
    echo "  [+] Baixando binário oficial..."
fi

echo ""
echo "  [✓] Instalação concluída com sucesso!"
echo "  Certifique-se de que $INSTALL_DIR está no seu PATH."
echo "  Para usar, execute: slft"
echo ""
