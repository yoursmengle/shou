using Shou.Windows.Presentation;

namespace Shou.Windows.Presentation.Tests;

public sealed class ReviewErrorPresentationTests
{
    [Theory]
    [InlineData("active_or_inaccessible", "These files are in use. Close the application and scan again.")]
    [InlineData("time_limit", "The scan reached its time limit. Scan this location separately or choose a smaller folder.")]
    [InlineData("entry_limit", "The scan reached its item limit. Scan this location separately or choose a smaller folder.")]
    [InlineData("resource_limit", "The operation reached its resource limit. Scan one location or choose a smaller folder.")]
    [InlineData("depth_limit", "The scan reached its folder-depth limit. Choose a smaller folder and scan again.")]
    [InlineData("permission_denied", "Access to this location is unavailable.")]
    [InlineData("source_changed", "The scan or settings changed. Scan again before reviewing.")]
    [InlineData("active_target", "An application or build tool may be using these files. Close it and scan again.")]
    [InlineData("tracked_artifact_content", "tracked_artifact_content")]
    [InlineData("artifact_evidence_unavailable", "artifact_evidence_unavailable")]
    [InlineData(null, "This operation could not be completed. Try again.")]
    [InlineData("unknown_error", "This operation could not be completed. Try again.")]
    public void ErrorsRetainSpecificRecoveryGuidance(string? code, string expected) =>
        Assert.Equal(expected, ReviewErrorPresentation.MessageKey(code));
}
