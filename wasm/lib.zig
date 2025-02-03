const std = @import("std");
const mem = std.mem;

extern "debug" fn consoleLog(arg: u32) void;

const Ime = @import("ime").Ime;

// TODO: There is a memory leak somewhere

var ime: Ime = undefined;

// Buffer for input text
var input_buffer = std.mem.zeroes([1024]u8);
export fn getInputBufferPointer() [*]u8 {
    return @ptrCast(&input_buffer);
}

// Buffer for the ime
var ime_buffer = std.mem.zeroes([32_000_000]u8);
var fba = std.heap.FixedBufferAllocator.init(&ime_buffer);
var last_insert_result: ?Ime.MatchModification = undefined;

// Buffer for storing the current match text
var match_buffer = std.mem.zeroes([4096]u8);

export fn init() void {
    ime = Ime.init(fba.allocator()) catch |err| {
        switch (err) {
            error.OutOfMemory => consoleLog(1),
            error.EndOfStream => consoleLog(3),
        }
        return;
    };
}

export fn insert(length: usize) void {
    const slice = input_buffer[0..length];
    last_insert_result = ime.insert(slice) catch {
        consoleLog(4);
        return;
    };
}

export fn getDeletedCodepoints() usize {
    return if (last_insert_result) |result| result.deleted_codepoints else 0;
}

export fn getInsertedTextLength() usize {
    return if (last_insert_result) |result| result.inserted_text.len else 0;
}

export fn getInsertedTextPointer() [*]const u8 {
    return @ptrCast(if (last_insert_result) |result| result.inserted_text.ptr else undefined);
}

export fn deleteBack() void {
    ime.deleteBack() catch return;
}

export fn deleteForward() void {
    ime.deleteForward() catch return;
}

export fn moveCursorBack(n: usize) void {
    ime.moveCursorBack(n);
}

export fn moveCursorForward(n: usize) void {
    ime.moveCursorForward(n);
}

export fn getMatchCount() usize {
    if (ime.getMatches()) |matches| {
        return matches.len;
    }
    return 0;
}

export fn getMatchText(index: usize) [*]const u8 {
    if (ime.getMatches()) |matches| {
        if (index < matches.len) {
            const word = matches[index].word;
            @memcpy(match_buffer[0..word.len], word);
            return @ptrCast(&match_buffer);
        }
    }
    return @ptrCast(&match_buffer);
}

export fn getMatchTextLength(index: usize) usize {
    if (ime.getMatches()) |matches| {
        if (index < matches.len) {
            return matches[index].word.len;
        }
    }
    return 0;
}

export fn applyMatch() void {
    last_insert_result = ime.applyMatch() catch return;
}
