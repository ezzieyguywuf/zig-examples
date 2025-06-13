const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    const allocator = tsa.allocator();
    var server = try MyRouterServer.init(allocator);
    defer server.deinit();
    std.debug.print("Server is listening on port 4042\n", .{});

    while (true) {
        std.debug.print("Main thread sleeping for 10s\n", .{});
        std.time.sleep(10 * std.time.ns_per_s);
    }
}

const MyRouterServer = struct {
    const Server = httpz.Server(void);

    server: Server,
    thread: std.Thread,

    pub fn init(allocator: std.mem.Allocator) !MyRouterServer {
        var server = try Server.init(allocator, .{ .port = 4042 }, {});
        var router = try server.router(.{});
        router.post("/foo", handleFoo, .{});
        const thread = try server.listenInNewThread();

        return .{
            .server = server,
            .thread = thread,
        };
    }

    pub fn deinit(self: *MyRouterServer) void {
        self.server.stop();
        self.thread.join();
        self.server.deinit();
    }
};

const MyHandlerServer = struct {
    const Server = httpz.Server(*Handler);

    server: Server,
    thread: std.Thread,
    handler: *Handler,

    pub fn init(allocator: std.mem.Allocator) !MyHandlerServer {
        const handler = try allocator.create(Handler);
        handler.* = Handler{};
        var server = try httpz.Server(*Handler).init(allocator, .{ .port = 4042 }, handler);

        const thread = try server.listenInNewThread();

        return .{
            .server = server,
            .thread = thread,
            .handler = handler,
        };
    }

    pub fn deinit(self: *MyHandlerServer, allocator: std.mem.Allocator) void {
        self.server.stop();
        self.thread.join();
        self.server.deinit();
        allocator.destroy(self.handler);
    }
};

const Handler = struct {
    pub fn handle(_: *Handler, req: *httpz.Request, res: *httpz.Response) void {
        // std.debug.print("Got query: {any}\n", .{req});
        handleFoo(req, res) catch |err| {
            std.debug.print("handlFoo failed: {any}\n", .{err});
        };
        res.status = 200;
        res.json(.{ .message = "Everything groovy" }, .{}) catch |err| {
            std.debug.print("Could not write json, {any}\n", .{err});
        };
        return;
    }
};

fn handleFoo(_: *httpz.Request, res: *httpz.Response) !void {
    std.debug.print("Got query in handleFoo\n", .{});
    try res.json(.{ .message = "request succeeded btw" }, .{});
}

test "HandlerServer success" {
    var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = std.testing.allocator };
    const allocator = tsa.allocator();
    var server = try MyHandlerServer.init(allocator);
    defer server.deinit(allocator);

    // Initialize HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Define URI and request body
    const uri = try std.Uri.parse("http://127.0.0.1:4042/foo");
    var server_headers: [1024]u8 = undefined;

    // This makes our request match the one from curl (including .omit later)
    var request = try client.open(.POST, uri, .{ .server_header_buffer = &server_headers });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    try std.testing.expectEqual(std.http.Status.ok, request.response.status);
}

test "RouterServer failure (returns NotFound)" {
    var tsa = std.heap.ThreadSafeAllocator{ .child_allocator = std.testing.allocator };
    const allocator = tsa.allocator();
    var server = try MyRouterServer.init(allocator);
    defer server.deinit();

    // Initialize HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Define URI and request body
    const uri = try std.Uri.parse("http://127.0.0.1:4042/foo");
    var server_headers: [1024]u8 = undefined;

    // This makes our request match the one from curl (including .omit later)
    var request = try client.open(.POST, uri, .{ .server_header_buffer = &server_headers });
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();

    // want this
    // try std.testing.expectEqual(std.http.Status.ok, request.response.status);
    // but get this
    try std.testing.expectEqual(std.http.Status.not_found, request.response.status);
}
