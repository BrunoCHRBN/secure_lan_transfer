; Script de Instalacao Inno Setup para Secure LAN File Transfer (SLFT)
; Requer Inno Setup 6.x (https://jrsoftware.org/isdl.php)

#define MyAppName "Secure LAN File Transfer"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Secure LAN Transfer Team"
#define MyAppExeName "secure_lan_transfer.exe"
#define MyCliExeName "slft.exe"

[Setup]
AppId={{9C52E4B7-3F7B-4F18-8A31-29E57A2BD4A1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={userappdata}\Programs\SecureLANTransfer
DisableProgramGroupPage=yes
LicenseFile=TERMS_OF_USE.txt
PrivilegesRequired=lowest
OutputDir=installer_output
OutputBaseFilename=Setup_SecureLANTransfer_v1.1.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "addtopath"; Description: "Adicionar 'slft' ao PATH do Windows para uso global no Prompt/PowerShell"

[Types]
Name: "full"; Description: "Instalacao Completa (Desktop GUI + CLI no Terminal)"
Name: "desktoponly"; Description: "Apenas Aplicativo Desktop"
Name: "clionly"; Description: "Apenas Utilitario de Terminal (CLI)"
Name: "custom"; Description: "Personalizada"; Flags: iscustom

[Components]
Name: "gui"; Description: "Aplicativo Desktop (Interface Grafica)"; Types: full desktoponly custom
Name: "cli"; Description: "Utilitario de Linha de Comando (slft.exe)"; Types: full clionly custom

[Files]
; GUI Files
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: gui
; CLI Files
Source: "slft.exe"; DestDir: "{app}"; Flags: ignoreversion; Components: cli

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Components: gui
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Components: gui

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; Components: gui
