const std = @import("std");
const clap = @import("clap");
const SliceIterator = @import("./slice_iterator.zig").SliceIterator;
const readString = @import("./parsers/string.zig").readString;
const readNumber = @import("./parsers/number.zig").readNumber;

const heap = std.heap;
const io = std.io;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const JsonObject = std.StringHashMap(JsonValue);

fn is_ascii(char: ?u8) bool {
    if (char) |c|
        return (c > 31) and c != 127 and c != 255
    else
        return true;
}

pub const JsonValue = union(enum) {
    Object: JsonObject,
    Array: ArrayList(JsonValue),
    String: []u8,
    Number: f64,
    Boolean: bool,
    Null,

    /// Frees all memory used by the JsonValue
    fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .String => |string| allocator.free(string),
            .Array => |array| {
                for (array.items) |value| {
                    value.deinit(allocator);
                }
                array.deinit();
            },
            .Object => |object| {
                var iterator = object.iterator();
                while (iterator.next()) |kv| {
                    kv.value_ptr.*.deinit(allocator);
                    allocator.free(kv.key_ptr.*);
                }
                var object_m = object;
                object_m.unmanaged.deinit(allocator);
            },
            .Boolean, .Null, .Number => {},
        }
    }

    pub fn format(value: @This(), comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .String => |str| {
                try std.fmt.format(writer, "\"", .{});
                var iterator = SliceIterator(u8).from_slice(&str);
                while (iterator.next()) |char| {
                    if (char == '"') {
                        try std.fmt.format(writer, "\\\"", .{});
                    } else if (char == '\\') {
                        try std.fmt.format(writer, "\\\\", .{});
                    } else if (is_ascii(char)) {
                        try std.fmt.format(writer, "{c}", .{char});
                    } else {
                        switch (char) {
                            8 => try std.fmt.format(writer, "\\b", .{}),
                            12 => try std.fmt.format(writer, "\\f", .{}),
                            10 => try std.fmt.format(writer, "\\n", .{}),
                            13 => try std.fmt.format(writer, "\\r", .{}),
                            9 => try std.fmt.format(writer, "\\t", .{}),
                            else => {
                                if (!is_ascii(iterator.peekCopy())) // Orelse printable char
                                    try std.fmt.format(writer, "\\u{x}{x}", .{ char, iterator.next() orelse unreachable })
                                else
                                    try std.fmt.format(writer, "\\u00{x}", .{char});
                            },
                        }
                    }
                }
                try std.fmt.format(writer, "\"", .{});
            },
            .Null => try std.fmt.format(writer, "null", .{}),
            .Boolean => |val| try std.fmt.format(writer, "{}", .{val}),
            .Number => |val| try std.fmt.format(writer, "{d}", .{val}),
            .Array => |arr| {
                try std.fmt.format(writer, "[", .{});
                for (arr.items) |itm, i| {
                    try itm.format(fmt, opts, writer);
                    if (i < arr.items.len - 1) {
                        try std.fmt.format(writer, ",", .{});
                    }
                }
                try std.fmt.format(writer, "]", .{});
            },
            .Object => |obj| {
                try std.fmt.format(writer, "{{\n", .{});
                var iterator = obj.iterator();
                var kv_maybe = iterator.next();
                while (kv_maybe) |kv| {
                    try std.fmt.format(writer, "\"{s}\": {}", .{ kv.key_ptr.*, kv.value_ptr.* });
                    kv_maybe = iterator.next();
                    if (kv_maybe) |_| {
                        try std.fmt.format(writer, ",\n", .{});
                    } else {
                        try std.fmt.format(writer, "\n", .{});
                    }
                }
                try std.fmt.format(writer, "}}", .{});
            },
        }
    }
};
const ParseState = enum { Value, Object, Array };

pub const ParseError = error{ StringInvalidEscape, ExpectedEndOfString, ExpectedEndOfFile, ExpectedString, ExpectedNextValue, ExpectedColon, OutOfMemory, FileTooLong, InvalidNumberLiteral, SystemError };

pub fn main() !void {
    // var gpa = heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    const allocator = std.heap.c_allocator;
    const params = comptime clap.parseParamsComptime(
        \\-h, --help     display this help and exit.
        \\-p, --print    print the JSON file
        \\<FILE>         path to JSON file to read, or `-` for stdin
        \\
    );
    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .FILE = clap.parsers.string }, .{ .diagnostic = &diag }) catch |err| {
        // Report error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.args.help) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const file_name = if (args.positionals.len >= 1) args.positionals[0] else "-";
    const json_body = x: {
        if (mem.eql(u8, file_name, "-"))
            break :x try io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(isize))
        else
            break :x try std.fs.cwd().readFileAlloc(allocator, file_name, std.math.maxInt(isize));
    };
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_alloc = arena.allocator();
    const val = try parse(&json_body, arena_alloc);
    defer arena.deinit();
    if (args.args.print) {
        return std.io.getStdOut().writer().print("{}\n", .{val});
    }
}

pub fn parse(json_buf: *const []const u8, allocator: Allocator) ParseError!JsonValue {
    if (json_buf.len >= 0x20000000) {
        return ParseError.FileTooLong; // 500 MiB is longest file size
    }
    var json = SliceIterator(u8).from_slice(json_buf);
    var state: ParseState = .Value;
    var value: JsonValue = try parseNext(&json, state, allocator);
    if (json.len > 0) {
        return ParseError.ExpectedEndOfFile;
    }
    return value;
}

fn parseNext(json: *SliceIterator(u8), state: ParseState, allocator: Allocator) ParseError!JsonValue {
    ignoreWs(json);
    const ch = json.peekCopy();
    if (ch) |char| {
        switch (state) {
            .Value => {
                if (isString(char)) {
                    return .{ .String = try readString(json, allocator) };
                }
                if (isNumber(char)) {
                    return .{ .Number = try readNumber(json) };
                }
                if (isObject(char)) {
                    json.ignoreNext();
                    return try parseNext(json, .Object, allocator);
                }
                if (isArray(char)) {
                    json.ignoreNext();
                    return try parseNext(json, .Array, allocator);
                }
                if (json.peek_multiple(4)) |next_4| {
                    if (mem.eql(u8, &next_4, "null")) {
                        _ = json.take(4) orelse unreachable;
                        return JsonValue.Null;
                    }
                    if (mem.eql(u8, &next_4, "true")) {
                        _ = json.take(4) orelse unreachable;
                        return .{ .Boolean = true };
                    }
                    if (json.peek_multiple(5)) |next_5| {
                        if (mem.eql(u8, &next_5, "false")) {
                            _ = json.take(5) orelse unreachable;
                            return .{ .Boolean = false };
                        }
                    }
                }
                std.debug.print("Unexpected character {c}\n", .{char});
                std.debug.print("Remaining string: {s}\n", .{json.ptr[0..json.len]});
                return ParseError.ExpectedNextValue;
            },
            .Array => {
                var contents = ArrayList(JsonValue).init(allocator);
                errdefer {
                    for (contents.items) |itm| {
                        itm.deinit(allocator);
                    }
                    contents.deinit();
                }
                if ((json.peekCopy() orelse return ParseError.ExpectedNextValue) == ']') {
                    json.ignoreNext();
                    return .{ .Array = contents };
                }
                while (true) {
                    ignoreWs(json);

                    try contents.append(try parseNext(json, .Value, allocator));
                    ignoreWs(json);

                    switch (json.next() orelse return ParseError.ExpectedNextValue) {
                        ']' => break,
                        ',' => continue,
                        else => return ParseError.ExpectedNextValue,
                    }
                }
                contents.shrinkRetainingCapacity(contents.items.len);
                return .{ .Array = contents };
            },
            .Object => {
                var contents = JsonObject.init(allocator);
                errdefer {
                    var iterator = contents.iterator();
                    while (iterator.next()) |kv| {
                        kv.value_ptr.*.deinit(allocator);
                        allocator.free(kv.key_ptr.*);
                    }
                }
                ignoreWs(json);
                const next = json.peekCopy() orelse return ParseError.ExpectedNextValue;
                if (next == '}') {
                    json.ignoreNext();
                    return .{ .Object = contents };
                }
                while (true) {
                    ignoreWs(json);
                    const key = try readString(json, allocator);
                    ignoreWs(json);
                    if ((json.next() orelse return ParseError.ExpectedColon) != ':') {
                        return ParseError.ExpectedColon;
                    }
                    ignoreWs(json);
                    const value = try parseNext(json, .Value, allocator);
                    try contents.put(key, value);
                    ignoreWs(json);
                    switch (json.next() orelse return ParseError.ExpectedNextValue) {
                        '}' => break,
                        ',' => continue,
                        else => return ParseError.ExpectedNextValue,
                    }
                }
                return .{ .Object = contents };
            },
        }
    } else {
        return .Null;
    }
}

fn ignoreWs(json: *SliceIterator(u8)) void {
    while (isWs(json.peekCopy()))
        json.ignoreNext();
}

fn isWs(char: ?u8) bool {
    if (char) |ch| {
        return ch == 0x0020 or ch == 0x000A or ch == 0x000D or ch == 0x0009;
    } else {
        return false;
    }
}
fn isString(char: u8) bool {
    return char == '"';
}
fn isObject(char: u8) bool {
    return char == '{';
}
fn isArray(char: u8) bool {
    return char == '[';
}
fn isNumber(char: u8) bool {
    return (char >= '0' and char <= '9') or char == '-';
}
fn isTrue(char: [4]u8) bool {
    return mem.eql(u8, char, "true");
}
fn isFalse(char: [4]u8) bool {
    return mem.eql(u8, char, "false");
}
fn isNull(char: [4]u8) bool {
    return mem.eql(u8, char, "null");
}

fn copy_slice(allocator: std.mem.Allocator, slice: []const u8) ![]u8 {
    var out_slice = try allocator.alloc(u8, slice.len);
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        out_slice[i] = slice[i];
    }
    return out_slice;
}

test "json string" {
    var string = "\"test, test,\\n\\u00FF\\u02FF\"";
    var mut_slice = SliceIterator(u8).from_slice(&mem.span(string));
    const string_ret = try readString(&mut_slice, std.testing.allocator);
    defer std.testing.allocator.free(string_ret);
    try std.testing.expectEqualStrings("test, test,\n\xFF\x02\xFF", string_ret);
}

test "json array" {
    const string = ("[5   ,\n\n" ** 400) ++ "[\"algo\", 3.1415926535, 5.2e+50, \"\",null,true,false,[],[],[],[[[[[[[[[[[[[[]]]]]]]]]]]]]]]" ++ ("]" ** 400);
    const ret = try parse(&mem.span(string), std.testing.allocator);
    std.debug.print("{}\n", .{ret});
    defer ret.deinit(std.testing.allocator);
}

test "json atoms" {
    const string = "[null,true,false,null,true,       false]";
    const ret = try parse(&mem.span(string), std.testing.allocator);
    defer ret.deinit(std.testing.allocator);
}

test "json object" {
    const string = "{\n\t\t\"name\":\"Steve\"\n\t}";
    const ret = try parse(&mem.span(string), std.testing.allocator);
    defer ret.deinit(std.testing.allocator);
    switch (ret) {
        .Object => |object| {
            switch (object.get("name") orelse return error.ExpectedName) {
                .String => |str| try std.testing.expectEqualStrings("Steve", str),
                else => return error.ExpectedString,
            }
        },
        else => return error.ExpectedObject,
    }
}

test "invalid json array" {
    // Testing for memory leaks during parsing mostly
    const string = "[1,2,\"string\",\"spring\",[1,  0.5, 3.2e+7, face], bull]";
    if (parse(&mem.span(string), std.testing.allocator)) |ret| {
        ret.deinit(std.testing.allocator);
        return error.ShouldNotCompleteParsing;
    } else |err| {
        try std.testing.expectEqual(ParseError.ExpectedNextValue, err);
    }
}
