const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;

const glob = @import("glob.zig");
const SimpleTar = @import("tar.zig").SimpleTar;
const core = @import("core");
const datastructs = @import("datastructs");
const WordEntry = core.WordEntry;
const LoudsTrie = datastructs.louds_trie.LoudsTrie(WordEntry);
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder(WordEntry);
const DictionarySerializer = core.dictionary.DictionarySerializer;

const Config = struct {
    lex_path: []const u8,
    matrix_path: []const u8,
    char_path: []const u8,
    unk_path: []const u8,
    out_path: []const u8,
    compress: bool,
    include: []const []const u8,

    pub fn deinit(self: *Config, allocator: mem.Allocator) void {
        for (self.include) |path| {
            allocator.free(path);
        }
        allocator.free(self.include);
    }
};

fn parseArgs(allocator: mem.Allocator) !Config {
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();

    // Skip executable name
    _ = args_it.skip();

    var config = Config{
        .lex_path = "",
        .matrix_path = "",
        .char_path = "",
        .unk_path = "",
        .out_path = "",
        .compress = false,
        .include = &[_][]const u8{},
    };

    var include_list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (include_list.items) |path| {
            allocator.free(path);
        }
        include_list.deinit();
    }

    while (args_it.next()) |arg| {
        if (mem.eql(u8, arg, "--lex")) {
            const val = args_it.next() orelse fatal("Missing value for --lex\n", .{});
            config.lex_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--matrix")) {
            const val = args_it.next() orelse fatal("Missing value for --matrix\n", .{});
            config.matrix_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--char")) {
            const val = args_it.next() orelse fatal("Missing value for --char\n", .{});
            config.char_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--unk")) {
            const val = args_it.next() orelse fatal("Missing value for --unk\n", .{});
            config.unk_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--out")) {
            const val = args_it.next() orelse fatal("Missing value for --out\n", .{});
            config.out_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--compress")) {
            config.compress = true;
        } else if (std.mem.eql(u8, arg, "--include")) {
            const pattern = args_it.next() orelse {
                fatal("Missing value for --include\n", .{});
            };
            // Process glob pattern for include files
            const matched_files = glob.matchFiles(allocator, std.fs.cwd(), pattern) catch |err| {
                fatal("Failed to match files with pattern (--include) '{s}': {s}\n", .{ pattern, @errorName(err) });
            };
            if (matched_files.items.len == 0) {
                fatal("No files found matching pattern (--include): {s}\n", .{pattern});
            }
            try include_list.appendSlice(matched_files.items);
        }
    }

    if (config.lex_path.len == 0) fatal("Missing required lexicon path. Use --lex <path>\n", .{});
    if (config.matrix_path.len == 0) fatal("Missing required connection matrix path. Use --matrix <path>\n", .{});
    if (config.char_path.len == 0) fatal("Missing required character definition path. Use --char <path>\n", .{});
    if (config.unk_path.len == 0) fatal("Missing required unknown word definition path. Use --unk <path>\n", .{});
    if (config.out_path.len == 0) fatal("Missing required output path. Use --out <path>\n", .{});

    config.include = try include_list.toOwnedSlice();
    return config;
}

/// custom csv field reader to correctly parse quoted fields with ',' in them
/// only the first field in the lexicons use this
fn getNextCsvField(it: *mem.SplitIterator(u8, .scalar)) ?[]const u8 {
    const first = it.peek() orelse return null;
    if (first.len == 0) {
        _ = it.next();
        return "";
    }

    // Not a quoted field, return as is
    if (first[0] != '"') {
        return it.next();
    }

    // For quoted field, find the start position (after the quote)
    const start = it.index.? + 1;
    _ = it.next(); // consume the first quoted part

    // Keep going until we find the closing quote
    while (it.peek()) |part| {
        if (part.len > 0 and part[part.len - 1] == '"') {
            const end = it.index.? + part.len - 1;
            _ = it.next(); // consume the last part
            return it.buffer[start..end];
        }
        _ = it.next(); // consume this part and continue
    }

    return null; // malformed CSV, no closing quote found
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config = try parseArgs(allocator);

    var bldr = LoudsTrieBuilder.init(allocator);
    var ltrie: LoudsTrie = undefined;

    {
        std.debug.print("[lex] start\n", .{});

        // Process glob pattern for lexicon files
        const lex_files = try glob.matchFiles(allocator, std.fs.cwd(), config.lex_path);
        if (lex_files.items.len == 0) {
            fatal("No lexicon files found matching pattern: {s}\n", .{config.lex_path});
        }

        std.debug.print("[lex] found {d} lexicon file(s)\n", .{lex_files.items.len});

        for (lex_files.items) |file_path| {
            std.debug.print("[lex] processing {s}...\n", .{file_path});

            var input_file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                fatal("unable to open '{s}': {s}", .{ file_path, @errorName(err) });
            };
            defer input_file.close();

            const file = try input_file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

            var lex_line_it = mem.tokenizeScalar(u8, file, '\n');
            while (lex_line_it.next()) |line| {
                var it = mem.splitScalar(u8, line, ',');
                const word = getNextCsvField(&it) orelse break;
                const left_id = try fmt.parseInt(u32, it.next().?, 10);
                const right_id = try fmt.parseInt(u32, it.next().?, 10);
                const cost = try fmt.parseInt(i16, it.next().?, 10);
                inline for (0..9) |_| {
                    _ = it.next();
                }
                const reading = it.next().?;
                try bldr.insert(reading, .{
                    .word = word,
                    .left_id = left_id,
                    .right_id = right_id,
                    .cost = cost,
                });
            }
        }

        std.debug.print("[lex] building louds trie index...\n", .{});
        ltrie = try bldr.build();
        std.debug.print("[lex] end\n", .{});
    }

    var cost_arr: std.ArrayList(i16) = undefined;

    var right_count: u32 = undefined;

    {
        std.debug.print("[matrix] start\n", .{});

        var input_file = std.fs.cwd().openFile(config.matrix_path, .{}) catch |err| {
            fatal("unable to open '{s}': {s}", .{ config.matrix_path, @errorName(err) });
        };
        defer input_file.close();

        const file = try input_file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

        var matrix_line_it = mem.tokenizeScalar(u8, file, '\n');

        var first_line_it = mem.tokenizeScalar(u8, matrix_line_it.next().?, ' ');
        const left_count = try std.fmt.parseInt(u32, first_line_it.next().?, 10);
        right_count = try std.fmt.parseInt(u32, first_line_it.next().?, 10);

        std.debug.print("[matrix] found {d} left, {d} right ids...\n", .{ left_count, right_count });
        std.debug.print("[matrix] initializing arraylist with {d} capacity...\n", .{left_count * right_count});

        cost_arr = try std.ArrayList(i16).initCapacity(allocator, left_count * right_count);

        std.debug.print("[matrix] inserting values...\n", .{});

        cost_arr.items.len = left_count * right_count;

        while (matrix_line_it.next()) |line| {
            var it = mem.splitScalar(u8, line, ' ');
            const left_id = try std.fmt.parseInt(u32, it.next().?, 10);
            const right_id = try std.fmt.parseInt(u32, it.next().?, 10);
            cost_arr.items[left_id * right_count + right_id] = try std.fmt.parseInt(i16, it.next().?, 10);
        }

        std.debug.print("[matrix] end\n", .{});
    }

    {
        std.debug.print("[out] start\n", .{});

        const tar_path = try std.fmt.allocPrint(allocator, "{s}.tar", .{config.out_path});
        const tar_gz_path = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{config.out_path});

        std.debug.print("[out] creating file: {s}...\n", .{config.out_path});

        var dic_file = std.fs.cwd().createFile(config.out_path, .{}) catch |err| {
            fatal("unable to open '{s}': {s}\n", .{ config.out_path, @errorName(err) });
        };
        errdefer dic_file.close();

        const dic_writer = dic_file.writer();

        var buffered_writer = std.io.BufferedWriter(4096 * 4, @TypeOf(dic_writer)){ .unbuffered_writer = dic_writer };

        std.debug.print("[out] serializing dictionary...\n", .{});

        DictionarySerializer.serialize(&.{
            .trie = ltrie,
            .costs = cost_arr,
            .right_count = right_count,
        }, buffered_writer.writer()) catch |err| {
            fatal("unable to serialize dictionary: {s}\n", .{@errorName(err)});
        };

        try buffered_writer.flush();

        std.debug.print("[out] freeing up memory...\n", .{});

        // Close the dictionary handle so we can open it back up with for tar
        dic_file.close();

        // Only create tar if we're compressing or have included files
        const should_tar = config.compress or config.include.len > 0;
        if (!should_tar) {
            std.debug.print("[out] end\n", .{});
            return;
        }

        var files_to_include = std.ArrayList([]const u8).init(allocator);

        // Always include the dictionary file
        try files_to_include.append(config.out_path);
        // Add any additional files
        try files_to_include.appendSlice(config.include);

        if (config.compress) {
            std.debug.print("[out] creating file: {s}...\n", .{tar_gz_path});

            var tar_gz_file = std.fs.cwd().createFile(tar_gz_path, .{}) catch |err| {
                fatal("unable to open '{s}': {s}\n", .{ tar_gz_path, @errorName(err) });
            };
            defer tar_gz_file.close();

            var data = std.ArrayList(u8).init(allocator);

            try SimpleTar.create(std.fs.cwd(), data.writer(), files_to_include.items);
            var data_fbs = std.io.fixedBufferStream(data.items);

            const tar_gz_writer = tar_gz_file.writer();
            var bw = std.io.BufferedWriter(4096 * 4, @TypeOf(tar_gz_writer)){ .unbuffered_writer = tar_gz_writer };

            // TODO: look into xz or lzma compression (should have better compression). Not implemented by the std (they only have decompression)
            try std.compress.gzip.compress(data_fbs.reader(), bw.writer(), .{ .level = .fast });

            try bw.flush();
        } else {
            std.debug.print("[out] creating file: {s}...\n", .{tar_path});

            var tar_file = std.fs.cwd().createFile(tar_path, .{}) catch |err| {
                fatal("unable to open '{s}': {s}\n", .{ tar_path, @errorName(err) });
            };
            defer tar_file.close();

            const tar_writer = tar_file.writer();
            var bw = std.io.BufferedWriter(4096 * 4, @TypeOf(tar_writer)){ .unbuffered_writer = tar_writer };

            try SimpleTar.create(std.fs.cwd(), bw.writer(), files_to_include.items);

            try bw.flush();
        }

        std.debug.print("[out] deleting intermediate file: {s}...\n", .{config.out_path});
        std.fs.cwd().deleteFile(config.out_path) catch |err| {
            fatal("unable to delete '{s}': {s}\n", .{ config.out_path, @errorName(err) });
        };

        std.debug.print("[out] end\n", .{});
    }
}

fn fatal(comptime format: []const u8, arg: anytype) noreturn {
    std.debug.print(format, arg);
    std.process.exit(1);
}
