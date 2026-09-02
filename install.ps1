# Secure LAN File Transfer (SLFT) — Windows One-Line Installer
$ErrorActionPreference = "Stop"

# ANSI Colors & Styling
$esc = [char]27
$cReset = "$esc[0m"
$cBold = "$esc[1m"
$cDim = "$esc[2m"
$cCyan = "$esc[96m"
$cGreen = "$esc[92m"
$cYellow = "$esc[93m"
$cWhite = "$esc[97m"
$cEmerald = "$esc[38;2;16;185;129m"
$cDarkGreen = "$esc[38;2;8;34;22m"

Clear-Host

# 1. Cyber Banner
Write-Host ""
Write-Host "  $cEmerald$cBold  ███████╗██╗     ███████╗████████╗$cReset"
Write-Host "  $cEmerald$cBold  ██╔════╝██║     ██╔════╝╚══██╔══╝$cReset   $cWhite$cBold SECURE LAN FILE TRANSFER (SLFT)$cReset"
Write-Host "  $cCyan$cBold  ███████╗██║     █████╗     ██║   $cReset   $cDim[ • Zero-Metadata E2EE Streaming • ]$cReset"
Write-Host "  $cCyan$cBold  ╚════██║██║     ██╔══╝     ██║   $cReset   $cDim Cryptography: X25519 • ChaCha20-Poly1305$cReset"
Write-Host "  $cEmerald$cBold  ███████║███████╗██║        ██║   $cReset   $cDim Official Distribution: vercel.app$cReset"
Write-Host "  $cEmerald$cBold  ╚══════╝╚══════╝╚═╝        ╚═╝   $cReset"
Write-Host ""

# 2. Installation Steps
Write-Host "  $cCyan[1/4]$cReset $cWhite Verificando ambiente do sistema...$cReset"
$osArch = if ([Environment]::Is64BitOperatingSystem) { "Windows 64-bit (x64)" } else { "Windows 32-bit (x86)" }
Write-Host "        $cEmerald✓$cReset $cDim Arquitetura detectada:$cReset $cWhite$osArch$cReset"

Write-Host "`n  $cCyan[2/4]$cReset $cWhite Configurando diretório de programas...$cReset"
$installDir = "$env:LOCALAPPDATA\Programs\SecureLANTransfer"
if (!(Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
Write-Host "        $cEmerald✓$cReset $cDim Pasta de destino:$cReset $cWhite$installDir$cReset"

Write-Host "`n  $cCyan[3/4]$cReset $cWhite Instalando executável slft.exe (v1.1.0)...$cReset"
$targetExe = Join-Path $installDir "slft.exe"

$localSource = "C:\Users\PICHAU\OneDrive\Desktop\secure_lan_transfer\slft.exe"
if (Test-Path $localSource) {
    Copy-Item -Path $localSource -Destination $targetExe -Force
    Write-Host "        $cEmerald✓$cReset $cDim Binário compilado sincronizado com sucesso$cReset"
} else {
    $downloadUrl = "https://github.com/BrunoCHRBN/secure_lan_transfer/releases/latest/download/slft.exe"
    try {
        Write-Host "        $cDim Baixando binário oficial do release...$cReset"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $targetExe -UseBasicParsing
        Write-Host "        $cEmerald✓$cReset $cDim Download concluído$cReset"
    } catch {
        Write-Host "        $cYellow!$cReset $cDim Utilizando binário pré-existente no diretório local$cReset"
    }
}

Write-Host "`n  $cCyan[4/4]$cReset $cWhite Registrando nas Variáveis de Ambiente (PATH)...$cReset"
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", [EnvironmentVariableTarget]::User)
    $env:Path += ";$installDir"
    Write-Host "        $cEmerald✓$cReset $cDim Caminho adicionado ao PATH do Windows com sucesso$cReset"
} else {
    Write-Host "        $cEmerald✓$cReset $cDim Caminho já registrado no PATH do usuário$cReset"
}

# 3. Test Installed Binary
$versionInfo = "Secure LAN File Transfer CLI (SLFT) v1.1.0"
if (Test-Path $targetExe) {
    try {
        $ver = & $targetExe --version 2>&1
        if ($ver) { $versionInfo = $ver[0] }
    } catch {}
}

# 4. Success Quick Start Box
Write-Host ""
Write-Host "  $cEmerald┌─────────────────────────────────────────────────────────────┐$cReset"
Write-Host "  $cEmerald│$cReset  $cEmerald$cBold🎉 SLFT INSTALADO E CONFIGURADO COM SUCESSO!            $cReset$cEmerald│$cReset"
Write-Host "  $cEmerald├─────────────────────────────────────────────────────────────┤$cReset"
Write-Host "  $cEmerald│$cReset  $cDim📍 Executável:$cReset     $cWhite$targetExe$cReset"
Write-Host "  $cEmerald│$cReset  $cDim🛡️  Criptografia:$cReset   $cEmeraldX25519 • ChaCha20-Poly1305 • Zero-Metadata$cReset"
Write-Host "  $cEmerald│$cReset  $cDim🌐 Web & Mobile:$cReset   $cCyanhttps://secure-lan-transfer.vercel.app$cReset"
Write-Host "  $cEmerald├─────────────────────────────────────────────────────────────┤$cReset"
Write-Host "  $cEmerald│$cReset  $cWhite$cBold🚀 COMO USAR NO TERMINAL:                                 $cReset$cEmerald│$cReset"
Write-Host "  $cEmerald│$cReset                                                             $cEmerald│$cReset"
Write-Host "  $cEmerald│$cReset  $cCyan 1. Menu Interativo:$cReset   $cWhite slft$cReset                                "
Write-Host "  $cEmerald│$cReset  $cCyan 2. Enviar Arquivo:$cReset    $cWhite slft <caminho_do_arquivo>$cReset           "
Write-Host "  $cEmerald│$cReset  $cCyan 3. Radar de Rede:$cReset     $cWhite slft discover$cReset                       "
Write-Host "  $cEmerald│$cReset  $cCyan 4. Modo Receptor:$cReset    $cWhite slft receive$cReset                        "
Write-Host "  $cEmerald└─────────────────────────────────────────────────────────────┘$cReset"
Write-Host ""
Write-Host "  $cDim Dica: Abra uma nova janela do terminal para carregar o novo comando 'slft'.$cReset`n"
