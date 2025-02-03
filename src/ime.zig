const std = @import("std");
const mem = std.mem;

const core = @import("core");
const ImeCore = core.ime.Ime;
const Dictionary = core.dictionary.Dictionary;
const DictionarySerializer = core.dictionary.DictionarySerializer;

const dic = @embedFile("dic");

const DicLoader = struct {
    pub fn loadDictionary(allocator: mem.Allocator) !Dictionary {
        var dict_fbs = std.io.fixedBufferStream(dic);

        return try DictionarySerializer.deserialize(
            allocator,
            dict_fbs.reader(),
        );
    }

    pub fn freeDictionary(dict: *Dictionary) void {
        dict.deinit();
    }
};

pub const Ime = ImeCore(DicLoader);
pub const WordEntry = core.WordEntry;
