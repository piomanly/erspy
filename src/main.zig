const std = @import("std");
const memory = @import("memory/memory.zig");
const roblox = @import("roblox/roblox.zig");
const remote_spy = @import("remote_spy/remote_spy.zig");
const winnt_api = @import("c_imports.zig").winnt_api;

const Allocator = std.mem.Allocator;

const Process = memory.Process;
const StlEx = memory.StlEx;

const Instance = roblox.Instance;
const Reflection = roblox.Reflection;
const Offsets = roblox.Offsets;

const DescriptorDetours = remote_spy.DescriptorDetours;
const RemoteInfo = remote_spy.RemoteInfo;
const RemoteHook = remote_spy.RemoteHook;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const process_id = Process.getProcessId("RobloxPlayerBeta.exe") orelse {
        std.debug.print("Failed to find roblox.", .{});
        return;
    };

    std.debug.print("Roblox Process ID: {d}\n", .{process_id});

    var process = try Process.init(process_id);
    defer process.deinit();
    const base_address = process.base_address;

    const process_ptr = try allocator.create(Process);
    defer allocator.destroy(process_ptr);
    process_ptr.* = process;

    var rspy = try RemoteHook.init(allocator, process_ptr);
    defer rspy.deinit() catch {};

    rspy.on_fire = &onFireCallback;

    try rspy.hookDescriptor(base_address + Offsets.FireServerDescriptor, &DescriptorDetours.fireServerDetour);
    try rspy.hookDescriptor(base_address + Offsets.UnreliableFireServerDescriptor, &DescriptorDetours.unreliableFireServerDetour);
    // invokeServer has diff callback offset

    try rspy.setup();
    try rspy.run();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_wrapper = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_wrapper.interface;

    // press enter to exit
    _ = try stdin.takeByte();
}

const ArgumentsHandler = struct {
    allocator: Allocator,
    process: *const Process,

    arguments: *Reflection.Tuple,

    const Self = @This();

    pub fn init(arguments: *Reflection.Tuple) ArgumentsHandler {
        return .{
            .allocator = arguments.allocator,
            .process = arguments.process,
            .arguments = arguments,
        };
    }

    pub fn print(self: *const Self) !void {
        const arguments_size = self.arguments.size();
        var argument_index: usize = 0;

        while (self.arguments.next()) |item| : (argument_index += 1) {
            const item_address = (self.arguments.current - self.arguments.step) + @offsetOf(Reflection.TupleItem, "value");

            const value = try item.readValue(self.allocator, self.process, item_address);
            switch (value) {
                .bool => |b| std.debug.print("{}", .{b}),
                .double => |d| std.debug.print("{d}", .{d}),
                .string => |s| std.debug.print("\"{s}\"", .{s}),
                .Instance => |i| std.debug.print("{s}", .{try i.getFullName()}),
                .Vector2 => |v| std.debug.print("Vector2.new({d}, {d})", .{ v.x, v.y }),
                .Vector3 => |v| std.debug.print("Vector3.new({d}, {d}, {d})", .{ v.x, v.y, v.z }),
                .Vector2int16 => |v| std.debug.print("Vector2int16.new({d}, {d})", .{ v.x, v.y }),
                .Vector3int16 => |v| std.debug.print("Vector3int16.new({d}, {d}, {d})", .{ v.x, v.y, v.z }),
                .Array => |a| std.debug.print("Array {x}", .{a.address}), // am too lazy to make recursive
                .nil => std.debug.print("nil", .{}),
            }

            if (argument_index + 1 < arguments_size) {
                std.debug.print(", ", .{});
            }
        }
    }
};

fn onFireCallback(instance: *const RemoteHook, remote_info: *const RemoteInfo) !void {
    const remote = Instance.init(instance.allocator, instance.process, @intFromPtr(remote_info.remote.?));

    const remote_class = try remote.getClassName();
    defer instance.allocator.free(remote_class);

    const method = if (std.mem.eql(u8, remote_class, "RemoteEvent") or std.mem.eql(u8, remote_class, "UnreliableRemoteEvent"))
        "FireServer"
    else
        "InvokeServer";

    const remote_path = if (try remote.getParent() == null)
        try std.fmt.allocPrint(instance.allocator, "Instance.new(\"{s}\")", .{remote_class})
    else
        try remote.getFullName();
    defer instance.allocator.free(remote_path);

    std.debug.print(
        \\local remote = {s}
        \\remote:{s}(
    , .{ remote_path, method });

    var arguments = try remote_info.readArguments(instance.allocator, instance.process);
    if (arguments != null) {
        const arguments_handler = ArgumentsHandler.init(&arguments.?);
        try arguments_handler.print();
    }

    std.debug.print(")\n", .{});
}
