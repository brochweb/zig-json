const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-json", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("clap", "libs/zig-clap/clap.zig");
    exe.strip = mode == .ReleaseFast;
    exe.dead_strip_dylibs = mode == .ReleaseFast;
    exe.install();

    var sign_step = b.step("sign", "Sign the app");
    sign_step.makeFn = codesign;
    sign_step.dependOn(b.getInstallStep());

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn codesign(_: *std.build.Step) !void {
    var proc = std.ChildProcess.init(&[_][]const u8{ "xcrun", "codesign", "-s", std.os.getenv("XCODE_ID") orelse return error.NoXcodeId, "--entitlements", "entitlements.plist", "zig-out/bin/zig-json" }, std.heap.page_allocator);
    try proc.spawn();
    _ = try proc.wait();
}
