const std = @import("std");
const memory = @import("../memory/memory.zig");
const winnt_api = @import("../c_imports.zig").winnt_api;

const Allocator = std.mem.Allocator;

const Process = memory.Process;
const StlEx = memory.StlEx;

const Offsets = @import("offsets.zig").Offsets;

pub const Instance = struct {
    allocator: Allocator,
    process: *const Process,
    address: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, process: *const Process, address: usize) Self {
        return .{
            .allocator = allocator,
            .process = process,
            .address = address,
        };
    }

    pub fn getClassName(self: *const Self) ![]const u8 {
        const class_descriptor = self.process.readType(usize, self.address + Offsets.InstanceClassDescriptor) orelse {
            return error.FailedToReadInstanceClassDescriptor;
        };

        const class_name_address = self.process.readType(usize, class_descriptor + Offsets.ClassDescriptorName) orelse {
            return error.FailedToReadInstanceClassName;
        };

        const class_name = try StlEx.readCppString(self.allocator, self.process, class_name_address);
        return class_name;
    }

    pub fn getName(self: *const Self) ![]const u8 {
        const name_address = self.process.readType(usize, self.address + Offsets.InstanceName) orelse {
            return error.FailedToReadInstanceName;
        };

        const name = try StlEx.readCppString(self.allocator, self.process, name_address);
        return name;
    }

    pub fn getParent(self: *const Self) !?Instance {
        const parent_address = self.process.readType(usize, self.address + Offsets.InstanceParent) orelse {
            return error.FailedToReadInstanceParent;
        };

        const instance = Instance.init(self.allocator, self.process, parent_address);
        return if (parent_address == 0) null else instance;
    }

    pub fn getChildren(self: *const Self) !memory.StlEx.Vector(usize) {
        const children_address = self.process.readType(usize, self.address + Offsets.InstanceChildren) orelse {
            return error.FailedToReadInstanceChildren;
        };

        return .init(self.allocator, self.process, children_address, 0x10);
    }

    pub fn getFullName(self: *const Self) ![]const u8 {
        const class_name = try self.getClassName();
        var name = try self.getName();
        const parent = try self.getParent();

        if (parent) |p| {
            const parent_name = try p.getFullName();
            name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ parent_name, name });
        } else if (std.mem.eql(u8, class_name, "DataModel")) {
            name = "Game";
        }

        return name;
    }

    pub fn findFirstChild(self: *const Self, name: []const u8) !?Instance {
        return self.findFirstChildMatching(getName, name);
    }

    pub fn findFirstChildOfClass(self: *const Self, class_name: []const u8) !?Instance {
        return self.findFirstChildMatching(getClassName, class_name);
    }

    fn findFirstChildMatching(
        self: *const Self,
        matcher: fn (*const Self) anyerror![]const u8,
        data: []const u8,
    ) !?Instance {
        var children = try self.getChildren();
        const child = try children.findByPredicate([]const u8, &data, struct {
            pub fn f(
                data_ptr: ?*const @TypeOf(data),
                allocator: Allocator,
                process: *const Process,
                child: usize,
            ) !bool {
                if (data_ptr == null) {
                    return false;
                }

                const instance = Instance.init(allocator, process, child);
                const result = try matcher(&instance);
                defer allocator.free(result);

                return std.mem.eql(u8, result, data_ptr.?.*);
            }
        }.f) orelse {
            return null;
        };

        const instance = Instance.init(self.allocator, self.process, child);
        return instance;
    }
};
