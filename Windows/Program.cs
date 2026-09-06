using System.Windows;

namespace YukiCompanion.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var configuration = CompanionConfiguration.Load();
        var window = new CompanionWindow(configuration);
        MainWindow = window;
        window.Show();
    }
}
