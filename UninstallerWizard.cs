using System;
using System.IO;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SecureLanTransfer.Uninstaller
{
    public class App : Application
    {
        [STAThread]
        public static void Main()
        {
            var app = new App();
            app.Run(new UninstallerWindow());
        }
    }

    public class DetectedLocation
    {
        public string Path { get; set; }
        public string Description { get; set; }
        public bool IsSourceCode { get; set; }
        public CheckBox CheckBox { get; set; }

        public DetectedLocation(string path, string desc, bool isSource = false)
        {
            Path = path;
            Description = desc;
            IsSourceCode = isSource;
        }
    }

    public class UninstallerWindow : Window
    {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19;

        private int _currentPage = 1;
        private readonly List<DetectedLocation> _detectedLocations = new List<DetectedLocation>();

        // UI Controls
        private TextBlock _headerSubtitle;
        private StackPanel _pageConfirm;
        private StackPanel _pageProgress;
        private StackPanel _pageComplete;

        private StackPanel _locationsListPanel;
        private CheckBox _chkRemoveShortcuts;
        private CheckBox _chkRemovePath;
        private CheckBox _chkRemoveUserData;

        private ProgressBar _progressBar;
        private TextBlock _txtUninstallLog;

        private Button _btnCancel;
        private Button _btnUninstall;

        public UninstallerWindow()
        {
            Title = "Assistente de Desinstalação — Secure LAN File Transfer";
            Width = 750;
            Height = 620;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ResizeMode = ResizeMode.NoResize;
            Background = new SolidColorBrush(Color.FromRgb(15, 20, 28)); // #0F141C
            Foreground = new SolidColorBrush(Color.FromRgb(224, 230, 237));
            FontFamily = new FontFamily("Segoe UI");

            ScanForInstallations();

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
            UpdateUIState();
        }

        private static string ResolveShortcutTarget(string shortcutPath)
        {
            if (!File.Exists(shortcutPath)) return null;
            try
            {
                var vbsCode = string.Format(
                    "Set w = CreateObject(\"WScript.Shell\")\n" +
                    "Set s = w.CreateShortcut(\"{0}\")\n" +
                    "WScript.Echo s.TargetPath\n",
                    shortcutPath.Replace("\\", "\\\\")
                );
                var tempVbs = Path.Combine(Path.GetTempPath(), "resolve_" + Guid.NewGuid().ToString("N") + ".vbs");
                File.WriteAllText(tempVbs, vbsCode);
                try
                {
                    var p = new Process
                    {
                        StartInfo = new ProcessStartInfo("cscript.exe", string.Format("//NoLogo \"{0}\"", tempVbs))
                        {
                            RedirectStandardOutput = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        }
                    };
                    p.Start();
                    var output = p.StandardOutput.ReadToEnd().Trim();
                    p.WaitForExit(2000);
                    if (!string.IsNullOrEmpty(output) && File.Exists(output))
                    {
                        return Path.GetDirectoryName(output);
                    }
                }
                finally
                {
                    if (File.Exists(tempVbs)) File.Delete(tempVbs);
                }
            }
            catch { }
            return null;
        }

        private void ScanForInstallations()
        {
            _detectedLocations.Clear();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // 1. Shortcut from Desktop
            var desktopLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Secure LAN Transfer.lnk");
            var targetFromDesktop = ResolveShortcutTarget(desktopLnk);
            if (!string.IsNullOrEmpty(targetFromDesktop) && Directory.Exists(targetFromDesktop) && !seen.Contains(targetFromDesktop))
            {
                bool isSrc = File.Exists(Path.Combine(targetFromDesktop, "pubspec.yaml"));
                _detectedLocations.Add(new DetectedLocation(targetFromDesktop, "Atalho da Área de Trabalho (" + (isSrc ? "Código-Fonte" : "Instalação") + ")", isSrc));
                seen.Add(targetFromDesktop);
            }

            // 2. Shortcut from Start Menu
            var startLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Secure LAN Transfer.lnk");
            var targetFromStart = ResolveShortcutTarget(startLnk);
            if (!string.IsNullOrEmpty(targetFromStart) && Directory.Exists(targetFromStart) && !seen.Contains(targetFromStart))
            {
                bool isSrc = File.Exists(Path.Combine(targetFromStart, "pubspec.yaml"));
                _detectedLocations.Add(new DetectedLocation(targetFromStart, "Atalho do Menu Iniciar (" + (isSrc ? "Código-Fonte" : "Instalação") + ")", isSrc));
                seen.Add(targetFromStart);
            }

            // 3. Standard LocalAppData directory
            var defaultPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SecureLANTransfer");
            if (Directory.Exists(defaultPath) && !seen.Contains(defaultPath))
            {
                _detectedLocations.Add(new DetectedLocation(defaultPath, "Pasta Padrão de Programas (AppData)", false));
                seen.Add(defaultPath);
            }

            // 4. Downloads folder installation
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var downloadsInstall = Path.Combine(userProfile, "Downloads", "SecureLANTransfer");
            if (Directory.Exists(downloadsInstall) && !seen.Contains(downloadsInstall))
            {
                _detectedLocations.Add(new DetectedLocation(downloadsInstall, "Instalação Personalizada em Downloads", false));
                seen.Add(downloadsInstall);
            }

            // 5. Check PATH environment variable entries
            var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
            foreach (var part in userPath.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var p = part.Trim();
                if (Directory.Exists(p) && !seen.Contains(p))
                {
                    if (File.Exists(Path.Combine(p, "slft.exe")) || File.Exists(Path.Combine(p, "secure_lan_transfer.exe")))
                    {
                        bool isSrc = File.Exists(Path.Combine(p, "pubspec.yaml"));
                        _detectedLocations.Add(new DetectedLocation(p, "Diretório Registrado no PATH", isSrc));
                        seen.Add(p);
                    }
                }
            }

            // 6. Running processes location
            try
            {
                foreach (var proc in Process.GetProcessesByName("secure_lan_transfer"))
                {
                    var exePath = proc.MainModule.FileName;
                    var dir = Path.GetDirectoryName(exePath);
                    if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir) && !seen.Contains(dir))
                    {
                        bool isSrc = File.Exists(Path.Combine(dir, "pubspec.yaml"));
                        _detectedLocations.Add(new DetectedLocation(dir, "Instalação Ativa em Execução", isSrc));
                        seen.Add(dir);
                    }
                }
            }
            catch { }
        }

        private void BuildUI()
        {
            var rootGrid = new Grid();
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(72) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(64) });

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
                Text = "Desinstalar Secure LAN File Transfer",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 113, 113))
            };
            _headerSubtitle = new TextBlock
            {
                Text = "Varredura e Remoção Completa de Instalações",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 3, 0, 0)
            };
            headerStack.Children.Add(headerTitle);
            headerStack.Children.Add(_headerSubtitle);

            var badgeBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(40, 15, 20)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(248, 113, 113)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(5),
                Padding = new Thickness(10, 4, 10, 4),
                VerticalAlignment = VerticalAlignment.Center
            };
            var badgeText = new TextBlock
            {
                Text = "Varredura Automática",
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 113, 113))
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

            // Page 1: Multi-Location Selection
            _pageConfirm = new StackPanel();
            _pageConfirm.Children.Add(new TextBlock
            {
                Text = "Locais de Instalação Identificados no Sistema:",
                FontSize = 15,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 4)
            });
            _pageConfirm.Children.Add(new TextBlock
            {
                Text = "O assistente varreu o sistema e encontrou as pastas abaixo vinculadas ao aplicativo. Selecione quais deseja remover:",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 10),
                TextWrapping = TextWrapping.Wrap
            });

            // Locations List Box
            var scrollLocations = new ScrollViewer
            {
                Height = 175,
                Background = new SolidColorBrush(Color.FromRgb(19, 26, 36)),
                Padding = new Thickness(10),
                Margin = new Thickness(0, 0, 0, 10),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            var locationsBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(19, 26, 36)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Child = scrollLocations
            };
            _locationsListPanel = new StackPanel();
            PopulateLocationsList();
            scrollLocations.Content = _locationsListPanel;
            _pageConfirm.Children.Add(locationsBorder);

            // Add manual folder button row
            var manualRow = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            var btnAddManual = new Button
            {
                Content = "+ Adicionar Outra Pasta Manualmente...",
                Background = new SolidColorBrush(Color.FromRgb(26, 35, 50)),
                Foreground = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(56, 189, 248)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(12, 4, 12, 4),
                FontSize = 11,
                Cursor = System.Windows.Input.Cursors.Hand,
                HorizontalAlignment = HorizontalAlignment.Left
            };
            btnAddManual.Click += (s, e) =>
            {
                var dialog = new System.Windows.Forms.FolderBrowserDialog
                {
                    Description = "Selecione a pasta onde o Secure LAN File Transfer está instalado:"
                };
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    var path = dialog.SelectedPath;
                    bool isSrc = File.Exists(Path.Combine(path, "pubspec.yaml"));
                    var loc = new DetectedLocation(path, "Pasta Adicionada Manualmente", isSrc);
                    _detectedLocations.Add(loc);
                    PopulateLocationsList();
                }
            };
            manualRow.Children.Add(btnAddManual);
            _pageConfirm.Children.Add(manualRow);

            // Cleanup options
            var optionsCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(10)
            };
            var optionsStack = new StackPanel();
            _chkRemoveShortcuts = new CheckBox
            {
                Content = "Remover atalhos da Área de Trabalho e Menu Iniciar",
                IsChecked = true,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                Margin = new Thickness(0, 2, 0, 2),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _chkRemovePath = new CheckBox
            {
                Content = "Limpar entradas do comando 'slft' da variável de ambiente PATH",
                IsChecked = true,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                Margin = new Thickness(0, 2, 0, 2),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _chkRemoveUserData = new CheckBox
            {
                Content = "Limpar preferências e configurações do usuário",
                IsChecked = true,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225)),
                Margin = new Thickness(0, 2, 0, 2),
                Cursor = System.Windows.Input.Cursors.Hand
            };
            optionsStack.Children.Add(_chkRemoveShortcuts);
            optionsStack.Children.Add(_chkRemovePath);
            optionsStack.Children.Add(_chkRemoveUserData);
            optionsCard.Child = optionsStack;
            _pageConfirm.Children.Add(optionsCard);
            contentGrid.Children.Add(_pageConfirm);

            // Page 2: Progress
            _pageProgress = new StackPanel { Visibility = Visibility.Collapsed };
            _pageProgress.Children.Add(new TextBlock
            {
                Text = "Desinstalando o Secure LAN File Transfer...",
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
                Margin = new Thickness(0, 0, 0, 10)
            });
            _progressBar = new ProgressBar
            {
                Height = 12,
                Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
                Foreground = new SolidColorBrush(Color.FromRgb(248, 113, 113)),
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
            _txtUninstallLog = new TextBlock
            {
                FontFamily = new FontFamily("Consolas"),
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 18
            };
            logScroll.Content = _txtUninstallLog;
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

            // Page 3: Complete
            _pageComplete = new StackPanel { Visibility = Visibility.Collapsed };
            _pageComplete.Children.Add(new TextBlock
            {
                Text = "Desinstalação Concluída com Sucesso!",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromRgb(0, 210, 106)),
                Margin = new Thickness(0, 0, 0, 8)
            });
            _pageComplete.Children.Add(new TextBlock
            {
                Text = "Todos os arquivos das pastas selecionadas, atalhos e registros de ambiente foram removidos com sucesso.",
                FontSize = 13,
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                Margin = new Thickness(0, 0, 0, 16)
            });
            var completeCard = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14)
            };
            var completeStack = new StackPanel();
            completeStack.Children.Add(new TextBlock
            {
                Text = "✓ O sistema foi limpo e restaurado com 100% de integridade.",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(203, 213, 225))
            });
            completeCard.Child = completeStack;
            _pageComplete.Children.Add(completeCard);
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

            _btnCancel = new Button
            {
                Content = "Cancelar",
                Background = new SolidColorBrush(Color.FromRgb(26, 35, 50)),
                Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(71, 85, 105)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(18, 8, 18, 8),
                MinWidth = 110,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _btnCancel.Click += (s, e) => Close();

            _btnUninstall = new Button
            {
                Content = "Desinstalar Agora",
                Background = new SolidColorBrush(Color.FromRgb(220, 38, 38)),
                Foreground = new SolidColorBrush(Colors.White),
                BorderBrush = new SolidColorBrush(Color.FromRgb(248, 113, 113)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(18, 8, 18, 8),
                MinWidth = 140,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Cursor = System.Windows.Input.Cursors.Hand
            };
            _btnUninstall.Click += async (s, e) =>
            {
                if (_currentPage == 1)
                {
                    await PerformUninstallationAsync();
                }
                else if (_currentPage == 3)
                {
                    Close();
                }
            };

            Grid.SetColumn(_btnCancel, 0);
            Grid.SetColumn(_btnUninstall, 2);
            footerGrid.Children.Add(_btnCancel);
            footerGrid.Children.Add(_btnUninstall);
            footerBorder.Child = footerGrid;
            Grid.SetRow(footerBorder, 2);
            rootGrid.Children.Add(footerBorder);

            Content = rootGrid;
        }

        private void PopulateLocationsList()
        {
            _locationsListPanel.Children.Clear();
            if (_detectedLocations.Count == 0)
            {
                _locationsListPanel.Children.Add(new TextBlock
                {
                    Text = "Nenhuma instalação automática foi detectada. Use o botão abaixo para adicionar a pasta.",
                    Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                    FontSize = 12,
                    Margin = new Thickness(4)
                });
                return;
            }

            foreach (var loc in _detectedLocations)
            {
                var card = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(22, 32, 46)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(36, 52, 71)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(10, 8, 10, 8),
                    Margin = new Thickness(0, 0, 0, 6)
                };
                var row = new Grid();
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var chk = new CheckBox
                {
                    IsChecked = !loc.IsSourceCode, // Don't check source code repo by default
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 10, 0)
                };
                loc.CheckBox = chk;

                var textStack = new StackPanel();
                textStack.Children.Add(new TextBlock
                {
                    Text = loc.Path,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(loc.IsSourceCode ? Color.FromRgb(251, 191, 36) : Color.FromRgb(241, 245, 249)),
                    FontSize = 12
                });
                textStack.Children.Add(new TextBlock
                {
                    Text = "↳ " + loc.Description + (loc.IsSourceCode ? " ⚠️ (Pasta do Projeto - marque apenas se quiser apagar o código)" : ""),
                    Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                    FontSize = 11,
                    Margin = new Thickness(0, 2, 0, 0)
                });

                Grid.SetColumn(chk, 0);
                Grid.SetColumn(textStack, 1);
                row.Children.Add(chk);
                row.Children.Add(textStack);
                card.Child = row;
                _locationsListPanel.Children.Add(card);
            }
        }

        private void UpdateUIState()
        {
            _pageConfirm.Visibility = _currentPage == 1 ? Visibility.Visible : Visibility.Collapsed;
            _pageProgress.Visibility = _currentPage == 2 ? Visibility.Visible : Visibility.Collapsed;
            _pageComplete.Visibility = _currentPage == 3 ? Visibility.Visible : Visibility.Collapsed;

            _btnCancel.Visibility = _currentPage == 1 ? Visibility.Visible : Visibility.Collapsed;

            switch (_currentPage)
            {
                case 1:
                    _headerSubtitle.Text = "Varredura e Remoção Completa de Instalações";
                    _btnUninstall.Content = "Desinstalar Agora";
                    _btnUninstall.Background = new SolidColorBrush(Color.FromRgb(220, 38, 38));
                    _btnUninstall.Foreground = new SolidColorBrush(Colors.White);
                    _btnUninstall.BorderBrush = new SolidColorBrush(Color.FromRgb(248, 113, 113));
                    _btnUninstall.IsEnabled = true;
                    break;
                case 2:
                    _headerSubtitle.Text = "Removendo arquivos e registros...";
                    _btnUninstall.Visibility = Visibility.Collapsed;
                    _btnCancel.Visibility = Visibility.Collapsed;
                    break;
                case 3:
                    _headerSubtitle.Text = "Remoção Finalizada";
                    _btnUninstall.Visibility = Visibility.Visible;
                    _btnUninstall.Content = "Concluir";
                    _btnUninstall.Background = new SolidColorBrush(Color.FromRgb(0, 210, 106));
                    _btnUninstall.Foreground = new SolidColorBrush(Color.FromRgb(11, 15, 23));
                    _btnUninstall.BorderBrush = new SolidColorBrush(Color.FromRgb(0, 210, 106));
                    _btnUninstall.IsEnabled = true;
                    break;
            }
        }

        private void AppendLog(string msg)
        {
            _txtUninstallLog.Text += string.Format("[{0}] {1}\r\n", DateTime.Now.ToString("HH:mm:ss"), msg);
        }

        private async Task PerformUninstallationAsync()
        {
            _currentPage = 2;
            UpdateUIState();

            _progressBar.Value = 10;
            AppendLog("Encerrando processos ativos do Secure LAN Transfer...");

            try
            {
                foreach (var proc in Process.GetProcessesByName("secure_lan_transfer"))
                {
                    proc.Kill();
                    proc.WaitForExit(2000);
                }
                foreach (var proc in Process.GetProcessesByName("slft"))
                {
                    proc.Kill();
                    proc.WaitForExit(2000);
                }
            }
            catch { }

            await Task.Delay(300);
            _progressBar.Value = 30;

            if (_chkRemoveShortcuts.IsChecked == true)
            {
                AppendLog("Removendo atalhos do sistema...");
                var desktopShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Secure LAN Transfer.lnk");
                if (File.Exists(desktopShortcut))
                {
                    File.Delete(desktopShortcut);
                    AppendLog("✓ Atalho da Área de Trabalho removido.");
                }

                var startShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Secure LAN Transfer.lnk");
                if (File.Exists(startShortcut))
                {
                    File.Delete(startShortcut);
                    AppendLog("✓ Atalho do Menu Iniciar removido.");
                }

                var uninstallerLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Desinstalar Secure LAN Transfer.lnk");
                if (File.Exists(uninstallerLnk))
                {
                    File.Delete(uninstallerLnk);
                    AppendLog("✓ Atalho do Desinstalador removido.");
                }
            }

            await Task.Delay(300);
            _progressBar.Value = 55;

            var removedPaths = new List<string>();
            foreach (var loc in _detectedLocations)
            {
                if (loc.CheckBox != null && loc.CheckBox.IsChecked == true)
                {
                    removedPaths.Add(loc.Path);
                }
            }

            if (_chkRemovePath.IsChecked == true)
            {
                AppendLog("Limpando variável de ambiente PATH do usuário...");
                var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
                var entries = userPath.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);
                var cleaned = new List<string>();
                foreach (var entry in entries)
                {
                    bool shouldRemove = false;
                    foreach (var rp in removedPaths)
                    {
                        if (entry.Trim().Equals(rp, StringComparison.OrdinalIgnoreCase))
                        {
                            shouldRemove = true;
                            break;
                        }
                    }
                    if (!shouldRemove)
                    {
                        cleaned.Add(entry);
                    }
                }
                Environment.SetEnvironmentVariable("Path", string.Join(";", cleaned), EnvironmentVariableTarget.User);
                AppendLog("✓ PATH do usuário atualizado.");
            }

            await Task.Delay(300);
            _progressBar.Value = 75;

            if (_chkRemoveUserData.IsChecked == true)
            {
                AppendLog("Removendo dados e preferências locais...");
                try
                {
                    var appDataRoaming = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "com.example", "secure_lan_transfer");
                    if (Directory.Exists(appDataRoaming))
                    {
                        Directory.Delete(appDataRoaming, true);
                        AppendLog("✓ Pasta AppData Roaming limpa.");
                    }
                }
                catch { }
            }

            await Task.Delay(300);
            _progressBar.Value = 90;

            // Delete all checked installation directories
            var currentExe = Process.GetCurrentProcess().MainModule.FileName;
            foreach (var path in removedPaths)
            {
                if (Directory.Exists(path))
                {
                    AppendLog(string.Format("Removendo pasta: {0}...", path));
                    try
                    {
                        if (currentExe.StartsWith(path, StringComparison.OrdinalIgnoreCase))
                        {
                            Process.Start(new ProcessStartInfo
                            {
                                FileName = "cmd.exe",
                                Arguments = string.Format("/c timeout /t 2 & rmdir /s /q \"{0}\"", path),
                                WindowStyle = ProcessWindowStyle.Hidden,
                                CreateNoWindow = true
                            });
                            AppendLog("✓ Limpeza agendada após o fechamento do assistente.");
                        }
                        else
                        {
                            Directory.Delete(path, true);
                            AppendLog("✓ Diretório excluído com sucesso.");
                        }
                    }
                    catch (Exception ex)
                    {
                        AppendLog("Nota: Alguns arquivos serão limpos no próximo logon: " + ex.Message);
                    }
                }
            }

            _progressBar.Value = 100;
            AppendLog("✓ Desinstalação concluída com sucesso!");

            await Task.Delay(600);
            _currentPage = 3;
            UpdateUIState();
        }
    }
}
