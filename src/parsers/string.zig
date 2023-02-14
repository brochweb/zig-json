const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseError = @import("../main.zig").ParseError;
const SliceIterator = @import("../slice_iterator.zig").SliceIterator;

/// Caller owns returned slice
pub fn readString(json: *SliceIterator(u8), allocator: Allocator) ParseError![]u8 {
    var string = std.ArrayList(u8).init(allocator);
    errdefer string.deinit();
    if (json.next() orelse 0 != '"') {
        return ParseError.ExpectedString;
    }
    while (json.peekMany(8)) |chars| {
        // ASCII optimization
        if (chars[0] != '\\' and chars[0] != '"' and chars[1] != '\\' and chars[1] != '"' and chars[2] != '\\' and chars[2] != '"' and chars[3] != '\\' and chars[3] != '"' and chars[4] != '\\' and chars[4] != '"' and chars[5] != '\\' and chars[5] != '"' and chars[6] != '\\' and chars[6] != '"' and chars[7] != '\\' and chars[7] != '"') {
            try string.appendSlice(&chars);
            json.ignoreMany(8);
            // std.debug.print("Ignored these bytes because not special: {s}\n", .{chars});
            continue;
        }
        var i: usize = 0;
        var to_ignore: usize = 0;
        while (i < chars.len) : (i += 1) {
            const char = chars[i];
            switch (char) {
                '\\' => {
                    const next_char = block: {
                        if (i + 1 < chars.len) {
                            i += 1;
                            to_ignore += 2; // Because to_ignore is not auto-incremented like `i` is
                            break :block chars[i];
                        } else {
                            // It means this is the last element, so this is safe:
                            // std.debug.print("Ignored these bytes: {s}\n", .{json.dynTake(to_ignore + 1) orelse unreachable});
                            json.ignoreMany(to_ignore + 1); // One for backslash
                            to_ignore = 0;
                            break :block json.next() orelse return ParseError.StringInvalidEscape;
                        }
                    };
                    // std.debug.print("Escaping {c}\n", .{next_char});
                    try escape(next_char, &to_ignore, &i, &string, json);
                },
                '"' => {
                    json.ignoreMany(to_ignore + 1); // For the last quote
                    to_ignore = 0;
                    return prepareString(&string);
                },
                else => {
                    try string.append(char);
                    to_ignore += 1;
                },
            }
        }
        // std.debug.print("Ignoring {} bytes because out of loop\n", .{to_ignore});
        json.ignoreMany(to_ignore);
    }
    // If this code is running here, it means the string hasn’t ended yet and there are less than 8 bytes left
    while (json.next()) |char| {
        switch (char) {
            '\\' => {
                const next_char = json.next() orelse return ParseError.StringInvalidEscape;
                try escape(next_char, null, null, &string, json);
            },
            '"' => return prepareString(&string),
            else => try string.append(char),
        }
    }
    return ParseError.ExpectedEndOfString;
}

inline fn escape(char: u8, to_ignore: ?*usize, i: ?*usize, string: *std.ArrayList(u8), json: *SliceIterator(u8)) ParseError!void {
    switch (char) {
        '"', '\\' => try string.append(char),
        'b' => try string.append(8), // Backspace character
        'f' => try string.append(12), // Formfeed character
        'n' => try string.append(10), // Newline character
        'r' => try string.append(13), // Carriage return character
        't' => try string.append(9), // Tab character
        'u' => {
            if (to_ignore) |ignore| {
                // std.debug.print("Ignoring {d} bytes because escaping char\n", .{ignore.*});
                json.ignoreMany(ignore.*); // These bytes have already been put into the string
                // std.debug.print("Ignoring {s} because escaping char\n", .{json.dynTake(ignore.*) orelse unreachable});
                ignore.* = 0;
            }
            const first_bytes = json.take(4) orelse return ParseError.StringInvalidEscape;
            if (i) |idx| {
                idx.* += 4; // Because it just took 4 bytes
            }
            const next_six = json.peekMany(6) orelse [_]u8{0} ** 6;
            var eight_bytes: [2][4]u8 = undefined;
            eight_bytes[0] = first_bytes;
            var escape_groups: []const [4]u8 = eight_bytes[0..1];
            if (std.mem.eql(u8, next_six[0..2], "\\u")) {
                json.ignoreMany(6);
                if (i) |idx| {
                    idx.* += 6;
                }
                eight_bytes[1] = next_six[2..].*;
                escape_groups = eight_bytes[0..2];
            }
            var utf16: [2]u16 = undefined;
            for (escape_groups) |bytes, idx| {
                utf16[idx] = std.fmt.parseUnsigned(u16, &bytes, 16) catch return ParseError.StringInvalidEscape;
            }
            // std.debug.print("Eight bytes: {} {}\nUTF-16: {x}\n", .{ std.fmt.fmtSliceHexUpper(&eight_bytes[0]), std.fmt.fmtSliceHexUpper(&eight_bytes[1]), utf16 });
            var utf8: [8]u8 = undefined;
            const utf8_len = std.unicode.utf16leToUtf8(&utf8, utf16[0..escape_groups.len]) catch return ParseError.StringInvalidEscape;
            // std.debug.print("UTF-8 len: {}\n", .{utf8_len});
            // std.debug.print("UTF-8: {}", .{std.fmt.fmtSliceHexUpper(utf8[0..utf8_len])});
            try string.appendSlice(utf8[0..utf8_len]);
        },
        else => return ParseError.StringInvalidEscape,
    }
}

inline fn prepareString(string: *std.ArrayList(u8)) []u8 {
    string.shrinkAndFree(string.items.len);
    const slice = string.toOwnedSlice();
    string.deinit();
    return slice;
}
