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
        // If we have an asterisk, it must be in the format "/*.ext" or "*.ext"
        const last_separator = std.mem.lastIndexOf(u8, pattern, "/");
        const asterisk_pos = std.mem.indexOf(u8, pattern, "*").?;

        // Check if there's a path separator, it must come before the asterisk
        if (last_separator) |sep| {
            if (sep > asterisk_pos) return false;
            if (asterisk_pos != sep + 1) return false;
        }

        // Must have an extension after asterisk
        if (asterisk_pos == pattern.len - 1) return false;
        if (pattern[asterisk_pos + 1] != '.') return false;
        if (asterisk_pos + 2 >= pattern.len) return false; // Must have chars after dot
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
pub fn matchFiles(allocator: std.mem.Allocator, pattern: []const u8) !std.ArrayList([]const u8) {
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
    const last_separator = std.mem.lastIndexOf(u8, pattern, "/");
    const has_wildcard = std.mem.indexOf(u8, pattern, "*") != null;

    if (has_wildcard) {
        // Get the directory path and the pattern
        const dir_path = if (last_separator) |sep| pattern[0..sep] else ".";
        const file_pattern = if (last_separator) |sep| pattern[sep + 1 ..] else pattern;

        const extension = file_pattern[1..];
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                if (std.mem.endsWith(u8, entry.name, extension)) {
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
        const file = std.fs.cwd().openFile(pattern, .{}) catch |err| switch (err) {
            error.FileNotFound => return result,
            else => |e| return e,
        };
        file.close();

        const path_copy = try allocator.dupe(u8, pattern);
        try result.append(path_copy);
    }

    return result;
}

test "matchFiles - direct file" {
    const allocator = std.testing.allocator;

    // Create a test file
    {
        const file = try std.fs.cwd().createFile("test.csv", .{});
        file.close();
    }
    defer std.fs.cwd().deleteFile("test.csv") catch {};

    const matches = try matchFiles(allocator, "test.csv");
    defer {
        for (matches.items) |item| {
            allocator.free(item);
        }
        matches.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), matches.items.len);
    try std.testing.expectEqualStrings("test.csv", matches.items[0]);
}

test "matchFiles - wildcard" {
    const allocator = std.testing.allocator;

    // Create test files
    {
        const file1 = try std.fs.cwd().createFile("test1.csv", .{});
        file1.close();
        const file2 = try std.fs.cwd().createFile("test2.csv", .{});
        file2.close();
        const file3 = try std.fs.cwd().createFile("test3.txt", .{});
        file3.close();
    }
    defer {
        std.fs.cwd().deleteFile("test1.csv") catch {};
        std.fs.cwd().deleteFile("test2.csv") catch {};
        std.fs.cwd().deleteFile("test3.txt") catch {};
    }

    const matches = try matchFiles(allocator, "/*.csv");
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

test "matchFiles - complex patterns" {
    const allocator = std.testing.allocator;

    // Create test directory structure
    try std.fs.cwd().makeDir("testdir");
    defer std.fs.cwd().deleteDir("testdir") catch {};

    // Create test files in different locations
    {
        const file1 = try std.fs.cwd().createFile("testdir/nested.csv", .{});
        file1.close();
        const file2 = try std.fs.cwd().createFile("testdir/other.txt", .{});
        file2.close();
        const file3 = try std.fs.cwd().createFile("root.csv", .{});
        file3.close();
    }
    defer {
        std.fs.cwd().deleteFile("testdir/nested.csv") catch {};
        std.fs.cwd().deleteFile("testdir/other.txt") catch {};
        std.fs.cwd().deleteFile("root.csv") catch {};
    }

    // Test direct file in subdirectory
    {
        const matches = try matchFiles(allocator, "testdir/nested.csv");
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
        const matches = try matchFiles(allocator, "testdir/*.txt");
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
        const matches = try matchFiles(allocator, "testdir/*.nonexistent");
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
        const matches = try matchFiles(allocator, "testdir/nonexistent.txt");
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

    // Multiple asterisks
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/*.csv/*.txt"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "**/*.csv"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "*.*"));

    // Asterisk in wrong position
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/*.csv*"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/csv/*."));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "test*file.csv"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/*."));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/*"));

    // Asterisk after directory separator
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "test/*.csv/*"));
    try std.testing.expectError(GlobError.InvalidPattern, matchFiles(allocator, "/*/*.csv"));
}
