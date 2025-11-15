const HOOK_ARRAY_SIZE = 1024;

const std = @import("std");
const memory = @import("../memory/memory.zig");
const roblox = @import("../roblox/roblox.zig");
const winnt_api = @import("../c_imports.zig").winnt_api;

const Allocator = std.mem.Allocator;

const Process = memory.Process;
const StlEx = memory.StlEx;
const Scanner = memory.Scanner;

const Reflection = roblox.Reflection;
const Offsets = roblox.Offsets;

const FixedArray = @import("miscellaneous.zig").FixedArray;
const DescriptorDetours = @import("detours.zig").DescriptorDetours;

extern "api-ms-win-core-memory-l1-1-5" fn MapViewOfFileNuma2(FileMappingHandle: winnt_api.HANDLE, ProcessHandle: winnt_api.HANDLE, Offset: winnt_api.ULONG64, BaseAddress: winnt_api.PVOID, ViewSize: winnt_api.SIZE_T, AllocationType: winnt_api.ULONG, PageProtection: winnt_api.ULONG, PreferredNode: winnt_api.ULONG) callconv(.winapi) winnt_api.PVOID;

var release_semaphore_ptr: winnt_api.FARPROC = null;
var release_mutex_ptr: winnt_api.FARPROC = null;
var wait_for_single_object_ptr: winnt_api.FARPROC = null;

pub const RemoteInfo = extern struct {
    remote: winnt_api.PVOID,
    arguments: winnt_api.PVOID,
    script: winnt_api.PVOID,

    const Self = @This();

    pub fn readArguments(self: *const Self, allocator: Allocator, process: *const Process) !?Reflection.Tuple {
        if (self.arguments == null) {
            return null;
        }

        return try Reflection.Tuple.init(
            allocator,
            process,
            @intFromPtr(self.arguments.?),
            @sizeOf(Reflection.TupleItem),
        );
    }
};

pub const RemoteHook = struct {
    allocator: Allocator,
    process: *const Process,

    array: ?*Array = null,
    remote_array: ?*Array = null,

    handles: Handles = .{
        .file = null,
        .mutex = null,
        .remote_mutex = null,
        .semaphore = null,
        .remote_semaphore = null,
        .wait_object = null,
    },

    detour_info: DetourInfo = .{
        .size = null,
        .address = null,
        .old_char = null,
    },

    descriptors: std.AutoArrayHashMap(usize, DescriptorInfo),
    on_fire: ?*const OnFireCallback = null,

    pub const Array = FixedArray(RemoteInfo, HOOK_ARRAY_SIZE);

    const Handles = struct {
        file: winnt_api.HANDLE,
        mutex: winnt_api.HANDLE,
        remote_mutex: winnt_api.HANDLE,
        semaphore: winnt_api.HANDLE,
        remote_semaphore: winnt_api.HANDLE,
        wait_object: winnt_api.HANDLE,
    };

    const DetourInfo = struct {
        size: ?usize,
        address: ?usize,
        old_char: ?u8,
    };

    const DescriptorInfo = struct {
        callback: usize,
        detour: winnt_api.LPCVOID,
    };

    const OnFireCallback = fn (instance: *const Self, remote_info: *const RemoteInfo) anyerror!void;
    const Self = @This();

    pub fn init(allocator: Allocator, process: *const Process) !Self {
        return .{
            .allocator = allocator,
            .process = process,
            .descriptors = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) !void {
        try self.deinitDetour();
        self.deinitHandles();
        self.deinitArray();

        self.descriptors.deinit();
    }

    pub fn hookDescriptor(self: *Self, descriptor: usize, detour_ptr: winnt_api.LPCVOID) !void {
        const descriptor_callback = self.process.readType(usize, descriptor + Offsets.BoundFuncDescriptorCallback) orelse {
            return error.FailedToReadDescriptorCallback;
        };

        try self.descriptors.put(descriptor, .{
            .callback = descriptor_callback,
            .detour = detour_ptr,
        });
    }

    pub fn setup(self: *Self) !void {
        try self.setupArray();
        try self.setupHandles();
        try self.setupDetour();
    }

    pub fn run(self: *Self) !void {
        const register_status = winnt_api.RegisterWaitForSingleObject(
            &self.handles.wait_object,
            self.handles.semaphore,
            &semaphoreCallback,
            self,
            winnt_api.INFINITE,
            winnt_api.WT_EXECUTEINIOTHREAD,
        );

        if (register_status == 0) {
            return error.FailedToRegisterWaitForSingleObject;
        }
    }

    fn setupArray(self: *Self) !void {
        const file = winnt_api.CreateFileMappingA(
            winnt_api.INVALID_HANDLE_VALUE,
            null,
            winnt_api.PAGE_READWRITE,
            0,
            @sizeOf(Array),
            null,
        ) orelse {
            return error.FailedToCreateFileMapping;
        };

        const array = winnt_api.MapViewOfFile(
            file,
            winnt_api.FILE_MAP_ALL_ACCESS,
            0,
            0,
            @sizeOf(Array),
        ) orelse {
            return error.FailedToCreateLocalArrayMapping;
        };

        const remote_array = MapViewOfFileNuma2(
            file,
            self.process.handle,
            0,
            null,
            0,
            0,
            winnt_api.PAGE_READWRITE,
            winnt_api.NUMA_NO_PREFERRED_NODE,
        ) orelse {
            return error.FailedToMapArrayToRemoteProcess;
        };

        self.handles.file = file;
        self.array = @ptrCast(@alignCast(array));
        self.remote_array = @ptrCast(@alignCast(remote_array));
    }

    fn setupHandles(self: *Self) !void {
        const semaphore = winnt_api.CreateSemaphoreA(null, 0, 8, null) orelse {
            return error.FailedToCreateSemaphore;
        };

        const mutex = winnt_api.CreateMutexA(null, 0, null) orelse {
            return error.FailedToCreateSemaphore;
        };

        self.handles.semaphore = semaphore;
        self.handles.mutex = mutex;

        const current_process = winnt_api.GetCurrentProcess();
        const semaphore_dup_status = winnt_api.DuplicateHandle(
            current_process,
            semaphore,
            self.process.handle,
            &self.handles.remote_semaphore,
            winnt_api.SEMAPHORE_ALL_ACCESS,
            0,
            0,
        );

        if (semaphore_dup_status == 0) {
            return error.FailedToDuplicateSemaphore;
        }

        const mutex_dup_status = winnt_api.DuplicateHandle(
            current_process,
            mutex,
            self.process.handle,
            &self.handles.remote_mutex,
            winnt_api.MUTEX_ALL_ACCESS,
            0,
            0,
        );

        if (mutex_dup_status == 0) {
            return error.FailedToDuplicateMutex;
        }
    }

    fn setupDetour(self: *Self) !void {
        if (release_semaphore_ptr == null or release_mutex_ptr == null or wait_for_single_object_ptr == null) {
            const kernel32 = winnt_api.LoadLibraryA("kernel32.dll");

            release_semaphore_ptr = winnt_api.GetProcAddress(kernel32, "ReleaseSemaphore");
            release_mutex_ptr = winnt_api.GetProcAddress(kernel32, "ReleaseMutex");
            wait_for_single_object_ptr = winnt_api.GetProcAddress(kernel32, "WaitForSingleObject");
        }

        const detour_bytes = blk: {
            const size = DescriptorDetours.getSize();
            const source: [*]const u8 = @ptrCast(&DescriptorDetours.mainDetour);

            var dest = try self.allocator.alloc(u8, size);
            @memmove(dest[0..size], source[0..size]);

            break :blk dest;
        };
        defer self.allocator.free(detour_bytes);

        var replacements = std.ArrayList(usize).empty;
        defer replacements.deinit(self.allocator);

        try replacements.appendSlice(self.allocator, &[_]usize{
            @intFromPtr(self.remote_array),
            @intFromPtr(self.handles.remote_semaphore),
            @intFromPtr(self.handles.remote_mutex),
            @intFromPtr(release_semaphore_ptr),
            @intFromPtr(release_mutex_ptr),
            @intFromPtr(wait_for_single_object_ptr),
        });

        var iterator = self.descriptors.iterator();
        while (iterator.next()) |e| {
            try replacements.append(self.allocator, e.value_ptr.*.callback);
        }

        const slice = try replacements.toOwnedSlice(self.allocator);
        DescriptorDetours.replaceStubs(detour_bytes[0..], slice);

        const detour = blk: {
            const code_cave = try Scanner.findCodeCave(self.allocator, self.process, detour_bytes.len) orelse {
                return error.FailedToFindCodeCave;
            };

            const write_status = self.process.writeBuffer(
                code_cave,
                detour_bytes.ptr,
                detour_bytes.len,
                null,
            );

            if (!write_status) {
                return error.FailedToWriteDetour;
            }

            break :blk code_cave;
        };

        const old_char = self.process.readType(u8, detour) orelse {
            return error.FailedToReadCaveChar;
        };

        self.detour_info.size = detour_bytes.len;
        self.detour_info.address = detour;
        self.detour_info.old_char = old_char;

        iterator.reset();
        while (iterator.next()) |e| {
            try self.placeDescriptorHook(e.key_ptr.*, e.value_ptr.*.detour);
        }
    }

    fn deinitArray(self: *Self) void {
        if (self.remote_array) |p| {
            _ = winnt_api.UnmapViewOfFile2(self.process.handle, p, 0);
        }

        if (self.array) |p| {
            _ = winnt_api.UnmapViewOfFile(p);
        }
    }

    fn deinitHandles(self: *Self) void {
        if (self.handles.mutex) |m| {
            _ = winnt_api.CloseHandle(m);
        }

        if (self.handles.semaphore) |s| {
            _ = winnt_api.CloseHandle(s);
        }

        if (self.handles.file) |h| {
            _ = winnt_api.CloseHandle(h);
        }
    }

    fn deinitDetour(self: *Self) !void {
        try self.restoreDescriptorCallbacks();

        if (self.handles.wait_object) |h| {
            _ = winnt_api.UnregisterWait(h);
        }

        if (self.detour_info.old_char) |c| {
            const buffer = try self.allocator.alloc(u8, self.detour_info.size.?);
            defer self.allocator.free(buffer);

            @memset(buffer, c);

            const write_status = self.process.writeBuffer(
                self.detour_info.address.?,
                buffer.ptr,
                buffer.len,
                null,
            );

            if (!write_status) {
                return error.FailedToWriteDetour;
            }
        }
    }

    fn placeDescriptorHook(self: *const Self, descriptor: usize, detour_ptr: winnt_api.LPCVOID) !void {
        if (self.detour_info.address == null) {
            return error.NoDetourAddress;
        }

        const detour_offset = (@intFromPtr(detour_ptr) - @intFromPtr(&DescriptorDetours.mainDetour));
        const new_callback = self.detour_info.address.? + detour_offset;

        const write_status = self.process.writeType(usize, descriptor + Offsets.BoundFuncDescriptorCallback, new_callback);
        if (!write_status) {
            return error.FailedToWriteDescriptorHook;
        }
    }

    fn restoreDescriptorCallbacks(self: *Self) !void {
        var iterator = self.descriptors.iterator();
        while (iterator.next()) |e| {
            const callback_ptr = e.key_ptr.* + Offsets.BoundFuncDescriptorCallback;
            const write_status = self.process.writeType(usize, callback_ptr, e.value_ptr.*.callback);

            if (!write_status) {
                return error.FailedToRestoreDescriptorCallback;
            }
        }
    }
};

fn semaphoreCallback(lp_param: winnt_api.PVOID, _: winnt_api.BOOLEAN) callconv(.c) void {
    const instance: *const RemoteHook = @ptrCast(@alignCast(lp_param));

    _ = winnt_api.WaitForSingleObject(instance.handles.mutex, winnt_api.INFINITE);
    defer _ = winnt_api.ReleaseMutex(instance.handles.mutex);

    const array = instance.array orelse {
        return;
    };

    if (instance.on_fire) |c| {
        c(instance, &array.get()) catch |e| {
            std.debug.print("Callback error: {}\n", .{e});
        };
    }
}
