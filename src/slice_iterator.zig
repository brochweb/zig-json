const mem = @import("std").mem;

/// Works over memory owned by another function
pub fn SliceIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        ptr: [*]const T,
        len: usize,
        /// Source of the slice MUST last for at least as long as the SliceIterator
        pub fn from_slice(slice: *const []const T) Self {
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
        pub fn take(self: *Self, number: usize) ?[]const T {
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
        pub fn peek_multiple(self: *const Self, comptime n: usize) ?[n]T {
            if (self.len >= n) {
                var out: [n]T = undefined;
                mem.copy(u8, out[0..], self.ptr[0..n]);
                return out;
            } else {
                return null;
            }
        }
    };
}
