# Jaime

A headless Japanese IME (Input Method Editor) engine for Zig projects that provides:

- Romaji to hiragana/katakana conversion

  eiennni → えいえんに

- Full-width character conversion

  abc123 → ａｂｃ１２３

- Dictionary-based word conversion

  かんじ → 漢字

- Built-in cursor and buffer management

Based on Google 日本語入力 behavior.

<table>
<tr>
<td>

On the **terminal** with libvaxis

[View repository](https://github.com/egegungordu/ja-ime-terminal-demo)

<img src=".github/assets/term-demo.gif" width="400" alt="Terminal demo">

</td>
<td>

On the **web** with webassembly

[Online demo](https://jaime-wasm.pages.dev/)

<img src=".github/assets/web-demo.gif" width="400" alt="Web demo">

</td>
</tr>
</table>

## Zig Version

The minimum Zig version required is 0.13.0.

## Integrating jaime into your Zig Project

You can add jaime as a dependency in your `build.zig.zon` file in two ways:

### Development Version

```bash
# Get the latest development version from main branch
zig fetch --save git+https://github.com/egegungordu/jaime
```

### Release Version

```bash
# Get a specific release version (replace x.y.z with desired version)
zig fetch --save https://github.com/egegungordu/jaime/archive/refs/tags/vx.y.z.tar.gz
```

Then instantiate the dependency in your `build.zig`:

```zig
const jaime = b.dependency("jaime", .{
    .dic_fetch = .unidic, // Download and use UniDic (recommended)
    // .dic_fetch = .ipadic, // Or use IPADIC
    // .dic_file = "path/to/custom.bin", // Or use your own dictionary binary
});

exe.root_module.addImport("kana", jaime.module("kana")); // For simple kana conversion
exe.root_module.addImport("ime", jaime.module("ime")); // For IME functionality
```

## Dictionary Options

There are two ways to use a dictionary with jaime:

### 1. Pre-built Dictionaries

Use the `dic-fetch` option to automatically download and use a pre-built dictionary:

```zig
const jaime = b.dependency("jaime", .{
    .dic_fetch = .unidic,
});
```

### 2. Custom Dictionary

You can build your own dictionary from source files using the dictionary builder tool. Clone the repository and do:

```bash
# Build a dictionary from lexicon files
zig build dictionary \
    -Ddic-gen-out=custom.bin \
    -Ddic-gen-lex=path/to/lex/*.csv \
    -Ddic-gen-char=path/to/char.def \
    -Ddic-gen-matrix=path/to/matrix.def \
    -Ddic-gen-unk=path/to/unk.def
```

```zig
# Then use the generated dictionary
const jaime = b.dependency("jaime", .{
    .dic_file = "custom.bin",
});
```

## Licensing Information

Each dictionary has its own license requirements and restrictions that may affect how you can use and redistribute them in your application. The license terms for each dictionary can be found here:

- UniDic: [TODO: Add license link]
- IPADIC: [TODO: Add license link]

## Usage

The library provides two main modules:

### 1. Kana Module - Simple Conversions

For simple romaji to hiragana conversions without IME functionality:

```zig
const kana = @import("kana");

// Using a provided buffer (no allocations)
var buf: [100]u8 = undefined;
const result = try kana.convertBuf(&buf, "konnnichiha");
try std.testing.expectEqualStrings("こんにちは", result);

// Using an allocator (returns owned slice)
const result2 = try kana.convert(allocator, "konnnichiha");
defer allocator.free(result2);
try std.testing.expectEqualStrings("こんにちは", result2);
```

### 2. IME Module - Full Featured IME

For applications that want to use the full-featured IME with dictionary support:

```zig
const ime = @import("ime");

// Using owned buffer (with allocator)
var ime_instance = ime.Ime(.owned).init(allocator);
defer ime_instance.deinit();

// Using borrowed buffer (fixed size, no allocations)
var buf: [100]u8 = undefined;
var ime_instance = ime.Ime(.borrowed).init(&buf);

// Common IME operations
const result = try ime_instance.insert("k");
const result2 = try ime_instance.insert("o");
const result3 = try ime_instance.insert("n");
try std.testing.expectEqualStrings("こん", ime_instance.input.buf.items());

// Dictionary Matches
if (ime_instance.getMatches()) |matches| {
    // Get suggested conversions from the dictionary
    // Returns []WordEntry containing possible word matches
}
try ime_instance.applyMatch();    // Apply the best dictionary match to the current input

// Cursor Movement and Editing
ime_instance.moveCursorBack(1);   // Move cursor left n positions
ime_instance.moveCursorForward(1);// Move cursor right n positions
try ime_instance.insert("y");     // Insert at cursor position
ime_instance.clear();             // Clear the input buffer
try ime_instance.deleteBack();    // Delete one character before cursor
try ime_instance.deleteForward(); // Delete one character after cursor
```

## WebAssembly Bindings

For web applications, you can build the WebAssembly bindings:

```bash
# Build the WebAssembly library
zig build
```

The WebAssembly library uses the IPADIC dictionary by default. For a complete example of how to use the WebAssembly bindings in a web application, check out the [web example](examples/web/index.js).

The WebAssembly library provides the following functions:

```javascript
// Initialize the IME
init();

// Get pointer to input buffer for writing input text
getInputBufferPointer();

// Insert text at current position
// length: number of bytes to read from input buffer
insert(length);

// Get information about the last insertion
getDeletedCodepoints(); // Number of codepoints deleted
getInsertedTextLength(); // Length of inserted text in bytes
getInsertedTextPointer(); // Pointer to inserted text

// Cursor movement and editing
deleteBack(); // Delete character before cursor
deleteForward(); // Delete character after cursor
moveCursorBack(n); // Move cursor back n positions
moveCursorForward(n); // Move cursor forward n positions
```

Example usage in JavaScript:

```javascript
// Initialize
init();

// Get input buffer
const inputPtr = getInputBufferPointer();
const inputBuffer = new Uint8Array(memory.buffer, inputPtr, 64);

// Write and insert characters one by one
const text = "ka";
for (const char of text) {
  // Write single character to buffer
  const bytes = new TextEncoder().encode(char);
  inputBuffer.set(bytes);

  // Insert and get result
  insert(bytes.length);

  // Get the inserted text
  const insertedLength = getInsertedTextLength();
  const insertedPtr = getInsertedTextPointer();
  const insertedText = new TextDecoder().decode(
    new Uint8Array(memory.buffer, insertedPtr, insertedLength)
  );

  // Check if any characters were deleted
  const deletedCount = getDeletedCodepoints();

  console.log({
    inserted: insertedText,
    deleted: deletedCount,
  });
}
// Final result is "か"
```

## Testing

To run the test suite:

```bash
zig build test --summary all
```

## Features

- Romaji to hiragana/full-width character conversion based on Google 日本語入力 mapping
  - Basic hiragana (あ、い、う、え、お、か、き、く...)
    - a -> あ
    - ka -> か
  - Small hiragana (ゃ、ゅ、ょ...)
    - xya -> や
    - li -> ぃ
  - Sokuon (っ)
    - tte -> って
  - Full-width characters
    - k -> ｋ
    - 1 -> １
  - Punctuation
    - . -> 。
    - ? -> ？
    - [ -> 「

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a Pull Request.

## Acknowledgments

- Based on [Google 日本語入力](https://www.google.co.jp/ime/) transliteration mappings
- [mozc](https://github.com/google/mozc) - Google's open source Japanese Input Method Editor, which provided valuable insights for IME implementation
- The following projects were used as a reference for the codebase structure:
  - [chipz - 8-bit emulator in zig](https://github.com/floooh/chipz)
  - [zg - Unicode text processing for zig](https://codeberg.org/atman/zg)

## Further Reading & References

For those interested in the data structures and algorithms used in this project, or looking to implement similar functionality, the following academic papers provide excellent background:

- [Efficient dictionary and language model compression for input method editors](https://aclanthology.org/W11-3503/) - Describes techniques for compressing IME dictionaries while maintaining fast lookup times
- [Space-efficient static trees and graphs](https://doi.org/10.1109/SFCS.1989.63533) - Introduces fundamental succinct data structure techniques that enable near-optimal space usage while supporting fast operations
- [最小コスト法に基づく形態素解析における CPU キャッシュの効率化](https://www.anlp.jp/proceedings/annual_meeting/2023/pdf_dir/C2-4.pdf) - Discusses CPU cache optimization techniques for morphological analysis using minimum-cost methods
- [Vibrato](https://github.com/daac-tools/vibrato) - Viterbi-based accelerated tokenizer
- [Vaporetto: 点予測法に基づく高速な日本語トークナイザ](https://www.anlp.jp/proceedings/annual_meeting/2022/pdf_dir/D2-5.pdf) - Presents a fast tokenization approach using linear classification and point prediction methods and three novel score preprocessing techniques
- [Vaporetto](https://github.com/daac-tools/vaporetto?tab=readme-ov-file) - Implementation of the pointwise prediction tokenizer described in the paper above
