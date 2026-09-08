using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;

namespace YukiCompanion.Windows;

public static class UpdateService
{
    public const string CurrentVersion = "1.0.6";
    public const string RepositoryUrl = "https://github.com/effyvolante/YukiCompanion";
    private const string ReleasesApi = "https://api.github.com/repos/effyvolante/YukiCompanion/releases/latest";
    private static readonly HttpClient Client = CreateClient();
    private static int checking;

    public static async Task CheckAsync(bool manual, Window? owner = null)
    {
        if (Interlocked.Exchange(ref checking, 1) == 1) return;
        try
        {
            var release = await LatestReleaseAsync();
            if (release is null)
            {
                if (manual) Show(owner, "No published update yet", "Yuki checks the project's GitHub Releases. The latest build will appear there when a release is published.", "Open GitHub", "Later", RepositoryUrl);
                return;
            }
            if (IsNewer(release.TagName))
            {
                var asset = release.Assets.FirstOrDefault(item => item.Name.Contains("windows", StringComparison.OrdinalIgnoreCase) && item.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase));
                Show(owner, $"Yuki {release.TagName} is available", "Open GitHub to download the Windows update? Choose Yes to open it, or No to keep using this version. Quit Yuki before replacing the app, then launch the new copy.", "Open update", "Later", asset?.DownloadUrl ?? release.HtmlUrl);
            }
            else if (manual)
            {
                Show(owner, "Yuki is up to date", $"You are running Yuki {CurrentVersion}.", "Done");
            }
        }
        catch
        {
            if (manual) Show(owner, "Couldn’t check for updates", "GitHub could not be reached right now. You can check the releases page manually.", "Open GitHub", "Later", RepositoryUrl);
        }
        finally { Volatile.Write(ref checking, 0); }
    }

    private static async Task<Release?> LatestReleaseAsync()
    {
        using var response = await Client.GetAsync(ReleasesApi);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync();
        return await JsonSerializer.DeserializeAsync<Release>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    private static bool IsNewer(string tag)
    {
        var current = Parts(CurrentVersion);
        var remote = Parts(tag);
        for (var index = 0; index < Math.Max(current.Length, remote.Length); index++)
        {
            var lhs = index < current.Length ? current[index] : 0;
            var rhs = index < remote.Length ? remote[index] : 0;
            if (lhs != rhs) return rhs > lhs;
        }
        return false;
    }

    private static int[] Parts(string value) => value.TrimStart('v', 'V').Split('.').Select(part => int.TryParse(new string(part.TakeWhile(char.IsDigit).ToArray()), out var number) ? number : 0).ToArray();

    private static void Show(Window? owner, string title, string detail, string firstButton, string? secondButton = null, string? url = null)
    {
        var result = System.Windows.MessageBox.Show(owner, detail, title, secondButton is null ? MessageBoxButton.OK : MessageBoxButton.YesNo, MessageBoxImage.Information);
        if (result == MessageBoxResult.Yes && url is not null) Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("YukiCompanion", CurrentVersion));
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        return client;
    }

    private sealed class Release
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; set; } = "";
        [JsonPropertyName("html_url")]
        public string HtmlUrl { get; set; } = RepositoryUrl;
        public List<Asset> Assets { get; set; } = [];
    }

    private sealed class Asset
    {
        public string Name { get; set; } = "";
        [JsonPropertyName("browser_download_url")]
        public string DownloadUrl { get; set; } = "";
    }
}
