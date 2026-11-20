//! Explicit fresh portable-tool children only. Never mutate the OS environment.
const std = @import("std");

fn starts(key: []const u8, prefix: []const u8) bool {
    return key.len >= prefix.len and std.ascii.eqlIgnoreCase(key[0..prefix.len], prefix);
}
fn ends(key: []const u8, suffix: []const u8) bool {
    return key.len >= suffix.len and std.ascii.eqlIgnoreCase(key[key.len - suffix.len ..], suffix);
}

pub fn exclude(key: []const u8) bool {
    for ([_][]const u8{ "NODE_", "NPM_", "NVM_", "LETTA_", "LETTACODE_", "BUN_", "OPENSSL_", "AWS_", "AZURE_", "GIT_", "SSH_", "SECRET_" }) |prefix| {
        if (starts(key, prefix)) return true;
    }
    for ([_][]const u8{ "_API_KEY", "_APIKEY", "_TOKEN", "_SECRET", "_PASSWORD", "_PROXY" }) |suffix| {
        if (ends(key, suffix)) return true;
    }
    for ([_][]const u8{
        "GOOGLE_APPLICATION_CREDENTIALS", "CLOUDSDK_CONFIG", "SSL_CERT_FILE",   "SSL_CERT_DIR", "CURL_CA_BUNDLE",
        "AGENT_ID",                       "AGENT_NAME",      "CONVERSATION_ID", "MEMORY_DIR",   "DATABASE_URL",
        "REDIS_URL",                      "PGPASSWORD",      "PGPASSFILE",      "NETRC",        "INIT_CWD",
    }) |name| {
        if (std.ascii.eqlIgnoreCase(key, name)) return true;
    }
    return false;
}

/// Actual removal (empty overrides would still inherit unrelated npm settings).
/// Explicit private Config.env overrides are installed AFTER this operation.
pub fn sanitize(env: *std.process.Environ.Map) !void {
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(env.allocator);
    var iterator = env.iterator();
    while (iterator.next()) |entry| {
        if (exclude(entry.key_ptr.*)) try keys.append(env.allocator, entry.key_ptr.*);
    }
    for (keys.items) |key| _ = env.swapRemove(key);
}

test "fresh portable child removes inherited injections and known auth, case insensitive" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    for ([_][]const u8{ "NODE_OPTIONS", "node_path", "npm_config_userconfig", "NPM_CONFIG_CACHE", "LETTA_BASE_URL", "LETTA_LOCAL_BACKEND_DIR", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GITHUB_TOKEN", "GOOGLE_APPLICATION_CREDENTIALS", "MEMORY_DIR", "SSH_AUTH_SOCK", "HTTPS_PROXY" }) |key| try env.put(key, "synthetic-do-not-inherit");
    try env.put("SystemRoot", "C:\\Windows");
    try env.put("TERM", "xterm-256color");
    try sanitize(&env);
    try std.testing.expectEqual(@as(usize, 2), env.count());
    try std.testing.expectEqualStrings("C:\\Windows", env.get("SystemRoot").?);
    // Approved private values are added after sanitation, not inherited.
    try env.put("LETTA_LOCAL_BACKEND_DIR", "D:\\owned\\home\\.letta\\local");
    try std.testing.expect(std.mem.startsWith(u8, env.get("LETTA_LOCAL_BACKEND_DIR").?, "D:"));
}

test "normal unrelated environment keys are not classified as credentials" {
    try std.testing.expect(!exclude("SystemRoot"));
    try std.testing.expect(!exclude("LOCALTERM_PORTABLE_TOOLS"));
    try std.testing.expect(!exclude("TERMINFO"));
}
