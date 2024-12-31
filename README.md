# metax - Miscellaneous zig metaprogramming features

I enjoy metaprogramming, often to a nerd-sniping extent. This repository is
intended to collect anything useful that comes out of those explorations, as
well as miscellaneous utility functions that the Zig `std` module doesn't
provide.

I do not consider this code to be production quality, but intend to clean it up
at some point in the future.

## `groupBy`

### Example usage:

```zig
const metax = @import("metax");
const std = @import("std");

const Opcode = union(enum) {
    pub const Arity = enum { nullary, unary, binary };

    halt,
    neg,
    inc,
    push: i32,
    drop,
    dup,
    add,
    sub,
    swap,
    print,

    pub fn arity(self: std.meta.Tag(Opcode)) Arity {
        return switch (self) {
            .halt, .push => .nullary,
            .neg, .inc, .dup, .drop, .print => .unary,
            .add, .sub, .swap => .binary,
        };
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ops: []const Opcode = &.{
        .{ .push = 42 },
        .{ .push = 69 },
        .add,
        .dup,
        .dup,
        .print,
        .add,
        .print,
    };

    var stack: std.ArrayListUnmanaged(i32) = .{};
    defer stack.deinit(allocator);

    for (ops) |op| {
        switch (metax.groupBy(op, Opcode.arity)) {
            .nullary => |o| switch (o) {
                .halt => return,
                .push => |i| try stack.append(allocator, i),
            },
            .unary => |o| {
                const x = stack.pop();
                switch (o) {
                    .drop => {},
                    .neg => try stack.append(allocator, -x),
                    .dup => {
                        try stack.append(allocator, x);
                        try stack.append(allocator, x);
                    },
                    .inc => try stack.append(allocator, x + 1),
                    .print => std.debug.print("{}\n", .{x}),
                }
            },
            .binary => |o| {
                const y = stack.pop();
                const x = stack.pop();
                switch (o) {
                    .add => try stack.append(allocator, x + y),
                    .sub => try stack.append(allocator, x - y),
                    .swap => {
                        try stack.append(allocator, y);
                        try stack.append(allocator, x);
                    },
                }
            },
        }
    }
}
```

## `ReturnType`

```zig
fn logCall(s: []const u8, func: anytype, args: anytype) ReturnType(func) {
    std.log.info("{}", s);
    return @call(.auto, func, args);
}
```
