//! Test artifact ONLY, installed by windows-render-client-check, not app install.
pub const gpu_worker_fault_fixture = true;
pub const gpu_worker_offscreen_context = true;
pub fn main() void {
    @import("win32_render_text_worker.zig").main();
}
