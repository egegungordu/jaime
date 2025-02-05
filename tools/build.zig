const std = @import("std");

pub const Options = struct {
    src_dir: []const u8,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build, opts: Options) void {
    const dict_builder_exe = b.addExecutable(.{
        .name = "dictionary_builder",
        .root_source_file = b.path(b.fmt("{s}/dictionary_builder.zig", .{opts.src_dir})),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    // Add module dependencies
    for (opts.imports) |import| {
        dict_builder_exe.root_module.addImport(import.name, import.module);
    }

    const run_dict_builder_exe = b.addRunArtifact(dict_builder_exe);

    if (b.args) |args| {
        run_dict_builder_exe.addArgs(args);
    }

    run_dict_builder_exe.has_side_effects = true;
    b.step("dictionary", "Build a dictionary from the given files").dependOn(&run_dict_builder_exe.step);
}
