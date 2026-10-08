const std = @import("std");
const godot = @import("godot_zig");

const Node = godot.generated.classes.Node;
const Node3D = godot.generated.classes.Node3D;
const Mesh = godot.generated.classes.Mesh;
const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const ArrayMesh = godot.generated.classes.ArrayMesh;
const Vector2 = godot.Vector2;
const Vector3 = godot.Vector3;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

const MAX_SAMPLES: usize = 12;
const MAX_VERTICES: usize = (MAX_SAMPLES - 1) * 6;
const TRAIL_UVS = createTrailUvs();

fn createTrailUvs() [MAX_VERTICES]Vector2 {
    var result = [_]Vector2{.{}} ** MAX_VERTICES;
    const segment_count: f32 = @floatFromInt(MAX_SAMPLES - 1);

    for (0..MAX_SAMPLES - 1) |i| {
        const vertex_i = i * 6;
        const uv_start: f32 = @as(f32, @floatFromInt(i)) / segment_count;
        const uv_end: f32 = @as(f32, @floatFromInt(i + 1)) / segment_count;

        result[vertex_i + 0] = .{ .x = uv_start, .y = 0.0 };
        result[vertex_i + 1] = .{ .x = uv_start, .y = 1.0 };
        result[vertex_i + 2] = .{ .x = uv_end, .y = 0.0 };
        result[vertex_i + 3] = .{ .x = uv_end, .y = 0.0 };
        result[vertex_i + 4] = .{ .x = uv_start, .y = 1.0 };
        result[vertex_i + 5] = .{ .x = uv_end, .y = 1.0 };
    }

    return result;
}

const Sample = struct {
    base: Vector3,
    tip: Vector3,
};

pub const RuntimeNames = struct {
    ready: godot.StringName,
    process: godot.StringName,
    blade_base_path: godot.NodePath,
    blade_tip_path: godot.NodePath,
    trail_path: godot.NodePath,
    trail_core_path: godot.NodePath,

    pub fn init() RuntimeNames {
        return .{
            .ready = godot.api.godot.stringName("_ready"),
            .process = godot.api.godot.stringName("_process"),
            .blade_base_path = godot.api.godot.nodePath("Model/BladeBase"),
            .blade_tip_path = godot.api.godot.nodePath("Model/BladeTip"),
            .trail_path = godot.api.godot.nodePath("SwingTrail"),
            .trail_core_path = godot.api.godot.nodePath("SwingTrailCore"),
        };
    }

    pub fn deinit(self: *RuntimeNames) void {
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.ready);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.process);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.blade_base_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.blade_tip_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.trail_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.trail_core_path);
    }
};

object: godot.c.GDExtensionObjectPtr,
show_trail: bool = false,
since_last_eviction: f64 = 0.0,
names: *RuntimeNames,
blade_base: ?Node3D = null,
blade_tip: ?Node3D = null,
trail_mesh: ?ArrayMesh = null,
samples: [MAX_SAMPLES]Sample = undefined,
sample_count: usize = 0,
vertices: [MAX_VERTICES]Vector3 = [_]Vector3{.{}} ** MAX_VERTICES,
vertex_upload: ?godot.PackedByteArray = null,

pub fn initWithUserdata(object: godot.c.GDExtensionObjectPtr, class_userdata: ?*anyopaque) Self {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    return .{
        .object = object,
        .names = names,
    };
}

pub fn deinit(self: *Self) void {
    if (self.vertex_upload) |*upload| {
        upload.destroy();
    }
    self.vertex_upload = null;
}

pub fn ready(self: *Self) callconv(.c) void {
    const node = Node.init(self.object);
    node.set_process(true);

    const base_node = node.get_node(self.names.blade_base_path);
    const tip_node = node.get_node(self.names.blade_tip_path);
    const trail_node = node.get_node(self.names.trail_path);
    const core_node = node.get_node(self.names.trail_core_path);

    if (base_node.isNull() or tip_node.isNull() or trail_node.isNull() or core_node.isNull()) {
        const message = "Sword trail nodes are missing";
        util.log(message);
        @panic(message);
    }

    self.blade_base = Node3D.init(base_node.asObject().ptr);
    self.blade_tip = Node3D.init(tip_node.asObject().ptr);

    const trail_visual = MeshInstance3D.init(trail_node.asObject().ptr);
    const core_visual = MeshInstance3D.init(core_node.asObject().ptr);
    const mesh = util.createArrayMesh();

    trail_visual.set_mesh(Mesh.init(mesh.asObject().ptr));
    core_visual.set_mesh(Mesh.init(mesh.asObject().ptr));

    // Both layers share world-space vertices. Ignore the sword's transform.
    for ([_]godot.c.GDExtensionObjectPtr{ trail_node.asObject().ptr, core_node.asObject().ptr }) |visual_node| {
        const transform = Node3D.init(visual_node);
        transform.set_as_top_level(true);
        transform.set_identity();
    }

    self.trail_mesh = mesh;
    self.createTrailSurface();
}

fn createTrailSurface(self: *Self) void {
    const mesh = self.trail_mesh orelse return;

    var packed_vertices = godot.PackedVector3Array.fromSlice(self.vertices[0..]);
    defer packed_vertices.destroy();

    var packed_uvs = godot.PackedVector2Array.fromSlice(TRAIL_UVS[0..]);
    defer packed_uvs.destroy();

    var arrays = util.createMeshArray();
    defer arrays.destroy();
    arrays.setPackedVector3Array(.vertex, &packed_vertices);
    arrays.setPackedVector2Array(.tex_uv, &packed_uvs);

    var blend_shapes = util.createEmptyArray();
    defer blend_shapes.destroy();

    var lods = util.createEmptyDictionary();
    defer godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY,
        &lods,
    );

    mesh.add_surface_from_arrays(
        Mesh.PrimitiveType.triangles,
        arrays,
        blend_shapes,
        lods,
        Mesh.ArrayFormat.flag_use_dynamic_update,
    );

    self.vertex_upload = godot.PackedByteArray.fromSlice(
        std.mem.sliceAsBytes(self.vertices[0..]),
    );
}

pub fn process(self: *Self, delta: f64) callconv(.c) void {
    const EVICTION_THRESHOLD: f64 = 0.05;

    // TODO: this might look really jarring. we should probably do this on the shader level
    if (!self.show_trail) {
        if (self.since_last_eviction > EVICTION_THRESHOLD and self.sample_count > 0) {
            self.since_last_eviction = 0.0;
            self.evictSample();
        } else {
            self.since_last_eviction += delta;
        }

        self.updateTrail();
        return;
    }

    const blade_base = self.blade_base orelse return;
    const blade_tip = self.blade_tip orelse return;

    self.pushSample(.{
        .base = blade_base.get_global_position(),
        .tip = blade_tip.get_global_position(),
    });
    self.updateTrail();
}

fn pushSample(self: *Self, sample: Sample) void {
    if (self.sample_count < MAX_SAMPLES) {
        self.samples[self.sample_count] = sample;
        self.sample_count += 1;
        return;
    }

    @memmove(
        self.samples[0 .. MAX_SAMPLES - 1],
        self.samples[1..MAX_SAMPLES],
    );
    self.samples[MAX_SAMPLES - 1] = sample;
}

fn evictSample(self: *Self) void {
    self.sample_count -= 1;
}

fn updateTrail(self: *Self) void {
    if (self.sample_count == 0) return;

    var vertex_count: usize = 0;
    if (self.sample_count >= 2) {
        for (0..self.sample_count - 1) |i| {
            const old = self.samples[i];
            const new = self.samples[i + 1];

            self.vertices[vertex_count + 0] = old.base;
            self.vertices[vertex_count + 1] = old.tip;
            self.vertices[vertex_count + 2] = new.base;

            self.vertices[vertex_count + 3] = new.base;
            self.vertices[vertex_count + 4] = old.tip;
            self.vertices[vertex_count + 5] = new.tip;

            vertex_count += 6;
        }
    }

    // The GPU surface has a fixed size. Degenerate all unused triangles so
    // they do not render while the sample history is filling.
    const collapse_point = self.samples[self.sample_count - 1].tip;
    for (self.vertices[vertex_count..]) |*vertex| {
        vertex.* = collapse_point;
    }

    self.uploadVertices();
}

fn uploadVertices(self: *Self) void {
    const mesh = self.trail_mesh orelse return;
    const upload = if (self.vertex_upload) |*value| value else return;
    const bytes = std.mem.sliceAsBytes(self.vertices[0..]);

    for (bytes, 0..) |byte, i| {
        upload.set(@intCast(i), byte);
    }

    // Positions occupy the first bytes of this vertex-only surface.
    mesh.surface_update_vertex_region(0, 0, upload.*);
    self.updateBounds(mesh);
}

fn updateBounds(self: *Self, mesh: ArrayMesh) void {
    if (self.sample_count == 0) return;

    var min = self.samples[0].base;
    var max = min;

    for (self.samples[0..self.sample_count]) |sample| {
        for ([_]Vector3{ sample.base, sample.tip }) |point| {
            min.x = @min(min.x, point.x);
            min.y = @min(min.y, point.y);
            min.z = @min(min.z, point.z);
            max.x = @max(max.x, point.x);
            max.y = @max(max.y, point.y);
            max.z = @max(max.z, point.z);
        }
    }

    const padding: f32 = 0.1;
    mesh.set_custom_aabb(.{
        .position = .{
            .x = min.x - padding,
            .y = min.y - padding,
            .z = min.z - padding,
        },
        .size = .{
            .x = max.x - min.x + padding * 2.0,
            .y = max.y - min.y + padding * 2.0,
            .z = max.z - min.z + padding * 2.0,
        },
    });
}

pub fn getVirtualCallData(
    class_userdata: ?*anyopaque,
    name: godot.c.GDExtensionConstStringNamePtr,
    _: u32,
) callconv(.c) ?*anyopaque {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    if (stringNameEqual(name, &names.ready)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &names.process)) return @ptrCast(@constCast(&process));
    return null;
}

pub fn callVirtualWithData(
    instance: godot.c.GDExtensionClassInstancePtr,
    _: godot.c.GDExtensionConstStringNamePtr,
    userdata: ?*anyopaque,
    args: [*c]const godot.c.GDExtensionConstTypePtr,
    ret: godot.c.GDExtensionTypePtr,
) callconv(.c) void {
    _ = ret;
    const self: *Self = @ptrCast(@alignCast(instance.?));

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&ready)))) {
        ready(self);
        return;
    }

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&process)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        process(self, delta.*);
    }
}
