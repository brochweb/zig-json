const std = @import("std");
const heap = std.heap;
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    var file_name = try copy_slice(allocator, args.next() orelse "-");
    std.debug.print("in_path: {s}", .{file_name});
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
