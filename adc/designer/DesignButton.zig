const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignDialog = @import("./DesignDialog.zig");

const DesignButton = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    parent: *DesignDialog.Impl,

    // state
    r1: usize,
    c1: usize,
    label: std.ArrayListUnmanaged(u8),
    primary: bool,
    cancel: bool,

    r2: usize = undefined,
    c2: usize = undefined,
    label_orig: std.ArrayListUnmanaged(u8) = .{},

    state: union(enum) {
        idle,
        move: struct { origin_row: usize, origin_col: usize },
        label_edit,
    } = .idle,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .parent = parent,
                .deinit = deinit,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: []const u8, _: bool, _: bool) void {
        self.r2 = self.r1 + 1;
        self.c2 = self.c1 + 4 + self.label.items.len;

        const r1 = self.parent.r1 + self.r1;
        const r2 = self.parent.r1 + self.r2;
        const c1 = self.parent.c1 + self.c1;
        const c2 = self.parent.c1 + self.c2;

        if (self.primary) {
            self.imtui.text_mode.paintColour(r1, c1, r2, c1 + 1, 0x7f, .fill);
            self.imtui.text_mode.paintColour(r1, c2 - 1, r2, c2, 0x7f, .fill);
        }

        self.imtui.text_mode.write(r1, c1, "<");
        self.imtui.text_mode.writeAccelerated(r1, c1 + 2, self.label.items, true);
        self.imtui.text_mode.write(r1, c2 - 1, ">");

        switch (self.state) {
            .idle => {
                if (self.imtui.focus_stack.items.len > 1)
                    return;

                // XXX: The below isn't aware of DesignDialog.state
                // == .title_edit, for example. (the above doesn't catch it
                // because it doesn't add a new focus item)

                var highlighted = false;
                if (!highlighted and
                    self.imtui.text_mode.mouse_row == self.parent.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.parent.c1 + self.c1 + 1 and
                    self.imtui.text_mode.mouse_col < self.parent.c1 + self.c2 - 1)
                {
                    self.imtui.text_mode.paintColour(
                        self.parent.r1 + self.r1,
                        self.parent.c1 + self.c1 + 1,
                        self.parent.r1 + self.r1 + 1,
                        self.parent.c1 + self.c2 - 1,
                        0x20,
                        .fill,
                    );
                    highlighted = true;
                }

                if (!highlighted and
                    self.imtui.text_mode.mouse_row == self.parent.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.parent.c1 + self.c1 and
                    self.imtui.text_mode.mouse_col < self.parent.c1 + self.c2)
                {
                    self.imtui.text_mode.paintColour(
                        self.parent.r1 + self.r1 - 1,
                        self.parent.c1 + self.c1 - 1,
                        self.parent.r1 + self.r2 + 1,
                        self.parent.c1 + self.c2 + 1,
                        0x20,
                        .outline,
                    );
                    highlighted = true;
                }
            },
            .move => |_| {},
            .label_edit => {
                self.imtui.text_mode.cursor_row = self.parent.r1 + self.r1;
                self.imtui.text_mode.cursor_col = self.parent.c1 + self.c1 + 2 + self.label.items.len;
                self.imtui.text_mode.cursor_inhibit = false;
            },
        }
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.parent.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.label.deinit(self.imtui.allocator);
        self.label_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (self.state) {
            .move => {},
            .label_edit => {
                switch (keycode) {
                    .backspace => if (self.label.items.len > 0) {
                        if (modifiers.get(.left_control) or modifiers.get(.right_control))
                            self.label.items.len = 0
                        else
                            self.label.items.len -= 1;
                    },
                    .@"return" => {
                        self.state = .idle;
                        self.imtui.unfocus(self.control());
                    },
                    .escape => {
                        self.state = .idle;
                        self.imtui.unfocus(self.control());
                        try self.label.replaceRange(self.imtui.allocator, 0, self.label.items.len, self.label_orig.items);
                    },
                    else => if (Imtui.Controls.isPrintableKey(keycode)) {
                        try self.label.append(self.imtui.allocator, Imtui.Controls.getCharacter(keycode, modifiers));
                    },
                }
                return;
            },
            else => unreachable,
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.state == .label_edit or
            (self.imtui.mouse_row >= self.parent.r1 + self.r1 and self.imtui.mouse_row < self.parent.r1 + self.r2 and
            self.imtui.mouse_col >= self.parent.c1 + self.c1 and self.imtui.mouse_col < self.parent.c1 + self.c2);
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        if (cm) return null;
        if (!isMouseOver(ptr))
            return self.imtui.fallbackMouseDown(b, clicks, cm);
        if (b != .left) return null;

        switch (self.state) {
            .idle => {
                if (self.imtui.text_mode.mouse_row == self.parent.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.parent.c1 + self.c1 + 1 and
                    self.imtui.text_mode.mouse_col < self.parent.c1 + self.c2 - 1)
                {
                    try self.label_orig.replaceRange(self.imtui.allocator, 0, self.label_orig.items.len, self.label.items);
                    self.state = .label_edit;
                    try self.imtui.focus(self.control());
                    return null;
                }

                if (self.imtui.text_mode.mouse_row == self.parent.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.parent.c1 + self.c1 and
                    self.imtui.text_mode.mouse_col < self.parent.c1 + self.c2)
                {
                    self.state = .{ .move = .{
                        .origin_row = self.imtui.text_mode.mouse_row,
                        .origin_col = self.imtui.text_mode.mouse_col,
                    } };
                    try self.imtui.focus(self.control());
                    return self.control();
                }

                unreachable;
            },
            .label_edit => {
                if (!(self.imtui.text_mode.mouse_row == self.parent.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.parent.c1 + self.c1 + 1 and
                    self.imtui.text_mode.mouse_col < self.parent.c1 + self.c2 - 1))
                {
                    self.state = .idle;
                    self.imtui.unfocus(self.control());
                }

                return null;
            },
            else => return null,
        }
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        switch (self.state) {
            .move => |*d| {
                const dr = @as(isize, @intCast(self.imtui.text_mode.mouse_row)) - @as(isize, @intCast(d.origin_row));
                const dc = @as(isize, @intCast(self.imtui.text_mode.mouse_col)) - @as(isize, @intCast(d.origin_col));
                const r1: isize = @as(isize, @intCast(self.r1)) + dr;
                const c1: isize = @as(isize, @intCast(self.c1)) + dc;
                const r2: isize = @as(isize, @intCast(self.r2)) + dr;
                const c2: isize = @as(isize, @intCast(self.c2)) + dc;
                if (r1 > 0 and r2 < self.parent.r2 - self.parent.r1) {
                    self.r1 = @intCast(r1);
                    self.r2 = @intCast(r2);
                    d.origin_row = @intCast(@as(isize, @intCast(d.origin_row)) + dr);
                }
                if (c1 > 0 and c2 < self.parent.c2 - self.parent.c1) {
                    self.c1 = @intCast(c1);
                    self.c2 = @intCast(c2);
                    d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
                }
            },
            else => unreachable,
        }
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        switch (self.state) {
            .move => {
                self.state = .idle;
                self.imtui.unfocus(self.control());
            },
            else => unreachable,
        }
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignDialog.Impl, ix: usize, _: usize, _: usize, _: []const u8, _: bool, _: bool) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignButton", ix });
}

pub fn create(imtui: *Imtui, parent: *DesignDialog.Impl, ix: usize, r1: usize, c1: usize, label: []const u8, primary: bool, cancel: bool) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .parent = parent,
        .r1 = r1,
        .c1 = c1,
        .label = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, label)),
        .primary = primary,
        .cancel = cancel,
    };
    d.describe(parent, ix, r1, c1, label, primary, cancel);
    return .{ .impl = d };
}

pub const Schema = struct {
    r1: usize,
    c1: usize,
    label: []const u8,
    primary: bool,
    cancel: bool,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.label);
    }
};

pub fn sync(self: DesignButton, allocator: Allocator, schema: *Schema) !void {
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    if (!std.mem.eql(u8, schema.label, self.impl.label.items)) {
        allocator.free(schema.label);
        schema.label = try allocator.dupe(u8, self.impl.label.items);
    }
}
