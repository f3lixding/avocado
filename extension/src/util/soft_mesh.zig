const std = @import("std");
const godot = @import("godot_zig");

const Vector3 = godot.Vector3;

pub const Params = struct {
    simulation_precision: i64 = 5,
    total_mass: f64 = 1.0,
    linear_stiffness: f64 = 0.5,
    pressure_coefficient: f64 = 0.0,
    damping_coefficient: f64 = 0.01,
    drag_coefficient: f64 = 0.0,
    gravity: Vector3 = .{},

    // Visual-only safety controls. Godot's real soft body solver is coupled to
    // its collision world; when used as a child mesh skin, impact acceleration can
    // be enormous, so clamp it and continuously shape-match back to rest.
    max_visual_acceleration: f64 = 20.0,
    rest_shape_stiffness: f64 = 0.2,
};

const Particle = struct {
    x0: Vector3, // undeformed mesh-local rest position
    x: Vector3, // current position
    q: Vector3, // previous/predicted anchor used by Godot's solver
    v: Vector3 = .{},
    f: Vector3 = .{},
    bv: Vector3 = .{},
    n: Vector3 = .{},
    area: f32 = 0.0,
    im: f32 = 1.0,
};

const Link = struct {
    a: usize,
    b: usize,
    c0: f32 = 0.0,
    c1: f32 = 0.0,
    c2: f32 = 0.0,
    c3: Vector3 = .{},
};

const Face = struct {
    a: usize,
    b: usize,
    c: usize,
    normal: Vector3 = .{},
    centroid: Vector3 = .{},
    ra: f32 = 0.0,
};

pub const SoftMesh = struct {
    particles: std.ArrayList(Particle) = .empty,
    links: std.ArrayList(Link) = .empty,
    faces: std.ArrayList(Face) = .empty,
    raw_to_particle: std.ArrayList(usize) = .empty,

    pub fn deinit(self: *SoftMesh, alloc: std.mem.Allocator) void {
        self.particles.deinit(alloc);
        self.links.deinit(alloc);
        self.faces.deinit(alloc);
        self.raw_to_particle.deinit(alloc);
        self.* = .{};
    }
};

const QuantizedVertexKey = struct {
    x: i64,
    y: i64,
    z: i64,

    fn fromVector3(v: Vector3, epsilon: f32) QuantizedVertexKey {
        return .{
            .x = @intFromFloat(@round(v.x / epsilon)),
            .y = @intFromFloat(@round(v.y / epsilon)),
            .z = @intFromFloat(@round(v.z / epsilon)),
        };
    }
};

const EdgeKey = struct {
    a: usize,
    b: usize,
};

fn add(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn sub(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn scale(v: Vector3, s: f32) Vector3 {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
}

fn dot(a: Vector3, b: Vector3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn cross(a: Vector3, b: Vector3) Vector3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn lenSq(v: Vector3) f32 {
    return dot(v, v);
}

fn len(v: Vector3) f32 {
    return @sqrt(lenSq(v));
}

fn normalized(v: Vector3) Vector3 {
    const l = len(v);
    if (l <= 0.000001) return .{};
    return scale(v, 1.0 / l);
}

fn clamp(value: f32, lo: f32, hi: f32) f32 {
    return @max(lo, @min(hi, value));
}

fn addEdge(alloc: std.mem.Allocator, links: *std.ArrayList(Link), seen: *std.AutoHashMap(EdgeKey, void), a: usize, b: usize) !void {
    if (a == b) return;
    const key: EdgeKey = if (a < b) .{ .a = a, .b = b } else .{ .a = b, .b = a };
    if (seen.contains(key)) return;
    try seen.put(key, {});
    try links.append(alloc, .{ .a = key.a, .b = key.b });
}

pub fn build(alloc: std.mem.Allocator, vertices: []const Vector3, surface_vertex_counts: []const usize, params: Params) !SoftMesh {
    var out: SoftMesh = .{};
    errdefer out.deinit(alloc);

    try out.raw_to_particle.ensureTotalCapacity(alloc, vertices.len);
    var unique_vertices = std.AutoHashMap(QuantizedVertexKey, usize).init(alloc);
    defer unique_vertices.deinit();

    for (vertices) |v| {
        const key = QuantizedVertexKey.fromVector3(v, 0.0001);
        const gop = try unique_vertices.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = out.particles.items.len;
            try out.particles.append(alloc, .{ .x0 = v, .x = v, .q = v });
        }
        out.raw_to_particle.appendAssumeCapacity(gop.value_ptr.*);
    }

    const inv_mass = if (params.total_mass > 0.0) @as(f32, @floatFromInt(out.particles.items.len)) / @as(f32, @floatCast(params.total_mass)) else 0.0;
    for (out.particles.items) |*p| p.im = inv_mass;

    var seen_edges = std.AutoHashMap(EdgeKey, void).init(alloc);
    defer seen_edges.deinit();

    var base: usize = 0;
    for (surface_vertex_counts) |count| {
        var i: usize = 0;
        while (i + 2 < count) : (i += 3) {
            const a = out.raw_to_particle.items[base + i];
            const b = out.raw_to_particle.items[base + i + 1];
            const c = out.raw_to_particle.items[base + i + 2];
            if (a == b or b == c or c == a) continue;
            try out.faces.append(alloc, .{ .a = a, .b = b, .c = c });
            try addEdge(alloc, &out.links, &seen_edges, a, b);
            try addEdge(alloc, &out.links, &seen_edges, b, c);
            try addEdge(alloc, &out.links, &seen_edges, c, a);
        }
        base += count;
    }

    updateConstants(&out, params, true);
    updateNormalsAndCentroids(&out);
    return out;
}

fn updateConstants(mesh: *SoftMesh, params: Params, update_rest_lengths: bool) void {
    const stiffness = @max(@as(f32, 0.0001), @as(f32, @floatCast(params.linear_stiffness)));
    const inv_stiffness = 1.0 / stiffness;
    for (mesh.links.items) |*link| {
        const pa = mesh.particles.items[link.a];
        const pb = mesh.particles.items[link.b];
        link.c0 = (pa.im + pb.im) * inv_stiffness;
        if (update_rest_lengths) {
            link.c1 = lenSq(sub(pb.x, pa.x));
        }
    }
}

fn updateNormalsAndCentroids(mesh: *SoftMesh) void {
    for (mesh.particles.items) |*p| {
        p.n = .{};
        p.area = 0.0;
    }

    for (mesh.faces.items) |*face| {
        const a = mesh.particles.items[face.a].x;
        const b = mesh.particles.items[face.b].x;
        const c = mesh.particles.items[face.c].x;
        const cr = cross(sub(b, a), sub(c, a));
        const area2 = len(cr);
        face.normal = if (area2 <= 0.000001) .{} else scale(cr, 1.0 / area2);
        face.ra = area2 * 0.5;
        face.centroid = scale(add(add(a, b), c), 1.0 / 3.0);

        const node_area = face.ra / 3.0;
        inline for (.{ face.a, face.b, face.c }) |idx| {
            mesh.particles.items[idx].n = add(mesh.particles.items[idx].n, scale(face.normal, node_area));
            mesh.particles.items[idx].area += node_area;
        }
    }

    for (mesh.particles.items) |*p| p.n = normalized(p.n);
}

pub fn applyVisualAcceleration(mesh: *SoftMesh, acceleration: Vector3, strength: f32, max_acceleration: f32) void {
    if (mesh.particles.items.len == 0 or strength == 0.0) return;

    const raw_mag = len(acceleration);
    if (raw_mag <= 0.000001) return;

    const mag = @min(raw_mag, max_acceleration);
    const dir = scale(acceleration, 1.0 / raw_mag);
    var center: Vector3 = .{};
    for (mesh.particles.items) |p| center = add(center, p.x0);
    center = scale(center, 1.0 / @as(f32, @floatFromInt(mesh.particles.items.len)));

    // A rigid-body acceleration alone is uniform and only translates a free soft
    // mesh. To make a visual solid-body skin deform, convert acceleration into a
    // squash/stretch field around the rest-shape center: points farther along the
    // acceleration axis receive stronger opposite acceleration.
    for (mesh.particles.items) |*p| {
        if (p.im <= 0.0) continue;
        const rest_offset = sub(p.x0, center);
        const axial = dot(rest_offset, dir);
        const visual_accel = scale(dir, -axial * mag * strength);
        p.f = add(p.f, scale(visual_accel, 1.0 / p.im));
    }
}

fn matchRestShape(mesh: *SoftMesh, params: Params) void {
    const stiffness = clamp(@as(f32, @floatCast(params.rest_shape_stiffness)), 0.0, 1.0);
    if (stiffness <= 0.0) return;

    for (mesh.particles.items) |*p| {
        // Also damp velocity toward the rest pose; otherwise the visual skin can
        // accumulate energy from collision spikes and explode.
        const correction = scale(sub(p.x0, p.x), stiffness);
        p.x = add(p.x, correction);
        p.v = scale(p.v, 1.0 - stiffness * 0.5);
    }
}

fn applyForces(mesh: *SoftMesh, params: Params) void {
    if (mesh.particles.items.len == 0 or mesh.faces.items.len == 0) return;

    var volume: f32 = 0.0;
    const origin = mesh.particles.items[0].x;
    for (mesh.faces.items) |face| {
        const a = sub(mesh.particles.items[face.a].x, origin);
        const b = sub(mesh.particles.items[face.b].x, origin);
        const c = sub(mesh.particles.items[face.c].x, origin);
        volume += dot(a, cross(b, c));
    }
    volume /= 6.0;

    const pressure = @as(f32, @floatCast(params.pressure_coefficient));
    if (pressure > 0.000001 and @abs(volume) > 0.000001) {
        const ivolumetp = pressure / @abs(volume);
        for (mesh.particles.items) |*p| {
            if (p.im > 0.0) p.f = add(p.f, scale(p.n, p.area * ivolumetp));
        }
    }
}

pub fn step(mesh: *SoftMesh, params: Params, delta_seconds: f64) void {
    if (mesh.particles.items.len == 0) return;
    const dt = @as(f32, @floatCast(delta_seconds));
    if (dt <= 0.0) return;
    const inv_dt = 1.0 / dt;

    const inv_mass = if (params.total_mass > 0.0) @as(f32, @floatFromInt(mesh.particles.items.len)) / @as(f32, @floatCast(params.total_mass)) else 0.0;
    for (mesh.particles.items) |*p| p.im = inv_mass;
    updateConstants(mesh, params, false);

    // Godot-style force prediction.
    for (mesh.particles.items) |*p| {
        if (p.im > 0.0) p.v = add(p.v, scale(params.gravity, dt));
    }
    applyForces(mesh, params);

    const max_displacement: f32 = 1000.0;
    const clamp_delta_v = max_displacement * inv_dt;
    const drag = @max(@as(f32, 0.0), @as(f32, @floatCast(params.drag_coefficient)));
    const drag_scale = 1.0 / (1.0 + drag * dt);

    for (mesh.particles.items) |*p| {
        p.q = p.x;
        var delta_v = scale(p.f, p.im * dt);
        delta_v.x = clamp(delta_v.x, -clamp_delta_v, clamp_delta_v);
        delta_v.y = clamp(delta_v.y, -clamp_delta_v, clamp_delta_v);
        delta_v.z = clamp(delta_v.z, -clamp_delta_v, clamp_delta_v);
        p.v = scale(add(p.v, delta_v), drag_scale);
        p.x = add(p.x, scale(p.v, dt));
        p.f = .{};
    }

    // Godot-style link solve.
    for (mesh.links.items) |*link| {
        link.c3 = sub(mesh.particles.items[link.b].q, mesh.particles.items[link.a].q);
        const denom = lenSq(link.c3) * link.c0;
        link.c2 = if (denom > 0.000001) 1.0 / denom else 0.0;
    }

    for (mesh.particles.items) |*p| p.x = add(p.q, scale(p.v, dt));

    const iterations: usize = @intCast(@max(@as(i64, 1), params.simulation_precision));
    var it: usize = 0;
    while (it < iterations) : (it += 1) solveLinks(mesh, 1.0);
    matchRestShape(mesh, params);

    const damping = clamp(@as(f32, @floatCast(params.damping_coefficient)), 0.0, 1.0);
    const vc = (1.0 - damping) * inv_dt;
    for (mesh.particles.items) |*p| {
        p.x = add(p.x, scale(p.bv, dt));
        p.bv = .{};
        p.v = scale(sub(p.x, p.q), vc);
        p.q = p.x;
    }

    updateNormalsAndCentroids(mesh);
}

fn solveLinks(mesh: *SoftMesh, kst: f32) void {
    for (mesh.links.items) |link| {
        if (link.c0 <= 0.0) continue;
        const node_a = &mesh.particles.items[link.a];
        const node_b = &mesh.particles.items[link.b];
        const del = sub(node_b.x, node_a.x);
        const l2 = lenSq(del);
        if (link.c1 + l2 <= 0.000001) continue;
        const k = ((link.c1 - l2) / (link.c0 * (link.c1 + l2))) * kst;
        node_a.x = sub(node_a.x, scale(del, k * node_a.im));
        node_b.x = add(node_b.x, scale(del, k * node_b.im));
    }
}

pub fn writeVertices(mesh: *const SoftMesh, out_vertices: []Vector3) void {
    std.debug.assert(out_vertices.len >= mesh.raw_to_particle.items.len);
    for (mesh.raw_to_particle.items, 0..) |particle_i, raw_i| out_vertices[raw_i] = mesh.particles.items[particle_i].x;
}
