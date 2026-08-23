const std = @import("std");

const godot = @import("godot_zig");
const root = @import("root.zig");

const Vector3 = godot.Vector3;
const ArrayMesh = godot.generated.classes.ArrayMesh;
const Mesh = godot.Mesh;
const RenderingServer = godot.generated.classes.RenderingServer;

const createArrayMesh = root.createArrayMesh;
const createEmptyArray = root.createEmptyArray;
const createEmptyDictionary = root.createEmtpyDictionary;
const v3subtract = root.v3subtract;
const v3cross = root.v3cross;
const v3addTo = root.v3addTo;
const writeEncodedNormal = root.writeEncodedNormal;

const MESH_ARRAY_FLAG_USE_DYNAMIC_UPDATE: i64 = 67_108_864;
const MIN_SQUASH: f32 = -0.35;
const MAX_SQUASH: f32 = 0.65;

const QuantizedVertexKey = struct {
    x: i64,
    y: i64,
    z: i64,

    fn fromVector3(v: godot.types.Vector3, epsilon: f32) QuantizedVertexKey {
        return .{
            .x = @intFromFloat(@round(v.x / epsilon)),
            .y = @intFromFloat(@round(v.y / epsilon)),
            .z = @intFromFloat(@round(v.z / epsilon)),
        };
    }
};

const SurfaceCache = struct {
    rest_vertices: []Vector3,
    vertices: []Vector3,
    normals: []Vector3,
    indices: []i32,
    normal_groups: []usize,
    normal_sums: []Vector3,
    // Persistent raw position bytes, reused for every deformation update.
    vertex_upload: godot.PackedByteArray,
    // Persistent encoded normal/tangent bytes, also reused on every update.
    normal_upload: godot.PackedByteArray,
    // Byte location of the normal/tangent block inside Godot's vertex buffer.
    normal_offset: i64 = 0,
    // Bytes between consecutive encoded normals (8 when tangents are present).
    normal_stride: usize = 0,

    primitive_type: i64 = 3,
    arrays: godot.Array,
};

const DeformationInfo = struct {
    deformation: f32 = 0.0,
    deformation_velocity: f32 = 0.0,
};

const State = union(enum) {
    at_rest,
    active: DeformationInfo,
};

const Self = @This();

alloc: std.mem.Allocator = std.heap.c_allocator,

surfaces: std.ArrayList(SurfaceCache) = .empty,
rest_center: Vector3 = .{ .x = 0, .y = 0, .z = 0 },
dynamic_mesh: ?ArrayMesh = null,
state: State = .at_rest,

pub fn prime(self: *Self, source_mesh: *const Mesh) !void {
    try self.collectSurfaces(source_mesh);
    self.calculateRestCenter();
    try self.recalculateNormals();
    try self.createDynamicMesh();
}

pub fn mesh(self: *const Self) ?ArrayMesh {
    return self.dynamic_mesh;
}

pub fn excite(self: *Self, deformation_velocity: f32) void {
    switch (self.state) {
        .at_rest => {
            self.state = .{ .active = .{
                .deformation_velocity = deformation_velocity,
            } };
        },
        .active => |*info| {
            info.deformation_velocity += deformation_velocity;
        },
    }
}

pub fn deinit(self: *Self) void {
    for (self.surfaces.items) |*surface| {
        surface.arrays.destroy();
        self.alloc.free(surface.rest_vertices);
        self.alloc.free(surface.vertices);
        self.alloc.free(surface.normals);
        self.alloc.free(surface.indices);
        self.alloc.free(surface.normal_groups);
        self.alloc.free(surface.normal_sums);
        surface.vertex_upload.destroy();
        surface.normal_upload.destroy();
    }

    self.surfaces.deinit(self.alloc);
}

pub fn tick(self: *Self, delta: f64) !void {
    const deformation = switch (self.state) {
        .at_rest => return,
        .active => |*info| blk: {
            simulate(info, delta);
            if (nearlyStopped(info)) {
                break :blk @as(f32, 0.0);
            }
            break :blk info.deformation;
        },
    };

    self.applySquash(deformation);
    try self.recalculateNormals();
    try self.updateDeformedMesh();

    if (deformation == 0.0) {
        self.state = .at_rest;
    }
}

fn collectSurfaces(self: *Self, source_mesh: *const Mesh) !void {
    const surface_count = source_mesh.get_surface_count();

    var surface_i: i64 = 0;
    while (surface_i < surface_count) : (surface_i += 1) {
        var arrays = source_mesh.surface_get_arrays(surface_i);
        errdefer arrays.destroy();

        var packed_vertices = arrays.vertices();
        defer packed_vertices.destroy();

        var packed_indices = arrays.indices();
        defer packed_indices.destroy();

        const vertex_count: usize = @intCast(packed_vertices.size());
        const index_count: usize = @intCast(packed_indices.size());

        if (index_count == 0)
            return error.MeshHasNoIndices;

        // copy
        const rest_vertices = try self.alloc.alloc(Vector3, vertex_count);
        errdefer self.alloc.free(rest_vertices);

        const vertices = try self.alloc.alloc(Vector3, vertex_count);
        errdefer self.alloc.free(vertices);

        const normals = try self.alloc.alloc(Vector3, vertex_count);
        errdefer self.alloc.free(normals);

        const indices = try self.alloc.alloc(i32, index_count);
        errdefer self.alloc.free(indices);

        const normal_groups = try self.alloc.alloc(usize, vertex_count);
        errdefer self.alloc.free(normal_groups);

        for (rest_vertices, 0..) |*vertex, i| {
            vertex.* = packed_vertices.get(@intCast(i));
        }

        @memcpy(vertices, rest_vertices);

        var vertex_upload = godot.PackedByteArray.fromSlice(
            std.mem.sliceAsBytes(vertices),
        );
        errdefer vertex_upload.destroy();

        var normal_upload = godot.PackedByteArray.init();
        errdefer normal_upload.destroy();

        @memset(normals, .{});

        for (indices, 0..) |*index, i| {
            index.* = packed_indices.get(@intCast(i));
        }

        // Build seam-welding groups once. Normal updates reuse these arrays.
        var group_by_position = std.AutoHashMap(QuantizedVertexKey, usize).init(self.alloc);
        defer group_by_position.deinit();

        var group_count: usize = 0;
        for (rest_vertices, 0..) |rest, i| {
            const key = QuantizedVertexKey.fromVector3(rest, 0.0001);
            const entry = try group_by_position.getOrPut(key);
            if (!entry.found_existing) {
                entry.value_ptr.* = group_count;
                group_count += 1;
            }
            normal_groups[i] = entry.value_ptr.*;
        }

        const normal_sums = try self.alloc.alloc(Vector3, group_count);
        errdefer self.alloc.free(normal_sums);
        @memset(normal_sums, .{});

        try self.surfaces.append(self.alloc, .{
            .arrays = arrays,
            .rest_vertices = rest_vertices,
            .vertices = vertices,
            .normals = normals,
            .indices = indices,
            .normal_groups = normal_groups,
            .normal_sums = normal_sums,
            .vertex_upload = vertex_upload,
            .normal_upload = normal_upload,
        });
    }
}

fn calculateRestCenter(self: *Self) void {
    const first = self.surfaces.items[0].rest_vertices[0];

    var min = first;
    var max = first;

    for (self.surfaces.items) |*surface| {
        for (surface.rest_vertices) |*vertex| {
            min.x = @min(min.x, vertex.x);
            min.y = @min(min.y, vertex.y);
            min.z = @min(min.z, vertex.z);

            max.x = @max(max.x, vertex.x);
            max.y = @max(max.y, vertex.y);
            max.z = @max(max.z, vertex.z);
        }
    }

    self.rest_center = .{
        .x = (min.x + max.x) * 0.5,
        .y = (min.y + max.y) * 0.5,
        .z = (min.z + max.z) * 0.5,
    };
}

fn createDynamicMesh(self: *Self) !void {
    const dynamic_mesh = createArrayMesh();

    var blend_shapes = createEmptyArray();
    defer blend_shapes.destroy();

    var lods = createEmptyDictionary();
    defer godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY,
        &lods,
    );

    const rendering_server = RenderingServer.singleton();
    for (self.surfaces.items, 0..) |*surface, surface_i| {
        dynamic_mesh.add_surface_from_arrays(
            surface.primitive_type,
            surface.arrays,
            blend_shapes,
            lods,
            MESH_ARRAY_FLAG_USE_DYNAMIC_UPDATE,
        );

        const format = dynamic_mesh.surface_get_format(@intCast(surface_i));
        surface.normal_stride = @intCast(rendering_server.mesh_surface_get_format_normal_tangent_stride(
            format,
            @intCast(surface.vertices.len),
        ));
        if (surface.normal_upload.resize(@intCast(surface.vertices.len * surface.normal_stride)) != 0) {
            return error.NormalUploadResizeFailed;
        }
        surface.normal_offset = rendering_server.mesh_surface_get_format_offset(
            format,
            @intCast(surface.vertices.len),
            @intFromEnum(godot.Array.MeshArrayType.normal),
        );
    }

    dynamic_mesh.set_custom_aabb(self.deformationSafeAabb());
    self.dynamic_mesh = dynamic_mesh;
}

fn deformationSafeAabb(self: *Self) godot.types.AABB {
    var rest_min = self.surfaces.items[0].rest_vertices[0];
    var rest_max = rest_min;

    for (self.surfaces.items) |surface| {
        for (surface.rest_vertices) |vertex| {
            rest_min.x = @min(rest_min.x, vertex.x);
            rest_min.y = @min(rest_min.y, vertex.y);
            rest_min.z = @min(rest_min.z, vertex.z);
            rest_max.x = @max(rest_max.x, vertex.x);
            rest_max.y = @max(rest_max.y, vertex.y);
            rest_max.z = @max(rest_max.z, vertex.z);
        }
    }

    const transverse_max = 1.0 / @sqrt(1.0 - MAX_SQUASH);
    const axial_max = 1.0 - MIN_SQUASH;
    const safe_min = Vector3{
        .x = self.rest_center.x + (rest_min.x - self.rest_center.x) * transverse_max,
        .y = self.rest_center.y + (rest_min.y - self.rest_center.y) * axial_max,
        .z = self.rest_center.z + (rest_min.z - self.rest_center.z) * transverse_max,
    };
    const safe_max = Vector3{
        .x = self.rest_center.x + (rest_max.x - self.rest_center.x) * transverse_max,
        .y = self.rest_center.y + (rest_max.y - self.rest_center.y) * axial_max,
        .z = self.rest_center.z + (rest_max.z - self.rest_center.z) * transverse_max,
    };

    return .{
        .position = safe_min,
        .size = v3subtract(safe_max, safe_min),
    };
}

fn simulate(info: *DeformationInfo, delta: f64) void {
    const angular_frequency: f32 = 12.0;
    const damping_ratio: f32 = 0.25;
    const dt: f32 = @floatCast(delta);

    const acceleration =
        -angular_frequency * angular_frequency * info.deformation -
        2.0 * damping_ratio * angular_frequency * info.deformation_velocity;

    // Semi-implicit Euler: update velocity before displacement. This is
    // more stable for a spring than updating displacement first.
    info.deformation_velocity += acceleration * dt;
    info.deformation += info.deformation_velocity * dt;
}

fn nearlyStopped(info: *const DeformationInfo) bool {
    return @abs(info.deformation) < 0.0005 and
        @abs(info.deformation_velocity) < 0.005;
}

fn applySquash(self: *Self, squash: f32) void {
    const safe_squash = @min(@max(squash, MIN_SQUASH), MAX_SQUASH);
    const axial = 1.0 - safe_squash;
    const transverse = 1.0 / @sqrt(axial);

    for (self.surfaces.items) |surface| {
        for (
            surface.rest_vertices,
            surface.vertices,
        ) |rest, *out| {
            const offset = Vector3{
                .x = rest.x - self.rest_center.x,
                .y = rest.y - self.rest_center.y,
                .z = rest.z - self.rest_center.z,
            };

            out.* = .{
                .x = self.rest_center.x + offset.x * transverse,
                .y = self.rest_center.y + offset.y * axial,
                .z = self.rest_center.z + offset.z * transverse,
            };
        }
    }
}

fn recalculateNormals(self: *Self) !void {
    for (self.surfaces.items) |surface| {
        @memset(surface.normals, .{});

        var i: usize = 0;
        while (i + 2 < surface.indices.len) : (i += 3) {
            const raw_a = surface.indices[i];
            const raw_b = surface.indices[i + 1];
            const raw_c = surface.indices[i + 2];

            if (raw_a < 0 or raw_b < 0 or raw_c < 0)
                return error.InvalidMeshIndex;

            const a: usize = @intCast(raw_a);
            const b: usize = @intCast(raw_b);
            const c: usize = @intCast(raw_c);

            if (a >= surface.vertices.len or
                b >= surface.vertices.len or
                c >= surface.vertices.len)
            {
                return error.InvalidMeshIndex;
            }

            const ab = v3subtract(
                surface.vertices[b],
                surface.vertices[a],
            );

            const ac = v3subtract(
                surface.vertices[c],
                surface.vertices[a],
            );

            const face_normal = v3cross(ac, ab);

            v3addTo(&surface.normals[a], face_normal);
            v3addTo(&surface.normals[b], face_normal);
            v3addTo(&surface.normals[c], face_normal);
        }

        @memset(surface.normal_sums, .{});

        for (surface.normals, surface.normal_groups) |normal, group| {
            v3addTo(&surface.normal_sums[group], normal);
        }

        for (surface.normals, surface.normal_groups) |*normal, group| {
            normal.* = surface.normal_sums[group].normalized();
        }
    }
}

fn updateDeformedMesh(self: *Self) !void {
    const dynamic_mesh = self.dynamic_mesh orelse return error.DynamicMeshNotCreated;

    for (self.surfaces.items, 0..) |*surface, surface_i| {
        const bytes = std.mem.sliceAsBytes(surface.vertices);

        for (bytes, 0..) |byte, byte_i| {
            surface.vertex_upload.set(@intCast(byte_i), byte);
        }

        // Positions begin at byte zero in Godot's vertex buffer.
        dynamic_mesh.surface_update_vertex_region(
            @intCast(surface_i),
            0,
            surface.vertex_upload,
        );

        for (surface.normals, 0..) |normal, normal_i| {
            writeEncodedNormal(
                &surface.normal_upload,
                normal_i,
                surface.normal_stride,
                normal,
            );
        }

        // Despite its name, this updates any byte range in the vertex
        // buffer. Godot locates the normal/tangent block by this offset.
        dynamic_mesh.surface_update_vertex_region(
            @intCast(surface_i),
            surface.normal_offset,
            surface.normal_upload,
        );
    }
}
