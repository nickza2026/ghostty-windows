//! Standalone CPU-only contract/layout test root; not a terminal host.
test {
    _ = @import("renderer/GlslData.zig");
    _ = @import("renderer/GlslCatalog.zig");
    _ = @import("renderer/remote/Protocol.zig");
    _ = @import("renderer/remote/Registry.zig");
    _ = @import("renderer/remote/Commands.zig");
    _ = @import("renderer/remote/ShaderPayload.zig");
    _ = @import("renderer/remote/TextFrame.zig");
    _ = @import("renderer/CpuExportedFrame.zig");
    _ = @import("renderer/remote/RequestBuffer.zig");
}
