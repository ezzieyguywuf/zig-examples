const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush();
}

const MyServer = struct {
    const Server = httpz.Server(void);

    server: Server,
    thread: std.Thread,

    pub fn init(allocator: std.mem.Allocator) !MyServer {
        var server = try Server.init(allocator, .{ .port = 4042 }, {});
        var router = try server.router(.{});
        router.post("/foo", handleFoo, .{});
        const thread = try server.listenInNewThread();

        return .{
            .server = server,
            .thread = thread,
        };
    }

    pub fn deinit(self: *MyServer) void {
        self.server.stop();
        self.thread.join();
        self.server.deinit();
    }
};

fn handleFoo(_: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("Got query\n", .{});
    try res.json(.{ .message = "request succeeded btw" }, .{});
}

test "why does this crash" {
    var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = std.testing.allocator };
    const allocator = tsa.allocator();
    var server = try MyServer.init(allocator);
    defer server.deinit();

    // Initialize HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // this lets us try the server with curl
    // curl -X POST http://127.0.0.1:4042/foo
    std.debug.print("server is listening on 4042, sleeping for 10s\n", .{});
    std.time.sleep(10 * std.time.ns_per_s);

    // Define URI and request body
    const uri = try std.Uri.parse("http://127.0.0.1:4042/foo");
    var server_headers: [1024]u8 = undefined;

    // This makes our request match the one from curl (including .omit later)
    const extra_headers = [_]std.http.Header{
        .{ .name = "Host", .value = "127.0.0.1:4042" },
        .{ .name = "User-Agent", .value = "curl/8.13.0" },
        .{ .name = "Accept", .value = "*/*" },
    };
    var request = try client.open(.POST, uri, .{
        .server_header_buffer = &server_headers,
        .headers = .{
            .host = .omit,
            .accept_encoding = .omit,
            .connection = .omit,
            .user_agent = .omit,
        },
        .extra_headers = &extra_headers,
    });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    std.debug.print("Status: {}\n", .{request.response.status});
    var body_buffer: [1024]u8 = undefined;
    _ = try request.read(&body_buffer);
    std.debug.print("{s}\n", .{body_buffer});
}
