Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Assistente de Instalacao - Secure LAN File Transfer"
        Height="580" Width="720"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#0F141C"
        Foreground="#E0E6ED"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1A2332"/>
            <Setter Property="Foreground" Value="#00D26A"/>
            <Setter Property="BorderBrush" Value="#00D26A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="70"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="60"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#141B26" BorderBrush="#1E293B" BorderThickness="0,0,0,1" Padding="20,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center">
                    <TextBlock x:Name="HeaderTitle" Text="Secure LAN File Transfer (SLFT)" FontSize="18" FontWeight="Bold" Foreground="#00D26A"/>
                    <TextBlock x:Name="HeaderSubtitle" Text="Assistente de Instalacao e Configuracao de Seguranca" FontSize="12" Foreground="#94A3B8"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#0A2A1A" BorderBrush="#00D26A" BorderThickness="1" CornerRadius="4" Padding="8,4" VerticalAlignment="Center">
                    <TextBlock Text="v1.1.0 • E2EE" FontSize="11" FontWeight="Bold" Foreground="#00D26A"/>
                </Border>
            </Grid>
        </Border>

        <!-- Main Content Area (Pages) -->
        <Grid Grid.Row="1" Margin="24,16">
            <!-- PAGE 1: Welcome & Overview -->
            <StackPanel x:Name="PageWelcome" Visibility="Visible">
                <TextBlock Text="Bem-vindo ao Secure LAN File Transfer" FontSize="16" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,8"/>
                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#94A3B8" Margin="0,0,0,14" LineHeight="18">
                    O SLFT e uma plataforma de transferencia ponto a ponto (P2P) projetada para alta performance, privacidade absoluta e transmissao em rede local sem intermediacao de servidores em nuvem.
                </TextBlock>

                <Border Background="#16202E" BorderBrush="#243447" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
                    <StackPanel>
                        <TextBlock Text="Principais Aplicabilidades:" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                        <TextBlock Text="• Compartilhamento ultra-rapido de arquivos pesados (videos 4K, ISOs, ZIPs) na rede Wi-Fi/Ethernet." FontSize="12" Foreground="#CBD5E1" Margin="0,2"/>
                        <TextBlock Text="• Envio automatico de pastas inteiras com compactacao em streaming sob demanda." FontSize="12" Foreground="#CBD5E1" Margin="0,2"/>
                        <TextBlock Text="• Operacao 100% offline (nao depende de conexao com a Internet)." FontSize="12" Foreground="#CBD5E1" Margin="0,2"/>
                        <TextBlock Text="• Suporte integrado para Desktop (Windows GUI) e Terminal (CLI Headless)." FontSize="12" Foreground="#CBD5E1" Margin="0,2"/>
                    </StackPanel>
                </Border>

                <Border Background="#0E2319" BorderBrush="#00D26A" BorderThickness="1" CornerRadius="8" Padding="12">
                    <StackPanel>
                        <TextBlock Text="Garantias de Seguranca Padrao:" FontWeight="Bold" Foreground="#00D26A" Margin="0,0,0,4"/>
                        <TextBlock Text="Criptografia X25519 ECDH + ChaCha20-Poly1305, autenticacao SAS (codigo numerico anti-MitM) e politica rigorosa de Zero-Metadata (nenhum historico e gravado no disco)." FontSize="12" Foreground="#A7F3D0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </StackPanel>

            <!-- PAGE 2: Security Terms & Acceptance -->
            <StackPanel x:Name="PageTerms" Visibility="Collapsed">
                <TextBlock Text="Termos de Uso, Privacidade e Seguranca" FontSize="16" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,6"/>
                <TextBlock Text="Leia atentamente as diretrizes de seguranca antes de prosseguir:" FontSize="12" Foreground="#94A3B8" Margin="0,0,0,8"/>

                <Border Background="#131A24" BorderBrush="#243447" BorderThickness="1" CornerRadius="6" Height="220" Margin="0,0,0,12">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="12">
                        <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#CBD5E1" LineHeight="18">
1. PRIVACIDADE E POLITICA ZERO-METADATA
A aplicacao opera estritamente no modelo Zero-Metadata por padrao. Nomes de arquivos, registros de conexoes e identificadores de dispositivos trafegam exclusivamente criptografados e nao sao armazenados em arquivos persistentes de log no disco, existindo apenas na memoria RAM volatil durante a execucao da sessao.

2. CRIPTOGRAFIA DE PONTA A PONTA (E2EE)
Todas as transferencias utilizam a suite criptografica moderna com troca de chaves assincronas X25519 (Curve25519 ECDH), derivacao HKDF-SHA256 e cifra autenticada ChaCha20-Poly1305 / AES-GCM. A validacao de integridade ocorre via MAC Poly1305 por bloco e hash final SHA-256.

3. AUTENTICACAO E CODIGO SAS
Para protecao ativa contra ataques de interceptacao na rede local (Man-in-the-Middle), o sistema disponibiliza autenticacao SAS (Short Authentication String) com verificacao visual de digitos e suporte a senhas PIN pre-compartilhadas.

4. OFUSCACAO DE TRAFEGO
O protocolo inclui preenchimento aleatorio de pacotes (padding framing) para prevenir analise de trafego por inspecao profunda (DPI) dentro da rede local.

5. ISENCAO E RESPONSABILIDADE DO USUARIO
O usuario reconhece que a aplicacao e uma ferramenta para transporte seguro e legitimo de dados em redes autorizadas, sendo o proprio usuario o unico responsavel pelos arquivos transmitidos.
                        </TextBlock>
                    </ScrollViewer>
                </Border>

                <CheckBox x:Name="ChkAcceptTerms" Content="Li e concordo com os Termos de Seguranca e autorizo a instalacao." Foreground="#00D26A" FontWeight="SemiBold"/>
            </StackPanel>

            <!-- PAGE 3: Components & Options -->
            <StackPanel x:Name="PageOptions" Visibility="Collapsed">
                <TextBlock Text="Selecao de Componentes e Atalhos" FontSize="16" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,6"/>
                <TextBlock Text="Escolha como deseja utilizar o Secure LAN File Transfer no seu computador:" FontSize="12" Foreground="#94A3B8" Margin="0,0,0,12"/>

                <Border Background="#16202E" BorderBrush="#243447" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="Componentes a Instalar:" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                        <CheckBox x:Name="ChkInstallDesktop" Content="Aplicativo Grafico Desktop (Janela Moderna com Drag &amp; Drop)" IsChecked="True"/>
                        <CheckBox x:Name="ChkInstallCli" Content="Utilitario de Terminal CLI (Comando 'slft' no PowerShell/CMD)" IsChecked="True"/>
                    </StackPanel>
                </Border>

                <Border Background="#16202E" BorderBrush="#243447" BorderThickness="1" CornerRadius="8" Padding="14">
                    <StackPanel>
                        <TextBlock Text="Tarefas Adicionais no Sistema:" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                        <CheckBox x:Name="ChkAddToPath" Content="Adicionar 'slft' ao PATH de Usuario (Acesso global no terminal)" IsChecked="True"/>
                        <CheckBox x:Name="ChkDesktopShortcut" Content="Criar atalho na Area de Trabalho (Desktop)" IsChecked="True"/>
                        <CheckBox x:Name="ChkStartMenuShortcut" Content="Criar atalho no Menu Iniciar" IsChecked="True"/>
                    </StackPanel>
                </Border>
            </StackPanel>

            <!-- PAGE 4: Installation Progress -->
            <StackPanel x:Name="PageProgress" Visibility="Collapsed">
                <TextBlock Text="Instalando o Secure LAN File Transfer..." FontSize="16" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,12"/>
                <ProgressBar x:Name="InstallProgressBar" Height="14" Background="#1E293B" Foreground="#00D26A" Margin="0,0,0,12" Maximum="100" Value="0"/>
                <Border Background="#0B0F17" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="6" Height="220">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
                        <TextBlock x:Name="TxtInstallLog" FontFamily="Consolas" FontSize="11" Foreground="#94A3B8" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
            </StackPanel>

            <!-- PAGE 5: Completion -->
            <StackPanel x:Name="PageComplete" Visibility="Collapsed">
                <TextBlock Text="Instalacao Concluida com Sucesso!" FontSize="18" FontWeight="Bold" Foreground="#00D26A" Margin="0,0,0,8"/>
                <TextBlock Text="O Secure LAN File Transfer esta pronto para uso na sua rede." FontSize="13" Foreground="#94A3B8" Margin="0,0,0,16"/>

                <Border Background="#16202E" BorderBrush="#243447" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,16">
                    <StackPanel>
                        <TextBlock Text="Como comecar:" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                        <TextBlock Text="• Abra o aplicativo grafico pelo icone na Area de Trabalho." FontSize="12" Foreground="#CBD5E1" Margin="0,3"/>
                        <TextBlock Text="• Ou abra o terminal (CMD/PowerShell) e digite 'slft' para o Hub interativo." FontSize="12" Foreground="#CBD5E1" Margin="0,3"/>
                        <TextBlock Text="• Exemplo rapido: 'slft foto.png' ou 'slft recv'." FontSize="12" Foreground="#CBD5E1" Margin="0,3"/>
                    </StackPanel>
                </Border>

                <CheckBox x:Name="ChkRunNow" Content="Executar o Secure LAN Transfer agora" IsChecked="True" Foreground="#38BDF8" FontWeight="SemiBold"/>
            </StackPanel>
        </Grid>

        <!-- Footer Navigation -->
        <Border Grid.Row="2" Background="#141B26" BorderBrush="#1E293B" BorderThickness="0,1,0,0" Padding="20,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="BtnCancel" Grid.Column="0" Content="Cancelar" Width="90"/>
                <Button x:Name="BtnBack" Grid.Column="2" Content="« Voltar" Width="90" Margin="0,0,10,0" Visibility="Collapsed"/>
                <Button x:Name="BtnNext" Grid.Column="3" Content="Avancar »" Width="100" Background="#00D26A" Foreground="#0B0F17"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Controls binding
$pageWelcome = $window.FindName("PageWelcome")
$pageTerms = $window.FindName("PageTerms")
$pageOptions = $window.FindName("PageOptions")
$pageProgress = $window.FindName("PageProgress")
$pageComplete = $window.FindName("PageComplete")

$headerSubtitle = $window.FindName("HeaderSubtitle")
$chkAcceptTerms = $window.FindName("ChkAcceptTerms")
$chkInstallDesktop = $window.FindName("ChkInstallDesktop")
$chkInstallCli = $window.FindName("ChkInstallCli")
$chkAddToPath = $window.FindName("ChkAddToPath")
$chkDesktopShortcut = $window.FindName("ChkDesktopShortcut")
$chkStartMenuShortcut = $window.FindName("ChkStartMenuShortcut")
$chkRunNow = $window.FindName("ChkRunNow")

$installProgressBar = $window.FindName("InstallProgressBar")
$txtInstallLog = $window.FindName("TxtInstallLog")

$btnCancel = $window.FindName("BtnCancel")
$btnBack = $window.FindName("BtnBack")
$btnNext = $window.FindName("BtnNext")

$script:currentPage = 1
$script:installDir = "$env:LOCALAPPDATA\Programs\SecureLANTransfer"
$script:sourceDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($script:sourceDir)) {
    $script:sourceDir = Get-Location
}

function Update-UIState {
    $pageWelcome.Visibility = if ($script:currentPage -eq 1) { "Visible" } else { "Collapsed" }
    $pageTerms.Visibility = if ($script:currentPage -eq 2) { "Visible" } else { "Collapsed" }
    $pageOptions.Visibility = if ($script:currentPage -eq 3) { "Visible" } else { "Collapsed" }
    $pageProgress.Visibility = if ($script:currentPage -eq 4) { "Visible" } else { "Collapsed" }
    $pageComplete.Visibility = if ($script:currentPage -eq 5) { "Visible" } else { "Collapsed" }

    $btnBack.Visibility = if ($script:currentPage -gt 1 -and $script:currentPage -lt 4) { "Visible" } else { "Collapsed" }
    $btnCancel.Visibility = if ($script:currentPage -le 3) { "Visible" } else { "Collapsed" }

    switch ($script:currentPage) {
        1 {
            $headerSubtitle.Text = "Visao Geral e Arquitetura da Aplicacao"
            $btnNext.Content = "Avancar »"
            $btnNext.IsEnabled = $true
        }
        2 {
            $headerSubtitle.Text = "Termos de Seguranca e Privacidade E2EE"
            $btnNext.Content = "Aceitar e Continuar »"
            $btnNext.IsEnabled = [bool]$chkAcceptTerms.IsChecked
        }
        3 {
            $headerSubtitle.Text = "Personalizacao de Componentes e Atalhos"
            $btnNext.Content = "Iniciar Instalacao"
            $btnNext.IsEnabled = $true
        }
        4 {
            $headerSubtitle.Text = "Copiando arquivos e registrando comandos..."
            $btnNext.Visibility = "Collapsed"
            $btnBack.Visibility = "Collapsed"
            $btnCancel.Visibility = "Collapsed"
        }
        5 {
            $headerSubtitle.Text = "Pronto para uso!"
            $btnNext.Visibility = "Visible"
            $btnNext.Content = "Concluir"
            $btnNext.IsEnabled = $true
        }
    }
}

$chkAcceptTerms.Add_Checked({ Update-UIState })
$chkAcceptTerms.Add_Unchecked({ Update-UIState })

$btnCancel.Add_Click({ $window.Close() })

$btnBack.Add_Click({
    if ($script:currentPage -gt 1) {
        $script:currentPage--
        Update-UIState
    }
})

function Append-Log($msg) {
    $timeStr = (Get-Date).ToString("HH:mm:ss")
    $txtInstallLog.Text += "[$timeStr] $msg`r`n"
}

function Perform-Installation {
    $script:currentPage = 4
    Update-UIState

    $installProgressBar.Value = 10
    Append-Log "Criando diretorio de instalacao: $script:installDir"
    New-Item -ItemType Directory -Path $script:installDir -Force | Out-Null

    $installProgressBar.Value = 30
    if ($chkInstallDesktop.IsChecked) {
        Append-Log "Copiando binarios do Aplicativo Desktop (Flutter GUI)..."
        $releaseGuiDir = Join-Path $script:sourceDir "build\windows\x64\runner\Release"
        if (Test-Path $releaseGuiDir) {
            Copy-Item -Path "$releaseGuiDir\*" -Destination $script:installDir -Recurse -Force
            Append-Log "Aplicativo Desktop instalado com sucesso."
        } else {
            Append-Log "Pasta Release da GUI nao encontrada."
        }
    }

    $installProgressBar.Value = 60
    if ($chkInstallCli.IsChecked) {
        Append-Log "Copiando executavel nativo do CLI (slft.exe)..."
        $cliExe = Join-Path $script:sourceDir "slft.exe"
        if (Test-Path $cliExe) {
            Copy-Item -Path $cliExe -Destination $script:installDir -Force
            Append-Log "CLI 'slft.exe' copiado para a pasta de programas."
        }
    }

    $installProgressBar.Value = 75
    if ($chkAddToPath.IsChecked) {
        Append-Log "Adicionando $script:installDir ao PATH do Usuario..."
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ";" -contains $script:installDir)) {
            $newPath = if ($userPath) { "$userPath;$script:installDir" } else { $script:installDir }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Append-Log "PATH atualizado com sucesso. O comando 'slft' funcionara no terminal."
        } else {
            Append-Log "Pasta ja se encontra no PATH do usuario."
        }
    }

    $installProgressBar.Value = 85
    $wsh = New-Object -ComObject WScript.Shell

    if ($chkDesktopShortcut.IsChecked) {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Secure LAN Transfer.lnk"
        $target = Join-Path $script:installDir "secure_lan_transfer.exe"
        if (Test-Path $target) {
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $target
            $shortcut.WorkingDirectory = $script:installDir
            $shortcut.Description = "Secure LAN File Transfer (E2EE)"
            $shortcut.Save()
            Append-Log "Atalho criado na Area de Trabalho."
        }
    }

    if ($chkStartMenuShortcut.IsChecked) {
        $programsPath = [Environment]::GetFolderPath("Programs")
        $shortcutPath = Join-Path $programsPath "Secure LAN Transfer.lnk"
        $target = Join-Path $script:installDir "secure_lan_transfer.exe"
        if (Test-Path $target) {
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $target
            $shortcut.WorkingDirectory = $script:installDir
            $shortcut.Description = "Secure LAN File Transfer"
            $shortcut.Save()
            Append-Log "Atalho criado no Menu Iniciar."
        }
    }

    $uninstallerScript = Join-Path $script:installDir "uninstall.ps1"
    $uninstallLines = @(
        "`$installDir = '$script:installDir'",
        "`$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Secure LAN Transfer.lnk'",
        "`$startShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Secure LAN Transfer.lnk'",
        "if (Test-Path `$desktopShortcut) { Remove-Item -Force `$desktopShortcut }",
        "if (Test-Path `$startShortcut) { Remove-Item -Force `$startShortcut }",
        "`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')",
        "`$cleanPath = (`$userPath -split ';' | Where-Object { `$_ -ne `$installDir }) -join ';'",
        "[Environment]::SetEnvironmentVariable('Path', `$cleanPath, 'User')",
        "Remove-Item -Recurse -Force `$installDir",
        "[System.Windows.MessageBox]::Show('Secure LAN File Transfer foi desinstalado com sucesso.', 'Desinstalacao Concluida')"
    )
    $uninstallLines | Set-Content -Path $uninstallerScript -Encoding UTF8

    $installProgressBar.Value = 100
    Append-Log "Instalacao e registros concluidos com sucesso!"

    Start-Sleep -Milliseconds 800
    $script:currentPage = 5
    Update-UIState
}

$btnNext.Add_Click({
    if ($script:currentPage -eq 1) {
        $script:currentPage = 2
        Update-UIState
    } elseif ($script:currentPage -eq 2) {
        $script:currentPage = 3
        Update-UIState
    } elseif ($script:currentPage -eq 3) {
        Perform-Installation
    } elseif ($script:currentPage -eq 5) {
        if ($chkRunNow.IsChecked) {
            $appPath = Join-Path $script:installDir "secure_lan_transfer.exe"
            if (Test-Path $appPath) {
                Start-Process -FilePath $appPath
            }
        }
        $window.Close()
    }
})

Update-UIState
$window.ShowDialog() | Out-Null
