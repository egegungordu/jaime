const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;

const matchFiles = @import("glob.zig").matchFiles;
const core = @import("core");
const datastructs = @import("datastructs");
const WordEntry = core.WordEntry;
const LoudsTrie = datastructs.louds_trie.LoudsTrie(WordEntry);
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder(WordEntry);
const DictionarySerializer = core.dictionary.DictionarySerializer;

// zig fmt: off
const paths = @import("paths");
const prefix = paths.prefix;

// Check if required paths are set
const lex_path = if (@hasDecl(paths, "lex")) paths.lex else {
    @compileError("Missing required lexicon path. Please provide -D" ++ prefix ++ "-lex=<path>");
};
const matrix_path = if (@hasDecl(paths, "matrix")) paths.matrix else {
    @compileError("Missing required matrix path. Please provide -D" ++ prefix ++ "-matrix=<path>");
};
const char_path = if (@hasDecl(paths, "char")) paths.char else {
    @compileError("Missing required character definition path. Please provide -D" ++ prefix ++ "-char=<path>");
};
const unk_path = if (@hasDecl(paths, "unk")) paths.unk else {
    @compileError("Missing required unknown word definition path. Please provide -D" ++ prefix ++ "-unk=<path>");
};
const out_path = if (@hasDecl(paths, "out")) paths.out else {
    @compileError("Missing required output path. Please provide -D" ++ prefix ++ "-out=<path>");
};
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
    defer bldr.deinit();

    var ltrie: LoudsTrie = undefined;
    defer ltrie.deinit();

    {
        std.debug.print("[lex] start\n", .{});

        var matched_files = matchFiles(allocator, lex_path) catch |err| switch (err) {
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
    defer cost_arr.deinit();

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
        std.debug.print("[out] opening file: {s}...\n", .{out_path});

        var out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
            fatal("unable to open '{s}': {s}", .{ out_path, @errorName(err) });
        };
        defer out_file.close();

        std.debug.print("[out] serializing dictionary...\n", .{});

        DictionarySerializer.serialize(&.{
            .trie = ltrie,
            .costs = cost_arr,
            .right_count = right_count,
        }, out_file.writer()) catch |err| {
            fatal("unable to serialize dictionary: {s}", .{@errorName(err)});
        };

        std.debug.print("[out] end\n", .{});
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
