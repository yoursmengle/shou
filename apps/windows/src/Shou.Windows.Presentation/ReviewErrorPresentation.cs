namespace Shou.Windows.Presentation;

public static class ReviewErrorPresentation
{
    public static string MessageKey(string? code) => code switch
    {
        "plan_stale" or "source_changed" => "The scan or settings changed. Scan again before reviewing.",
        "activity_unknown" or "active_target" => "An application or build tool may be using these files. Close it and scan again.",
        "active_or_inaccessible" => "These files are in use. Close the application and scan again.",
        "time_limit" => "The scan reached its time limit. Scan this location separately or choose a smaller folder.",
        "entry_limit" => "The scan reached its item limit. Scan this location separately or choose a smaller folder.",
        "resource_limit" => "The operation reached its resource limit. Scan one location or choose a smaller folder.",
        "depth_limit" => "The scan reached its folder-depth limit. Choose a smaller folder and scan again.",
        "tracked_artifact_content" or "artifact_evidence_unavailable" => code,
        "permission_denied" or "access_expired" => "Access to this location is unavailable.",
        "foreign_owner" => "This location is not owned by the current account.",
        "scan_location_permissions" => "This location's permissions could not be verified.",
        "unsupported_location" => "Choose a local folder without links.",
        "store_busy" => "Another operation is using Shou. Try again shortly.",
        "store_corrupt" => "The saved record could not be verified.",
        "overlapping_selection" => "The selected items overlap. Choose either a folder or its contents.",
        "selection_limit" => "Select up to 256 items for one review.",
        "selection_unavailable" => "This item is protected or incomplete.",
        _ => "This operation could not be completed. Try again."
    };
}
