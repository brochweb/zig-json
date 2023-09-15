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

const JsonObject = std.StringArrayHashMap(JsonValue);

fn isUtf8(char: ?u8) bool {
    if (char) |c|
        return std.unicode.utf8ValidateSlice(&[_]u8{c})
    else
        return true;
}

pub const RootJsonValue = struct {
    value: JsonValue,
    allocator: std.heap.ArenaAllocator,
    pub fn deinit(self: @This()) void {
        self.allocator.deinit();
    }
};

pub const JsonValue = union(enum) {
    Object: *JsonObject,
    // Array: ArrayList(JsonValue),
    Array: *[]JsonValue,
    String: *[]u8,
    Number: f64,
    Boolean: bool,
    Null,

    /// Frees all memory used by the JsonValue
    fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .String => |string| {
                allocator.free(string.*);
                allocator.destroy(string);
            },
            .Array => |array| {
                for (array.*) |value| {
                    // for (array.items) |value| {
                    value.deinit(allocator);
                }
                allocator.free(array.*);
                allocator.destroy(array);
                // array.deinit();
            },
            .Object => |object| {
                var iterator = object.iterator();
                while (iterator.next()) |kv| {
                    kv.value_ptr.*.deinit(allocator);
                    allocator.free(kv.key_ptr.*);
                }
                var object_m = object.*;
                object_m.unmanaged.deinit(allocator);
                allocator.destroy(object);
            },
            else => {},
        }
    }

    fn deepClone(self: *const @This(), new_alloc: Allocator) !JsonValue {
        switch (self.*) {
            .String => |*string| {
                var buf = try new_alloc.alloc(u8, string.len);
                mem.copy(u8, buf, string.*);
                return .{ .String = buf };
            },
            .Array => |array| {
                var buf = try new_alloc.alloc(JsonValue, array.len);
                mem.copy(JsonValue, buf, array);
                for (buf) |*value| {
                    value.* = try value.deepClone(new_alloc);
                }
                return .{ .Array = buf };
            },
            .Object => |object| {
                var new_obj = try object.*.cloneWithAllocator(new_alloc);
                var iterator = new_obj.iterator();
                while (iterator.next()) |*kv| {
                    kv.value_ptr.* = try kv.value_ptr.*.deepClone(new_alloc);
                    var key_buf = try new_alloc.alloc(u8, kv.key_ptr.len);
                    mem.copy(u8, key_buf, kv.key_ptr.*);
                    kv.key_ptr.* = key_buf;
                }
                return .{ .Object = &new_obj };
            },
            .Boolean => |val| return .{ .Boolean = val },
            .Number => |val| return .{ .Number = val },
            .Null => return .Null,
        }
    }

    pub fn format(value: @This(), comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .String => |str| {
                try std.fmt.format(writer, "\"", .{});
                var iterator = SliceIterator(u8).from_slice(str.*);
                while (iterator.next()) |char| {
                    if (char == '"') {
                        try std.fmt.format(writer, "\\\"", .{});
                    } else if (char == '\\') {
                        try std.fmt.format(writer, "\\\\", .{});
                    } else if (isUtf8(char)) {
                        try std.fmt.format(writer, "{c}", .{char});
                    } else {
                        switch (char) {
                            0x08 => try std.fmt.format(writer, "\\b", .{}),
                            0x0C => try std.fmt.format(writer, "\\f", .{}),
                            0x0A => try std.fmt.format(writer, "\\n", .{}),
                            0x0D => try std.fmt.format(writer, "\\r", .{}),
                            0x09 => try std.fmt.format(writer, "\\t", .{}),
                            else => {
                                outer: {
                                    if (char <= 0x1F) {
                                        try std.fmt.format(writer, "\\u00{X:0>2}", .{char});
                                        break :outer;
                                    }
                                    const is_byte_sequence: ?u3 = std.unicode.utf8ByteSequenceLength(char) catch null;
                                    inner: {
                                        if (is_byte_sequence) |len| {
                                            if (iterator.peekManyRef(len - 1)) |other_bytes| {
                                                var utf8_buf: [4]u8 = undefined;
                                                utf8_buf[0] = char;
                                                for (other_bytes, 0..) |v, i| {
                                                    utf8_buf[i + 1] = v;
                                                }
                                                if (std.unicode.utf8ValidateSlice(utf8_buf[0..len])) {
                                                    iterator.ignoreMany(len - 1);
                                                    try std.fmt.format(writer, "{s}", .{utf8_buf[0..len]});
                                                    break :outer;
                                                }
                                            }
                                            var utf8_buf: [4]u8 = undefined;
                                            utf8_buf[0] = char;
                                            var i: usize = 1;
                                            while (i < len) : (i += 1) {
                                                utf8_buf[i] = iterator.next() orelse break :inner;
                                            }
                                            var utf16_buf: [4]u16 = undefined;
                                            var utf16_len = std.unicode.utf8ToUtf16Le(&utf16_buf, &utf8_buf) catch break :inner;
                                            var j: usize = 0;
                                            while (j < utf16_len) : (j += 1) {
                                                try std.fmt.format(writer, "\\u{x:0>4}", .{utf16_buf[j]});
                                            }
                                            break :outer;
                                        }
                                    }

                                    try std.fmt.format(writer, "{c}", .{char});
                                }
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
                for (arr.*, 0..) |itm, i| {
                    // for (arr.items) |itm, i| {
                    try itm.format(fmt, opts, writer);
                    if (i < arr.len - 1) {
                        // if (i < arr.items.len - 1) {
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

pub const ParseError = error{ StringInvalidEscape, InvalidString, ExpectedEndOfString, ExpectedEndOfFile, ExpectedString, ExpectedNextValue, ExpectedColon, OutOfMemory, FileTooLong, InvalidNumberLiteral, SystemError };

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // const allocator = std.heap.c_allocator;
    // const allocator = std.heap.page_allocator;
    const params = comptime clap.parseParamsComptime(
        \\-h, --help     display this help and exit.
        \\-p, --print    print the JSON file
        \\-s, --stdlib   use the stdlib JSON parser instead of zig-json implementation
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

    if (args.args.help == 1) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const file_name = if (args.positionals.len >= 1) args.positionals[0] else "-";
    const json_body = x: {
        if (mem.eql(u8, file_name, "-"))
            break :x try io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(isize))
        else
            break :x try std.fs.cwd().readFileAlloc(allocator, file_name, std.math.maxInt(isize));
    };
    // const val = try parse(&json_body, allocator);
    if (args.args.stdlib == 1) {
        var val = x: {
            break :x try std.json.parseFromSlice(std.json.Value,allocator,json_body,.{});
        };
        defer val.deinit();
        if (args.args.print == 1) {
            try std.io.getStdOut().writer().print("{}\n", .{val});
        }
    } else {
        const val = try parse(json_body, allocator);
        defer val.deinit();
        if (args.args.print == 1) {
            try std.io.getStdOut().writer().print("{}\n", .{val.value});
        }
    }
}

pub fn parse(json_buf: []const u8, allocator: Allocator) ParseError!RootJsonValue {
    if (json_buf.len >= 0x20000000) {
        return ParseError.FileTooLong; // 500 MiB is longest file size
    }
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    const arena_alloc = arena.allocator();
    var json = SliceIterator(u8).from_slice(json_buf);
    var state: ParseState = .Value;

    ignoreWs(&json);
    const value: JsonValue = parseNext(&json, state, arena_alloc) catch |err| {
        std.debug.print("{}\n. Remaining json: \"{s}\"\n", .{ err, json.ptr[0..json.len] });
        return err;
    };
    ignoreWs(&json);
    if (json.len > 0) {
        return ParseError.ExpectedEndOfFile;
    }
    return RootJsonValue{ .value = value, .allocator = arena };
}

fn parseNext(json: *SliceIterator(u8), state: ParseState, allocator: Allocator) ParseError!JsonValue {
    ignoreWs(json);
    const ch = json.peekCopy();
    if (ch) |char| {
        switch (state) {
            .Value => {
                if (isString(char)) {
                    var string = try allocator.create([]u8);
                    errdefer allocator.destroy(string);
                    string.* = try readString(json, allocator);
                    return .{ .String = string };
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
                if (json.peekMany(4)) |next_4| {
                    if (mem.eql(u8, &next_4, "null")) {
                        _ = json.take(4) orelse unreachable;
                        return JsonValue.Null;
                    }
                    if (mem.eql(u8, &next_4, "true")) {
                        _ = json.take(4) orelse unreachable;
                        return .{ .Boolean = true };
                    }
                    if (json.peekMany(5)) |next_5| {
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
                    var array = try allocator.create([]JsonValue);
                    array.* = try contents.toOwnedSlice();
                    return .{ .Array = array };
                    // return .{ .Array = contents };
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
                var array = try allocator.create([]JsonValue);
                array.* = try contents.toOwnedSlice();
                return .{ .Array = array };
                // return .{ .Array = contents };
            },
            .Object => {
                var contents = try allocator.create(JsonObject);
                contents.* = JsonObject.init(allocator);
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
    var string = "\"test, test,\\n🎸\\uD83E\\uDD95\\u3ED8\\u0003\\f\"";
    var mut_slice = SliceIterator(u8).from_slice(string);
    const string_ret = try readString(&mut_slice, std.testing.allocator);
    defer std.testing.allocator.free(string_ret);
    try std.testing.expectEqualStrings("test, test,\n🎸🦕㻘\x03\x0C", string_ret);
}

test "sizes" {
    std.debug.print("JsonValue: {}\nRootJsonValue: {}\n[]JsonValue: {}\nJsonObject: {}\nArrayList(JsonValue): {}\n*JsonObject: {}\n[]u8: {}\n", .{ @sizeOf(JsonValue), @sizeOf(RootJsonValue), @sizeOf([]JsonValue), @sizeOf(JsonObject), @sizeOf(ArrayList(JsonValue)), @sizeOf(*JsonObject), @sizeOf([]u8) });
}

test "json array" {
    const string = ("[5   ,\n\n" ** 400) ++ "[\"algo\", 3.1415926535, 5.2e+50, \"\",null,true,false,[],[],[],[[[[[[[[[[[[[[]]]]]]]]]]]]]]]" ++ ("]" ** 400);
    const ret = try parse(string, std.testing.allocator);
    std.debug.print("{}\n", .{ret});
    defer ret.deinit();
}

test "json atoms" {
    const string = "[null,true,false,null,true,       false]";
    const ret = try parse(string, std.testing.allocator);
    defer ret.deinit();
}

test "json object" {
    const string = "{\n\t\t\"name\":\"Steve\"\n\t}";
    const ret = try parse(string, std.testing.allocator);
    defer ret.deinit();
    switch (ret.value) {
        .Object => |object| {
            switch (object.get("name") orelse return error.ExpectedName) {
                .String => |str| try std.testing.expectEqualStrings("Steve", str.*),
                else => return error.ExpectedString,
            }
        },
        else => return error.ExpectedObject,
    }
}

test "invalid json array" {
    // Testing for memory leaks during parsing mostly
    const string = "[1,2,\"string\",\"spring\",[1,  0.5, 3.2e+7, face], bull]";
    if (parse(string, std.testing.allocator)) |ret| {
        ret.deinit();
        return error.ShouldNotCompleteParsing;
    } else |err| {
        try std.testing.expectEqual(ParseError.ExpectedNextValue, err);
    }
}
