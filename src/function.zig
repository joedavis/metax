const testing = @import("std").testing;

pub fn ReturnType(f: anytype) type {
    return @typeInfo(@TypeOf(f)).@"fn".return_type.?;
}

test "ReturnType" {
    const Foo = struct {
        fn bar() i32 {
            return 42;
        }
    };
    try testing.expectEqual(ReturnType(Foo.bar), i32);
    try testing.expectEqual(ReturnType(ReturnType), type);
}
