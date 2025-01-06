// TODO: clean this up, it's terrible

const std = @import("std");
const Type = std.builtin.Type;
const meta = std.meta;
const enums = std.enums;
const ReturnType = @import("./function.zig").ReturnType;

fn SubEnum(T: type, comptime distinguisher: anytype) type {
    const Tags = ReturnType(distinguisher);
    const ti = @typeInfo(T);

    var fields: []const Type.UnionField = &.{};
    inline for (meta.fields(Tags)) |f| {
        var inner_fields: []const Type.EnumField = &.{};

        inline for (std.meta.fields(T)) |tf| {
            if (std.mem.eql(
                u8,
                @tagName(distinguisher(@field(T, tf.name))),
                f.name,
            )) {
                inner_fields = inner_fields ++ .{
                    tf,
                };
            }
        }
        const InnerType = @Type(
            .{ .@"enum" = .{
                .tag_type = ti.@"enum".tag_type,
                .fields = inner_fields,
                .decls = &.{},
                .is_exhaustive = true,
            } },
        );
        fields = fields ++ .{Type.UnionField{
            .name = f.name,
            .type = InnerType,
            .alignment = @alignOf(InnerType),
        }};
    }

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = Tags,
        .fields = fields,
        .decls = &.{},
    } });
}

fn FieldTypeByName(T: type, field: [:0]const u8) type {
    return meta.FieldType(T, @field(T, field));
}

fn SubUnion(T: type, comptime distinguisher: anytype) type {
    const Tags = ReturnType(distinguisher);

    var fields: []const Type.UnionField = &.{};
    const SubEnumOfUnionTags = SubEnum(meta.Tag(T), distinguisher);
    const Fields = std.meta.fields(T);
    inline for (meta.fields(Tags)) |f| {
        var inner_fields: []const Type.UnionField = &.{};

        inline for (Fields) |tf| {
            if (std.mem.eql(
                u8,
                @tagName(distinguisher(@field(T, tf.name))),
                f.name,
            )) {
                inner_fields = inner_fields ++ .{
                    tf,
                };
            }
        }
        const InnerType = @Type(
            .{ .@"union" = .{
                .layout = .auto,
                .tag_type = FieldTypeByName(SubEnumOfUnionTags, f.name),
                .fields = inner_fields,
                .decls = &.{},
            } },
        );
        fields = fields ++ .{Type.UnionField{
            .name = f.name,
            .type = InnerType,
            .alignment = @alignOf(InnerType),
        }};
    }

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = Tags,
        .fields = fields,
        .decls = &.{},
    } });
}

fn subTypeBranchQuota(comptime distinguisher: anytype) comptime_int {
    const R = ReturnType(distinguisher);
    const x = std.meta.fields(R).len;
    // Coefficients found experimentally, with an additional thousand added for headroom
    return 15 * (x * x) - 40 * x + 630 + 1000;
}

fn SubType(T: type, comptime distinguisher: anytype) type {
    @setEvalBranchQuota(subTypeBranchQuota(distinguisher));
    return switch (@typeInfo(T)) {
        .@"union" => SubUnion(T, distinguisher),
        .@"enum" => SubEnum(T, distinguisher),
        else => @compileError("only enums and unions are supported"),
    };
}

pub fn groupBy(e: anytype, comptime distinguisher: anytype) SubType(@TypeOf(e), distinguisher) {
    const typ = comptime std.meta.activeTag(@typeInfo(@TypeOf(e)));

    const Sub = SubType(@TypeOf(e), distinguisher);
    inline for (comptime meta.tags(ReturnType(distinguisher))) |tag| {
        if (distinguisher(e) == tag) {
            return @unionInit(
                Sub,
                @tagName(tag),
                switch (typ) {
                    inline .@"union" => brk: {
                        const InnerType = meta.TagPayloadByName(Sub, @tagName(tag));
                        break :brk switch (e) {
                            inline else => |v, t| if (comptime @hasField(InnerType, @tagName(t)))
                                @unionInit(
                                    InnerType,
                                    @tagName(t),
                                    v,
                                )
                            else
                                unreachable,
                        };
                    },
                    inline .@"enum" => std.enums.nameCast(Sub, e),
                    else => @compileError("groupBy only accepts unions or enums"),
                },
            );
        }
    }
    unreachable;
}

test "Union" {
    const Opcode = union(enum) {
        push: i32,
        neg,
        ret,
        add,

        pub const Arity = enum { nullary, unary, binary };

        pub fn arity(tag: std.meta.Tag(@This())) Arity {
            return switch (tag) {
                .push => .nullary,
                .neg, .ret => .unary,
                .add => .binary,
            };
        }
    };

    const ops: []const Opcode = &.{
        .{ .push = 42 },
        .{ .push = 31 },
        .neg,
        .add,
        .ret,
    };
    var stack: std.BoundedArray(i32, 16) = .{};

    var ret: i32 = 0;

    for (ops) |op| {
        switch (groupBy(op, Opcode.arity)) {
            .nullary => |o| switch (o) {
                .push => |val| try stack.append(val),
            },
            .unary => |o| {
                const x = stack.pop();
                switch (o) {
                    .neg => try stack.append(-x),
                    .ret => ret = x,
                }
            },
            .binary => |o| {
                const y = stack.pop();
                const x = stack.pop();
                switch (o) {
                    .add => try stack.append(x + y),
                }
            },
        }
    }

    try std.testing.expectEqual(ret, 11);
}
