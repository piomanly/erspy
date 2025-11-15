const std = @import("std");
const winnt_api = @import("../c_imports.zig").winnt_api;

const Allocator = std.mem.Allocator;
const Process = @import("process.zig").Process;

pub const Scanner = struct {
    pub fn findCodeCave(allocator: Allocator, process: *const Process, size: usize) !?usize {
        var system_info = winnt_api.SYSTEM_INFO{};
        winnt_api.GetSystemInfo(&system_info);

        const start: usize = @intFromPtr(system_info.lpMinimumApplicationAddress);
        const end: usize = @intFromPtr(system_info.lpMaximumApplicationAddress);

        var mbi = winnt_api.MEMORY_BASIC_INFORMATION{};
        var current = start;

        while (current < end) : (current += mbi.RegionSize) {
            const query_size = process.queryBuffer(current, &mbi);
            if (query_size == 0) {
                continue;
            }

            const is_commit = mbi.State == winnt_api.MEM_COMMIT;
            const is_mapped = (mbi.Type & (winnt_api.MEM_PRIVATE | winnt_api.MEM_MAPPED)) != 0;
            const is_executeable = (mbi.Protect & (winnt_api.PAGE_EXECUTE_READ | winnt_api.PAGE_EXECUTE_READWRITE | winnt_api.PAGE_EXECUTE_WRITECOPY)) != 0;

            if (!is_commit or !is_mapped or !is_executeable) {
                continue;
            }

            var buffer = try allocator.alloc(u8, mbi.RegionSize);
            defer allocator.free(buffer);

            var bytes_read: usize = 0;
            const read_status = process.readBuffer(
                current,
                buffer.ptr,
                buffer.len,
                &bytes_read,
            );

            if (!read_status) {
                continue;
            }

            const found = findWriteableCave(
                process,
                current,
                buffer[0..bytes_read],
                size,
            );

            if (found) |address| {
                return address;
            }
        }

        return null;
    }

    inline fn findWriteableCave(process: *const Process, base_address: usize, buffer: []const u8, size: usize) ?usize {
        var count: usize = 1;
        for (1..buffer.len) |i| {
            if (buffer[i] != buffer[i - 1]) {
                count = 1;
                continue;
            }

            count += 1;
            if (count < size) {
                continue;
            }

            const cave_address = base_address + i - size + 1;
            var bytes_written: usize = 0;

            const write_status = process.writeBuffer(
                cave_address,
                &buffer[i],
                1,
                &bytes_written,
            );

            if (!write_status or bytes_written != 1) {
                count = 1;
                continue;
            }

            return cave_address;
        }

        return null;
    }
};
