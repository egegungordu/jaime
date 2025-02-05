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

// zig fmt: off
const args = @import("args");
const prefix = args.prefix;

// Check if required paths are set
const lex_path = if (@hasDecl(args, "lex")) args.lex else {
    @compileError("Missing required lexicon path. Please provide -D" ++ prefix ++ "-lex=<path>");
};
const matrix_path = if (@hasDecl(args, "matrix")) args.matrix else {
    @compileError("Missing required matrix path. Please provide -D" ++ prefix ++ "-matrix=<path>");
};
const char_path = if (@hasDecl(args, "char")) args.char else {
    @compileError("Missing required character definition path. Please provide -D" ++ prefix ++ "-char=<path>");
};
const unk_path = if (@hasDecl(args, "unk")) args.unk else {
    @compileError("Missing required unknown word definition path. Please provide -D" ++ prefix ++ "-unk=<path>");
};
const out_path = if (@hasDecl(args, "out")) args.out else {
    @compileError("Missing required output path. Please provide -D" ++ prefix ++ "-out=<path>");
};
const compress = args.compress;
const include = args.include;
// zig fmt: on

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

// TODO: use mmap / CreateFileMapping to make reading faster?
// TODO: all dictionary has to fit in memory, currently we load all files into memory and dont free them until the end
// 1. possibly serialize on the go, and deallocate files

const max_allocate_size = 9999999999;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var bldr = LoudsTrieBuilder.init(allocator);

    var ltrie: LoudsTrie = undefined;

    {
        std.debug.print("[lex] start\n", .{});

        var matched_files = glob.matchFiles(allocator, std.fs.cwd(), lex_path) catch |err| switch (err) {
            error.InvalidPattern => fatal("invalid lexicon path pattern: {s}", .{lex_path}),
            else => |e| return e,
        };
        defer {
            for (matched_files.items) |item| {
                allocator.free(item);
            }
            matched_files.deinit();
        }

        if (matched_files.items.len == 0) {
            fatal("no lexicon files found matching pattern: {s}", .{lex_path});
        }

        std.debug.print("[lex] found {d} lexicon file(s)\n", .{matched_files.items.len});

        for (matched_files.items) |file_path| {
            std.debug.print("[lex] processing {s}...\n", .{file_path});

            var input_file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                fatal("unable to open '{s}': {s}", .{ file_path, @errorName(err) });
            };
            defer input_file.close();

            const file = try input_file.reader().readAllAlloc(allocator, max_allocate_size);
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

        var input_file = std.fs.cwd().openFile(matrix_path, .{}) catch |err| {
            fatal("unable to open '{s}': {s}", .{ matrix_path, @errorName(err) });
        };
        defer input_file.close();

        const file = try input_file.reader().readAllAlloc(allocator, max_allocate_size);
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

        std.debug.print("[out] creating file: {s}...\n", .{out_path});

        var dic_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
            fatal("unable to open '{s}': {s}\n", .{ out_path, @errorName(err) });
        };

        std.debug.print("[out] serializing dictionary...\n", .{});

        DictionarySerializer.serialize(&.{
            .trie = ltrie,
            .costs = cost_arr,
            .right_count = right_count,
        }, dic_file.writer()) catch |err| {
            fatal("unable to serialize dictionary: {s}\n", .{@errorName(err)});
        };

        std.debug.print("[out] freeing up memory...\n", .{});

        // Free up memory for the remaining procedures
        bldr.deinit();
        ltrie.deinit();
        cost_arr.deinit();
        // Close the dictionary handle so we can open it back up with for tar
        dic_file.close();

        // Only create tar if we're compressing or have included files
        const should_tar = compress or include.len > 0;
        if (!should_tar) {
            std.debug.print("[out] end\n", .{});
            return;
        }

        var files_to_include = std.ArrayList([]const u8).init(allocator);
        defer files_to_include.deinit();

        // Always include the dictionary file
        try files_to_include.append(out_path);
        // Add any additional files
        try files_to_include.appendSlice(include);

        if (compress) {
            std.debug.print("[out] creating file: {s}...\n", .{out_path ++ ".tar.gz"});

            var tar_gz_file = std.fs.cwd().createFile(out_path ++ ".tar.gz", .{}) catch |err| {
                fatal("unable to open '{s}': {s}\n", .{ out_path ++ ".tar.gz", @errorName(err) });
            };
            defer tar_gz_file.close();

            var data = std.ArrayList(u8).init(allocator);
            defer data.deinit();

            try SimpleTar.create(std.fs.cwd(), data.writer(), files_to_include.items);

            var data_fbs = std.io.fixedBufferStream(data.items);
            try std.compress.gzip.compress(data_fbs.reader(), tar_gz_file.writer(), .{ .level = .best });
        } else {
            std.debug.print("[out] creating file: {s}...\n", .{out_path ++ ".tar"});

            var tar_file = std.fs.cwd().createFile(out_path ++ ".tar", .{}) catch |err| {
                fatal("unable to open '{s}': {s}\n", .{ out_path ++ ".tar", @errorName(err) });
            };
            defer tar_file.close();

            try SimpleTar.create(std.fs.cwd(), tar_file.writer(), files_to_include.items);
        }

        // Only delete the original dictionary file if we created a tar
        std.debug.print("[out] deleting intermediate file: {s}...\n", .{out_path});
        std.fs.cwd().deleteFile(out_path) catch |err| {
            fatal("unable to delete '{s}': {s}\n", .{ out_path, @errorName(err) });
        };

        std.debug.print("[out] end\n", .{});
    }
}

fn fatal(comptime format: []const u8, arg: anytype) noreturn {
    std.debug.print(format, arg);
    std.process.exit(1);
}
