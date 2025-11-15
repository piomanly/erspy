const std = @import("std");
const winnt_api = @import("../c_imports.zig").winnt_api;

pub const Process = struct {
    process_id: u32,
    handle: winnt_api.HANDLE,
    base_address: usize,

    const Self = @This();

    pub fn init(process_id: u32) !Self {
        const handle = winnt_api.OpenProcess(winnt_api.PROCESS_ALL_ACCESS, 0, process_id);
        const base_address = getBaseAddress(process_id);

        if (base_address == null) {
            return error.FailedToGetBaseAddress;
        }

        return .{
            .process_id = process_id,
            .handle = handle,
            .base_address = base_address.?,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.handle) |h| {
            _ = winnt_api.CloseHandle(h);
        }
    }

    pub fn allocate(self: *const Self, address: usize, size: usize, protection: ?u32) ?usize {
        const result = winnt_api.VirtualAllocEx(
            self.handle,
            @ptrFromInt(address),
            size,
            winnt_api.MEM_COMMIT | winnt_api.MEM_RESERVE,
            protection orelse winnt_api.PAGE_READWRITE,
        );

        return if (result == null) null else @intFromPtr(result.?);
    }

    pub fn free(self: *const Self, address: usize, size: usize) bool {
        const status = winnt_api.VirtualFreeEx(
            self.handle,
            @ptrFromInt(address),
            size,
            winnt_api.MEM_RELEASE,
        );

        return status == 1;
    }

    pub fn queryBuffer(self: *const Self, address: usize, buffer: *winnt_api.MEMORY_BASIC_INFORMATION) usize {
        const result = winnt_api.VirtualQueryEx(
            self.handle,
            @ptrFromInt(address),
            buffer,
            @sizeOf(winnt_api.MEMORY_BASIC_INFORMATION),
        );

        return result;
    }

    pub fn query(self: *const Self, address: usize) ?winnt_api.MEMORY_BASIC_INFORMATION {
        var buffer = winnt_api.MEMORY_BASIC_INFORMATION{};
        const query_size = self.queryBuffer(address, &buffer, @sizeOf(winnt_api.MEMORY_BASIC_INFORMATION));
        return if (query_size == 0) null else buffer;
    }

    pub fn readBuffer(self: *const Self, address: usize, buffer: winnt_api.LPVOID, size: usize, bytes_read: ?*usize) bool {
        const status = winnt_api.ReadProcessMemory(
            self.handle,
            @ptrFromInt(address),
            buffer,
            size,
            bytes_read,
        );

        return status == 1;
    }

    pub fn readType(self: *const Self, comptime T: type, address: usize) ?T {
        var buffer: T = undefined;
        const status = self.readBuffer(
            address,
            &buffer,
            @sizeOf(T),
            null,
        );

        return if (!status) null else buffer;
    }

    pub fn writeBuffer(self: *const Self, address: usize, buffer: winnt_api.LPCVOID, size: usize, bytes_written: ?*usize) bool {
        const status = winnt_api.WriteProcessMemory(
            self.handle,
            @ptrFromInt(address),
            buffer,
            size,
            bytes_written,
        );

        return status == 1;
    }

    pub fn writeType(self: *const Self, comptime T: type, address: usize, value: T) bool {
        const status = self.writeBuffer(
            address,
            &value,
            @sizeOf(T),
            null,
        );

        return status;
    }

    pub fn getProcessId(name: []const u8) ?u32 {
        const snapshot = winnt_api.CreateToolhelp32Snapshot(winnt_api.TH32CS_SNAPPROCESS, 0);
        if (snapshot == null) {
            return null;
        }

        defer _ = winnt_api.CloseHandle(snapshot);

        var entry = winnt_api.PROCESSENTRY32{};
        entry.dwSize = @sizeOf(winnt_api.PROCESSENTRY32);

        if (winnt_api.Process32First(snapshot, &entry) == 0) {
            return null;
        }

        while (winnt_api.Process32Next(snapshot, &entry) == 1) {
            const exe_file = entry.szExeFile[0..name.len];
            if (std.mem.eql(u8, exe_file, name)) {
                return entry.th32ProcessID;
            }
        }

        return null;
    }

    fn getBaseAddress(process_id: u32) ?usize {
        const snapshot = winnt_api.CreateToolhelp32Snapshot(winnt_api.TH32CS_SNAPMODULE | winnt_api.TH32CS_SNAPMODULE32, process_id);
        if (snapshot == null) {
            return null;
        }

        defer _ = winnt_api.CloseHandle(snapshot);

        var entry = winnt_api.MODULEENTRY32{};
        entry.dwSize = @sizeOf(winnt_api.MODULEENTRY32);

        if (winnt_api.Module32First(snapshot, &entry) == 0) {
            return null;
        }

        return @intFromPtr(entry.modBaseAddr);
    }
};
