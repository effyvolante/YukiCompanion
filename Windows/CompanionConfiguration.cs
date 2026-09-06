using System.Text.Json;

namespace YukiCompanion.Windows;

public sealed class CompanionConfiguration
{
    public int SchemaVersion { get; set; } = 1;
    public string CompanionDisplayName { get; set; } = "Yuki";
    public string ThemeId { get; set; } = "Yuki";
    public WatchedApplication? WatchedApplication { get; set; }
    public double Size { get; set; } = 180;
    public double BubbleWidth { get; set; } = 360;
    public bool OnboardingCompleted { get; set; }
    public bool LaunchAtLogin { get; set; }
    public bool AutomaticLook { get; set; }
    public bool AutomaticUpdates { get; set; } = true;

    private static string Path => System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "YukiCompanion", "config.json");

    public static CompanionConfiguration Load()
    {
        try { if (File.Exists(Path)) return JsonSerializer.Deserialize<CompanionConfiguration>(File.ReadAllText(Path)) ?? new(); }
        catch { /* Corrupt settings must not prevent launch; setup can repair them. */ }
        return new();
    }

    public void Save()
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        File.WriteAllText(Path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}

public sealed class WatchedApplication
{
    public string DisplayName { get; set; } = "";
    public string Platform { get; set; } = "Windows";
    public string Identifier { get; set; } = "";
    public string? WindowIdentifier { get; set; }
}
