const std = @import("std");
const cURL = @cImport({
    @cInclude("curl/curl.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();

    const allocator = arena_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len < 2) {
        try stdout.print("ffetch - fetch fetch\n{s} to={{file}} {{url}}\n{s} {{url}}\n", .{ args[0], args[0] });
        std.os.exit(1);
    }

    var to: []const u8 = "";
    var val: []const u8 = "";
    _ = val;

    for (args[0..]) |argument| {
        if (argument.len >= 2 and std.mem.eql(u8, argument[0..3], "to=")) {
            if (args.len < 3) {
                try stdout.print("expected url after to={{file}} specifier\n", .{});
                std.os.exit(1);
            }

            to = argument[3..];
        }
    }

    if (to.len > 0 and args.len < 3) {
        try stdout.print("expected url after to={{file}} specifier\n", .{});
        std.os.exit(1);
    }

    if (cURL.curl_global_init(cURL.CURL_GLOBAL_ALL) != cURL.CURLE_OK)
        return error.CURLGlobalInitFailed;
    defer cURL.curl_global_cleanup();

    const handle = cURL.curl_easy_init() orelse return error.CURLHandleInitFailed;
    defer cURL.curl_easy_cleanup(handle);

    var response_buffer = std.ArrayList(u8).init(allocator);
    defer response_buffer.deinit();

    if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_URL, @ptrCast([*]const u8, args[args.len - 1])) != cURL.CURLE_OK)
        return error.CouldNotSetURL;

    if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_WRITEFUNCTION, writeToArrayListCallback) != cURL.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (cURL.curl_easy_setopt(handle, cURL.CURLOPT_WRITEDATA, &response_buffer) != cURL.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (cURL.curl_easy_perform(handle) != cURL.CURLE_OK)
        return error.FailedToPerformRequest;

    if (to.len > 0) {
        var file_stream = try std.fs.cwd().createFile(to, .{});
        defer file_stream.close();

        try file_stream.writeAll(response_buffer.items);
    } else {
        try stdout.print("{s}", .{response_buffer.items});
    }
}

fn writeToArrayListCallback(data: *anyopaque, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.C) c_uint {
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}
