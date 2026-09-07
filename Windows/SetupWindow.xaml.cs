using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace YukiCompanion.Windows;

public partial class SetupWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.ApplicationInfo> applications = [];
    private int step;
    public SetupWindow(CompanionConfiguration configuration) { InitializeComponent(); this.configuration = configuration; ShowStep(); }
    private void ShowStep()
    {
        StepTitle.Text = step switch { 0 => "Let’s set up your app companion.", 1 => "What should your companion be called?", 2 => "What app should your companion be able to look at?", 3 => "Connect Chrome or Edge", _ => "Your companion is ready!" };
        StepBody.Text = step switch { 0 => "Yuki stays on your desktop and talks through your normal logged-in ChatGPT conversation in Chrome or Edge. This short setup covers the pieces she needs.", 1 => "This name appears in the companion bubble and in your chat transcript. You can change it later in Settings.", 2 => "Choose an application that is currently open, then choose its visible window. Yuki captures only that window when you ask her to look.", 3 => "Open Chrome or Edge’s extension page, load the matching extension folder included with this download, then open your Yuki — App Companion conversation and bind that tab from the Yuki extension menu.", _ => "Yuki is ready. Keep the selected application window open, and keep the bound ChatGPT tab open in your browser." };
        NameBox.Visibility = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        ApplicationBox.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        WindowBox.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        BrowserButtons.Visibility = step == 3 ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = step > 0 && step < 4 ? Visibility.Visible : Visibility.Collapsed;
        NextButton.Content = step >= 4 ? "Finish" : "Continue";
        if (step == 1) { NameBox.Text = configuration.CompanionDisplayName; NameBox.Focus(); }
        if (step == 2) { RefreshApplications(); }
    }

    private void RefreshApplications()
    {
        applications = windows.DiscoverApplications();
        ApplicationBox.ItemsSource = applications;
        var watched = configuration.WatchedApplication;
        ApplicationBox.SelectedItem = applications.FirstOrDefault(item => string.Equals(item.Identifier, watched?.Identifier, StringComparison.OrdinalIgnoreCase)) ?? applications.FirstOrDefault();
    }

    private void ApplicationChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ApplicationBox.SelectedItem is not WatchedWindowService.ApplicationInfo application) return;
        WindowBox.ItemsSource = application.Windows;
        WindowBox.SelectedItem = application.Windows.FirstOrDefault(window => string.Equals(window.Title, configuration.WatchedApplication?.WindowIdentifier, StringComparison.OrdinalIgnoreCase)) ?? application.Windows.FirstOrDefault();
    }

    private void Back(object sender, RoutedEventArgs e) { if (step > 0) { step--; ShowStep(); } }

    private void Next(object sender, RoutedEventArgs e)
    {
        if (step == 1)
        {
            if (string.IsNullOrWhiteSpace(NameBox.Text)) { System.Windows.MessageBox.Show("Choose a name for Yuki first.", Title); return; }
            configuration.CompanionDisplayName = NameBox.Text.Trim();
        }
        if (step == 2)
        {
            if (ApplicationBox.SelectedItem is not WatchedWindowService.ApplicationInfo application || WindowBox.SelectedItem is not WatchedWindowService.WindowInfo selected)
            { System.Windows.MessageBox.Show("Open the application you want Yuki to watch, then choose its window.", Title); return; }
            configuration.WatchedApplication = new() { DisplayName = application.DisplayName, Identifier = application.Identifier, WindowIdentifier = selected.Title };
        }
        if (step >= 4) { configuration.OnboardingCompleted = true; configuration.Save(); DialogResult = true; Close(); return; }
        step++; ShowStep();
    }

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
}
