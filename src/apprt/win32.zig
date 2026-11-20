//! Experimental native runtime. Window/core event loop first; terminal creation
//! is gated on the graphics and IO readiness checks in windows-integration.md.
pub const App = @import("win32/App.zig");
pub const Surface = @import("win32/Surface.zig");
pub const resourcesDir = @import("../os/main.zig").resourcesDir;
