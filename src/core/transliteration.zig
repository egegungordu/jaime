const std = @import("std");

// based on Google IME

// TODO: should probably use hashmaps because staticstringmap does eql checks on equal length strings groups
// TODO: can also build this comptime from a text file using embedFile

// zig fmt: off
pub const transliterables = std.StaticStringMap(void).initComptime(.{
    // vowels
    .{"ａ"}, .{"ｉ"}, .{"ｕ"}, .{"ｅ"}, .{"ｏ"},

    // consonants
    .{"ｋ"}, .{"ｓ"}, .{"ｔ"}, .{"ｎ"}, .{"ｈ"}, .{"ｍ"}, .{"ｙ"}, 
    .{"ｒ"}, .{"ｗ"}, .{"ｇ"}, .{"ｚ"}, .{"ｄ"}, .{"ｂ"}, .{"ｐ"}, 
    .{"ｎ"}, .{"ｃ"}, .{"ｑ"}, .{"ｊ"}, .{"ｖ"}, .{"ｆ"},

    // small kana modifier
    .{"ｘ"}, .{"ｌ"},
});
// zig fmt: on

// zig fmt: off
pub const full_width_map = std.StaticStringMap([]const u8).initComptime(.{
    // latin letters
    .{ "a", "ａ" },
    .{ "b", "ｂ" },
    .{ "c", "ｃ" },
    .{ "d", "ｄ" },
    .{ "e", "ｅ" },
    .{ "f", "ｆ" },
    .{ "g", "ｇ" },
    .{ "h", "ｈ" },
    .{ "i", "ｉ" },
    .{ "j", "ｊ" },
    .{ "k", "ｋ" },
    .{ "l", "ｌ" },
    .{ "m", "ｍ" },
    .{ "n", "ｎ" },
    .{ "o", "ｏ" },
    .{ "p", "ｐ" },
    .{ "q", "ｑ" },
    .{ "r", "ｒ" },
    .{ "s", "ｓ" },
    .{ "t", "ｔ" },
    .{ "u", "ｕ" },
    .{ "v", "ｖ" },
    .{ "w", "ｗ" },
    .{ "x", "ｘ" },
    .{ "y", "ｙ" },
    .{ "z", "ｚ" },

    // numbers
    .{ "0", "０" },
    .{ "1", "１" },
    .{ "2", "２" },
    .{ "3", "３" },
    .{ "4", "４" },
    .{ "5", "５" },
    .{ "6", "６" },
    .{ "7", "７" },
    .{ "8", "８" },
    .{ "9", "９" },

    // punctuation & symbols
    .{ "`", "｀" },
    .{ "~", "～" },
    .{ "!", "！" },
    .{ "@", "＠" },
    .{ "#", "＃" },
    .{ "$", "＄" },
    .{ "%", "％" },
    .{ "^", "＾" },
    .{ "&", "＆" },
    .{ "*", "＊" },
    .{ "(", "（" },
    .{ ")", "）" },
    .{ "-", "ー" },
    .{ "_", "＿" },
    .{ "=", "＝" },
    .{ "+", "＋" },
    .{ "[", "「" },
    .{ "{", "｛" },
    .{ "]", "」" },
    .{ "}", "｝" }, 
    .{ "\\", "￥" }, // TODO: doing double \\ will turn the first '￥' into '\'
    .{ "|", "｜" },
    .{ ";", "；" },
    .{ ":", "：" },
    .{ "'", "’" },
    .{ "\"", "”" },
    .{ ",", "、" },
    .{ "<", "＜" },
    .{ ".", "。" },
    .{ ">", "＞" },
    .{ "/", "・" },
    .{ "?", "？" },
});
// zig fmt: on

// zig fmt: off
pub const transliteration_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "ａ", "あ" },
    .{ "ｉ", "い" },
    .{ "ｕ", "う" },
    .{ "ｅ", "え" },
    .{ "ｏ", "お" },

    .{ "ｋａ", "か" },
    .{ "ｋｉ", "き" },
    .{ "ｋｕ", "く" },
    .{ "ｋｅ", "け" },
    .{ "ｋｏ", "こ" },

    .{ "ｓａ", "さ" },
    .{ "ｓｉ", "し" },
    .{ "ｓｕ", "す" },
    .{ "ｓｅ", "せ" },
    .{ "ｓｏ", "そ" },

    .{ "ｔａ", "た" },
    .{ "ｔｉ", "ち" },
    .{ "ｔｕ", "つ" },
    .{ "ｔｅ", "て" },
    .{ "ｔｏ", "と" },

    .{ "ｎａ", "な" },
    .{ "ｎｉ", "に" },
    .{ "ｎｕ", "ぬ" },
    .{ "ｎｅ", "ね" },
    .{ "ｎｏ", "の" },

    .{ "ｈａ", "は" },
    .{ "ｈｉ", "ひ" },
    .{ "ｈｕ", "ふ" },
    .{ "ｈｅ", "へ" },
    .{ "ｈｏ", "ほ" },

    .{ "ｍａ", "ま" },
    .{ "ｍｉ", "み" },
    .{ "ｍｕ", "む" },
    .{ "ｍｅ", "め" },
    .{ "ｍｏ", "も" },

    .{ "ｙａ", "や" },
    .{ "ｙｕ", "ゆ" },
    .{ "ｙｏ", "よ" },

    .{ "ｒａ", "ら" },
    .{ "ｒｉ", "り" },
    .{ "ｒｕ", "る" },
    .{ "ｒｅ", "れ" },
    .{ "ｒｏ", "ろ" },

    .{ "ｗａ", "わ" },
    .{ "ｗｏ", "を" },
    .{ "ｎｎ", "ん" },

    .{ "ｇａ", "が" },
    .{ "ｇｉ", "ぎ" },
    .{ "ｇｕ", "ぐ" },
    .{ "ｇｅ", "げ" },
    .{ "ｇｏ", "ご" },

    .{ "ｚａ", "ざ" },
    .{ "ｚｉ", "じ" },
    .{ "ｚｕ", "ず" },
    .{ "ｚｅ", "ぜ" },
    .{ "ｚｏ", "ぞ" },

    .{ "ｄａ", "だ" },
    .{ "ｄｉ", "ぢ" },
    .{ "ｄｕ", "づ" },
    .{ "ｄｅ", "で" },
    .{ "ｄｏ", "ど" },

    .{ "ｂａ", "ば" },
    .{ "ｂｉ", "び" },
    .{ "ｂｕ", "ぶ" },
    .{ "ｂｅ", "べ" },
    .{ "ｂｏ", "ぼ" },

    .{ "ｐａ", "ぱ" },
    .{ "ｐｉ", "ぴ" },
    .{ "ｐｕ", "ぷ" },
    .{ "ｐｅ", "ぺ" },
    .{ "ｐｏ", "ぽ" },

    .{ "ｋｙａ", "きゃ" },
    .{ "ｋｙｉ", "きぃ"},
    .{ "ｋｙｕ", "きゅ" },
    .{ "ｋｙｅ", "きぇ" },
    .{ "ｋｙｏ", "きょ" },

    .{ "ｇｙａ", "ぎゃ" },
    .{ "ｇｙｉ", "ぎぃ"},
    .{ "ｇｙｕ", "ぎゅ" },
    .{ "ｇｙｅ", "ぎぇ" },
    .{ "ｇｙｏ", "ぎょ" },

    .{ "ｓｙａ", "しゃ" },
    .{ "ｓｙｉ", "しぃ"},
    .{ "ｓｙｕ", "しゅ" },
    .{ "ｓｙｅ", "しぇ" },
    .{ "ｓｙｏ", "しょ" },

    .{ "ｎｙａ", "にゃ" },
    .{ "ｎｙｉ", "にぃ" },
    .{ "ｎｙｕ", "にゅ" },
    .{ "ｎｙｅ", "にぇ" },
    .{ "ｎｙｏ", "にょ" },

    .{ "ｈｙａ", "ひゃ" },
    .{ "ｈｙｉ", "ひぃ" },
    .{ "ｈｙｕ", "ひゅ" },
    .{ "ｈｙｅ", "ひぇ" },
    .{ "ｈｙｏ", "ひょ" },

    .{ "ｍｙａ", "みゃ" },
    .{ "ｍｙｉ", "みぃ" },
    .{ "ｍｙｕ", "みゅ" },
    .{ "ｍｙｅ", "みぇ" },
    .{ "ｍｙｏ", "みょ" },

    .{ "ｒｙａ", "りゃ" },
    .{ "ｒｙｉ", "りぃ" },
    .{ "ｒｙｕ", "りゅ" },
    .{ "ｒｙｅ", "りぇ" },
    .{ "ｒｙｏ", "りょ" },

    .{ "ｔｙａ", "ちゃ" },
    .{ "ｔｙｉ", "ちぃ" },
    .{ "ｔｙｕ", "ちゅ" },
    .{ "ｔｙｅ", "ちぇ" },
    .{ "ｔｙｏ", "ちょ" },

    .{ "ｃｙａ", "ちゃ" },
    .{ "ｃｙｉ", "ちぃ" },
    .{ "ｃｙｕ", "ちゅ" },
    .{ "ｃｙｅ", "ちぇ" },
    .{ "ｃｙｏ", "ちょ" },
    
    .{ "ｐｙａ", "ぴゃ" },
    .{ "ｐｙｉ", "ぴぃ" },
    .{ "ｐｙｕ", "ぴゅ" },
    .{ "ｐｙｅ", "ぴぇ" },
    .{ "ｐｙｏ", "ぴょ" },
    
    .{ "ｂｙａ", "びゃ" },
    .{ "ｂｙｉ", "びぃ" },
    .{ "ｂｙｕ", "びゅ" },
    .{ "ｂｙｅ", "びぇ" },
    .{ "ｂｙｏ", "びょ" },

    .{ "ｔｓａ", "つぁ" },
    .{ "ｔｓｉ", "つぃ" },
    .{ "ｔｓｕ", "つ" },
    .{ "ｔｓｅ", "つぇ" },
    .{ "ｔｓｏ", "つぉ" },

    .{ "ｔｈａ", "てゃ" },
    .{ "ｔｈｉ", "てぃ" },
    .{ "ｔｈｕ", "てゅ" },
    .{ "ｔｈｅ", "てぇ" },
    .{ "ｔｈｏ", "てょ" },

    .{ "ｃｈａ", "ちゃ" },
    .{ "ｃｈｉ", "ち" },
    .{ "ｃｈｕ", "ちゅ" },
    .{ "ｃｈｅ", "ちぇ" },
    .{ "ｃｈｏ", "ちょ" },

    .{ "ｓｈａ", "しゃ" },
    .{ "ｓｈｉ", "し" },
    .{ "ｓｈｕ", "しゅ" },
    .{ "ｓｈｅ", "しぇ" },
    .{ "ｓｈｏ", "しょ" },

    .{ "ｋｗａ", "くぁ" },
    .{ "ｋｗｉ", "くぃ" },
    .{ "ｋｗｕ", "くぅ" },
    .{ "ｋｗｅ", "くぇ" },
    .{ "ｋｗｏ", "くぉ" },

    .{ "ｇｗａ", "ぐぁ" },
    .{ "ｇｗｉ", "ぐぃ" },
    .{ "ｇｗｕ", "ぐぅ" },
    .{ "ｇｗｅ", "ぐぇ" },
    .{ "ｇｗｏ", "ぐぉ" },

    .{ "ｓｗａ", "すぁ" },
    .{ "ｓｗｉ", "すぃ" },
    .{ "ｓｗｕ", "すぅ" },
    .{ "ｓｗｅ", "すぇ" },
    .{ "ｓｗｏ", "すぉ" },

    .{ "ｚｗａ", "ずぁ" },
    .{ "ｚｗｉ", "ずぃ" },
    .{ "ｚｗｕ", "ずぅ" },
    .{ "ｚｗｅ", "ずぇ" },
    .{ "ｚｗｏ", "ずぉ" },

    .{ "ｔｗａ", "とぁ" },
    .{ "ｔｗｉ", "とぃ" },
    .{ "ｔｗｕ", "とぅ" },
    .{ "ｔｗｅ", "とぇ" },
    .{ "ｔｗｏ", "とぉ" },

    .{ "ｄｗａ", "どぁ" },
    .{ "ｄｗｉ", "どぃ" },
    .{ "ｄｗｕ", "どぅ" },
    .{ "ｄｗｅ", "どぇ" },
    .{ "ｄｗｏ", "どぉ" },

    .{ "ｃａ", "か" },
    .{ "ｃｉ", "し" },
    .{ "ｃｕ", "く" },
    .{ "ｃｅ", "せ" },
    .{ "ｃｏ", "こ" },

    .{ "ｑａ", "くぁ" },
    .{ "ｑｉ", "くぃ" },
    .{ "ｑｕ", "く" },
    .{ "ｑｅ", "くぇ" },
    .{ "ｑｏ", "くぉ" },

    .{ "ｆａ", "ふぁ" },
    .{ "ｆｉ", "ふぃ" },
    .{ "ｆｕ", "ふ" },
    .{ "ｆｅ", "ふぇ" },
    .{ "ｆｏ", "ふぉ" },

    .{ "ｊａ", "じゃ" },
    .{ "ｊｉ", "じ" },
    .{ "ｊｕ", "じゅ" },
    .{ "ｊｅ", "じぇ" },
    .{ "ｊｏ", "じょ" },

    .{ "ｖａ", "ゔぁ" },
    .{ "ｖｉ", "ゔぃ" },
    .{ "ｖｕ", "ゔ" },
    .{ "ｖｅ", "ゔぇ" },
    .{ "ｖｏ", "ゔぉ" },

    .{ "ｗｉ", "うぃ" },
    .{ "ｗｕ", "う" },
    .{ "ｗｅ", "うぇ" },

    .{ "ｙｅ", "いぇ" },

    .{ "ｘｔｓｕ", "っ" },

    .{ "ｘｋｅ", "ヶ" },
    .{ "ｘｋａ", "ヵ" },

    .{ "ｘａ", "ぁ" },
    .{ "ｘｉ", "ぃ" },
    .{ "ｘｕ", "ぅ" },
    .{ "ｘｅ", "ぇ" },
    .{ "ｘｏ", "ぉ" },

    .{ "ｘｙａ", "ゃ" },
    .{ "ｘｙｉ", "ぃ" },
    .{ "ｘｙｕ", "ゅ" },
    .{ "ｘｙｅ", "ぇ" },
    .{ "ｘｙｏ", "ょ" },

    .{ "ｌｔｓｕ", "っ" },

    .{ "ｌｋｅ", "ヶ" },
    .{ "ｌｋａ", "ヵ" },

    .{ "ｌａ", "ぁ" },
    .{ "ｌｉ", "ぃ" },
    .{ "ｌｕ", "ぅ" },
    .{ "ｌｅ", "ぇ" },
    .{ "ｌｏ", "ぉ" },

    .{ "ｌｙａ", "ゃ" },
    .{ "ｌｙｉ", "ぃ" },
    .{ "ｌｙｕ", "ゅ" },
    .{ "ｌｙｅ", "ぇ" },
    .{ "ｌｙｏ", "ょ" },

    .{ "ｋｋ", "っｋ" },
    .{ "ｑｑ", "っｑ" },
    .{ "ｓｓ", "っｓ" },
    .{ "ｔｔ", "っｔ" },
    .{ "ｐｐ", "っｐ" },
    .{ "ｂｂ", "っｂ" },
    .{ "ｄｄ", "っｄ" },
    .{ "ｆｆ", "っｆ" },
    .{ "ｇｇ", "っｇ" },
    .{ "ｈｈ", "っｈ" },
    .{ "ｊｊ", "っｊ" },
    .{ "ｋｋ", "っｋ" },
    .{ "ｌｌ", "っｌ" },
    .{ "ｒｒ", "っｒ" },
    .{ "ｘｘ", "っｘ" },
    .{ "ｚｚ", "っｚ" },
    .{ "ｃｃ", "っｃ" },
    .{ "ｍｍ", "っｍ" },
    .{ "ｙｙ", "っｙ" },

    .{ "ｎｋ", "んｋ" },
    .{ "ｎｑ", "んｑ" },
    .{ "ｎｓ", "んｓ" },
    .{ "ｎｔ", "んｔ" },
    .{ "ｎｐ", "んｐ" },
    .{ "ｎｂ", "んｂ" },
    .{ "ｎｄ", "んｄ" },
    .{ "ｎｆ", "んｆ" },
    .{ "ｎｇ", "んｇ" },
    .{ "ｎｈ", "んｈ" },
    .{ "ｎｊ", "んｊ" },
    .{ "ｎｋ", "んｋ" },
    .{ "ｎｌ", "んｌ" },
    .{ "ｎｒ", "んｒ" },
    .{ "ｎｘ", "んｘ" },
    .{ "ｎｚ", "んｚ" },
    .{ "ｎｃ", "んｃ" },
    .{ "ｎｍ", "んｍ" },
});