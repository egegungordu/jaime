const std = @import("std");
const http = std.http;

const tools = @import("tools/build.zig");
const tests = @import("tests/build.zig");
const wasm = @import("wasm/build.zig");

const padding = " " ** 31;
const inner_padding = padding ++ " " ** 12;

const Dictionary = enum {
    unidic,
    ipadic,

    pub fn desc(self: Dictionary) []const u8 {
        return switch (self) {
            // zig fmt: off
            .unidic => 
                \\(recommended)
                \\
                ++ inner_padding ++
                \\Based on   : unidic-cwj-3.1.1
                \\
                ++ inner_padding ++
                \\Released in: 2022-09-02
                \\
                ++ inner_padding ++
                \\Entry count: 879,222
            ,
            .ipadic => 
                \\Based on   : mecab-ipadic-2.7.0.20070801
                \\
                ++ inner_padding ++
                \\Released in: 2007-08-01
                \\
                ++ inner_padding ++
                \\Entry count: TODO
            ,
            // zig fmt: on
        };
    }

    pub fn url(self: Dictionary) []const u8 {
        return switch (self) {
            .unidic => "https://github.com/egegungordu/jaime/releases/download/dictionary-v1/unidic.bin",
            .ipadic => "https://github.com/egegungordu/jaime/releases/download/dictionary-v1/ipadic.bin",
        };
    }

    pub fn file_name(self: Dictionary) []const u8 {
        return switch (self) {
            .unidic => "unidic.bin",
            .ipadic => "ipadic.bin",
        };
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Private modules

    const mod_datastructs = b.createModule(.{
        .root_source_file = b.path("src/datastructs/datastructs.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_utf8utils = b.createModule(.{
        .root_source_file = b.path("src/utf8utils/utf8utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_core = b.createModule(.{
        .root_source_file = b.path("src/core/core.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "utf8utils", .module = mod_utf8utils },
        },
    });

    // Dictionary builder tool
    //
    // The dictionary builder needs the following arguments to generate
    // a binary to be used in this program:
    // -Ddic-gen-out
    //      Output name for the dictionary
    // -Ddic-gen-lex
    //      Lexicon used for the dictionary generation (*.csv). Accepts simple
    //      glob pattern like "/*.csv" or "dir/*.csv" to match multiple csv files
    // -Ddic-gen-char
    //      Character category map used for the dictionary generation (char.def)
    // -Ddic-gen-matrix
    //      Cost matrix used for the dictionary generation (matrix.def)
    // -Ddic-gen-unk
    //      Unknown word definitions used for the dictionary generation (matrix.def)

    tools.build(b, .{
        .src_dir = "tools",
        .opt_prefix = "dic-gen",
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "core", .module = mod_core },
        },
    });

    //TODO: check b.makeTempPath, could be interesting for the download path or something?

    // Input options for the dictionaries
    //
    // There are 2 ways to specify a dictionary to the program:
    // 1. From a local file (built by the dictionary builder tool)
    // 2. Automatically downloaded (prebuilt and hosted on github assets)

    var dic_fetch_desc: []const u8 = "Dictionary to download and use. Either use dic-fetch\n" ++ padding ++
        "or dic-file to specify a dictionary.";
    inline for (comptime std.enums.values(Dictionary)) |dic| {
        dic_fetch_desc = b.fmt(
            "{s}\n" ++ padding ++ "  {s:<8}: {s}",
            .{ dic_fetch_desc, @tagName(dic), dic.desc() },
        );
    }

    const opt_dic_file = b.option(
        []const u8,
        "dic-file",
        "Dictionary to use. Either use dic-fetch or dic-file\n" ++ padding ++ "to specify a dictionary.",
    );
    const opt_dic_fetch = b.option(Dictionary, "dic-fetch", dic_fetch_desc);

    if (opt_dic_fetch != null and opt_dic_file != null) {
        fatal("Cannot specify both dic-fetch and dic-file options at the same time\n", .{});
    }

    if (opt_dic_fetch) |dic_fetch| {
        const download_path = b.path(dic_fetch.file_name()).getPath(b);
        std.debug.print("Checking dictionary file {s}\n", .{download_path});
        const access: ?void = blk: {
            std.fs.accessAbsolute(download_path, .{}) catch |err| {
                switch (err) {
                    std.fs.Dir.AccessError.FileNotFound => {
                        std.debug.print("Downloading {s} from {s}\n", .{ @tagName(dic_fetch), dic_fetch.url() });
                        downloadUrl(b, dic_fetch.url(), download_path);
                        std.debug.print("Download completed successfully\n", .{});
                    },
                    else => fatal(
                        "Something went wrong while accessing the file {s}: {s}\n",
                        .{ download_path, @errorName(err) },
                    ),
                }
                break :blk null;
            };
        };

        if (access != null) {
            std.debug.print("File already downloaded, skipping download\n", .{});
        }
    }

    const dic_path: ?[]const u8 =
        // zig fmt: off
        if (opt_dic_file) |dic_file|
            dic_file
        else if (opt_dic_fetch) |dic_fetch|
            dic_fetch.file_name()
        else
            null;
        // zig fmt: on

    // Public (exported) modules

    // kana
    const mod_kana = b.addModule("kana", .{
        .root_source_file = b.path("src/kana.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });

    // ime
    const mod_ime = b.addModule("ime", .{
        .root_source_file = b.path("src/ime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });
    if (dic_path) |path| {
        mod_ime.addAnonymousImport("dic", .{ .root_source_file = b.path(path) });
    }

    // WASM lib

    wasm.build(b, .{
        .src_dir = "wasm",
        .imports = &.{
            .{ .name = "ime", .module = mod_ime },
        },
    });

    // Tests

    tests.build(b, .{
        .src_dir = "tests",
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "core", .module = mod_core },
            .{ .name = "utf8utils", .module = mod_utf8utils },
            .{ .name = "kana", .module = mod_kana },
        },
    });
}

fn downloadUrl(b: *std.Build, url: []const u8, out: []const u8) void {
    var client = http.Client{
        .allocator = b.allocator,
    };
    defer client.deinit();

    var response = std.ArrayList(u8).init(b.allocator);
    defer response.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .max_append_size = 32 * 1024 * 1024,
        .response_storage = .{ .dynamic = &response },
    }) catch |err| {
        fatal("Failed to fetch url {s}: {s}\n", .{ url, @errorName(err) });
    };

    switch (result.status) {
        .ok => {
            var out_file = std.fs.createFileAbsolute(out, .{}) catch |err| {
                fatal("Unable to open '{s}': {s}\n", .{ out, @errorName(err) });
            };
            defer out_file.close();

            out_file.writer().writeAll(response.items) catch |err| {
                fatal("Someting went wrong while writing to file: {s}\n", .{@errorName(err)});
            };
        },
        else => {
            fatal("Fetched the url, but got status: {s}\n", .{@tagName(result.status)});
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
