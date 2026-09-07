using System.Windows;

namespace YukiCompanion.Windows;

public partial class App : System.Windows.Application
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
        window.Hide();
        var pet = new PetWindow(window);
        pet.Show();
        if (configuration.AutomaticUpdates) _ = UpdateService.CheckAsync(manual: false, window);
    }
}
