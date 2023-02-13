const std = @import("std");
const SliceIterator = @import("../slice_iterator.zig").SliceIterator;
const ParseError = @import("../main.zig").ParseError;

pub fn readNumber(json: *SliceIterator(u8)) ParseError!f64 {
    if (json.peekCopy() orelse 0 == '-') {
        json.ignoreNext();
    }
    return try parseUnsignedNumber(json);
}

fn parseUnsignedNumber(json: *SliceIterator(u8)) ParseError!f64 {
    var num_buf: [308]u8 = undefined;
    var num_length: usize = 0;
    var frac: f64 = 0;
    var exp: i16 = 1;
    while (json.peekCopy()) |char| {
        switch (char) {
            '0'...'9' => {
                if (num_length >= num_buf.len) return ParseError.InvalidNumberLiteral;
                num_buf[num_length] = json.next() orelse unreachable;
                num_length += 1;
            },
            '.' => {
                json.ignoreNext();
                frac = try parseFrac(json);
            },
            'e', 'E' => {
                json.ignoreNext();
                exp = try parseExp(json);
            },
            else => break,
        }
    }
    var number = std.fmt.parseFloat(f64, num_buf[0..num_length]) catch return ParseError.InvalidNumberLiteral;
    number += frac;
    if (exp != 1) {
        number = std.math.pow(f64, number, @intToFloat(f64, exp));
    }
    return number;
}
inline fn parseFrac(json: *SliceIterator(u8)) ParseError!f64 {
    var frac_buf: [324]u8 = undefined;
    var frac_length: usize = 2;
    frac_buf[0] = '0';
    frac_buf[1] = '.';
    while (json.peekCopy()) |char| {
        switch (char) {
            '0'...'9' => {
                if (frac_length >= frac_buf.len) return ParseError.InvalidNumberLiteral;
                frac_buf[frac_length] = json.next() orelse unreachable;
                frac_length += 1;
            },
            else => break,
        }
    }
    return std.fmt.parseFloat(f64, frac_buf[0..frac_length]) catch return ParseError.InvalidNumberLiteral;
}
inline fn parseExp(json: *SliceIterator(u8)) ParseError!i16 {
    var exp_buf: [4]u8 = undefined;
    var exp_len: usize = 0;
    var next = json.peekCopy() orelse 0;
    if (next == '-' or next == '+') {
        exp_buf[0] = json.next() orelse unreachable;
        exp_len += 1;
    }
    while (json.peekCopy()) |char| {
        switch (char) {
            '0'...'9' => {
                if (exp_len >= exp_buf.len) return ParseError.InvalidNumberLiteral;
                exp_buf[exp_len] = json.next() orelse unreachable;
                exp_len += 1;
            },
            else => break,
        }
    }
    return std.fmt.parseInt(i16, exp_buf[0..exp_len], 10) catch return ParseError.InvalidNumberLiteral;
}
