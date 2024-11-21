const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardOptimizeOption(.{});

    const clap = b.addModule("clap", .{
        .root_source_file = b.path("libs/zig-clap/clap.zig")
    });

    const exe = b.addExecutable(.{
        .name = "zig-json",
        .root_source_file = b.path("src/main.zig"),
        .optimize = mode,
        .target = target,
    });
    exe.root_module.addImport("clap", clap);
    exe.dead_strip_dylibs = mode == .ReleaseFast;

    b.installArtifact(exe);

    if (builtin.target.os.tag == .macos) {
        var sign_step = b.step("sign", "Sign the app");
        sign_step.makeFn = codesign;
        sign_step.dependOn(b.getInstallStep());
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn codesign(_: *std.Build.Step, _: std.Progress.Node) anyerror!void {
    if (builtin.target.os.tag == .macos) {
        var proc = std.process.Child.init(&[_][]const u8{ "xcrun", "codesign", "-s", std.posix.getenv("XCODE_ID") orelse return error.NoXcodeId, "--entitlements", "entitlements.plist", "zig-out/bin/zig-json" }, std.heap.page_allocator);
        try proc.spawn();
        _ = try proc.wait();
    } else {
        return void;
    }
}
