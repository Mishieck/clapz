const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("clapz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const examples = [_][]const u8{ "main", "simple" };

    inline for (examples) |name| {
        const example = b.addExecutable(.{
            .name = "example-" ++ name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "clapz", .module = mod },
                },
            }),
        });

        b.installArtifact(example);

        const example_run_step = b.step(
            name ++ "-example",
            "Run " ++ name ++ " example.",
        );

        const example_run_cmd = b.addRunArtifact(example);
        example_run_step.dependOn(&example_run_cmd.step);
        example_run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| example_run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
