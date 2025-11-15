const std = @import("std");
const memory = @import("../memory/memory.zig");
const winnt_api = @import("../c_imports.zig").winnt_api;

const Process = memory.Process;
const StlEx = memory.StlEx;

const Instance = @import("instance.zig").Instance;

pub const Reflection = @This();

pub const TTypeID = enum(i32) { // look at rbxstu source for more ttypeids
    nil = 0,
    bool,
    double = 5,
    string,
    Instance = 8,
    Ray = 10,
    Vector2,
    Vector3,
    Vector2int16,
    Vector3int16,
    Array = 35,
    Dictionary,
};

pub const TType = extern struct {
    vtable: winnt_api.PVOID,
    tag: winnt_api.PVOID,
    _pad0: [0x30]u8,
    type_id: i32,
};

pub const Tuple = StlEx.Vector(TupleItem);
pub const Array = StlEx.Vector(TupleItem);

pub const TupleItem = extern struct {
    ttype: ?*TType,
    value_vtable: winnt_api.PVOID,
    value: winnt_api.PVOID,
    _pad0: [0x38]u8,

    const Self = @This();

    pub fn readValue(self: Self, allocator: std.mem.Allocator, process: *const Process, value_ptr: usize) !Value {
        const ttype = process.readType(TType, @intFromPtr(self.ttype.?)) orelse {
            return error.FailedToReadTType;
        };

        const type_id: TTypeID = @enumFromInt(ttype.type_id);

        return switch (type_id) {
            .bool => .{ .bool = @intFromPtr(self.value.?) == 1 },
            .double => .{ .double = @bitCast(@intFromPtr(self.value.?)) },
            .string => .{ .string = try StlEx.readCppString(allocator, process, value_ptr) },
            .Instance => .{ .Instance = Instance.init(allocator, process, @intFromPtr(self.value.?)) },
            .Vector2 => .{ .Vector2 = process.readType(Vector2, value_ptr) orelse Vector2.zero },
            .Vector3 => .{ .Vector3 = process.readType(Vector3, value_ptr) orelse Vector3.zero },
            .Vector2int16 => .{ .Vector2int16 = process.readType(Vector2int16, value_ptr) orelse Vector2int16.zero },
            .Vector3int16 => .{ .Vector3int16 = process.readType(Vector3int16, value_ptr) orelse Vector3int16.zero },
            .Array => .{ .Array = try Array.init(allocator, process, @intFromPtr(self.value.?), @sizeOf(TupleItem)) },
            else => .{ .nil = {} },
        };
    }
};

pub const Value = union(enum) {
    nil: void,
    bool: bool,
    double: f64,
    string: []const u8,
    Instance: Instance,
    Vector2: Vector2,
    Vector3: Vector3,
    Vector2int16: Vector2int16,
    Vector3int16: Vector3int16,
    Array: Array,
};

pub const Vector2 = extern struct {
    pub const zero = @This(){ .x = 0, .y = 0 };

    x: f32,
    y: f32,
};

pub const Vector3 = extern struct {
    pub const zero = @This(){ .x = 0, .y = 0, .z = 0 };

    x: f32,
    y: f32,
    z: f32,
};

pub const Vector2int16 = extern struct {
    pub const zero = @This(){ .x = 0, .y = 0 };

    x: i16,
    y: i16,
};

pub const Vector3int16 = extern struct {
    pub const zero = @This(){ .x = 0, .y = 0, .z = 0 };

    x: i16,
    y: i16,
    z: i16,
};
