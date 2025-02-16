const std = @import("std");
const win = std.os.windows;
const utils = @import("utils.zig");
const win32 = @import("win32");

fn path_from_dir(allocator: std.mem.Allocator, dir: std.fs.Dir) ![]u8 {
    var file_path: [win.MAX_PATH:0]win.CHAR = undefined;
    const len = win32.storage.file_system.GetFinalPathNameByHandleA(dir.fd, &file_path, win.MAX_PATH, .NORMALIZED);

    return try allocator.dupe(win.CHAR, file_path[0..len]);
}

fn find_steam_path(allocator: std.mem.Allocator) ![]u8 {
    const registry = win32.system.registry;
    var key: ?registry.HKEY = null;

    if (registry.RegOpenKeyExA(registry.HKEY_CURRENT_USER, "SOFTWARE\\Valve\\Steam", 0, registry.KEY_READ, &key) != .NO_ERROR) {
        utils.print("Failed to read regkey @ SOFTWARE\\Valve\\Steam", .{});
        return error.CantOpen;
    }
    defer _ = registry.RegCloseKey(key);

    var dataType: win32.system.registry.REG_VALUE_TYPE = undefined;
    var data: [win.MAX_PATH]u8 = undefined;
    var dataSize: u32 = data.len;

    if (registry.RegQueryValueExA(key, "SteamPath", null, &dataType, @ptrCast(&data), &dataSize) != .NO_ERROR) {
        utils.print("Failed to read SteamPath value from regkey @ SOFTWARE\\Valve\\Steam", .{});
        return error.CantOpen;
    }
    return try allocator.dupe(u8, data[0..dataSize]);
}

fn find_tf2_path(allocator: std.mem.Allocator, steam_folder: []const u8) ![]u8 {
    const dir = try std.fs.openDirAbsolute(steam_folder, .{});
    const file = try dir.openFile("steamapps\\libraryfolders.vdf", .{});
    defer file.close();

    var last_path: ?[]u8 = null;
    while (try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(usize))) |line| {
        defer allocator.free(line);

        const search = "\"path\"\t\t\"";
        if (utils.find_string(line, search)) |idx| {
            if (last_path) |prev| allocator.free(prev);

            last_path = try allocator.dupe(u8, line[idx + search.len .. line.len - 1]);
        }

        if (utils.find_string(line, "\t\t\t\"440\"\t\t")) |_|
            return last_path orelse error.NotFound;
    }

    return error.NotFound;
}

pub fn get_tf2_maps_dir(allocator: std.mem.Allocator) !std.fs.Dir {
    const steam_folder = find_steam_path(allocator) catch @panic("Could not find Steam via Windows registry");
    defer allocator.free(steam_folder);
    utils.print("Steam folder: {s}", .{steam_folder});

    var tf2_path = find_tf2_path(allocator, steam_folder) catch @panic("TF2 not installed via Steam library or could not be found in steamapps\\libraryfolders.vdf");
    defer allocator.free(tf2_path);

    const len = try win.normalizePath(u8, tf2_path);
    if (allocator.resize(tf2_path, len))
        tf2_path = tf2_path[0..len];

    utils.print("TF2 drive: {s}", .{tf2_path});

    const tf2_dir = std.fs.openDirAbsolute(tf2_path, .{}) catch @panic("Could not open the drive you have TF2 installed on, have you changed your drive letter without updating steam?");
    const tf2_maps_dir = tf2_dir.openDir("steamapps\\common\\Team Fortress 2\\tf\\maps", .{}) catch @panic("Could not open TF2 directory, have you manually uninstalled it?");

    const tf2_maps_path = try path_from_dir(allocator, tf2_maps_dir);
    utils.print("TF2 map folder: {s}", .{tf2_maps_path});
    allocator.free(tf2_maps_path);

    return tf2_maps_dir;
}
