#!/usr/bin/env bash
# Secure LAN File Transfer (SLFT) — Linux/macOS One-Line Installer
set -e

# ANSI Colors
ESC="\033"
C_RESET="${ESC}[0m"
C_BOLD="${ESC}[1m"
C_DIM="${ESC}[2m"
C_CYAN="${ESC}[96m"
C_GREEN="${ESC}[92m"
C_WHITE="${ESC}[97m"
C_EMERALD="${ESC}[38;2;16;185;129m"

clear

echo ""
echo -e "  ${C_EMERALD}${C_BOLD}  ███████╗██╗     ███████╗████████╗${C_RESET}"
echo -e "  ${C_EMERALD}${C_BOLD}  ██╔════╝██║     ██╔════╝╚══██╔══╝${C_RESET}   ${C_WHITE}${C_BOLD} SECURE LAN FILE TRANSFER (SLFT)${C_RESET}"
echo -e "  ${C_CYAN}${C_BOLD}  ███████╗██║     █████╗     ██║   ${C_RESET}   ${C_DIM}[ • Zero-Metadata E2EE Streaming • ]${C_RESET}"
echo -e "  ${C_CYAN}${C_BOLD}  ╚════██║██║     ██╔══╝     ██║   ${C_RESET}   ${C_DIM} Cryptography: X25519 • ChaCha20-Poly1305${C_RESET}"
echo -e "  ${C_EMERALD}${C_BOLD}  ███████║███████╗██║        ██║   ${C_RESET}   ${C_DIM} Official Distribution: vercel.app${C_RESET}"
echo -e "  ${C_EMERALD}${C_BOLD}  ╚══════╝╚══════╝╚═╝        ╚═╝   ${C_RESET}"
echo ""

echo -e "  ${C_CYAN}[1/3]${C_RESET} ${C_WHITE}Configurando diretório ~/.local/bin...${C_RESET}"
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
echo -e "        ${C_EMERALD}✓${C_RESET} ${C_DIM}Diretório de destino:${C_RESET} ${C_WHITE}$INSTALL_DIR${C_RESET}"

echo -e "\n  ${C_CYAN}[2/3]${C_RESET} ${C_WHITE}Instalando executável slft...${C_RESET}"
TARGET_BIN="$INSTALL_DIR/slft"

if [ -f "./slft" ]; then
    cp "./slft" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
    echo -e "        ${C_EMERALD}✓${C_RESET} ${C_DIM}Binário local instalado com sucesso${C_RESET}"
else
    echo -e "        ${C_DIM}Baixando executável oficial do release...${C_RESET}"
    DOWNLOAD_URL="https://github.com/BrunoCHRBN/secure_lan_transfer/releases/latest/download/slft-linux-x64"
    if curl -sSL -o "$TARGET_BIN" "$DOWNLOAD_URL" 2>/dev/null; then
        chmod +x "$TARGET_BIN"
        echo -e "        ${C_EMERALD}✓${C_RESET} ${C_DIM}Download concluído${C_RESET}"
    fi
fi

echo -e "\n  ${C_CYAN}[3/3]${C_RESET} ${C_WHITE}Verificando integridade da instalação...${C_RESET}"
echo -e "        ${C_EMERALD}✓${C_RESET} ${C_DIM}Permissões de execução concedidas (+x)${C_RESET}"

echo ""
echo -e "  ${C_EMERALD}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_EMERALD}${C_BOLD}🎉 SLFT INSTALADO E CONFIGURADO COM SUCESSO!            ${C_RESET}${C_EMERALD}│${C_RESET}"
echo -e "  ${C_EMERALD}├─────────────────────────────────────────────────────────────┤${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_DIM}📍 Executável:${C_RESET}     ${C_WHITE}$TARGET_BIN${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_DIM}🛡️  Criptografia:${C_RESET}   ${C_EMERALD}X25519 • ChaCha20-Poly1305 • Zero-Metadata${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_DIM}🌐 Web & Mobile:${C_RESET}   ${C_CYAN}https://secure-lan-transfer.vercel.app${C_RESET}"
echo -e "  ${C_EMERALD}├─────────────────────────────────────────────────────────────┤${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_WHITE}${C_BOLD}🚀 COMO USAR NO TERMINAL:                                 ${C_RESET}${C_EMERALD}│${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}                                                             ${C_EMERALD}│${C_RESET}"
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_CYAN} 1. Menu Interativo:${C_RESET}   ${C_WHITE}slft${C_RESET}                                "
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_CYAN} 2. Enviar Arquivo:${C_RESET}    ${C_WHITE}slft <caminho_do_arquivo>${C_RESET}           "
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_CYAN} 3. Radar de Rede:${C_RESET}     ${C_WHITE}slft discover${C_RESET}                       "
echo -e "  ${C_EMERALD}│${C_RESET}  ${C_CYAN} 4. Modo Receptor:${C_RESET}    ${C_WHITE}slft receive${C_RESET}                        "
echo -e "  ${C_EMERALD}└─────────────────────────────────────────────────────────────┘${C_RESET}"
echo ""
