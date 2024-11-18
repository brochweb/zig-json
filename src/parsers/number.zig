const std = @import("std");
const SliceIterator = @import("../slice_iterator.zig").SliceIterator;
const ParseError = @import("../main.zig").ParseError;

const powers_of_ten_f64 = [32]f64{
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,
    1e8,  1e9,  1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
    1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22, 1e23,
    1e24, 1e25, 1e26, 1e27, 1e28, 1e29, 1e30, 1e31,
};

const powers_of_ten_neg_f64 = [32]f64{
    1e-1,  1e-2,  1e-3,  1e-4,  1e-5,  1e-6,  1e-7,
    1e-8,  1e-9,  1e-10, 1e-11, 1e-12, 1e-13, 1e-14,
    1e-15, 1e-16, 1e-17, 1e-18, 1e-19, 1e-20, 1e-21,
    1e-22, 1e-23, 1e-24, 1e-25, 1e-26, 1e-27, 1e-28,
    1e-29, 1e-30, 1e-31, 1e-32,
};

const powers_of_ten_i16 = [5]i16{ 1, 10, 100, 1000, 10000 };

pub fn readNumber(json: *SliceIterator(u8)) ParseError!f64 {
    const neg = json.peekCopy() orelse 0 == '-';
    if (neg) {
        json.ignoreNext();
    }
    const num = try parseUnsignedNumber(json);
    if (neg) {
        return num * -1;
    } else {
        return num;
    }
}

fn parseUnsignedNumber(json: *SliceIterator(u8)) ParseError!f64 {
    var num_buf: [320]u8 = undefined;
    var num_length: usize = 0;
    while (json.peekCopy()) |char| {
        switch (char) {
            '0'...'9', '.', 'e', 'E', '-', '+' => {
                if (num_length >= num_buf.len) return ParseError.InvalidNumberLiteral;
                num_buf[num_length] = json.next() orelse unreachable;
                num_length += 1;
            },
            else => break,
        }
    }
    const number = std.fmt.parseFloat(f64, num_buf[0..num_length]) catch return ParseError.InvalidNumberLiteral;

    return number;
}

fn parseUnsignedNumberFast(json: *SliceIterator(u8)) ParseError!f64 {
    var num: f64 = 0;
    var frac: f64 = 0;
    var exp: i16 = 1;
    var i: usize = 0;
    while (json.peekCopy()) |char| : (i += 1) {
        switch (char) {
            '0'...'9' => {
                json.ignoreNext();
                const val = char - '0';
                num += @as(f64, @floatFromInt(val)) * powers_of_ten_f64[i & 31];
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
    num += frac;
    if (exp != 1) {
        num = std.math.pow(f64, num, @as(f64, @floatFromInt(exp)));
    }
    return num;
}
inline fn parseFrac(json: *SliceIterator(u8)) ParseError!f64 {
    var out: f64 = 0;
    var i: usize = 0;
    while (json.peekCopy()) |char| : (i += 1) {
        switch (char) {
            '0'...'9' => {
                json.ignoreNext();
                const val = char - '0';
                out += @as(f64, @floatFromInt(val)) * powers_of_ten_neg_f64[i & 31];
            },
            else => break,
        }
    }
    return out;
}
inline fn parseExp(json: *SliceIterator(u8)) ParseError!i16 {
    var exp: i16 = 0;
    const next = json.peekCopy() orelse 0;
    if (next == '-' or next == '+') {
        json.ignoreNext();
    }
    const neg = next == '-';
    var i: usize = 0;
    while (json.peekCopy()) |char| : (i += 1) {
        if (i > 4)
            return ParseError.InvalidNumberLiteral;
        switch (char) {
            '0'...'9' => {
                json.ignoreNext();
                const val = char - '0';
                exp = std.math.add(i16, exp, val * powers_of_ten_i16[i]) catch return ParseError.InvalidNumberLiteral;
            },
            else => break,
        }
    }
    if (neg) {
        return -1 * exp;
    } else {
        return exp;
    }
}
