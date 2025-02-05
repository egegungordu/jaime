const std = @import("std");

pub const Options = struct {
    src_dir: []const u8,
    opt_prefix: []const u8,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build, opts: Options) void {
    const dict_builder_exe = b.addExecutable(.{
        .name = "dictionary_builder",
        .root_source_file = b.path(b.fmt("{s}/dictionary_builder.zig", .{opts.src_dir})),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });

    var path_opts = b.addOptions();

    const pn = createPrefixedName(b, opts.opt_prefix);
    path_opts.addOption([]const u8, "prefix", opts.opt_prefix);

    if (b.option([]const u8, pn.f("out"), "Output name for the dictionary")) |out| {
        path_opts.addOption([]const u8, "out", out);
    }

    if (b.option(bool, pn.f("compress"), "Enable compression of the dictionary output")) |compress| {
        path_opts.addOption(bool, "compress", compress);
    } else {
        path_opts.addOption(bool, "compress", false); // uncompressed by default
    }

    if (b.option([]const []const u8, pn.f("include"), "Additional files to include in the dictionary archive")) |include_files| {
        path_opts.addOption([]const []const u8, "include", include_files);
    } else {
        path_opts.addOption([]const []const u8, "include", &[_][]const u8{});
    }

    // TODO: might not be the best idea to include these options as compiler options,
    // maybe put them in the dictionary_builder.zig?
    const padding = " " ** 31;
    inline for ([_]struct { name: []const u8, desc: []const u8 }{
        // zig fmt: off
        .{ .name = "lex", .desc = 
            \\Lexicon used for the dictionary generation (*.csv).
            \\
            ++ padding ++
            \\Accepts simple glob pattern like "*.csv" or "dir/*.csv"
            \\
            ++ padding ++
            \\to match multiple csv files" 
        },
        // zig fmt: on
        .{ .name = "char", .desc = "Character category map used for the dictionary generation (char.def)" },
        .{ .name = "matrix", .desc = "Cost matrix used for the dictionary generation (matrix.def)" },
        .{ .name = "unk", .desc = "Unknown word definitions used for the dictionary generation (matrix.def)" },
    }) |opt| {
        if (b.option([]const u8, pn.f(opt.name), opt.desc)) |val| {
            path_opts.addOption([]const u8, opt.name, val);
        }
    }
    dict_builder_exe.root_module.addOptions("args", path_opts);

    for (opts.imports) |import| {
        dict_builder_exe.root_module.addImport(import.name, import.module);
    }

    const run_dict_builder_exe = b.addRunArtifact(dict_builder_exe);
    run_dict_builder_exe.has_side_effects = true;
    b.step("dictionary", "Build a dictionary from the given files").dependOn(&run_dict_builder_exe.step);
}

const PrefixedNameFormatter = struct {
    b: *std.Build,
    prefix: []const u8,

    fn f(self: PrefixedNameFormatter, arg: []const u8) []const u8 {
        return self.b.fmt("{s}-{s}", .{ self.prefix, arg });
    }
};

fn createPrefixedName(b: *std.Build, prefix: []const u8) PrefixedNameFormatter {
    return .{ .b = b, .prefix = prefix };
}
