const std = @import("std");
const Allocator = std.mem.Allocator;

const loc = @import("../loc.zig");
const Range = loc.Range;
const WithRange = loc.WithRange;
const ty = @import("../ty.zig");

const Expr = @This();

payload: Payload,
range: Range,

pub fn init(payload: Payload, range: Range) Expr {
    return .{ .payload = payload, .range = range };
}

pub fn deinit(self: Expr, allocator: Allocator) void {
    self.payload.deinit(allocator);
}

pub fn deinitSlice(allocator: Allocator, ex: []const Expr) void {
    for (ex) |e| e.deinit(allocator);
    allocator.free(ex);
}

pub fn formatAst(self: Expr, indent: usize, writer: anytype) !void {
    try self.payload.formatAst(indent, writer);
}

pub const Op = enum {
    const Self = @This();

    add,
    mul,
    fdiv,
    idiv,
    sub,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    @"and",
    @"or",
    xor,
    mod,
};

pub const Payload = union(enum) {
    const Self = @This();

    imm_integer: i16,
    imm_long: i32,
    imm_single: f32,
    imm_double: f64,
    imm_string: []const u8,
    label: []const u8,
    binop: struct {
        lhs: *const Expr,
        op: WithRange(Op),
        rhs: *const Expr,
    },
    // This doesn't need to exist at all, except right now our pretty-printer
    // doesn't know when an expression needs to be parenthesised/it does if we
    // want to preserve the user's formatting. AST CST blahST DST
    paren: *const Expr,
    negate: *const Expr,

    // Used by:
    // * FOR...NEXT's default STEP.
    // * Tests when zero values are too divide-by-zero-y.
    pub fn oneImm(@"type": ty.Type) Self {
        return switch (@"type") {
            .integer => .{ .imm_integer = 1 },
            .long => .{ .imm_long = 1 },
            .single => .{ .imm_single = 1 },
            .double => .{ .imm_double = 1 },
            .string => .{ .imm_string = "a" },
        };
    }

    pub fn formatAst(self: Self, indent: usize, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            .imm_integer => |n| try std.fmt.format(writer, "Integer({d})", .{n}),
            .imm_long => |n| try std.fmt.format(writer, "Long({d})", .{n}),
            .imm_single => |n| try std.fmt.format(writer, "Single({d})", .{n}),
            .imm_double => |n| try std.fmt.format(writer, "Double({d})", .{n}),
            .imm_string => |s| try std.fmt.format(writer, "String({s})", .{s}),
            .label => |l| try std.fmt.format(writer, "Label({s})", .{l}),
            .binop => |b| {
                try std.fmt.format(writer, "Binop({s})\n", .{@tagName(b.op.payload)});
                try writer.writeBytesNTimes("  ", indent + 1);
                try b.lhs.formatAst(indent + 1, writer);
                try writer.writeByte('\n');
                try writer.writeBytesNTimes("  ", indent + 1);
                try b.rhs.formatAst(indent + 1, writer);
            },
            .paren => |e| {
                try writer.writeAll("Paren\n");
                try writer.writeBytesNTimes("  ", indent + 1);
                try e.formatAst(indent + 1, writer);
            },
            .negate => |e| {
                try writer.writeAll("Negate\n");
                try writer.writeBytesNTimes("  ", indent + 1);
                try e.formatAst(indent + 1, writer);
            },
            // else => unreachable,
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .imm_integer => {},
            .imm_long => {},
            .imm_single => {},
            .imm_double => {},
            .imm_string => {},
            .label => {},
            .binop => |b| {
                b.lhs.deinit(allocator);
                b.rhs.deinit(allocator);
                allocator.destroy(b.lhs);
                allocator.destroy(b.rhs);
            },
            .paren, .negate => |e| {
                e.deinit(allocator);
                allocator.destroy(e);
            },
        }
    }
};
