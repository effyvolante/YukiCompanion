using System.Windows;

namespace YukiCompanion.Windows;

public partial class App : Application
{
    [STAThread]
    public static void Main() => new App().Run();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var configuration = CompanionConfiguration.Load();
        if (!configuration.OnboardingCompleted)
        {
            var setup = new SetupWindow(configuration);
            if (setup.ShowDialog() != true) { Shutdown(); return; }
        }
        var window = new CompanionWindow(configuration);
        MainWindow = window;
        window.Show();
    }
}
