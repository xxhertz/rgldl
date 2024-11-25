const std = @import("std");
const win = std.os.windows;
const http = std.http;
const unicode = std.unicode;
const L = unicode.utf8ToUtf16LeStringLiteral;
const wtoa = unicode.utf16LeToUtf8;
const wapi = @cImport({
    @cInclude("windows.h");
});

const maps = [_][]const u8{ "pl_vigil_rc10.bsp", "koth_ashville_final1.bsp", "koth_product_final.bsp", "koth_lakeside_r2.bsp", "koth_proot_b6c-alt2.bsp", "pl_upward_f12.bsp", "cp_steel_f12.bsp", "pl_eruption_b13.bsp", "koth_cascade_rc1a.bsp" };
const downloadUrl = "https://dl.serveme.tf/maps/{s}";

fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

fn findString(text: []const u8, find: []const u8) isize {
    for (text, 0..) |char, idx| {
        if (char == find[0] and text.len > idx + find.len) {
            const search = text[idx .. idx + find.len];
            const eq = std.mem.eql(u8, search, find);
            if (eq)
                return @intCast(idx);
        }
    }

    return -1;
}

fn getFolderPath(allocator: std.mem.Allocator, handle: win.HANDLE) ![]u8 {
    var filePath: [win.MAX_PATH]win.CHAR = undefined;
    const len = wapi.GetFinalPathNameByHandleA(handle, &filePath, win.MAX_PATH, win.VOLUME_NAME_DOS);

    return try allocator.dupe(win.CHAR, filePath[0..len]);
    // return filePath[0..len];
}

fn getSteamFolder(allocator: std.mem.Allocator) ![]u8 {
    var hKey: wapi.HKEY = null;
    if (wapi.RegOpenKeyExA(0x80000001, "SOFTWARE\\Valve\\Steam", 0, wapi.KEY_READ, &hKey) != 0) {
        println("Failed to get SOFTWARE\\Valve\\Steam key", .{});
        return error.CantOpen;
    }
    std.debug.assert(hKey != null);
    defer _ = wapi.RegCloseKey(hKey);

    var dataType: win.DWORD = 0;
    var data: [256]u8 = undefined;
    var dataSize: win.ULONG = data.len;

    if (wapi.RegQueryValueExA(hKey, "SteamPath", null, &dataType, &data, &dataSize) != wapi.ERROR_SUCCESS) {
        println("Failed to get SteamPath value from SOFTWARE\\Valve\\Steam key", .{});
        return error.CantOpen;
    }
    return try allocator.dupe(u8, data[0..dataSize]);
}

fn getTF2Folder(allocator: std.mem.Allocator, steamFolder: []const u8) ![]u8 {
    const dir = try std.fs.openDirAbsolute(steamFolder, .{});
    const file = try dir.openFile("steamapps\\libraryfolders.vdf", .{});
    defer file.close();

    var drive: ?[]u8 = null;
    var found = false;

    while (try file.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(usize))) |line| {
        defer allocator.free(line);

        const search = "\"path\"\t\t\"";
        const pathidx = findString(line, search);
        if (pathidx != -1) {
            if (drive) |oldPath| allocator.free(oldPath);
            drive = try allocator.dupe(u8, line[@as(usize, @intCast(pathidx + search.len)) .. line.len - 1]);
        }

        const tf2loc = findString(line, "\t\t\t\"440\"\t\t");
        if (tf2loc != -1) {
            found = true;
            break;
        }
    }
    if (!found or drive == null)
        return error.NotFound;

    return drive.?;
}

fn httpGet(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var buf: [4096]u8 = undefined;

    const uri = std.Uri.parse(url) catch unreachable;

    var request = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
    defer request.deinit();

    try request.send();
    try request.wait();

    return try request.reader().readAllAlloc(allocator, 1024 * 1024 * 48); // 48 mebibytes
}

fn download(allocator: std.mem.Allocator, tf2Maps: std.fs.Dir, mapName: []const u8) !void {
    println("Downloading {s}", .{mapName});
    const file = tf2Maps.createFile(mapName, .{ .exclusive = true }) catch |err| {
        if (err == error.PathAlreadyExists) {
            println("Map is already downloaded - skipping", .{});
            return;
        } else std.debug.panic("Ran into an error while creating the file for {s}, error name: {s}", .{ mapName, @errorName(err) });
    };

    const url = try std.fmt.allocPrint(allocator, downloadUrl, .{mapName});
    const fileData = try httpGet(allocator, url);
    allocator.free(url);
    defer allocator.free(fileData);

    try file.writeAll(fileData);
    println("Downloaded {s}", .{mapName});
}

fn safeDownload(allocator: std.mem.Allocator, tf2Maps: std.fs.Dir, mapName: []const u8) void {
    download(allocator, tf2Maps, mapName) catch |err| std.debug.panic("Failed to download, err: {s}", .{@errorName(err)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    const allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("Memory leak", .{});
        }
    }

    const steamFolder = getSteamFolder(allocator) catch @panic("Could not find Steam via Windows registry");
    defer allocator.free(steamFolder);
    println("Steam folder: {s}", .{steamFolder});

    var tf2Drive = getTF2Folder(allocator, steamFolder) catch @panic("TF2 not installed via Steam library or could not be found in steamapps\\libraryfolders.vdf");
    defer allocator.free(tf2Drive);

    const len = try win.normalizePath(u8, tf2Drive);
    if (allocator.resize(tf2Drive, len))
        tf2Drive = tf2Drive[0..len];

    println("TF2 drive: {s}", .{tf2Drive});

    const tf2Dir = std.fs.openDirAbsolute(tf2Drive, .{}) catch @panic("Could not open the drive you have TF2 installed on, have you changed your drive letter without updating steam?");
    const tf2Maps = tf2Dir.openDir("steamapps\\common\\Team Fortress 2\\tf\\maps", .{}) catch @panic("Could not open TF2 directory, have you manually uninstalled it?");

    const tf2MapsString = try getFolderPath(allocator, tf2Maps.fd);
    println("TF2 map folder: {s}", .{tf2MapsString});
    allocator.free(tf2MapsString);

    // download file and move to this directory with a specific name

    // const cpus = try std.Thread.getCpuCount();
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    for (maps) |map|
        try pool.spawn(safeDownload, .{ allocator, tf2Maps, map });
}
