using Xunit;

namespace YukiCompanion.Windows.Tests;

public sealed class CompanionConfigurationTests
{
    [Theory]
    [InlineData("Yuki", "Yuki")]
    [InlineData("Peaches", "Peaches")]
    [InlineData("Belle", "Yuki")]
    [InlineData("Nova", "Yuki")]
    public void RestrictsThemeSelectionToReleasedChoices(string requested, string expected)
    {
        var configuration = new YukiCompanion.Windows.CompanionConfiguration { ThemeId = requested };

        Assert.Equal(expected, configuration.ThemeId);
    }
}
