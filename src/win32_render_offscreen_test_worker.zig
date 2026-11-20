//! Private functional fixture only; never installed by the app install step.
pub const gpu_worker_offscreen_context = true;
pub fn main() void {
    @import("win32_render_text_worker.zig").main();
}
