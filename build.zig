const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = .windows } });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "rgldl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const win32_dep = b.dependency("win32", .{});
    exe.root_module.addImport("win32", win32_dep.module("win32"));
    // exe.linkLibC();

    b.installArtifact(exe);
}
