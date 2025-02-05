const std = @import("std");
const assert = std.debug.assert;

/// SimpleTar is a minimal implementation of the tar archive format.
/// It provides basic functionality to create tar archives by concatenating files.
///
/// Features:
/// - Creates standard-compliant tar archives
/// - Handles only regular files (no directories or symlinks)
/// - Uses ustar format for compatibility
/// - Supports files up to 99 characters in name length
/// - Automatically handles block alignment and padding
///
/// Example usage:
/// ```zig
/// const files = &[_][]const u8{"file1.txt", "file2.txt"};
/// var dir = try std.fs.cwd();
///
/// var output = try dir.createFile("output.tar", .{});
/// defer output.close();
///
/// try SimpleTar.create(dir, output.writer(), files);
/// ```
///
/// Note: This is a simplified implementation focused on basic file archiving.
/// A simple tar implementation that only handles file concatenation.
/// Does not support directories, symlinks, or other special files.
pub const SimpleTar = struct {
    /// Header block size in tar format
    const BLOCK_SIZE = 512;

    /// Header structure that matches tar file format
    const Header = extern struct {
        name: [100]u8,
        mode: [8]u8,
        uid: [8]u8,
        gid: [8]u8,
        size: [12]u8,
        mtime: [12]u8,
        checksum: [8]u8,
        typeflag: u8,
        linkname: [100]u8,
        magic: [6]u8,
        version: [2]u8,
        uname: [32]u8,
        gname: [32]u8,
        devmajor: [8]u8,
        devminor: [8]u8,
        prefix: [155]u8,
        pad: [12]u8,

        pub fn init() Header {
            var header = std.mem.zeroes(Header);
            // Set magic and version for ustar format
            @memcpy(&header.magic, "ustar\x00");
            @memcpy(&header.version, "00");
            header.typeflag = '0'; // regular file
            return header;
        }

        pub fn setPath(self: *Header, path: []const u8) !void {
            if (path.len > 99) return error.PathTooLong;
            @memset(&self.name, 0);
            @memcpy(self.name[0..path.len], path);
        }

        pub fn setSize(self: *Header, size: u64) !void {
            // Write size in octal format
            const size_str = try std.fmt.bufPrint(&self.size, "{o:0>11}", .{size});
            self.size[size_str.len] = 0;
        }

        pub fn setMode(self: *Header, mode: u32) !void {
            // Write mode in octal format
            const mode_str = try std.fmt.bufPrint(&self.mode, "{o:0>7}", .{mode});
            self.mode[mode_str.len] = 0;
        }

        pub fn setMtime(self: *Header, mtime: i128) !void {
            // Convert nanoseconds to seconds
            const seconds = @as(u64, @intCast(@divFloor(mtime, std.time.ns_per_s)));

            // Clear the field first
            @memset(&self.mtime, 0);
            var buf: [32]u8 = undefined;
            const mtime_str = try std.fmt.bufPrint(&buf, "{o:0>11}", .{seconds});
            if (mtime_str.len != 11) return error.InvalidMtimeFormat;
            @memcpy(self.mtime[0..11], mtime_str);
        }

        pub fn setUid(self: *Header, uid: u32) !void {
            @memset(&self.uid, 0);
            const uid_str = try std.fmt.bufPrint(&self.uid, "{o:0>7}", .{uid});
            self.uid[uid_str.len] = 0;
        }

        pub fn setGid(self: *Header, gid: u32) !void {
            @memset(&self.gid, 0);
            const gid_str = try std.fmt.bufPrint(&self.gid, "{o:0>7}", .{gid});
            self.gid[gid_str.len] = 0;
        }

        pub fn updateChecksum(self: *Header) !void {
            // First set checksum field to spaces
            @memset(&self.checksum, ' ');

            // Calculate checksum
            var sum: usize = 0;
            for (std.mem.asBytes(self)) |byte| {
                sum += byte;
            }

            // Write checksum in octal format
            const checksum_str = try std.fmt.bufPrint(&self.checksum, "{o:0>6}", .{sum});
            self.checksum[checksum_str.len] = 0;
        }

        comptime {
            assert(@sizeOf(Header) == BLOCK_SIZE);
        }
    };

    /// Creates a tar archive containing the specified files.
    /// Files are read from the provided directory and written to the writer.
    pub fn create(dir: std.fs.Dir, writer: anytype, files: []const []const u8) !void {
        // Write each file
        for (files) |path| {
            const file = try dir.openFile(path, .{});
            defer file.close();

            // Extract just the filename from the path
            const basename = std.fs.path.basename(path);
            try writeFileToArchive(file, writer, basename);
        }

        // Write two empty blocks to mark end of archive
        const empty_block = [_]u8{0} ** BLOCK_SIZE;
        try writer.writeAll(&empty_block);
        try writer.writeAll(&empty_block);
    }

    /// Internal helper to write a single file to the archive
    fn writeFileToArchive(file: std.fs.File, writer: anytype, path: []const u8) !void {
        const stat = try file.stat();

        // Create and fill header
        var header = Header.init();
        try header.setPath(path);
        try header.setSize(stat.size);
        // Set mode: combine regular file bit (0o100000) with permissions (0o644)
        try header.setMode(0o100000 | 0o644);
        try header.setMtime(stat.mtime);
        try header.setUid(0); // Set UID to root (0)
        try header.setGid(0); // Set GID to root (0)

        try header.updateChecksum();

        // Write header
        try writer.writeAll(std.mem.asBytes(&header));

        // Write file content
        var buffer: [8192]u8 = undefined;
        var bytes_remaining = stat.size;
        while (bytes_remaining > 0) {
            const to_read = @min(buffer.len, bytes_remaining);
            const bytes_read = try file.read(buffer[0..to_read]);
            if (bytes_read == 0) break;
            try writer.writeAll(buffer[0..bytes_read]);
            bytes_remaining -= bytes_read;
        }

        // Add padding to align with block size
        const padding_size = (BLOCK_SIZE - (stat.size % BLOCK_SIZE)) % BLOCK_SIZE;
        if (padding_size > 0) {
            const padding = [_]u8{0} ** BLOCK_SIZE;
            try writer.writeAll(padding[0..padding_size]);
        }
    }
};

const testing = std.testing;

fn createFileWithContent(dir: std.fs.Dir, path: []const u8, content: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir_name| {
        try dir.makePath(dir_name);
    }
    const file = try dir.createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

fn verifyTarHeader(header: []const u8, name: []const u8, size: u64) !void {
    // Normalize path for comparison
    var normalized_name: [100]u8 = undefined;
    var normalized_len: usize = 0;

    for (name) |c| {
        if (normalized_len >= normalized_name.len) return error.PathTooLong;
        normalized_name[normalized_len] = if (c == std.fs.path.sep) '/' else c;
        normalized_len += 1;
    }

    // Verify name field
    try testing.expectEqualStrings(normalized_name[0..normalized_len], std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&header[0])), 0));

    // Verify size field (in octal)
    var size_buf: [12]u8 = undefined;
    const size_str = try std.fmt.bufPrint(&size_buf, "{o:0>11}", .{size});
    try testing.expectEqualStrings(size_str, header[124..][0..11]);

    // Verify magic (ustar) and version
    try testing.expectEqualStrings("ustar\x00", header[257..][0..6]);
    try testing.expectEqualStrings("00", header[263..][0..2]);
}

test "SimpleTar - single file" {
    // Setup temporary directory
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a test file
    const test_content = "Hello, Tar!";
    try createFileWithContent(tmp.dir, "test.txt", test_content);

    // Create tar archive
    const tar_path = "output.tar";
    {
        var tar_file = try tmp.dir.createFile(tar_path, .{});
        defer tar_file.close();

        try SimpleTar.create(tmp.dir, tar_file.writer(), &[_][]const u8{"test.txt"});
    }

    // Read and verify tar contents
    {
        const tar_contents = try tmp.dir.readFileAlloc(testing.allocator, tar_path, 1024 * 1024);
        defer testing.allocator.free(tar_contents);

        // Verify header
        try verifyTarHeader(tar_contents[0..512], "test.txt", test_content.len);

        // Verify content
        try testing.expectEqualStrings(test_content, tar_contents[512..][0..test_content.len]);
    }
}

test "SimpleTar - multiple files" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create test files
    const files = [_]struct { name: []const u8, content: []const u8 }{
        .{ .name = "file1.txt", .content = "First file content" },
        .{ .name = "subdir" ++ std.fs.path.sep_str ++ "file2.txt", .content = "Second file in subdir" },
    };

    for (files) |file| {
        try createFileWithContent(tmp.dir, file.name, file.content);
    }

    // Create tar archive
    const tar_path = "output.tar";
    {
        var tar_file = try tmp.dir.createFile(tar_path, .{});
        defer tar_file.close();

        try SimpleTar.create(tmp.dir, tar_file.writer(), &[_][]const u8{ files[0].name, files[1].name });
    }

    // Read and verify tar contents
    {
        const tar_contents = try tmp.dir.readFileAlloc(testing.allocator, tar_path, 1024 * 1024);
        defer testing.allocator.free(tar_contents);

        var offset: usize = 0;
        for (files) |file| {
            const basename = std.fs.path.basename(file.name);
            // Verify header
            try verifyTarHeader(tar_contents[offset..][0..512], basename, file.content.len);
            offset += 512;

            // Verify content
            try testing.expectEqualStrings(file.content, tar_contents[offset..][0..file.content.len]);
            offset += std.mem.alignForward(usize, file.content.len, 512);
        }
    }
}

test "SimpleTar - path too long" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create a file with a path that's too long (>99 characters)
    const long_name = "a" ** 100 ++ ".txt";
    try createFileWithContent(tmp.dir, long_name, "test");

    // Attempt to create tar archive - should fail
    const tar_path = "output.tar";
    {
        var tar_file = try tmp.dir.createFile(tar_path, .{});
        defer tar_file.close();

        try testing.expectError(error.PathTooLong, SimpleTar.create(tmp.dir, tar_file.writer(), &[_][]const u8{long_name}));
    }
}
