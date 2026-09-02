using System;
using System.IO;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Documents;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace SecureLanTransfer.Installer
{
    public class App : Application
    {
        [STAThread]
        public static void Main()
        {
            var app = new App();
            app.Run(new MainWindow());
        }
    }

    public class MainWindow : Window
    {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19;

        private int _currentPage = 1;
        private string _installDir;
        private readonly string _sourceDir;

        // UI Controls
        private TextBlock _headerSubtitle;
        private StackPanel _pageWelcome;
        private StackPanel _pageTerms;
        private StackPanel _pageOptions;
        private StackPanel _pageProgress;
        private StackPanel _pageComplete;

        private CheckBox _chkAcceptTerms;
        private CheckBox _chkInstallDesktop;
        private CheckBox _chkInstallCli;
        private CheckBox _chkAddToPath;
        private CheckBox _chkDesktopShortcut;
        private CheckBox _chkStartMenuShortcut;
        private CheckBox _chkRunNow;
        private TextBox _txtDestinationPath;
        private Button _btnBrowsePath;

        // Upgrade / Clean install options
        private Border _existingInstallCard;
        private TextBlock _txtExistingInstallDetails;
        private RadioButton _rbCleanInstall;
        private RadioButton _rbOverwrite;

        private ProgressBar _progressBar;
        private TextBlock _txtInstallLog;

        private Button _btnCancel;
        private Button _btnBack;
        private Button _btnNext;

        public MainWindow()
        {
            Title = "Assistente de Instalação — Secure LAN File Transfer";
            Width = 760;
            Height = 650;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ResizeMode = ResizeMode.NoResize;
            Background = new SolidColorBrush(Color.FromRgb(15, 20, 28)); // #0F141C
            Foreground = new SolidColorBrush(Color.FromRgb(224, 230, 237));
            FontFamily = new FontFamily("Segoe UI");

            _installDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SecureLANTransfer");
            _sourceDir = AppDomain.CurrentDomain.BaseDirectory;

            Loaded += (s, e) =>
            {
                try
                {
                    var helper = new System.Windows.Interop.WindowInteropHelper(this);
                    int useDarkMode = 1;
                    DwmSetWindowAttribute(helper.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref useDarkMode, sizeof(int));
                    DwmSetWindowAttribute(helper.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1, ref useDarkMode, sizeof(int));
                }
                catch { }
            };

            BuildUI();
            CheckExistingInstallation(_installDir);
            UpdateUIState();
        }

        private void CheckExistingInstallation(string targetPath)
        {
            if (string.IsNullOrEmpty(targetPath)) return;
            bool exists = Directory.Exists(targetPath) &&
                (File.Exists(Path.Combine(targetPath, "secure_lan_transfer.exe")) || File.Exists(Path.Combine(targetPath, "slft.exe")));

            if (exists)
            {
                _existingInstallCard.Visibility = Visibility.Visible;
                _txtExistingInstallDetails.Text = string.Format("Uma versão anterior do SLFT foi detectada em: {0}", targetPath);
            }
            else
            {
                _existingInstallCard.Visibility = Visibility.Collapsed;
            }
        }

        private void BuildUI()
        {
            var rootGrid = new Grid();
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(76) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(68) });

            // 1. Header
            var headerBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(20, 27, 38)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(0, 0, 0, 1),
                Padding = new Thickness(24, 12, 24, 12)
            };
            var headerGrid = new Grid();
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var headerStack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var headerTitle = new TextBlock
            {
                Text = "Secure LAN File Transfer (SLFT)",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106))
            };
            _headerSubtitle = new TextBlock
            {
                Text = "Visão Geral e Arquitetura da Aplicação",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 3, 0, 0)
            };
            headerStack.Children.Add(headerTitle);
            headerStack.Children.Add(_headerSubtitle);

            var badgeBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(10, 42, 26)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0, 210, 106)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(5),
                Padding = new Thickness(12, 5, 12, 5),
                VerticalAlignment = VerticalAlignment.Center
            };
            var badgeText = new TextBlock
            {
                Text = "v1.1.0 • E2EE",
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106))
            };
            badgeBorder.Child = badgeText;

            Grid.SetColumn(headerStack, 0);
            Grid.SetColumn(badgeBorder, 1);
            headerGrid.Children.Add(headerStack);
            headerGrid.Children.Add(badgeBorder);
            headerBorder.Child = headerGrid;
            Grid.SetRow(headerBorder, 0);
            rootGrid.Children.Add(headerBorder);

            // 2. Content Pages
            var contentGrid = new Grid { Margin = new Thickness(24, 16, 24, 16) };

            // Page 1: Welcome
            _pageWelcome = new StackPanel();
            _pageWelcome.Children.Add(new TextBlock
            {
                Text = "Bem-vindo ao Secure LAN File Transfer",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 8)
            });
            _pageWelcome.Children.Add(new TextBlock
            {
                Text = "O SLFT é uma plataforma de transferência ponto a ponto (P2P) projetada para ultra-alta velocidade, privacidade absoluta e transmissão em rede local sem dependência de servidores em nuvem.",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 13,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 14),
                LineHeight = 19
            });

            var cardApp = CreateInfoCard("📌 Principais Aplicabilidades:", Color.FromRgb(56, 189, 248), new[]
            {
                "• Compartilhamento ultra-rápido de arquivos pesados (vídeos 4K, ISOs, ZIPs) na rede Wi-Fi/Ethernet.",
                "• Envio automático de pastas inteiras com compactação em streaming sob demanda.",
                "• Operação 100% offline (funciona perfeitamente sem conexão com a Internet).",
                "• Suporte integrado para Desktop (Windows GUI) e Terminal (CLI Headless)."
            });
            _pageWelcome.Children.Add(cardApp);

            var cardSec = CreateInfoCard("🛡️ Garantias de Segurança Padrão:", Color.FromRgb(0, 210, 106), new[]
            {
                "Criptografia ponta a ponta X25519 ECDH + ChaCha20-Poly1305, autenticação SAS (código numérico anti-MitM) e política rigorosa de Zero-Metadata (nenhum histórico ou arquivo temporário é gravado no disco)."
            });
            _pageWelcome.Children.Add(cardSec);
            contentGrid.Children.Add(_pageWelcome);

            // Page 2: Terms
            _pageTerms = new StackPanel { Visibility = Visibility.Collapsed };
            _pageTerms.Children.Add(new TextBlock
            {
                Text = "Termos de Uso, Privacidade e Segurança",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 6)
            });
            _pageTerms.Children.Add(new TextBlock
            {
                Text = "Leia atentamente as diretrizes de segurança antes de prosseguir com a instalação:",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 8)
            });

            var termsScroll = new ScrollViewer
            {
                Height = 250,
                Background = new SolidColorBrush(Color.FromRgb(19, 26, 36)),
                Padding = new Thickness(16),
                Margin = new Thickness(0, 0, 0, 12),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            var termsBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(19, 26, 36)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Child = termsScroll
            };

            var termsStack = new StackPanel();
            AddTermSection(termsStack, "1. PRIVACIDADE E POLÍTICA ZERO-METADATA", "A aplicação opera estritamente no modelo Zero-Metadata por padrão. Nomes de arquivos, registros de conexões e identificadores trafegam exclusivamente criptografados e não são armazenados em logs persistentes no disco, residindo apenas na memória RAM durante a sessão.");
            AddTermSection(termsStack, "2. CRIPTOGRAFIA DE PONTA A PONTA (E2EE)", "Todas as transferências utilizam troca de chaves assíncronas X25519 (Curve25519 ECDH), derivação HKDF-SHA256 e cifra autenticada ChaCha20-Poly1305 / AES-GCM com validação de integridade por bloco e hash final SHA-256.");
            AddTermSection(termsStack, "3. AUTENTICAÇÃO E CÓDIGO SAS", "Para proteção ativa contra ataques de interceptação na rede local (Man-in-the-Middle), o sistema disponibiliza autenticação SAS (Short Authentication String) com verificação visual de dígitos e suporte a senhas PIN.");
            AddTermSection(termsStack, "4. OFUSCAÇÃO DE TRÁFEGO", "O protocolo inclui preenchimento aleatório de pacotes (padding framing) para prevenir análise de tráfego por inspeção profunda (DPI) dentro da rede local.");
            AddTermSection(termsStack, "5. ISENÇÃO E RESPONSABILIDADE DO USUÁRIO", "O usuário reconhece que a aplicação é uma ferramenta para transporte seguro e legítimo de dados em redes autorizadas, sendo o próprio usuário o único responsável pelos arquivos transmitidos.");
            termsScroll.Content = termsStack;

            _pageTerms.Children.Add(termsBorder);

            _chkAcceptTerms = new CheckBox
            {
                Content = "Li e concordo com os Termos de Segurança e autorizo a instalação.",
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106)),
                FontWeight = FontWeights.SemiBold,
                FontSize = 13,
                Margin = new Thickness(0, 4, 0, 0),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _chkAcceptTerms.Checked += (s, e) => UpdateUIState();
            _chkAcceptTerms.Unchecked += (s, e) => UpdateUIState();
            _pageTerms.Children.Add(_chkAcceptTerms);
            contentGrid.Children.Add(_pageTerms);

            // Page 3: Options & Destination
            _pageOptions = new StackPanel { Visibility = Visibility.Collapsed };
            _pageOptions.Children.Add(new TextBlock
            {
                Text = "Seleção de Componentes e Destino",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 4)
            });
            _pageOptions.Children.Add(new TextBlock
            {
                Text = "Escolha os componentes, atalhos e a pasta de destino para a instalação:",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 8)
            });

            // Existing installation banner card
            _existingInstallCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(30, 40, 25)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(251, 191, 36)), // Amber
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12),
                Margin = new Thickness(0, 0, 0, 8),
                Visibility = Visibility.Collapsed
            };
            var existStack = new StackPanel();
            var existTitleRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
            existTitleRow.Children.Add(new TextBlock { Text = "🔄 Instalação Anterior Detectada", FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(251, 191, 36)), FontSize = 13 });
            existStack.Children.Add(existTitleRow);
            _txtExistingInstallDetails = new TextBlock
            {
                Text = "Uma instalação do SLFT já existe na pasta de destino.",
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                Margin = new Thickness(0, 0, 0, 6)
            };
            existStack.Children.Add(_txtExistingInstallDetails);

            var radioGroup = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 0, 0) };
            _rbCleanInstall = new RadioButton
            {
                Content = "Instalação Limpa (Excluir versão antiga e instalar nova - Recomendado)",
                IsChecked = true,
                Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 16, 0),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _rbOverwrite = new RadioButton
            {
                Content = "Sobrescrever / Atualizar arquivos",
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                FontSize = 12,
                Cursor = System.Windows.Input.Cursors.Hand
            };
            var radioStack = new StackPanel();
            radioStack.Children.Add(_rbCleanInstall);
            radioStack.Children.Add(_rbOverwrite);
            existStack.Children.Add(radioStack);
            _existingInstallCard.Child = existStack;
            _pageOptions.Children.Add(_existingInstallCard);

            // Components card
            var compCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12),
                Margin = new Thickness(0, 0, 0, 8)
            };
            var compStack = new StackPanel();
            compStack.Children.Add(new TextBlock { Text = "Componentes a Instalar:", FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)), Margin = new Thickness(0, 0, 0, 4) });
            _chkInstallDesktop = new CheckBox { Content = "Aplicativo Gráfico Desktop (Janela Flutter com Drag & Drop)", IsChecked = true, Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)), Margin = new Thickness(0, 2, 0, 2) };
            _chkInstallCli = new CheckBox { Content = "Utilitário de Terminal CLI (Comando 'slft' no PowerShell/CMD)", IsChecked = true, Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)), Margin = new Thickness(0, 2, 0, 2) };
            compStack.Children.Add(_chkInstallDesktop);
            compStack.Children.Add(_chkInstallCli);
            compCard.Child = compStack;
            _pageOptions.Children.Add(compCard);

            // Tasks card
            var taskCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12),
                Margin = new Thickness(0, 0, 0, 8)
            };
            var taskStack = new StackPanel();
            taskStack.Children.Add(new TextBlock { Text = "Tarefas Adicionais no Sistema:", FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)), Margin = new Thickness(0, 0, 0, 4) });
            _chkAddToPath = new CheckBox { Content = "Adicionar 'slft' ao PATH do Usuário (Acesso global no terminal)", IsChecked = true, Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)), Margin = new Thickness(0, 2, 0, 2) };
            _chkDesktopShortcut = new CheckBox { Content = "Criar atalho na Área de Trabalho (Desktop)", IsChecked = true, Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)), Margin = new Thickness(0, 2, 0, 2) };
            _chkStartMenuShortcut = new CheckBox { Content = "Criar atalho no Menu Iniciar", IsChecked = true, Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)), Margin = new Thickness(0, 2, 0, 2) };
            taskStack.Children.Add(_chkAddToPath);
            taskStack.Children.Add(_chkDesktopShortcut);
            taskStack.Children.Add(_chkStartMenuShortcut);
            taskCard.Child = taskStack;
            _pageOptions.Children.Add(taskCard);

            // Destination Folder Selection Card
            var destCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12)
            };
            var destStack = new StackPanel();
            destStack.Children.Add(new TextBlock
            {
                Text = "📁 Pasta de Destino da Instalação:",
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                Margin = new Thickness(0, 0, 0, 6)
            });

            var pathGrid = new Grid();
            pathGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            pathGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            _txtDestinationPath = new TextBox
            {
                Text = _installDir,
                Background = new SolidColorBrush(Color.FromRgb(15, 20, 28)),
                Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(10, 7, 10, 7),
                FontSize = 12,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            _txtDestinationPath.TextChanged += (s, e) =>
            {
                if (!string.IsNullOrEmpty(_txtDestinationPath.Text))
                {
                    _installDir = _txtDestinationPath.Text.Trim();
                    CheckExistingInstallation(_installDir);
                }
            };

            _btnBrowsePath = new Button
            {
                Content = "Procurar...",
                Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(14, 6, 14, 6),
                Margin = new Thickness(8, 0, 0, 0),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _btnBrowsePath.Click += (s, e) =>
            {
                var dialog = new System.Windows.Forms.FolderBrowserDialog
                {
                    Description = "Selecione o diretório onde o Secure LAN File Transfer será instalado:",
                    SelectedPath = _installDir,
                    ShowNewFolderButton = true
                };
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    var selected = dialog.SelectedPath.TrimEnd('\\', '/');
                    if (!selected.EndsWith("SecureLANTransfer", StringComparison.OrdinalIgnoreCase))
                    {
                        selected = Path.Combine(selected, "SecureLANTransfer");
                    }
                    _installDir = selected;
                    _txtDestinationPath.Text = _installDir;
                    CheckExistingInstallation(_installDir);
                }
            };

            Grid.SetColumn(_txtDestinationPath, 0);
            Grid.SetColumn(_btnBrowsePath, 1);
            pathGrid.Children.Add(_txtDestinationPath);
            pathGrid.Children.Add(_btnBrowsePath);
            destStack.Children.Add(pathGrid);
            destCard.Child = destStack;
            _pageOptions.Children.Add(destCard);

            contentGrid.Children.Add(_pageOptions);

            // Page 4: Progress
            _pageProgress = new StackPanel { Visibility = Visibility.Collapsed };
            _pageProgress.Children.Add(new TextBlock
            {
                Text = "Instalando o Secure LAN File Transfer...",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 10)
            });
            _progressBar = new ProgressBar
            {
                Height = 12,
                Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106)),
                Margin = new Thickness(0, 0, 0, 12),
                Maximum = 100,
                Value = 0
            };
            _pageProgress.Children.Add(_progressBar);

            var logScroll = new ScrollViewer
            {
                Height = 250,
                Background = new SolidColorBrush(Color.FromRgb(11, 15, 23)),
                Padding = new Thickness(12),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            _txtInstallLog = new TextBlock
            {
                FontFamily = new FontFamily("Consolas"),
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 18
            };
            logScroll.Content = _txtInstallLog;
            var logBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(11, 15, 23)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Child = logScroll
            };
            _pageProgress.Children.Add(logBorder);
            contentGrid.Children.Add(_pageProgress);

            // Page 5: Complete
            _pageComplete = new StackPanel { Visibility = Visibility.Collapsed };
            _pageComplete.Children.Add(new TextBlock
            {
                Text = "Instalação Concluída com Sucesso!",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106)),
                Margin = new Thickness(0, 0, 0, 8)
            });
            _pageComplete.Children.Add(new TextBlock
            {
                Text = "O Secure LAN File Transfer está pronto para uso na sua rede.",
                FontSize = 13,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 14)
            });

            var cardStart = CreateInfoCard("💡 Como começar:", Color.FromRgb(56, 189, 248), new[]
            {
                "• Abra o aplicativo gráfico pelo ícone na Área de Trabalho.",
                "• Ou abra o terminal (CMD/PowerShell) e digite 'slft' para o Hub interativo.",
                "• Exemplos: 'slft foto.png', 'slft pasta/' ou 'slft recv'."
            });
            _pageComplete.Children.Add(cardStart);

            _chkRunNow = new CheckBox
            {
                Content = "Executar o Secure LAN Transfer agora",
                IsChecked = true,
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                FontWeight = FontWeights.SemiBold,
                FontSize = 13,
                Margin = new Thickness(0, 10, 0, 0)
            };
            _pageComplete.Children.Add(_chkRunNow);
            contentGrid.Children.Add(_pageComplete);

            Grid.SetRow(contentGrid, 1);
            rootGrid.Children.Add(contentGrid);

            // 3. Footer Buttons
            var footerBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(20, 27, 38)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                BorderThickness = new Thickness(0, 1, 0, 0),
                Padding = new Thickness(24, 12, 24, 12)
            };
            var footerGrid = new Grid();
            footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            _btnCancel = CreateStyledButton("Cancelar", Color.FromRgb(26, 35, 50), Color.FromRgb(148, 163, 184), Color.FromRgb(71, 85, 105));
            _btnCancel.Click += (s, e) => Close();

            _btnBack = CreateStyledButton("< Voltar", Color.FromRgb(26, 35, 50), Color.FromRgb(203, 213, 225), Color.FromRgb(71, 85, 105));
            _btnBack.Margin = new Thickness(0, 0, 12, 0);
            _btnBack.Click += (s, e) =>
            {
                if (_currentPage > 1)
                {
                    _currentPage--;
                    UpdateUIState();
                }
            };

            _btnNext = CreateStyledButton("Avançar >", Color.FromRgb(0, 210, 106), Color.FromRgb(11, 15, 23), Color.FromRgb(0, 210, 106));
            _btnNext.Click += async (s, e) =>
            {
                if (_currentPage == 1)
                {
                    _currentPage = 2;
                    UpdateUIState();
                }
                else if (_currentPage == 2)
                {
                    _currentPage = 3;
                    UpdateUIState();
                }
                else if (_currentPage == 3)
                {
                    if (!string.IsNullOrEmpty(_txtDestinationPath.Text))
                    {
                        var path = _txtDestinationPath.Text.Trim().TrimEnd('\\', '/');
                        if (!path.EndsWith("SecureLANTransfer", StringComparison.OrdinalIgnoreCase))
                        {
                            path = Path.Combine(path, "SecureLANTransfer");
                        }
                        _installDir = path;
                        _txtDestinationPath.Text = _installDir;
                    }
                    await PerformInstallationAsync();
                }
                else if (_currentPage == 5)
                {
                    if (_chkRunNow.IsChecked == true)
                    {
                        var appExe = Path.Combine(_installDir, "secure_lan_transfer.exe");
                        if (File.Exists(appExe))
                        {
                            Process.Start(new ProcessStartInfo(appExe) { UseShellExecute = true });
                        }
                    }
                    Close();
                }
            };

            Grid.SetColumn(_btnCancel, 0);
            Grid.SetColumn(_btnBack, 2);
            Grid.SetColumn(_btnNext, 3);
            footerGrid.Children.Add(_btnCancel);
            footerGrid.Children.Add(_btnBack);
            footerGrid.Children.Add(_btnNext);
            footerBorder.Child = footerGrid;
            Grid.SetRow(footerBorder, 2);
            rootGrid.Children.Add(footerBorder);

            Content = rootGrid;
        }

        private void AddTermSection(StackPanel panel, string title, string text)
        {
            panel.Children.Add(new TextBlock
            {
                Text = title,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                Margin = new Thickness(0, 4, 0, 2),
                FontSize = 12
            });
            panel.Children.Add(new TextBlock
            {
                Text = text,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 8),
                LineHeight = 17
            });
        }

        private Border CreateInfoCard(string title, Color titleColor, string[] bullets)
        {
            var card = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14),
                Margin = new Thickness(0, 0, 0, 10)
            };
            var stack = new StackPanel();
            stack.Children.Add(new TextBlock
            {
                Text = title,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(titleColor),
                Margin = new Thickness(0, 0, 0, 6)
            });
            foreach (var b in bullets)
            {
                stack.Children.Add(new TextBlock
                {
                    Text = b,
                    FontSize = 12,
                    Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                    Margin = new Thickness(0, 2, 0, 2),
                    TextWrapping = TextWrapping.Wrap,
                    LineHeight = 17
                });
            }
            card.Child = stack;
            return card;
        }

        private Button CreateStyledButton(string text, Color bg, Color fg, Color border)
        {
            return new Button
            {
                Content = text,
                Background = new SolidColorBrush(bg),
                Foreground = new SolidColorBrush(fg),
                BorderBrush = new SolidColorBrush(border),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(18, 8, 18, 8),
                MinWidth = 135,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Cursor = System.Windows.Input.Cursors.Hand
            };
        }

        private void UpdateUIState()
        {
            _pageWelcome.Visibility = _currentPage == 1 ? Visibility.Visible : Visibility.Collapsed;
            _pageTerms.Visibility = _currentPage == 2 ? Visibility.Visible : Visibility.Collapsed;
            _pageOptions.Visibility = _currentPage == 3 ? Visibility.Visible : Visibility.Collapsed;
            _pageProgress.Visibility = _currentPage == 4 ? Visibility.Visible : Visibility.Collapsed;
            _pageComplete.Visibility = _currentPage == 5 ? Visibility.Visible : Visibility.Collapsed;

            _btnBack.Visibility = (_currentPage > 1 && _currentPage < 4) ? Visibility.Visible : Visibility.Collapsed;
            _btnCancel.Visibility = _currentPage <= 3 ? Visibility.Visible : Visibility.Collapsed;

            switch (_currentPage)
            {
                case 1:
                    _headerSubtitle.Text = "Visão Geral e Arquitetura da Aplicação";
                    _btnNext.Content = "Avançar >";
                    _btnNext.IsEnabled = true;
                    break;
                case 2:
                    _headerSubtitle.Text = "Termos de Segurança e Privacidade E2EE";
                    _btnNext.Content = "Aceitar e Continuar >";
                    _btnNext.IsEnabled = _chkAcceptTerms.IsChecked == true;
                    break;
                case 3:
                    _headerSubtitle.Text = "Personalização de Componentes e Destino";
                    _btnNext.Content = "Iniciar Instalação";
                    _btnNext.IsEnabled = true;
                    break;
                case 4:
                    _headerSubtitle.Text = "Copiando arquivos e registrando comandos...";
                    _btnNext.Visibility = Visibility.Collapsed;
                    _btnBack.Visibility = Visibility.Collapsed;
                    _btnCancel.Visibility = Visibility.Collapsed;
                    break;
                case 5:
                    _headerSubtitle.Text = "Pronto para uso!";
                    _btnNext.Visibility = Visibility.Visible;
                    _btnNext.Content = "Concluir";
                    _btnNext.IsEnabled = true;
                    break;
            }
        }

        private void AppendLog(string msg)
        {
            _txtInstallLog.Text += string.Format("[{0}] {1}\r\n", DateTime.Now.ToString("HH:mm:ss"), msg);
        }

        private async Task PerformInstallationAsync()
        {
            _currentPage = 4;
            UpdateUIState();

            _progressBar.Value = 5;
            AppendLog("Verificando processos ativos...");

            // Terminate existing processes if running
            try
            {
                foreach (var proc in Process.GetProcessesByName("secure_lan_transfer"))
                {
                    proc.Kill();
                    proc.WaitForExit(1500);
                }
                foreach (var proc in Process.GetProcessesByName("slft"))
                {
                    proc.Kill();
                    proc.WaitForExit(1500);
                }
            }
            catch { }

            _progressBar.Value = 15;

            // Handle clean install vs overwrite
            if (_existingInstallCard.Visibility == Visibility.Visible && _rbCleanInstall.IsChecked == true)
            {
                if (Directory.Exists(_installDir))
                {
                    AppendLog("Executando instalação limpa: removendo arquivos antigos...");
                    try
                    {
                        foreach (var f in Directory.GetFiles(_installDir))
                        {
                            try { File.Delete(f); } catch { }
                        }
                        foreach (var d in Directory.GetDirectories(_installDir))
                        {
                            try { Directory.Delete(d, true); } catch { }
                        }
                        AppendLog("✓ Diretório limpo com sucesso.");
                    }
                    catch { }
                }
            }
            else if (_existingInstallCard.Visibility == Visibility.Visible && _rbOverwrite.IsChecked == true)
            {
                AppendLog("Modo de atualização: sobrescrevendo arquivos existentes...");
            }

            AppendLog(string.Format("Preparando diretório: {0}", _installDir));
            Directory.CreateDirectory(_installDir);

            await Task.Delay(250);
            _progressBar.Value = 35;

            if (_chkInstallDesktop.IsChecked == true)
            {
                AppendLog("Instalando Aplicativo Desktop (Flutter GUI)...");
                var releaseGuiDir = Path.Combine(_sourceDir, "build", "windows", "x64", "runner", "Release");
                if (Directory.Exists(releaseGuiDir))
                {
                    CopyDirectory(releaseGuiDir, _installDir);
                    AppendLog("✓ Aplicativo Desktop instalado com sucesso.");
                }
                else
                {
                    AppendLog("⚠️ Pasta Release da GUI não encontrada.");
                }
            }

            await Task.Delay(250);
            _progressBar.Value = 60;

            if (_chkInstallCli.IsChecked == true)
            {
                AppendLog("Instalando CLI nativo (slft.exe)...");
                var cliExe = Path.Combine(_sourceDir, "slft.exe");
                if (File.Exists(cliExe))
                {
                    File.Copy(cliExe, Path.Combine(_installDir, "slft.exe"), true);
                    AppendLog("✓ Executável 'slft.exe' copiado.");
                }
            }

            await Task.Delay(250);
            _progressBar.Value = 75;

            if (_chkAddToPath.IsChecked == true)
            {
                AppendLog("Registrando 'slft' no PATH de usuário...");
                var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
                if (!userPath.Contains(_installDir))
                {
                    var newPath = string.IsNullOrEmpty(userPath) ? _installDir : userPath + ";" + _installDir;
                    Environment.SetEnvironmentVariable("Path", newPath, EnvironmentVariableTarget.User);
                    AppendLog("✓ PATH atualizado. O comando 'slft' funcionará em qualquer terminal.");
                }
                else
                {
                    AppendLog("✓ Pasta já presente no PATH.");
                }
            }

            await Task.Delay(250);
            _progressBar.Value = 85;

            if (_chkDesktopShortcut.IsChecked == true)
            {
                var desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                var targetExe = Path.Combine(_installDir, "secure_lan_transfer.exe");
                CreateShortcut(Path.Combine(desktopPath, "Secure LAN Transfer.lnk"), targetExe, _installDir);
                AppendLog("✓ Atalho criado na Área de Trabalho.");
            }

            if (_chkStartMenuShortcut.IsChecked == true)
            {
                var startPath = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                var targetExe = Path.Combine(_installDir, "secure_lan_transfer.exe");
                CreateShortcut(Path.Combine(startPath, "Secure LAN Transfer.lnk"), targetExe, _installDir);
                AppendLog("✓ Atalho criado no Menu Iniciar.");
            }

            // Copy uninstaller to install directory and create uninstaller shortcut
            try
            {
                var uninstallerExe = Path.Combine(_sourceDir, "Desinstalar.exe");
                if (File.Exists(uninstallerExe))
                {
                    var destUninstaller = Path.Combine(_installDir, "Desinstalar.exe");
                    File.Copy(uninstallerExe, destUninstaller, true);
                    var startPath = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                    CreateShortcut(Path.Combine(startPath, "Desinstalar Secure LAN Transfer.lnk"), destUninstaller, _installDir);
                    AppendLog("✓ Assistente de Desinstalação instalado.");
                }
            }
            catch { }

            _progressBar.Value = 100;
            AppendLog("✓ Instalação concluída com 100% de sucesso!");

            await Task.Delay(700);
            _currentPage = 5;
            UpdateUIState();
        }

        private static void CopyDirectory(string sourceDir, string destinationDir)
        {
            foreach (var dir in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
            {
                Directory.CreateDirectory(dir.Replace(sourceDir, destinationDir));
            }
            foreach (var file in Directory.GetFiles(sourceDir, "*.*", SearchOption.AllDirectories))
            {
                File.Copy(file, file.Replace(sourceDir, destinationDir), true);
            }
        }

        private static void CreateShortcut(string shortcutPath, string targetPath, string workingDir)
        {
            if (!File.Exists(targetPath)) return;
            var vbsCode = string.Format(
                "Set w = CreateObject(\"WScript.Shell\")\n" +
                "Set s = w.CreateShortcut(\"{0}\")\n" +
                "s.TargetPath = \"{1}\"\n" +
                "s.WorkingDirectory = \"{2}\"\n" +
                "s.Description = \"Secure LAN File Transfer\"\n" +
                "s.Save\n",
                shortcutPath.Replace("\\", "\\\\"),
                targetPath.Replace("\\", "\\\\"),
                workingDir.Replace("\\", "\\\\")
            );
            var tempVbs = Path.Combine(Path.GetTempPath(), "shortcut_" + Guid.NewGuid().ToString("N") + ".vbs");
            File.WriteAllText(tempVbs, vbsCode);
            try
            {
                var p = Process.Start("wscript.exe", tempVbs);
                p.WaitForExit(3000);
            }
            finally
            {
                if (File.Exists(tempVbs)) File.Delete(tempVbs);
            }
        }
    }
}
