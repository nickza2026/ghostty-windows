//! CPU-only candidate codec suite. Root at src/ so shared CPU GLSL layouts and
//! math stay within Zig's module boundary. No GPU or runtime imports required.
const std = @import("std");
test {
    std.testing.refAllDecls(@import("renderer/remote/ImageFrame.zig"));
}
