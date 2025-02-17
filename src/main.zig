const std = @import("std");
const win = std.os.windows;
const utils = @import("utils.zig");
const get_tf2_maps_dir = @import("locate_tf2.zig").get_tf2_maps_dir;
const safe_download = @import("download.zig").safe_download;

const maps = [_][]const u8{ "cp_reckoner_rc6.bsp", "cp_process_f12.bsp", "cp_metalworks_f5.bsp", "cp_gullywash_f9.bsp", "cp_granary_pro_rc8.bsp", "cp_prolands_rc2ta.bsp", "cp_sultry_b8a.bsp", "cp_villa_b19.bsp", "koth_clearcut_b17.bsp", "koth_bagel_rc10.bsp", "koth_product_final.bsp" };

pub fn main() !void {
    // TODO: look into rewriting this as a FixedBufferAllocator to prevent heap allocations
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("Memory leak", .{});
        }
    }

    const tf2_maps_dir = try get_tf2_maps_dir(allocator);

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    inline for (maps) |map|
        try pool.spawn(safe_download, .{ allocator, tf2_maps_dir, map });
}
