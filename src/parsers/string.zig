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
    while (json.len > 0) {
        const slice = json.takeWhileNeSimd(2, [2]@Vector(16, u8){ @splat(@as(u8, '"')), @splat(@as(u8, '\\')) });
        try string.appendSlice(slice);

        var i: u8 = 0;
        while (i < 16) : (i += 1) {
            const char = json.next() orelse break;
            switch (char) {
                '\\' => {
                    const next_char = json.next() orelse return ParseError.StringInvalidEscape;
                    try escape(next_char, null, null, &string, json);
                },
                '"' => return try prepareString(&string),
                else => try string.append(char),
            }
        }
    }
    return ParseError.ExpectedEndOfString;
}

inline fn escape(char: u8, to_ignore: ?*usize, i: ?*usize, string: *std.ArrayList(u8), json: *SliceIterator(u8)) ParseError!void {
    switch (char) {
        '"', '\\', '/' => try string.append(char),
        'b' => try string.append(0x08), // Backspace character
        'f' => try string.append(0x0C), // Formfeed character
        'n' => try string.append(0x0A), // Newline character
        'r' => try string.append(0x0D), // Carriage return character
        't' => try string.append(0x09), // Tab character
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
            for (escape_groups, 0..) |bytes, idx| {
                utf16[idx] = std.fmt.parseUnsigned(u16, &bytes, 16) catch return ParseError.StringInvalidEscape;
            }
            // std.debug.print("Eight bytes: {} {}\nUTF-16: {x}\n", .{ std.fmt.fmtSliceHexUpper(&eight_bytes[0]), std.fmt.fmtSliceHexUpper(&eight_bytes[1]), utf16 });
            var utf8: [8]u8 = undefined;
            const utf8_len = std.unicode.utf16leToUtf8(&utf8, utf16[0..escape_groups.len]) catch {
                for (utf16) |val| {
                    if (val <= 0x1F) {
                        try string.append(@as(u8, @truncate(val)));
                    } else {
                        return ParseError.InvalidString;
                    }
                }
                return;
            };
            // std.debug.print("UTF-8 len: {}\n", .{utf8_len});
            // std.debug.print("UTF-8: {}", .{std.fmt.fmtSliceHexUpper(utf8[0..utf8_len])});
            try string.appendSlice(utf8[0..utf8_len]);
        },
        else => return ParseError.StringInvalidEscape,
    }
}

inline fn prepareString(string: *std.ArrayList(u8)) ![]u8 {
    string.shrinkAndFree(string.items.len);
    const slice = try string.toOwnedSlice();
    string.deinit();
    return slice;
}
