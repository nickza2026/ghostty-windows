const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const buildpkg = @import("src/build/main.zig");
const translate_c = @import("translate_c");

/// App version from build.zig.zon.
const app_zon_version = @import("build.zig.zon").version;

/// Libghostty version. We use a separate version from the app.
const lib_version = "0.1.0-dev";

/// Minimum required zig version.
const minimum_zig_version = @import("build.zig.zon").minimum_zig_version;

comptime {
    buildpkg.requireZig(minimum_zig_version);
}

pub fn build(b: *std.Build) !void {
    // This defines all the available build options (e.g. `-D`). If you
    // want to know what options are available, you can run `--help` or
    // you can read `src/build/Config.zig`.

    // If we have a VERSION file (present in source tarballs) then we
    // use that as the version source of truth. Otherwise we fall back
    // to what is in the build.zig.zon.
    const file_version: ?[]const u8 = if (b.build_root.handle.readFileAlloc(
        b.graph.io,
        "VERSION",
        b.allocator,
        .limited(128),
    )) |content| std.mem.trim(
        u8,
        content,
        &std.ascii.whitespace,
    ) else |_| null;

    const config = try buildpkg.Config.init(
        b,
        file_version orelse app_zon_version,
        lib_version,
    );
    const test_filters = b.option(
        [][]const u8,
        "test-filter",
        "Filter for test. Only applies to Zig tests.",
    ) orelse &[0][]const u8{};

    // Phase 3A: a real native window without a fake core Surface, GPU, or PTY.
    // This explicit opt-in target does not change the default Ghostty build.
    if (config.target.result.os.tag == .windows) {
        const window = b.addExecutable(.{
            .name = "localterm-dev",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32/window_main.zig"),
                .target = config.target,
                .optimize = config.optimize,
                .link_libc = true,
            }),
            .use_llvm = true,
        });
        window.subsystem = .Windows;
        // Like GhosttyExe's Win32 build: retain CRT init and Zig's main wrapper.
        window.entry = .{ .symbol_name = "mainCRTStartup" };
        window.root_module.linkSystemLibrary("user32", .{});
        window.root_module.linkSystemLibrary("gdi32", .{});
        window.root_module.addCSourceFile(.{ .file = b.path("src/apprt/win32/diagnostics.c") });
        window.root_module.addWin32ResourceFile(.{
            .file = b.path("dist/windows/localterm-dev.rc"),
        });
        const install_window = b.addInstallArtifact(window, .{});
        b.step("windows-window", "Build the localterm-dev native window prototype (no terminal)")
            .dependOn(&install_window.step);
        const run_window = b.addRunArtifact(window);
        if (b.args) |args| run_window.addArgs(args);
        b.step("run-windows-window", "Run the native window prototype; pass -- --smoke-test for lifecycle checks")
            .dependOn(&run_window.step);

        const presenter_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32/presenter.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
            .use_llvm = true,
        });
        presenter_tests.root_module.linkSystemLibrary("gdi32", .{});
        b.step("test-windows-presenter", "Test RGBA/BGRA/row conversion, invalid frames, OOM and BMP header")
            .dependOn(&b.addRunArtifact(presenter_tests).step);

        const input_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32/text_input.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
            .use_llvm = true,
        });
        b.step("test-windows-input", "Test UTF-16/surrogates/Unicode scalar decoding (not paste)")
            .dependOn(&b.addRunArtifact(input_tests).step);

        const ime_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32/ime.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
            .use_llvm = true,
        });
        ime_tests.root_module.linkSystemLibrary("imm32", .{});
        b.step("test-windows-ime", "Test IMM logical/client pixel geometry (real IME still needs human verification)")
            .dependOn(&b.addRunArtifact(ime_tests).step);

        const clipboard_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/apprt/win32/clipboard.zig"),
                .target = config.target,
                .optimize = config.optimize,
            }),
            .use_llvm = true,
        });
        clipboard_tests.root_module.linkSystemLibrary("user32", .{});
        b.step("test-windows-clipboard", "Test bounded text decode/paste policy without reading or changing the system clipboard")
            .dependOn(&b.addRunArtifact(clipboard_tests).step);

        // Match the upstream SharedDeps module configuration; do not create a
        // second translate-c variant of the Windows SDK headers for this gate.
        if (if (config.emit_lib_vt) null else b.lazyDependency("opengl", .{})) |gl_dep| {
            const probe = b.addExecutable(.{
                .name = "localterm-dev-gl-probe",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_gl_probe.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            probe.root_module.addImport("opengl", gl_dep.module("opengl"));
            probe.root_module.addIncludePath(b.path("vendor/glad/include"));
            probe.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            probe.root_module.addCSourceFile(.{ .file = b.path("src/apprt/win32/diagnostics.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                probe.root_module.linkSystemLibrary(library, .{});
            const install_probe = b.addInstallArtifact(probe, .{});
            b.step("windows-gl-probe", "Build desktop GL 4.3/FBO/thread-handoff capability probe (no terminal)")
                .dependOn(&install_probe.step);
            const run_probe = b.addRunArtifact(probe);
            b.step("run-windows-gl-probe", "Run the native WGL capability and lifetime gate")
                .dependOn(&run_probe.step);

            const ipc_probe = b.addExecutable(.{
                .name = "localterm-dev-gpu-frame-child",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_gpu_frame_probe.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            ipc_probe.root_module.addImport("opengl", gl_dep.module("opengl"));
            ipc_probe.root_module.addIncludePath(b.path("src"));
            ipc_probe.root_module.addIncludePath(b.path("vendor/glad/include"));
            ipc_probe.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                ipc_probe.root_module.linkSystemLibrary(library, .{});
            b.step("windows-gpu-frame-probe", "Build isolated GPU frame shared-memory child (component PoC)")
                .dependOn(&b.addInstallArtifact(ipc_probe, .{}).step);

            const text_worker = b.addExecutable(.{
                .name = "localterm-render-text-worker",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_text_worker.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            text_worker.root_module.addImport("opengl", gl_dep.module("opengl"));
            text_worker.root_module.addIncludePath(b.path("vendor/glad/include"));
            text_worker.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                text_worker.root_module.linkSystemLibrary(library, .{});
            b.step("windows-render-text-worker", "Build private text-frame GPU worker (not the terminal host)")
                .dependOn(&b.addInstallArtifact(text_worker, .{}).step);
            if (config.windows_remote_renderer) b.getInstallStep().dependOn(&b.addInstallArtifact(text_worker, .{}).step);

            const cache_check = b.addExecutable(.{
                .name = "localterm-render-text-cache-check",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_text_cache_check.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            cache_check.root_module.addImport("opengl", gl_dep.module("opengl"));
            cache_check.root_module.addIncludePath(b.path("vendor/glad/include"));
            cache_check.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library| cache_check.root_module.linkSystemLibrary(library, .{});
            b.step("windows-render-text-cache-check", "Build GPU-context text resource reuse/resize check (not host readiness)")
                .dependOn(&b.addInstallArtifact(cache_check, .{}).step);

            const image_cache_check = b.addExecutable(.{
                .name = "localterm-render-image-cache-check",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_image_cache_check.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            image_cache_check.root_module.addImport("opengl", gl_dep.module("opengl"));
            image_cache_check.root_module.addIncludePath(b.path("vendor/glad/include"));
            image_cache_check.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library| image_cache_check.root_module.linkSystemLibrary(library, .{});
            b.step("windows-render-image-cache-check", "Build GPU image upload/cache component check (not terminal images)")
                .dependOn(&b.addInstallArtifact(image_cache_check, .{}).step);

            const image_frame_check = b.addExecutable(.{
                .name = "localterm-render-image-frame-check",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_image_frame_check.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            image_frame_check.root_module.addImport("opengl", gl_dep.module("opengl"));
            image_frame_check.root_module.addIncludePath(b.path("vendor/glad/include"));
            image_frame_check.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library| image_frame_check.root_module.linkSystemLibrary(library, .{});
            b.step("windows-render-image-frame-check", "Build GPU image compositing component check (not terminal images)")
                .dependOn(&b.addInstallArtifact(image_frame_check, .{}).step);

            const late_reply_worker = b.addExecutable(.{
                .name = "localterm-render-late-reply-test-worker",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_late_reply_test_worker.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            late_reply_worker.root_module.addImport("opengl", gl_dep.module("opengl"));
            late_reply_worker.root_module.addIncludePath(b.path("vendor/glad/include"));
            late_reply_worker.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                late_reply_worker.root_module.linkSystemLibrary(library, .{});

            const client_check = b.addExecutable(.{
                .name = "localterm-render-client-check",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/render_worker_client_check.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            client_check.root_module.addCSourceFile(.{ .file = b.path("src/render_worker_client_check.c"), .flags = &.{"-std=c11"} });
            client_check.root_module.linkSystemLibrary("kernel32", .{});
            const offscreen_worker = b.addExecutable(.{
                .name = "localterm-render-text-worker",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_render_offscreen_test_worker.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            offscreen_worker.root_module.addImport("opengl", gl_dep.module("opengl"));
            offscreen_worker.root_module.addIncludePath(b.path("vendor/glad/include"));
            offscreen_worker.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                offscreen_worker.root_module.linkSystemLibrary(library, .{});
            const check_step = b.step("windows-render-client-check", "Build private worker checks (execution includes real WGL/GPU fixtures)");
            check_step.dependOn(&b.addInstallArtifact(client_check, .{}).step);
            check_step.dependOn(&b.addInstallArtifact(offscreen_worker, .{}).step);
            check_step.dependOn(&b.addInstallArtifact(late_reply_worker, .{}).step);

            const bench = b.addExecutable(.{
                .name = "localterm-dev-frame-bench",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/win32_frame_bench.zig"),
                    .target = config.target,
                    .optimize = config.optimize,
                    .link_libc = true,
                }),
                .use_llvm = true,
            });
            bench.root_module.addImport("opengl", gl_dep.module("opengl"));
            bench.root_module.addIncludePath(b.path("vendor/glad/include"));
            bench.root_module.addCSourceFile(.{ .file = b.path("vendor/glad/src/gl.c") });
            for ([_][]const u8{ "user32", "gdi32", "opengl32" }) |library|
                bench.root_module.linkSystemLibrary(library, .{});
            b.step("windows-frame-bench", "Build offscreen 1080p readback/conversion/memory-DC component benchmark (not app FPS)")
                .dependOn(&b.addInstallArtifact(bench, .{}).step);
        }
    }

    // Ghostty dependencies used by many artifacts.
    const deps = try buildpkg.SharedDeps.init(b, &config);

    // The modules exported for Zig consumers of libghostty. If you're
    // writing a Zig program that uses libghostty, read this file.
    const mod = try buildpkg.GhosttyZig.init(
        b,
        &config,
        &deps,
    );

    // All our steps which we'll hook up later. The steps are shown
    // up here just so that they are more self-documenting.
    const run_step = b.step("run", "Run the app");
    const run_valgrind_step = b.step(
        "run-valgrind",
        "Run the app under valgrind",
    );
    const test_step = b.step("test", "Run tests");
    const test_lib_vt_step = b.step(
        "test-lib-vt",
        "Run libghostty-vt tests",
    );
    const test_lib_vt_build_step = b.step(
        "test-lib-vt-build",
        "Build libghostty-vt tests without running them (compile check)",
    );
    const test_lib_vt_schema_step = b.step(
        "test-lib-vt-schema",
        "Validate the libghostty-vt ABI type manifest",
    );
    const test_valgrind_step = b.step(
        "test-valgrind",
        "Run tests under valgrind",
    );
    const translations_step = b.step(
        "update-translations",
        "Update translation files",
    );

    // Ghostty resources like terminfo, shell integration, themes, etc.
    const resources = try buildpkg.GhosttyResources.init(b, &config, &deps);
    const i18n = if (config.i18n) try buildpkg.GhosttyI18n.init(b, &config) else null;

    // Ghostty executable, the actual runnable Ghostty program.
    const exe = try buildpkg.GhosttyExe.init(b, &config, &deps);

    // Ghostty docs
    const docs = try buildpkg.GhosttyDocs.init(b, &deps);
    if (config.emit_docs) {
        docs.install();
    } else if (config.target.result.os.tag.isDarwin()) {
        // If we aren't emitting docs we need to emit a placeholder so
        // our macOS xcodeproject builds since it expects the `share/man`
        // directory to exist to copy into the app bundle.
        docs.installDummy(b.getInstallStep());
    }

    // Ghostty webdata
    const webdata = try buildpkg.GhosttyWebdata.init(b, &deps);
    if (config.emit_webdata) webdata.install();

    // Ghostty bench tools
    if (config.emit_bench) {
        const bench = try buildpkg.GhosttyBench.init(b, &deps);
        bench.install();
    }

    // Ghostty dist tarball
    const dist = try buildpkg.GhosttyDist.init(b, &config);
    {
        const step = b.step("dist", "Build the dist tarball");
        step.dependOn(dist.install_step);
        const check_step = b.step("distcheck", "Install and validate the dist tarball");
        check_step.dependOn(dist.check_step);
        check_step.dependOn(dist.install_step);
    }

    // libghostty-vt
    const native_freestanding = config.target.result.os.tag == .freestanding and
        !config.target.result.cpu.arch.isWasm();
    const libghostty_vt_shared: ?buildpkg.GhosttyLibVt = shared: {
        if (config.target.result.cpu.arch.isWasm()) {
            break :shared try buildpkg.GhosttyLibVt.initWasm(
                b,
                &mod,
            );
        }
        if (native_freestanding) break :shared null;

        break :shared try buildpkg.GhosttyLibVt.initShared(
            b,
            &mod,
        );
    };
    if (libghostty_vt_shared) |shared| {
        shared.install(b.getInstallStep());

        const type_schema_test = b.addSystemCommand(&.{"python3"});
        type_schema_test.addFileArg(b.path("src/terminal/c/types-schema-verify.py"));
        type_schema_test.addFileArg(b.path("src/terminal/c/types.schema.json"));
        type_schema_test.addFileArg(shared.output);
        test_lib_vt_schema_step.dependOn(&type_schema_test.step);
    } else {
        try test_lib_vt_schema_step.addError(
            "cannot execute the ABI manifest for a native freestanding target",
            .{},
        );
    }

    // libghostty-vt static lib
    const libghostty_vt_static = try buildpkg.GhosttyLibVt.initStatic(
        b,
        &mod,
    );
    if (config.is_dep) {
        // If we're a dependency, we need to install everything as-is
        // so that dep.artifact("ghostty-vt-static") works.
        libghostty_vt_static.install(b.getInstallStep());
    } else {
        // If we're not a dependency, we rename the static lib to
        // be idiomatic. On Windows, we use a distinct name to avoid
        // colliding with the DLL import library (ghostty-vt.lib).
        const static_lib_name = if (config.target.result.os.tag == .windows)
            "ghostty-vt-static.lib"
        else
            "libghostty-vt.a";
        b.getInstallStep().dependOn(&b.addInstallLibFile(
            libghostty_vt_static.output,
            static_lib_name,
        ).step);

        if (native_freestanding) {
            b.getInstallStep().dependOn(&b.addInstallDirectory(.{
                .source_dir = b.path("include/ghostty"),
                .install_dir = .header,
                .install_subdir = "ghostty",
                .include_extensions = &.{".h"},
            }).step);
        }
    }

    // libghostty-vt xcframework (Apple only, universal binary).
    // Only when building on macOS (not cross-compiling) since
    // xcodebuild is required.
    if (config.emit_lib_vt and
        config.emit_xcframework and
        builtin.os.tag.isDarwin() and
        config.target.result.os.tag.isDarwin())
    {
        const apple_libs = try buildpkg.GhosttyLibVt.initStaticAppleUniversal(
            b,
            &config,
            &deps,
            &mod,
        );
        const xcframework = buildpkg.GhosttyLibVt.xcframework(&apple_libs, b);
        b.getInstallStep().dependOn(xcframework.step);
    }

    // Helpgen
    if (config.emit_helpgen) deps.help_strings.install();

    // Runtime "none" is libghostty, anything else is an executable.
    if (config.app_runtime != .none) {
        if (config.emit_exe) {
            exe.install();
            resources.install();
            if (i18n) |v| v.install();
        }
    } else if (!config.emit_lib_vt) {
        // The macOS Ghostty Library
        //
        // This is NOT libghostty (even though its named that for historical
        // reasons). It is just the glue between Ghostty GUI on macOS and
        // the full Ghostty GUI core.
        const lib_shared = try buildpkg.GhosttyLib.initShared(b, &deps);
        const lib_static = try buildpkg.GhosttyLib.initStatic(b, &deps);

        // We shouldn't have this guard but we don't currently
        // build on macOS this way ironically so we need to fix that.
        if (!config.target.result.os.tag.isDarwin()) {
            lib_shared.installHeader(); // Only need one header
            if (config.target.result.os.tag == .windows) {
                lib_shared.install("ghostty-internal.dll");
                lib_static.install("ghostty-internal-static.lib");
            } else {
                lib_shared.install("ghostty-internal.so");
                lib_static.install("ghostty-internal.a");
            }
        }
    }

    // macOS only artifacts. These will error if they're initialized for
    // other targets. In lib-vt mode emit_xcframework controls the lib-vt
    // xcframework above, not this one.
    if (!config.emit_lib_vt and config.target.result.os.tag.isDarwin() and
        (config.emit_xcframework or config.emit_macos_app))
    {
        // Ghostty xcframework
        const xcframework = try buildpkg.GhosttyXCFramework.init(
            b,
            &deps,
            config.xcframework_target,
        );
        if (config.emit_xcframework) {
            xcframework.install();

            // The xcframework build always installs resources because our
            // macOS xcode project contains references to them.
            resources.install();
            if (i18n) |v| v.install();
        }

        // Ghostty macOS app
        const macos_app = try buildpkg.GhosttyXcodebuild.init(
            b,
            &config,
            .{
                .xcframework = &xcframework,
                .docs = &docs,
                .i18n = if (i18n) |v| &v else null,
                .resources = &resources,
            },
        );
        if (config.emit_macos_app) {
            macos_app.install();
        }
    }

    // Run step
    run: {
        if (config.app_runtime != .none) {
            const run_cmd = b.addRunArtifact(exe.exe);
            if (b.args) |args| run_cmd.addArgs(args);

            // Set the proper resources dir so things like shell integration
            // work correctly. If we're running `zig build run` in Ghostty,
            // this also ensures it overwrites the release one with our debug
            // build.
            run_cmd.setEnvironmentVariable(
                "GHOSTTY_RESOURCES_DIR",
                b.getInstallPath(.prefix, "share/ghostty"),
            );

            run_step.dependOn(&run_cmd.step);
            break :run;
        }

        assert(config.app_runtime == .none);

        // On macOS we can run the macOS app. For "run" we always force
        // a native-only build so that we can run as quickly as possible.
        if (!config.emit_lib_vt and
            config.target.result.os.tag.isDarwin() and
            (config.emit_xcframework or config.emit_macos_app))
        {
            const xcframework_native = try buildpkg.GhosttyXCFramework.init(
                b,
                &deps,
                .native,
            );
            const macos_app_native_only = try buildpkg.GhosttyXcodebuild.init(
                b,
                &config,
                .{
                    .xcframework = &xcframework_native,
                    .docs = &docs,
                    .i18n = if (i18n) |v| &v else null,
                    .resources = &resources,
                },
            );

            // Run uses the native macOS app
            run_step.dependOn(&macos_app_native_only.open.step);

            // If we have no test filters, install the tests too
            if (test_filters.len == 0) {
                macos_app_native_only.addTestStepDependencies(test_step);
            }
        }
    }

    // Valgrind
    if (config.app_runtime != .none) {
        // We need to rebuild Ghostty with a baseline CPU target.
        const valgrind_exe = exe: {
            var valgrind_config = config;
            valgrind_config.target = valgrind_config.baselineTarget(b.graph.io);
            break :exe try buildpkg.GhosttyExe.init(
                b,
                &valgrind_config,
                &deps,
            );
        };

        const run_cmd = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--error-exitcode=1",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        run_cmd.addArtifactArg(valgrind_exe.exe);
        if (b.args) |args| run_cmd.addArgs(args);
        run_valgrind_step.dependOn(&run_cmd.step);
    }

    // Zig module tests
    {
        const mod_vt_test = b.addTest(.{
            .root_module = mod.vt,
            .filters = test_filters,
        });
        const mod_vt_test_run = b.addRunArtifact(mod_vt_test);
        test_lib_vt_step.dependOn(&mod_vt_test_run.step);
        test_lib_vt_build_step.dependOn(&mod_vt_test.step);

        const mod_vt_c_test = b.addTest(.{
            .root_module = mod.vt_c,
            .filters = test_filters,
        });
        const mod_vt_c_test_run = b.addRunArtifact(mod_vt_c_test);
        test_lib_vt_step.dependOn(&mod_vt_c_test_run.step);
        test_lib_vt_build_step.dependOn(&mod_vt_c_test.step);
    }

    // Tests (skip when building libghostty-vt)
    if (!config.emit_lib_vt) {
        // Full unit tests
        const test_exe = b.addTest(.{
            .name = "ghostty-test",
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = config.baselineTarget(b.graph.io),
                .optimize = .Debug,
                .strip = false,
                .omit_frame_pointer = false,
                .unwind_tables = .sync,
            }),
            // Crash on x86_64 without this
            .use_llvm = true,
        });
        if (test_exe.root_module.resolved_target.?.result.os.tag == .windows) {
            // Private test dependency: never installed with app/portable artifacts.
            const child = b.addExecutable(.{
                .name = "command-inheritance-child",
                .root_module = b.createModule(.{
                    .target = config.baselineTarget(b.graph.io),
                    .optimize = .Debug,
                    .link_libc = true,
                }),
            });
            child.root_module.addCSourceFile(.{
                .file = b.path("tools/windows/command-inheritance-child.c"),
                .flags = &.{"-std=c11"},
            });
            const options = b.addOptions();
            options.addOptionPath("child_path", child.getEmittedBin());
            test_exe.root_module.addOptions("windows_command_inheritance_options", options);
        }
        if (config.emit_test_exe) {
            const test_exe_install = b.addInstallArtifact(test_exe, .{});
            config.addPatchElf(test_exe, &test_exe_install.step);
            test_step.dependOn(&test_exe_install.step);
        }
        _ = try deps.add(test_exe);

        addGhosttyH(b, test_exe.root_module, config.baselineTarget(b.graph.io), .Debug);

        // Normal test running
        const test_run = b.addRunArtifact(test_exe);
        config.addPatchElf(test_exe, &test_run.step);
        test_step.dependOn(&test_run.step);

        // Normal tests always test our libghostty modules
        //test_step.dependOn(test_lib_vt_step);

        // Valgrind test running
        const valgrind_run = b.addSystemCommand(&.{
            "valgrind",
            "--leak-check=full",
            "--error-exitcode=1",
            "--num-callers=50",
            b.fmt("--suppressions={s}", .{b.pathFromRoot("valgrind.supp")}),
            "--gen-suppressions=all",
        });
        valgrind_run.addArtifactArg(test_exe);
        config.addPatchElf(test_exe, &valgrind_run.step);
        test_valgrind_step.dependOn(&valgrind_run.step);
    }

    // update-translations does what it sounds like and updates the "pot"
    // files. These should be committed to the repo.
    if (i18n) |v| {
        translations_step.dependOn(v.update_step);
    } else {
        try translations_step.addError("cannot update translations when i18n is disabled", .{});
    }
}

fn addGhosttyH(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    translate_c.addImportToModule(b, "ghostty.h", module, .{
        .source = .{ .includes = .{ .files = &.{
            .{ .path = "ghostty.h" },
        } } },
        .target = target,
        .optimize = optimize,
        .system_include_paths = &.{b.path("include")},
    }) catch unreachable;
}
