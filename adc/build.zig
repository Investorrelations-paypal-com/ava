const std = @import("std");
const SDL = @import("SDL.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdlsdk = SDL.init(b, null);

    const exe = b.addExecutable(.{
        .name = "adc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibCpp();
    sdlsdk.link(exe, .dynamic);
    exe.root_module.addImport("sdl2", sdlsdk.getWrapperModule());

    const avabasic_mod = b.dependency("avabasic", .{
        .target = target,
        .optimize = optimize,
    }).module("avabasic");
    exe.root_module.addImport("avabasic", avabasic_mod);

    const avacore_mod = b.dependency("avacore", .{
        .target = target,
        .optimize = optimize,
    }).module("avacore");
    exe.root_module.addImport("avacore", avacore_mod);

    const serial_mod = b.dependency("serial", .{
        .target = target,
        .optimize = optimize,
    }).module("serial");
    exe.root_module.addImport("serial", serial_mod);

    const known_folders_mod = b.dependency("known-folders", .{
        .target = target,
        .optimize = optimize,
    }).module("known-folders");
    exe.root_module.addImport("known-folders", known_folders_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
