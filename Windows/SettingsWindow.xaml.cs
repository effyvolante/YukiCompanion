using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;

namespace YukiCompanion.Windows;

public partial class SettingsWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.WindowInfo> availableWindows = [];
    public event Action? Saved;

    public SettingsWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute));
        this.configuration = configuration;
        NameBox.Text = configuration.CompanionDisplayName;
        ConversationBox.Text = configuration.ChromeConversation;
        ChatUrlBox.Text = configuration.ChatUrl;
        BrowserBox.ItemsSource = BrowserChoice.All;
        BrowserBox.SelectedValue = configuration.Browser;
        BackgroundBrowserBox.IsChecked = configuration.BackgroundBrowser;
        AutomaticLookBox.IsChecked = configuration.AutomaticLook;
        LaunchAtLoginBox.IsChecked = configuration.LaunchAtLogin;
        AutomaticUpdatesBox.IsChecked = configuration.AutomaticUpdates;
        ThemeBox.ItemsSource = ThemeChoice.All;
        ThemeBox.SelectedValue = configuration.ThemeId;
        RefreshApplicationList();
    }

    private void RefreshApplications(object sender, RoutedEventArgs e) => RefreshApplicationList();

    private void RefreshApplicationList()
    {
        availableWindows = windows.Discover();
        WindowBox.ItemsSource = availableWindows;
        var watched = configuration.WatchedApplication;
        WindowBox.SelectedItem = availableWindows.FirstOrDefault(item =>
            string.Equals(item.Identifier, watched?.Identifier, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(item.Title, watched?.WindowIdentifier, StringComparison.OrdinalIgnoreCase))
            ?? availableWindows.FirstOrDefault();
    }

    private void Save(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(NameBox.Text)) { System.Windows.MessageBox.Show("Choose a name for Yuki first.", Title); return; }
        configuration.CompanionDisplayName = NameBox.Text.Trim();
        configuration.ThemeId = (ThemeBox.SelectedValue as string) ?? "Yuki";
        configuration.ChromeConversation = ConversationBox.Text.Trim().Length == 0 ? "Yuki — App Companion" : ConversationBox.Text.Trim();
        configuration.ChatUrl = Uri.TryCreate(ChatUrlBox.Text.Trim(), UriKind.Absolute, out var chatUrl) && chatUrl.Scheme == Uri.UriSchemeHttps && (chatUrl.Host.Equals("chatgpt.com", StringComparison.OrdinalIgnoreCase) || chatUrl.Host.Equals("chat.openai.com", StringComparison.OrdinalIgnoreCase)) ? chatUrl.ToString() : "https://chatgpt.com/";
        configuration.Browser = (BrowserBox.SelectedValue as string) ?? "default";
        configuration.BackgroundBrowser = BackgroundBrowserBox.IsChecked != false;
        configuration.AutomaticLook = AutomaticLookBox.IsChecked == true;
        configuration.LaunchAtLogin = LaunchAtLoginBox.IsChecked == true;
        configuration.AutomaticUpdates = AutomaticUpdatesBox.IsChecked != false;
        if (WindowBox.SelectedItem is WatchedWindowService.WindowInfo window)
        {
            configuration.WatchedApplication = new WatchedApplication { DisplayName = window.ProcessName, Identifier = window.Identifier, WindowIdentifier = window.Title };
        }
        configuration.Save();
        Saved?.Invoke();
        Close();
    }

    private void Cancel(object sender, RoutedEventArgs e) => Close();

    private async void CheckForUpdates(object sender, RoutedEventArgs e) => await UpdateService.CheckAsync(manual: true, this);

    private void OpenChromeExtensions(object sender, RoutedEventArgs e)
    {
        OpenExtensionsPage("chrome://extensions", "Open Google Chrome and enter chrome://extensions in its address bar.");
    }

    private void OpenEdgeExtensions(object sender, RoutedEventArgs e)
    {
        OpenExtensionsPage("edge://extensions", "Open Microsoft Edge and enter edge://extensions in its address bar.");
    }

    private void OpenExtensionsPage(string address, string fallback)
    {
        try { Process.Start(new ProcessStartInfo { FileName = address, UseShellExecute = true }); }
        catch { System.Windows.MessageBox.Show(fallback, Title); }
    }

    private sealed record ThemeChoice(string Id, string Name)
    {
        public static readonly ThemeChoice[] All =
        [
            new("Yuki", "Yuki — Pink octopus"),
            new("Peaches", "Peaches — BETA · Cream bunny")
        ];
    }

    private sealed record BrowserChoice(string Id, string Name)
    {
        public static readonly BrowserChoice[] All = [new("default", "Default browser"), new("chrome", "Google Chrome"), new("edge", "Microsoft Edge")];
    }

}
