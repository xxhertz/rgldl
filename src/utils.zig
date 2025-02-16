const std = @import("std");

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn find_string(text: []const u8, find: []const u8) ?usize {
    if (find.len > text.len)
        return null;

    for (0..text.len - find.len) |ptr|
        if (std.mem.eql(u8, text[ptr .. ptr + find.len], find))
            return ptr;

    return null;
}
