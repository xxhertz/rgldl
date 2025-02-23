const std = @import("std");
const http = std.http;
const utils = @import("utils.zig");

const download_url = "https://fastdl.serveme.tf/maps/{s}";

fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var headers: [4096]u8 = undefined;

    const uri = std.Uri.parse(url) catch unreachable;

    var request = try client.open(.GET, uri, .{ .server_header_buffer = &headers });
    defer request.deinit();

    try request.send();
    try request.wait();

    return try request.reader().readAllAlloc(allocator, 1024 * 1024 * 128); // 128 MiB
}

pub fn download(allocator: std.mem.Allocator, tf2_dir: std.fs.Dir, comptime bsp_name: []const u8) !void {
    utils.print("Downloading {s}", .{bsp_name});
    const file = tf2_dir.createFile(bsp_name, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return utils.print("{s} is already downloaded - skipping", .{bsp_name}),
        else => std.debug.panic("Ran into an error while creating the file for {s}, error: {s}", .{ bsp_name, @errorName(err) }),
    };

    const file_data = try get(allocator, std.fmt.comptimePrint(download_url, .{bsp_name}));
    defer allocator.free(file_data);

    try file.writeAll(file_data);

    utils.print("Downloaded {s}", .{bsp_name});
}

pub fn safe_download(allocator: std.mem.Allocator, tf2_dir: std.fs.Dir, comptime bsp_name: []const u8) void {
    download(allocator, tf2_dir, bsp_name) catch |err| std.debug.panic("Failed to download, err: {s}", .{@errorName(err)});
}
