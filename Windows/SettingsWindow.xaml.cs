using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;

namespace YukiCompanion.Windows;

public partial class SettingsWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.ApplicationInfo> applications = [];
    private IReadOnlyList<WatchedWindowService.WindowInfo> selectedWindows = [];
    public event Action? Saved;

    public SettingsWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute));
        this.configuration = configuration;
        NameBox.Text = configuration.CompanionDisplayName;
        ConversationBox.Text = configuration.ChromeConversation;
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
        applications = windows.DiscoverApplications();
        ApplicationBox.ItemsSource = applications;
        var watched = configuration.WatchedApplication;
        ApplicationBox.SelectedItem = applications.FirstOrDefault(item => string.Equals(item.Identifier, watched?.Identifier, StringComparison.OrdinalIgnoreCase))
            ?? applications.FirstOrDefault();
        if (ApplicationBox.SelectedItem is null) WindowBox.ItemsSource = null;
    }

    private void ApplicationChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ApplicationBox.SelectedItem is not WatchedWindowService.ApplicationInfo application) return;
        selectedWindows = application.Windows;
        WindowBox.ItemsSource = selectedWindows;
        var previousTitle = configuration.WatchedApplication?.WindowIdentifier;
        WindowBox.SelectedItem = selectedWindows.FirstOrDefault(item => string.Equals(item.Title, previousTitle, StringComparison.OrdinalIgnoreCase))
            ?? selectedWindows.FirstOrDefault();
    }

    private void WindowChanged(object sender, SelectionChangedEventArgs e) { }

    private void Save(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(NameBox.Text)) { System.Windows.MessageBox.Show("Choose a name for Yuki first.", Title); return; }
        configuration.CompanionDisplayName = NameBox.Text.Trim();
        configuration.ThemeId = (ThemeBox.SelectedValue as string) ?? "Yuki";
        configuration.ChromeConversation = ConversationBox.Text.Trim().Length == 0 ? "Yuki — App Companion" : ConversationBox.Text.Trim();
        configuration.AutomaticLook = AutomaticLookBox.IsChecked == true;
        configuration.LaunchAtLogin = LaunchAtLoginBox.IsChecked == true;
        configuration.AutomaticUpdates = AutomaticUpdatesBox.IsChecked != false;
        if (ApplicationBox.SelectedItem is WatchedWindowService.ApplicationInfo application)
        {
            var window = WindowBox.SelectedItem as WatchedWindowService.WindowInfo ?? application.Windows.FirstOrDefault();
            configuration.WatchedApplication = new WatchedApplication { DisplayName = application.DisplayName, Identifier = application.Identifier, WindowIdentifier = window?.Title };
        }
        configuration.Save();
        Saved?.Invoke();
        DialogResult = true;
        Close();
    }

    private void Cancel(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }

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
}
