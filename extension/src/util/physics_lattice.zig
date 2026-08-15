const std = @import("std");
const godot = @import("godot_zig");

const Vector3 = godot.Vector3;

pub const lattice_segments_on_longest_axis: usize = 6;

pub const Particle = struct {
    rest_position: Vector3,
    position: Vector3,
    previous_position: Vector3,
    velocity: Vector3 = .{},
    inverse_mass: f32 = 1.0,
};

pub const Spring = struct {
    a: usize,
    b: usize,
    rest_length: f32,
};

pub const RenderVertexBinding = struct {
    /// Base lattice cell coordinate. The vertex is influenced by the 8 lattice
    /// particles at base + (0/1, 0/1, 0/1).
    cell_x: usize,
    cell_y: usize,
    cell_z: usize,
    weights: [8]f32,
};

pub const PhysicsLattice = struct {
    min: Vector3,
    max: Vector3,
    dims: [3]usize,
    particles: std.ArrayList(Particle),
    springs: std.ArrayList(Spring),
    vertex_bindings: std.ArrayList(RenderVertexBinding),
};

fn vec3Sub(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn vec3Distance(a: Vector3, b: Vector3) f32 {
    return vec3Sub(a, b).length();
}

fn latticeIndex(x: usize, y: usize, z: usize, dims: [3]usize) usize {
    return (z * dims[1] + y) * dims[0] + x;
}

fn axisDim(size: f32, spacing: f32) usize {
    if (size <= 0.0 or spacing <= 0.0) return 2;
    return @max(@as(usize, 2), @as(usize, @intFromFloat(@ceil(size / spacing))) + 1);
}

const CellCoord = struct { base: usize, frac: f32 };

fn cellCoord(value: f32, min: f32, max: f32, dim: usize) CellCoord {
    if (dim <= 1 or max <= min) return .{ .base = 0, .frac = 0.0 };

    const scaled = (value - min) / (max - min) * @as(f32, @floatFromInt(dim - 1));
    const max_base = dim - 2;
    if (scaled <= 0.0) return .{ .base = 0, .frac = 0.0 };
    if (scaled >= @as(f32, @floatFromInt(max_base))) return .{ .base = max_base, .frac = 1.0 };

    const base: usize = @intFromFloat(@floor(scaled));
    return .{ .base = base, .frac = scaled - @as(f32, @floatFromInt(base)) };
}

fn makeVertexBinding(v: Vector3, min: Vector3, max: Vector3, dims: [3]usize) RenderVertexBinding {
    const cx = cellCoord(v.x, min.x, max.x, dims[0]);
    const cy = cellCoord(v.y, min.y, max.y, dims[1]);
    const cz = cellCoord(v.z, min.z, max.z, dims[2]);

    const fx = cx.frac;
    const fy = cy.frac;
    const fz = cz.frac;

    return .{
        .cell_x = cx.base,
        .cell_y = cy.base,
        .cell_z = cz.base,
        .weights = .{
            (1.0 - fx) * (1.0 - fy) * (1.0 - fz),
            fx * (1.0 - fy) * (1.0 - fz),
            (1.0 - fx) * fy * (1.0 - fz),
            fx * fy * (1.0 - fz),
            (1.0 - fx) * (1.0 - fy) * fz,
            fx * (1.0 - fy) * fz,
            (1.0 - fx) * fy * fz,
            fx * fy * fz,
        },
    };
}

pub fn buildPhysicsLattice(alloc: std.mem.Allocator, vertices: []const Vector3) !PhysicsLattice {
    if (vertices.len == 0) return error.EmptyMesh;

    var min = vertices[0];
    var max = vertices[0];
    for (vertices[1..]) |v| {
        min.x = @min(min.x, v.x);
        min.y = @min(min.y, v.y);
        min.z = @min(min.z, v.z);
        max.x = @max(max.x, v.x);
        max.y = @max(max.y, v.y);
        max.z = @max(max.z, v.z);
    }

    var size = vec3Sub(max, min);
    const longest = @max(@max(size.x, size.y), size.z);
    const padding = @max(longest * 0.02, 0.001);
    min.x -= padding;
    min.y -= padding;
    min.z -= padding;
    max.x += padding;
    max.y += padding;
    max.z += padding;
    size = vec3Sub(max, min);

    const spacing = @max(@max(size.x, @max(size.y, size.z)) / @as(f32, @floatFromInt(lattice_segments_on_longest_axis)), 0.001);
    const dims = .{ axisDim(size.x, spacing), axisDim(size.y, spacing), axisDim(size.z, spacing) };

    var particles: std.ArrayList(Particle) = .empty;
    errdefer particles.deinit(alloc);
    var springs: std.ArrayList(Spring) = .empty;
    errdefer springs.deinit(alloc);
    var vertex_bindings: std.ArrayList(RenderVertexBinding) = .empty;
    errdefer vertex_bindings.deinit(alloc);

    const particle_count = dims[0] * dims[1] * dims[2];
    try particles.ensureTotalCapacity(alloc, particle_count);

    var z: usize = 0;
    while (z < dims[2]) : (z += 1) {
        var y: usize = 0;
        while (y < dims[1]) : (y += 1) {
            var x: usize = 0;
            while (x < dims[0]) : (x += 1) {
                const tx = if (dims[0] == 1) 0.0 else @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(dims[0] - 1));
                const ty = if (dims[1] == 1) 0.0 else @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(dims[1] - 1));
                const tz = if (dims[2] == 1) 0.0 else @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(dims[2] - 1));
                const p: Vector3 = .{
                    .x = min.x + size.x * tx,
                    .y = min.y + size.y * ty,
                    .z = min.z + size.z * tz,
                };
                particles.appendAssumeCapacity(.{
                    .rest_position = p,
                    .position = p,
                    .previous_position = p,
                });
            }
        }
    }

    z = 0;
    while (z < dims[2]) : (z += 1) {
        var y: usize = 0;
        while (y < dims[1]) : (y += 1) {
            var x: usize = 0;
            while (x < dims[0]) : (x += 1) {
                const a = latticeIndex(x, y, z, dims);
                if (x + 1 < dims[0]) {
                    const b = latticeIndex(x + 1, y, z, dims);
                    try springs.append(alloc, .{ .a = a, .b = b, .rest_length = vec3Distance(particles.items[a].position, particles.items[b].position) });
                }
                if (y + 1 < dims[1]) {
                    const b = latticeIndex(x, y + 1, z, dims);
                    try springs.append(alloc, .{ .a = a, .b = b, .rest_length = vec3Distance(particles.items[a].position, particles.items[b].position) });
                }
                if (z + 1 < dims[2]) {
                    const b = latticeIndex(x, y, z + 1, dims);
                    try springs.append(alloc, .{ .a = a, .b = b, .rest_length = vec3Distance(particles.items[a].position, particles.items[b].position) });
                }
            }
        }
    }

    try vertex_bindings.ensureTotalCapacity(alloc, vertices.len);
    for (vertices) |v| vertex_bindings.appendAssumeCapacity(makeVertexBinding(v, min, max, dims));

    return .{
        .min = min,
        .max = max,
        .dims = dims,
        .particles = particles,
        .springs = springs,
        .vertex_bindings = vertex_bindings,
    };
}
