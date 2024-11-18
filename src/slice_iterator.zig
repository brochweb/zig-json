const std = @import("std");
const mem = std.mem;

/// Works over memory owned by another function
pub fn SliceIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        ptr: [*]const T,
        len: usize,
        /// Source of the slice MUST last for at least as long as the SliceIterator
        pub fn from_slice(slice: []const T) Self {
            return Self{ .ptr = slice.ptr, .len = slice.len };
        }
        pub fn next(self: *Self) ?T {
            if (self.len >= 1) {
                const first = self.ptr[0];
                self.ptr += @sizeOf(T);
                self.len -= 1;
                return first;
            } else {
                return null;
            }
        }
        /// Does nothing if the iterator is empty
        pub fn ignoreNext(self: *Self) void {
            if (self.len >= 1) {
                self.ptr += @sizeOf(T);
                self.len -= 1;
            }
        }
        /// Returns a reference to the next value without consuming it.
        /// Once the iterator is consumed, the reference is no good
        pub fn peek(self: *const Self) ?*const T {
            if (self.len >= 1) {
                const first = self.ptr[0];
                return &first;
            } else {
                return null;
            }
        }
        /// Returns a copy of the next value, without consuming the iterator
        pub fn peekCopy(self: *const Self) ?T {
            if (self.len >= 1) {
                const first = self.ptr[0];
                return first;
            } else {
                return null;
            }
        }
        /// Fails completely if len is less than items, leaves items in slice
        pub fn take(self: *Self, comptime number: usize) ?[number]T {
            if (self.len >= number) {
                const items = self.ptr[0..number];
                self.ptr += @sizeOf(T) * number;
                self.len -= number;
                return items.*;
            } else {
                return null;
            }
        }
        /// Fails completely if len is less than items, leaves items in slice
        pub fn dynTake(self: *Self, number: usize) ?[]const T {
            if (self.len >= number) {
                const items = self.ptr[0..number];
                self.ptr += @sizeOf(T) * number;
                self.len -= number;
                return items;
            } else {
                return null;
            }
        }
        /// Fails completely if len is less than items
        /// Returns owned array, no worries about pointers
        pub fn peekMany(self: *const Self, comptime n: usize) ?[n]T {
            if (self.len >= n) {
                var out: [n]T = undefined;
                mem.copyForwards(u8, out[0..], self.ptr[0..n]);
                return out;
            } else {
                return null;
            }
        }

        /// Fails completely if len is less than items
        pub fn peekManyRef(self: *const Self, n: usize) ?[]const T {
            if (self.len >= n) {
                return self.ptr[0..n];
            } else {
                return null;
            }
        }

        /// Does nothing if slice runs out
        pub fn ignoreMany(self: *Self, n: usize) void {
            if (n == 0) return;
            if (self.len >= n) {
                self.ptr += n;
                self.len -= n;
            } else {
                self.ptr += self.len;
                self.len = 0;
            }
        }

        pub fn takeWhileNeSimd(self: *Self, comptime len: comptime_int, comptime conditions: [len]@Vector(16, u8)) []const u8 {
            var op_len: usize = 0;
            const op_ptr = self.ptr;
            outer: while (self.len >= 16) {
                const vec: @Vector(16, u8) = self.ptr[0..16].*;
                inline for (conditions) |condition| {
                    if (@reduce(.Or, vec == condition)) {
                        break :outer;
                    }
                }
                // Both succeeded
                self.ptr += 16;
                op_len += 16;
                self.len -= 16;
            }
            return op_ptr[0..op_len];
        }
    };
}
