const std = @import("std");
const winnt_api = @import("../c_imports.zig").winnt_api;

pub const SharedPtr = extern struct {
    ptr: winnt_api.PVOID,
    ref_object: ?*RefObject,

    const RefObject = extern struct {
        vftable: winnt_api.PVOID,
        ref_count: u32,
    };

    const Self = @This();

    pub inline fn increment(self: *Self) void {
        if (self.ref_object) |r| {
            r.ref_count += 1;
        }
    }
};

pub fn FixedArray(comptime T: type, comptime size: usize) type {
    return extern struct {
        items: Items,
        next: usize,

        const Items = [size]T;
        const Self = @This();

        pub fn init() Self {
            return .{
                .items = std.mem.zeroes(Items),
                .next = 0,
            };
        }

        pub inline fn append(self: *Self, item: T) void {
            self.items[self.next] = item;
            self.next = (self.next + 1) % size;
        }

        pub fn get(self: *const Self) T {
            const index = (self.next + size - 1) % size;
            return self.items[index];
        }
    };
}
