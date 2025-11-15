const std = @import("std");

const Allocator = std.mem.Allocator;
const Process = @import("process.zig").Process;

pub const StlEx = struct {
    pub fn readCppString(allocator: Allocator, process: *const Process, address: usize) ![]const u8 {
        const cpp_string = process.readType(CppString, address) orelse {
            return error.FailedToReadCppString;
        };

        var buffer = try allocator.alloc(u8, cpp_string.length);
        if (cpp_string.capacity <= 0xF) {
            const slice = cpp_string.data[0..cpp_string.length];
            @memmove(buffer[0..], slice);
            return buffer;
        }

        const data_ptr = std.mem.readInt(usize, cpp_string.data[0..8], .little);
        const status = process.readBuffer(data_ptr, buffer.ptr, buffer.len, null);

        if (!status) {
            return error.FailedToReadDataPointer;
        }

        return buffer;
    }

    pub fn Vector(comptime T: type) type {
        return struct {
            allocator: Allocator,
            process: *const Process,
            address: usize,
            step: usize,
            begin: usize,
            end: usize,
            current: usize,

            const Self = @This();

            pub fn init(allocator: Allocator, process: *const Process, address: usize, step: usize) !Self {
                if (step <= 0) {
                    return error.InvalidStep;
                }

                const iterators = process.readType([2]usize, address) orelse {
                    return error.FailedToReadVectorIterators;
                };

                const begin = iterators[0];
                const end = iterators[1];

                return .{
                    .allocator = allocator,
                    .process = process,
                    .address = address,
                    .step = step,
                    .begin = begin,
                    .end = end,
                    .current = begin,
                };
            }

            pub fn next(self: *Self) ?T {
                if (self.current >= self.end) {
                    return null;
                }

                const value = self.process.readType(T, self.current);
                self.current += self.step;

                return value;
            }

            pub fn findByPredicate(
                self: *Self,
                comptime DT: type,
                data_ptr: ?*const DT,
                predicate: fn (?*const DT, Allocator, *const Process, usize) anyerror!bool,
            ) !?T {
                defer self.reset();
                while (self.next()) |j| {
                    if (try predicate(data_ptr, self.allocator, self.process, j)) {
                        return j;
                    }
                }

                return null;
            }

            pub fn size(self: *const Self) usize {
                if (self.begin >= self.end) {
                    return 0;
                }

                return (self.end - self.begin) / self.step;
            }

            pub fn reset(self: *Self) void {
                self.current = self.begin;
            }
        };
    }
};

const CppString = extern struct {
    data: [15]u8,
    _pad0: u8,
    length: usize,
    capacity: usize,
};
