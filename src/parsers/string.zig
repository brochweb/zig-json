const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseError = @import("../main.zig").ParseError;
const SliceIterator = @import("../slice_iterator.zig").SliceIterator;

/// Caller owns returned slice
pub fn readString(json: *SliceIterator(u8), allocator: Allocator) ParseError![]u8 {
    var string = try std.ArrayList(u8).initCapacity(allocator, 32);
    if (json.next() orelse 0 != '"') {
        return ParseError.ExpectedString;
    }
    while (json.next()) |char| {
        switch (char) {
            '\\' => {
                const next_char = json.next() orelse return ParseError.StringInvalidEscape;
                switch (next_char) {
                    '"', '\\' => try string.append(next_char),
                    'b' => try string.append(8), // Backspace character
                    'f' => try string.append(12), // Formfeed character
                    'n' => try string.append(10), // Newline character
                    'r' => try string.append(13), // Carriage return character
                    't' => try string.append(9), // Tab character
                    'u' => {
                        const code_bytes = json.take(4) orelse return ParseError.StringInvalidEscape;
                        const code = std.fmt.parseUnsigned(u16, code_bytes, 16) catch return ParseError.StringInvalidEscape;
                        if (code <= 0x00FF) {
                            try string.append(@truncate(u8, code));
                        } else {
                            try string.append(@truncate(u8, code >> 8));
                            try string.append(@truncate(u8, code));
                        }
                    },
                    else => return ParseError.StringInvalidEscape,
                }
            },
            '"' => {
                return string.toOwnedSlice();
            },
            else => try string.append(char),
        }
    }
    return ParseError.ExpectedEndOfString;
}
