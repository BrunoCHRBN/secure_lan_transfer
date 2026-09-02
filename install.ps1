# Secure LAN File Transfer (SLFT) — Windows One-Line Installer
$ErrorActionPreference = "Stop"

Write-Host "`n  =================================================" -ForegroundColor DarkGreen
Write-Host "   SECURE LAN FILE TRANSFER (SLFT) — INSTALLER" -ForegroundColor Green
Write-Host "  =================================================`n" -ForegroundColor DarkGreen

$installDir = "$env:LOCALAPPDATA\Programs\SecureLANTransfer"
if (!(Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$targetExe = Join-Path $installDir "slft.exe"

# If local build exists, copy it
$localSource = "C:\Users\PICHAU\OneDrive\Desktop\secure_lan_transfer\slft.exe"
if (Test-Path $localSource) {
    Copy-Item -Path $localSource -Destination $targetExe -Force
    Write-Host "  [+] Executável SLFT copiado para: $targetExe" -ForegroundColor Cyan
}

# Add to User PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", [EnvironmentVariableTarget]::User)
    $env:Path += ";$installDir"
    Write-Host "  [+] Diretório adicionado ao PATH do Windows!" -ForegroundColor Green
}

Write-Host "`n  [✓] Instalação concluída com sucesso!" -ForegroundColor Green
Write-Host "  Para usar, abra um novo terminal e digite: slft`n" -ForegroundColor White
