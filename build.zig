const std = @import("std");
const http = std.http;
const log = std.log;

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

    pub fn file_name(self: Dictionary) []const u8 {
        return switch (self) {
            inline else => |val| @tagName(val) ++ ".bin",
        };
    }

    pub fn archive_name(self: Dictionary) []const u8 {
        return switch (self) {
            inline else => |val| comptime val.file_name() ++ ".tar.gz",
        };
    }

    pub fn url(self: Dictionary) []const u8 {
        return switch (self) {
            inline else => |val| "https://github.com/egegungordu/jaime/releases/download/dictionary-v1/" ++ comptime val.archive_name(),
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
    // --out
    //      Output name for the dictionary
    // --lex
    //      Lexicon used for the dictionary generation (*.csv). Accepts simple
    //      glob pattern like "/*.csv" or "dir/*.csv" to match multiple csv files
    // --char
    //      Character category map used for the dictionary generation (char.def)
    // --matrix
    //      Cost matrix used for the dictionary generation (matrix.def)
    // --unk
    //      Unknown word definitions used for the dictionary generation (matrix.def)
    //
    // Can also accept the following optional arguments
    // --compress
    //      Create a tar archive and compress it with gzip
    // --include
    //      Additional files to include in the tar archive (LICENSE etc.)

    tools.build(b, .{
        .src_dir = "tools",
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
        const download_path = b.path(dic_fetch.archive_name()).getPath(b);
        const dic_path = b.path(dic_fetch.file_name()).getPath(b);
        log.info("checking dictionary file {s}", .{dic_path});
        const access: ?void = blk: {
            std.fs.accessAbsolute(dic_path, .{}) catch |err| {
                log.info("dictionary file not found, starting download", .{});
                switch (err) {
                    std.fs.Dir.AccessError.FileNotFound => {
                        log.info("downloading {s} from {s}", .{ @tagName(dic_fetch), dic_fetch.url() });
                        downloadUrl(b, dic_fetch.url(), download_path);
                        log.info("download completed successfully", .{});
                        log.info("extracting dictionary from archive", .{});
                        extractDictionary(b, download_path, dic_path);
                        log.info("cleaning up archive file", .{});
                        std.fs.deleteFileAbsolute(download_path) catch |er| {
                            log.warn("failed to delete archive file: {s}", .{@errorName(er)});
                        };
                    },
                    else => fatal(
                        "something went wrong while accessing the file {s}: {s}",
                        .{ dic_path, @errorName(err) },
                    ),
                }
                break :blk null;
            };
        };

        if (access != null) {
            log.info("file already downloaded, skipping download", .{});
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
        fatal("failed to fetch url {s}: {s}", .{ url, @errorName(err) });
    };

    switch (result.status) {
        .ok => {
            var out_file = std.fs.createFileAbsolute(out, .{}) catch |err| {
                fatal("unable to open '{s}': {s}", .{ out, @errorName(err) });
            };
            defer out_file.close();

            log.info("writing {:.2} of data", .{std.fmt.fmtIntSizeDec(response.items.len)});

            out_file.writer().writeAll(response.items) catch |err| {
                fatal("something went wrong while writing to file: {s}", .{@errorName(err)});
            };
        },
        .not_found => {
            fatal("404 not found. the link might be broken.", .{});
        },
        else => {
            fatal("fetched the url, but got status: {s}", .{@tagName(result.status)});
        },
    }
}

fn extractDictionary(b: *std.Build, archive_path: []const u8, dic_path: []const u8) void {
    var archive_file = std.fs.openFileAbsolute(archive_path, .{}) catch |err| {
        fatal("unable to open archive '{s}': {s}", .{ archive_path, @errorName(err) });
    };
    defer archive_file.close();

    // Create a buffer to store decompressed data
    var decompressed = std.ArrayList(u8).init(b.allocator);
    defer decompressed.deinit();

    // Decompress gzip data
    std.compress.gzip.decompress(archive_file.reader(), decompressed.writer()) catch |err| {
        fatal("failed to decompress gzip data: {s}", .{@errorName(err)});
    };

    // Create a fixed buffer stream for the decompressed data
    var decompressed_stream = std.io.fixedBufferStream(decompressed.items);

    // Create tar reader
    var tar_it = std.tar.iterator(decompressed_stream.reader(), .{
        .file_name_buffer = b.allocator.alloc(u8, std.fs.MAX_PATH_BYTES) catch |err| {
            fatal("failed to allocate file name buffer: {s}", .{@errorName(err)});
        },
        .link_name_buffer = b.allocator.alloc(u8, std.fs.MAX_PATH_BYTES) catch |err| {
            fatal("failed to allocate link name buffer: {s}", .{@errorName(err)});
        },
    });
    defer b.allocator.free(tar_it.file_name_buffer);
    defer b.allocator.free(tar_it.link_name_buffer);

    // Read through tar entries until we find our .bin file
    while (tar_it.next() catch |err| {
        fatal("error reading tar entry: {s}", .{@errorName(err)});
    }) |entry| {
        const basename = std.fs.path.basename(entry.name);
        if (std.mem.eql(u8, basename, std.fs.path.basename(dic_path))) {
            var out_file = std.fs.createFileAbsolute(dic_path, .{}) catch |err| {
                fatal("unable to create dictionary file '{s}': {s}", .{ dic_path, @errorName(err) });
            };
            defer out_file.close();

            log.info("extracting {s} from archive", .{basename});

            entry.writeAll(out_file) catch |err| {
                fatal("failed to extract dictionary file: {s}", .{@errorName(err)});
            };
            return;
        }
    }
    fatal("dictionary file not found in archive", .{});
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.process.exit(1);
}
