//! Explicit user shortcuts only. Never enables guest clipboard protocols.
pub fn apply(config: anytype) !void {
    const alloc = config.arenaAlloc();
    // Only consume Ctrl+C when the real core copy action has a selection.
    // Otherwise its performable binding falls through to terminal ETX.
    try config.keybind.parseCLI(alloc, "performable:ctrl+c=copy_to_clipboard");
    try config.keybind.parseCLI(alloc, "ctrl+v=paste_from_clipboard");
    config.@"right-click-action" = .copy;
}
