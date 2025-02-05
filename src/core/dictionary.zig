const std = @import("std");
const mem = std.mem;

const WordEntry = @import("WordEntry.zig");
const datastructs = @import("datastructs");
const LoudsTrie = datastructs.louds_trie.LoudsTrie;
const SuccinctBitArray = datastructs.succinct_bit_array.SuccinctBitArray;
const SuccinctBitArrayBuilder = datastructs.succinct_bit_array.SuccinctBitArrayBuilder;
const Louds = datastructs.louds.Louds;
const BitArray = datastructs.BitArray;

// TODO: add a mapping layer, that will map input hiragana to smaller values
// so the trie labels will be smaller
// example: あ -> 0
//          い -> 0
//          ...

pub const Dictionary = struct {
    trie: LoudsTrie(WordEntry),
    costs: std.ArrayList(i16),
    right_count: u32,

    pub fn deinit(self: *Dictionary) void {
        self.trie.deinit();
        self.costs.deinit();
    }

    pub fn getCost(self: Dictionary, left_id: u32, right_id: u32) i16 {
        return self.costs.items[self.right_count * left_id + right_id];
    }
};

// TODO: could also write all sizes for all containers, so we can maybe deserialize more efficiently? (HOW?)

/// A serializer/deserializer for Dictionary.
/// The deserializer assumes that the lifetime of the reader's underlying buffer will outlive
/// the deserialized object, as it uses slices directly from the reader's buffer rather than
/// allocating new strings. This is safe when using @embedFile since the embedded data lives
/// for the entire program lifetime.
pub const DictionarySerializer = struct {
    const Self = @This();
    const wire_endian = .little;

    /// Note: For cross-platform compatibility, usize and isize values are truncated to 32 bits during serialization
    /// and expanded back during deserialization. This means values must fit within 32 bits to be correctly serialized.
    pub fn serialize(dict: *const Dictionary, writer: anytype) !void {
        // dict.ltrie.labels
        try serializeStringArrayList(&dict.trie.labels, writer);
        // dict.ltrie.values
        try serializeWordEntryArrayList(&dict.trie.values, writer);
        // dict.ltrie.value_offsets
        try serializeIntArrayList(usize, &dict.trie.value_offsets, writer);
        // dict.ltrie.louds.sba
        try serializeSuccinctBitArray(&dict.trie.louds.sba, writer);
        // dict.costs
        try serializeIntArrayList(i16, &dict.costs, writer);
        // dict.right_count
        try serializeInt(u32, dict.right_count, writer);
    }

    pub fn deserialize(allocator: mem.Allocator, reader: anytype) !Dictionary {
        var labels = try deserializeStringArrayList(allocator, reader);
        errdefer labels.deinit();
        var values = try deserializeWordEntryArrayList(allocator, reader);
        errdefer values.deinit();
        var value_offsets = try deserializeIntArrayList(usize, allocator, reader);
        errdefer value_offsets.deinit();
        var louds_sba = try deserializeSuccinctBitArray(allocator, reader);
        errdefer louds_sba.deinit();
        var costs = try deserializeIntArrayList(i16, allocator, reader);
        errdefer costs.deinit();
        const right_count = try deserializeInt(u32, reader);
        return .{
            .trie = .{
                .labels = labels,
                .values = values,
                .value_offsets = value_offsets,
                .louds = Louds(32).init(louds_sba),
            },
            .costs = costs,
            .right_count = right_count,
        };
    }

    fn serializeStringArrayList(list: *const std.ArrayList([]const u8), writer: anytype) !void {
        // First write the number of elements in the array
        try serializeInt(usize, list.items.len, writer);

        // For each element (which is []const u8)
        for (list.items) |str| {
            // Write number of bytes in this array
            try serializeInt(usize, str.len, writer);

            try writer.writeAll(str);
        }
    }

    fn serializeWordEntryArrayList(list: *const std.ArrayList(WordEntry), writer: anytype) !void {
        // First write the number of elements in the array
        try serializeInt(usize, list.items.len, writer);

        // For each element (which is WordEntry)
        for (list.items) |we| {
            try serializeWordEntry(we, writer);
        }
    }

    fn serializeWordEntry(we: WordEntry, writer: anytype) !void {
        try serializeInt(usize, we.word.len, writer);
        try writer.writeAll(we.word);
        try serializeInt(u32, we.left_id, writer);
        try serializeInt(u32, we.right_id, writer);
        try serializeInt(i16, we.cost, writer);
    }

    fn serializeSuccinctBitArray(sba: *const SuccinctBitArray(32), writer: anytype) !void {
        // serialize sba.bit_array
        try serializeBitArray(&sba.bit_array, writer);
        // serialize sba.index
        try serializeIntArrayList(usize, &sba.index, writer);
    }

    fn serializeBitArray(array: *const BitArray, writer: anytype) !void {
        // bit_len: usize,
        try serializeInt(usize, array.bit_len, writer);
        // bytes: std.ArrayList(u8),
        try serializeIntArrayList(u8, &array.bytes, writer);
    }

    fn serializeInt(comptime T: type, value: T, writer: anytype) !void {
        switch (T) {
            usize => try writer.writeInt(u32, @truncate(value), wire_endian),
            isize => try writer.writeInt(i32, @truncate(value), wire_endian),
            else => try writer.writeInt(T, value, wire_endian),
        }
    }

    fn serializeIntArrayList(comptime T: type, list: *const std.ArrayList(T), writer: anytype) !void {
        // First write the number of elements in the array
        try serializeInt(usize, list.items.len, writer);

        // For each element (which is usize)
        for (list.items) |element| {
            // Write it
            try serializeInt(T, element, writer);
        }
    }

    fn deserializeStringArrayList(allocator: mem.Allocator, reader: anytype) !std.ArrayList([]const u8) {
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();

        // Read number of elements
        const num_elements = try deserializeInt(usize, reader);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            // Read string length
            const str_len = try deserializeInt(usize, reader);

            // Read string
            const str = reader.context.buffer[reader.context.pos .. reader.context.pos + str_len];
            try reader.skipBytes(str_len, .{});

            try list.append(str);
        }

        return list;
    }

    fn deserializeWordEntryArrayList(allocator: mem.Allocator, reader: anytype) !std.ArrayList(WordEntry) {
        var list = std.ArrayList(WordEntry).init(allocator);
        errdefer list.deinit();

        // Read number of elements
        const num_elements = try deserializeInt(usize, reader);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            const we = try deserializeWordEntry(reader);
            try list.append(we);
        }

        return list;
    }

    fn deserializeWordEntry(reader: anytype) !WordEntry {
        const str_len = try deserializeInt(usize, reader);
        const word = reader.context.buffer[reader.context.pos .. reader.context.pos + str_len];
        try reader.skipBytes(str_len, .{});
        const left_id = try deserializeInt(u32, reader);
        const right_id = try deserializeInt(u32, reader);
        const cost = try deserializeInt(i16, reader);
        return .{
            .word = word,
            .left_id = left_id,
            .right_id = right_id,
            .cost = cost,
        };
    }

    fn deserializeSuccinctBitArray(allocator: mem.Allocator, reader: anytype) !SuccinctBitArray(32) {
        return .{
            .bit_array = try deserializeBitArray(allocator, reader),
            .index = try deserializeIntArrayList(usize, allocator, reader),
        };
    }

    fn deserializeBitArray(allocator: mem.Allocator, reader: anytype) !BitArray {
        return .{
            .bit_len = try deserializeInt(usize, reader),
            .bytes = try deserializeIntArrayList(u8, allocator, reader),
        };
    }

    fn deserializeInt(comptime T: type, reader: anytype) !T {
        return switch (T) {
            usize => @intCast(try reader.readInt(u32, wire_endian)),
            isize => @intCast(try reader.readInt(i32, wire_endian)),
            else => try reader.readInt(T, wire_endian),
        };
    }

    fn deserializeIntArrayList(comptime T: type, allocator: mem.Allocator, reader: anytype) !std.ArrayList(T) {
        var list = std.ArrayList(T).init(allocator);
        errdefer list.deinit();

        // First read the number of elements in the array
        const num_elements = try deserializeInt(usize, reader);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            // Read the element
            const element = try deserializeInt(T, reader);

            try list.append(element);
        }

        return list;
    }
};
