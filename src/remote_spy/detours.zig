const std = @import("std");
const memory = @import("../memory/memory.zig");
const winnt_api = @import("../c_imports.zig").winnt_api;

const SharedPtr = @import("miscellaneous.zig").SharedPtr;
const RemoteHook = @import("remote_hook.zig").RemoteHook;

pub const DescriptorDetours = struct {
    const section_name = ".piomanly";
    const DescriptorCallback = fn (...) callconv(.c) winnt_api.PVOID;

    pub noinline fn mainDetour(remote: winnt_api.PVOID, arguments: *SharedPtr, old_callback: *const DescriptorCallback) linksection(section_name) callconv(.c) winnt_api.PVOID {
        var array: *RemoteHook.Array = @ptrFromInt(unoptimizedStub());

        const semaphore: winnt_api.HANDLE = @ptrFromInt(unoptimizedStub());
        const mutex: winnt_api.HANDLE = @ptrFromInt(unoptimizedStub());

        const release_semaphore: *const @TypeOf(winnt_api.ReleaseSemaphore) = @ptrFromInt(unoptimizedStub());
        const release_mutex: *const @TypeOf(winnt_api.ReleaseMutex) = @ptrFromInt(unoptimizedStub());
        const wait_for_single_object: *const @TypeOf(winnt_api.WaitForSingleObject) = @ptrFromInt(unoptimizedStub());

        _ = wait_for_single_object(mutex, winnt_api.INFINITE);

        if (arguments.ptr != null) {
            arguments.increment();
        }

        array.append(.{
            .remote = remote,
            .arguments = arguments.ptr,
            .script = null,
        });

        _ = release_mutex(mutex);
        _ = release_semaphore(semaphore, 1, null);

        return old_callback(remote, arguments);
    }

    // unused detours doesnt get included in hook

    pub fn fireServerDetour(remote: winnt_api.PVOID, arguments: *SharedPtr) linksection(section_name) callconv(.c) winnt_api.PVOID {
        const old_callback: winnt_api.PVOID = @ptrFromInt(unoptimizedStub());
        return mainDetour(remote, arguments, @ptrCast(old_callback));
    }

    pub fn unreliableFireServerDetour(remote: winnt_api.PVOID, arguments: *SharedPtr) linksection(section_name) callconv(.c) winnt_api.PVOID {
        const old_callback: winnt_api.PVOID = @ptrFromInt(unoptimizedStub());
        return mainDetour(remote, arguments, @ptrCast(old_callback));
    }

    pub fn invokeServerDetour(remote: winnt_api.PVOID, arguments: *SharedPtr) linksection(section_name) callconv(.c) winnt_api.PVOID {
        const old_callback: winnt_api.PVOID = @ptrFromInt(unoptimizedStub());
        return mainDetour(remote, arguments, @ptrCast(old_callback));
    }

    fn detoursEnd() linksection(section_name) void {}

    pub fn getSize() usize {
        return @intFromPtr(&detoursEnd) - @intFromPtr(&mainDetour);
    }

    pub fn replaceStubs(slice: []u8, values: []const usize) void {
        var value_index: usize = 0;
        for (0..slice.len - @sizeOf(usize)) |i| {
            if (value_index >= values.len) {
                break;
            }

            const stub = std.mem.readInt(usize, slice[i..][0..@sizeOf(usize)], .little);
            if (stub == 0xaabbccddeeff) {
                std.mem.writeInt(
                    usize,
                    slice[i..][0..@sizeOf(usize)],
                    values[value_index],
                    .little,
                );

                value_index += 1;
            }
        }
    }

    inline fn unoptimizedStub() usize {
        var result: usize = undefined;
        asm volatile (
            \\ movq $0xaabbccddeeff, %[result]
            : [result] "=r" (result),
        );

        return result;
    }
};
