pub const winnt_api = @cImport({
    @cInclude("Windows.h");
    @cInclude("TlHelp32.h");
    @cInclude("Memoryapi.h");
});
