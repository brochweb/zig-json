const std = @import("std");
const clap = @import("clap");
const heap = std.heap;
const io = std.io;
const ArrayList = std.ArrayList;

pub fn main() !void {
    // var gpa = heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help     display this help and exit.") catch unreachable,
        clap.parseParam("<FILE>         path to JSON file to read, or `-` for stdin") catch unreachable,
    };
    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{
        .FILE = clap.parsers.string,
    }, .{ .diagnostic = &diag }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    const file_name = if (args.positionals.len >= 1) args.positionals[0] else "-";
    std.debug.print("{s}\n", .{file_name});
}

fn copy_slice(allocator: std.mem.Allocator, slice: []const u8) ![]u8 {
    var out_slice = try allocator.alloc(u8, slice.len);
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        out_slice[i] = slice[i];
    }
    return out_slice;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
