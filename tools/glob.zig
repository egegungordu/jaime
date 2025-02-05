const std = @import("std");

pub const GlobError = error{
    /// Returned when the glob pattern does not match the required format
    InvalidPattern,
};

/// Validates if a glob pattern matches the required format.
/// Valid patterns are:
/// - Direct file paths: "file.txt", "dir/file.txt"
/// - Simple wildcards: "*.ext", "/*.ext", "dir/*.ext"
///
/// The wildcard pattern must follow these rules:
/// - Only one asterisk is allowed
/// - Asterisk must be followed by a dot and extension
/// - If there's a path separator, asterisk must come immediately after it
///
/// Invalid patterns include:
/// - Multiple asterisks: "**/*.txt", "*.txt/*.csv"
/// - Asterisk in wrong position: "/*.txt*", "a*b.txt"
/// - Missing extension: "/*", "/*."
/// - Nested wildcards: "/*/*.txt"
fn isValidPattern(pattern: []const u8) bool {
    const asterisk_count = std.mem.count(u8, pattern, "*");
    if (asterisk_count > 1) return false;
    if (asterisk_count == 1) {
        // If we have an asterisk, it must be in the format "/*.ext", "*.ext", "/*", or "*"
        const last_separator = findLastPathSeparator(pattern);
        const asterisk_pos = std.mem.indexOf(u8, pattern, "*").?;

        // Check if there's a path separator, it must come before the asterisk
        if (last_separator) |sep| {
            if (sep > asterisk_pos) return false;
            if (asterisk_pos != sep + 1) return false;
        }

        // Pattern can either end with asterisk or must have an extension after asterisk
        if (asterisk_pos < pattern.len - 1) {
            // If not ending with asterisk, must have proper extension
            if (pattern[asterisk_pos + 1] != '.') return false;
            if (asterisk_pos + 2 >= pattern.len) return false; // Must have chars after dot
        }
    }
    return true;
}

/// Matches files according to a simple glob pattern.
/// Returns an ArrayList of matched file paths that the caller must free.
///
/// The function only accepts two types of patterns:
/// 1. Direct file paths:
///    - "file.txt"
///    - "directory/file.txt"
///
/// 2. Simple wildcard patterns with extensions:
///    - "*.ext"
///    - "/*.ext"
///    - "directory/*.ext"
///
/// The wildcard pattern must follow these rules:
/// - Only one asterisk is allowed
/// - Asterisk must be followed by a dot and extension
/// - If there's a path separator, asterisk must come immediately after it
///
/// For direct file paths, the function verifies the file exists.
/// For wildcard patterns, it searches in the specified directory for matching files.
///
/// Returns error.InvalidPattern if the pattern doesn't match the required format.
///
/// Memory Management:
/// - The caller owns the returned ArrayList and must call deinit() on it
/// - Each path string in the list is allocated and must be freed by the caller
pub fn matchFiles(allocator: std.mem.Allocator, dir: std.fs.Dir, pattern: []const u8) !std.ArrayList([]const u8) {
    if (!isValidPattern(pattern)) {
        return GlobError.InvalidPattern;
    }

    var result = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit();
    }

    // Find the last path separator
    const last_separator = findLastPathSeparator(pattern);
    const has_wildcard = std.mem.indexOf(u8, pattern, "*") != null;

    if (has_wildcard) {
        // Get the directory path and the pattern
        const dir_path = if (last_separator) |sep| pattern[0..sep] else ".";
        const file_pattern = if (last_separator) |sep| pattern[sep + 1 ..] else pattern;

        const asterisk_pos = std.mem.indexOf(u8, file_pattern, "*").?;
        const match_all = asterisk_pos == file_pattern.len - 1;
        const extension = if (!match_all) file_pattern[asterisk_pos + 1 ..] else "";

        var dirr = try dir.openDir(dir_path, .{ .iterate = true });
        defer dirr.close();

        var iter = dirr.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const should_include = if (match_all)
                    true
                else
                    std.mem.endsWith(u8, entry.name, extension);

                if (should_include) {
                    const full_path = if (std.mem.eql(u8, dir_path, "."))
                        try allocator.dupe(u8, entry.name)
                    else
                        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
                    try result.append(full_path);
                }
            }
        }
    } else {
        // For direct file paths, just verify the file exists and add it
        const file = dir.openFile(pattern, .{}) catch |err| switch (err) {
            error.FileNotFound => return result,
            else => |e| return e,
        };
        file.close();

        const path_copy = try allocator.dupe(u8, pattern);
        try result.append(path_copy);
    }

    return result;
}

fn findLastPathSeparator(path: []const u8) ?usize {
    var last_sep: ?usize = null;
    for (path, 0..) |c, i| {
        if (c == '/' or c == '\\') {
            last_sep = i;
        }
    }
    return last_sep;
}

const testing = std.testing;

test "matchFiles - direct file" {
    const allocator = testing.allocator;
    var root = testing.tmpDir(.{});
    defer root.cleanup();

    // Create a test file
    try createDirAndFile(root.dir, "test.csv");

    const matches = try matchFiles(allocator, root.dir, "test.csv");
    defer {
        for (matches.items) |item| {
            allocator.free(item);
        }
        matches.deinit();
    }

    try testing.expectEqual(@as(usize, 1), matches.items.len);
    try testing.expectEqualStrings("test.csv", matches.items[0]);
}

test "matchFiles - wildcard" {
    const allocator = std.testing.allocator;
    var root = testing.tmpDir(.{});
    defer root.cleanup();

    // Create test files
    try createDirAndFile(root.dir, "test1.csv");
    try createDirAndFile(root.dir, "test2.csv");
    try createDirAndFile(root.dir, "test3.txt");

    // Test extension matching
    {
        const matches = try matchFiles(allocator, root.dir, "/*.csv");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }

        try std.testing.expectEqual(@as(usize, 2), matches.items.len);
        // Note: The exact order might vary by filesystem
        for (matches.items) |item| {
            try std.testing.expect(std.mem.endsWith(u8, item, ".csv"));
        }
    }

    // Test matching all files
    {
        const matches = try matchFiles(allocator, root.dir, "/*");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }

        try std.testing.expectEqual(@as(usize, 3), matches.items.len);
    }

    // Test matching all files in current directory
    {
        const matches = try matchFiles(allocator, root.dir, "*");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }

        try std.testing.expectEqual(@as(usize, 3), matches.items.len);
    }
}

test "matchFiles - complex patterns" {
    const allocator = std.testing.allocator;
    var root = testing.tmpDir(.{});
    defer root.cleanup();

    // Create test files in different locations
    try createDirAndFile(root.dir, "testdir/nested.csv");
    try createDirAndFile(root.dir, "testdir/other.txt");
    try createDirAndFile(root.dir, "testdir/root.csv");

    // Test direct file in subdirectory
    {
        const matches = try matchFiles(allocator, root.dir, "testdir/nested.csv");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }
        try std.testing.expectEqual(@as(usize, 1), matches.items.len);
        try std.testing.expectEqualStrings("testdir/nested.csv", matches.items[0]);
    }

    // Test wildcard in subdirectory
    {
        const matches = try matchFiles(allocator, root.dir, "testdir/*.txt");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }
        try std.testing.expectEqual(@as(usize, 1), matches.items.len);
        try std.testing.expectEqualStrings("testdir/other.txt", matches.items[0]);
    }

    // Test non-existent pattern
    {
        const matches = try matchFiles(allocator, root.dir, "testdir/*.nonexistent");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }
        try std.testing.expectEqual(@as(usize, 0), matches.items.len);
    }

    // Test non-existent direct file
    {
        const matches = try matchFiles(allocator, root.dir, "testdir/nonexistent.txt");
        defer {
            for (matches.items) |item| {
                allocator.free(item);
            }
            matches.deinit();
        }
        try std.testing.expectEqual(@as(usize, 0), matches.items.len);
    }
}

test "matchFiles - invalid patterns" {
    const allocator = std.testing.allocator;
    var root = testing.tmpDir(.{});
    defer root.cleanup();

    // Multiple asterisks
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "/*.csv/*.txt"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "**/*.csv"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "*.*"));

    // Asterisk in wrong position
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "/*.csv*"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "/csv/*."));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "test*file.csv"));

    // Invalid directory patterns
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "/*/"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "test/*.csv/*"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, root.dir, "/*/*.csv"));
}

/// Creates a file and the directory if needed. Closes it right away
fn createDirAndFile(dir: std.fs.Dir, file_name: []const u8) !void {
    const temp_file = dir.createFile(file_name, .{ .exclusive = true }) catch |err| {
        if (err == error.FileNotFound) {
            if (std.fs.path.dirname(file_name)) |dir_name| {
                try dir.makePath(dir_name);
                const temp_file = try dir.createFile(file_name, .{ .exclusive = true });
                temp_file.close();
                return;
            }
        }
        return err;
    };
    temp_file.close();
}
