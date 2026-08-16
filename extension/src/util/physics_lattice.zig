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

/// Intentionally named like Godot's SoftBody3D properties/setters:
/// set_simulation_precision, set_total_mass, set_linear_stiffness,
/// set_pressure_coefficient, set_damping_coefficient, set_drag_coefficient.
///
/// This is not Bullet/Godot's exact solver; it is a small position-based lattice
/// solver using the same high-level controls.
pub const SoftBodySimulationParams = struct {
    simulation_precision: i64 = 5,
    total_mass: f64 = 1.0,
    linear_stiffness: f64 = 1.0,
    pressure_coefficient: f64 = 0.0,
    damping_coefficient: f64 = 0.01,
    drag_coefficient: f64 = 0.0,
    gravity: Vector3 = .{ .x = 0.0, .y = -9.8, .z = 0.0 },
    /// Pulls the visual lattice back to the undeformed mesh-local shape. This is
    /// what makes the solver useful for "rigid body + soft visual skin": Godot
    /// moves/collides the rigid body, while this lattice only jiggles locally.
    rest_shape_stiffness: f64 = 0.2,
};

fn vec3Add(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn vec3Sub(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn vec3Scale(a: Vector3, s: f32) Vector3 {
    return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
}

fn vec3Distance(a: Vector3, b: Vector3) f32 {
    return vec3Sub(a, b).length();
}

fn vec3LengthSquared(a: Vector3) f32 {
    return a.x * a.x + a.y * a.y + a.z * a.z;
}

fn vec3Normalize(a: Vector3) Vector3 {
    const len = @sqrt(vec3LengthSquared(a));
    if (len <= 0.000001) return .{};
    return vec3Scale(a, 1.0 / len);
}

fn clamp01(value: f32) f32 {
    return @max(0.0, @min(1.0, value));
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

fn latticeCenter(particles: []const Particle, use_rest: bool) Vector3 {
    if (particles.len == 0) return .{};

    var center: Vector3 = .{};
    for (particles) |p| {
        center = vec3Add(center, if (use_rest) p.rest_position else p.position);
    }
    return vec3Scale(center, 1.0 / @as(f32, @floatFromInt(particles.len)));
}

fn solveSpring(particles: []Particle, spring: Spring, stiffness: f32) void {
    const pa = &particles[spring.a];
    const pb = &particles[spring.b];
    const delta = vec3Sub(pb.position, pa.position);
    const len = @sqrt(vec3LengthSquared(delta));
    if (len <= 0.000001) return;

    const inv_a = pa.inverse_mass;
    const inv_b = pb.inverse_mass;
    const inv_sum = inv_a + inv_b;
    if (inv_sum <= 0.0) return;

    const length_error = len - spring.rest_length;
    const correction = vec3Scale(delta, (length_error / len) * stiffness);
    pa.position = vec3Add(pa.position, vec3Scale(correction, inv_a / inv_sum));
    pb.position = vec3Sub(pb.position, vec3Scale(correction, inv_b / inv_sum));
}

fn applyRestShapeMatch(particles: []Particle, params: SoftBodySimulationParams) void {
    const stiffness = clamp01(@as(f32, @floatCast(params.rest_shape_stiffness)));
    if (stiffness <= 0.0) return;

    for (particles) |*p| {
        if (p.inverse_mass <= 0.0) continue;
        p.position = vec3Add(p.position, vec3Scale(vec3Sub(p.rest_position, p.position), stiffness));
    }
}

fn applyPressureShapeMatch(particles: []Particle, params: SoftBodySimulationParams, delta: f32) void {
    if (particles.len == 0 or params.pressure_coefficient == 0.0) return;

    const rest_center = latticeCenter(particles, true);
    const cur_center = latticeCenter(particles, false);
    const pressure = @as(f32, @floatCast(params.pressure_coefficient));
    const strength = clamp01(@abs(pressure) * delta * 0.01);
    const expansion = if (pressure > 0.0) @as(f32, 1.0) else @as(f32, -1.0);

    for (particles) |*p| {
        if (p.inverse_mass <= 0.0) continue;

        const rest_offset = vec3Sub(p.rest_position, rest_center);
        const cur_offset = vec3Sub(p.position, cur_center);
        const rest_radius = @sqrt(vec3LengthSquared(rest_offset));
        if (rest_radius <= 0.000001) continue;

        const dir = vec3Normalize(cur_offset);
        const target = vec3Add(cur_center, vec3Scale(dir, rest_radius * (1.0 + expansion * 0.1)));
        p.position = vec3Add(p.position, vec3Scale(vec3Sub(target, p.position), strength));
    }
}

/// Advances the lattice particles by one physics tick.
///
/// Params intentionally mirror Godot SoftBody3D's common simulation properties:
/// - simulation_precision: number of constraint iterations
/// - total_mass: evenly distributed across lattice particles
/// - linear_stiffness: spring constraint stiffness, 0..1 useful range
/// - pressure_coefficient: rough volume/shape expansion term
/// - damping_coefficient: damps particle velocity
/// - drag_coefficient: additional velocity damping against the surrounding medium
pub fn simulateSoftBodyLattice(
    particles: []Particle,
    springs: []const Spring,
    params: SoftBodySimulationParams,
    delta_seconds: f64,
) void {
    if (particles.len == 0) return;

    const dt = @as(f32, @floatCast(@max(0.0, delta_seconds)));
    if (dt <= 0.0) return;

    const total_mass = @as(f32, @floatCast(params.total_mass));
    const inv_mass = if (total_mass > 0.0) @as(f32, @floatFromInt(particles.len)) / total_mass else 0.0;
    const damping = clamp01(@as(f32, @floatCast(params.damping_coefficient)));
    const drag = @max(@as(f32, 0.0), @as(f32, @floatCast(params.drag_coefficient)));
    const velocity_scale = @max(@as(f32, 0.0), (1.0 - damping) * (1.0 / (1.0 + drag * dt)));
    const gravity_step = vec3Scale(params.gravity, dt * dt);

    for (particles) |*p| {
        p.inverse_mass = inv_mass;
        if (p.inverse_mass <= 0.0) continue;

        const old_position = p.position;
        const velocity_step = vec3Scale(vec3Sub(p.position, p.previous_position), velocity_scale);
        p.position = vec3Add(vec3Add(p.position, velocity_step), gravity_step);
        p.previous_position = old_position;
        p.velocity = vec3Scale(vec3Sub(p.position, p.previous_position), 1.0 / dt);
    }

    const iterations: usize = @intCast(@max(@as(i64, 1), params.simulation_precision));
    const stiffness = clamp01(@as(f32, @floatCast(params.linear_stiffness)));
    const per_iteration_stiffness = 1.0 - std.math.pow(f32, 1.0 - stiffness, 1.0 / @as(f32, @floatFromInt(iterations)));

    var iteration: usize = 0;
    while (iteration < iterations) : (iteration += 1) {
        for (springs) |spring| solveSpring(particles, spring, per_iteration_stiffness);
        applyRestShapeMatch(particles, params);
        applyPressureShapeMatch(particles, params, dt);
    }

    for (particles) |*p| {
        p.velocity = vec3Scale(vec3Sub(p.position, p.previous_position), 1.0 / dt);
    }
}

pub fn deformVerticesFromLattice(
    bindings: []const RenderVertexBinding,
    particles: []const Particle,
    dims: [3]usize,
    out_vertices: []Vector3,
) void {
    std.debug.assert(out_vertices.len >= bindings.len);

    for (bindings, 0..) |binding, vertex_i| {
        const x = binding.cell_x;
        const y = binding.cell_y;
        const z = binding.cell_z;
        const indices = [_]usize{
            latticeIndex(x, y, z, dims),
            latticeIndex(x + 1, y, z, dims),
            latticeIndex(x, y + 1, z, dims),
            latticeIndex(x + 1, y + 1, z, dims),
            latticeIndex(x, y, z + 1, dims),
            latticeIndex(x + 1, y, z + 1, dims),
            latticeIndex(x, y + 1, z + 1, dims),
            latticeIndex(x + 1, y + 1, z + 1, dims),
        };

        var p: Vector3 = .{};
        for (indices, 0..) |particle_i, weight_i| {
            p = vec3Add(p, vec3Scale(particles[particle_i].position, binding.weights[weight_i]));
        }
        out_vertices[vertex_i] = p;
    }
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
