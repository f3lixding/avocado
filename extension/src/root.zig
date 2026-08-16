const std = @import("std");
const godot = @import("godot_zig");

const SoftBody3D = godot.generated.classes.SoftBody3D;
const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const ArrayMesh = godot.generated.classes.ArrayMesh;
const Crypto = godot.generated.classes.Crypto;
const Engine = godot.generated.classes.Engine;
const Mesh = godot.generated.classes.Mesh;
const PackedByteArray = godot.PackedByteArray;
const Vector3 = godot.Vector3;

const soft_mesh = @import("util/soft_mesh.zig");
const SoftBodySimulationParams = soft_mesh.Params;
const mesh_array_flag_use_dynamic_update: i64 = 67_108_864;

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

fn vec3Sub(a: Vector3, b: Vector3) Vector3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn vec3Scale(v: Vector3, scale: f32) Vector3 {
    return .{ .x = v.x * scale, .y = v.y * scale, .z = v.z * scale };
}

fn constructObject(comptime class_name_text: [:0]const u8) godot.c.GDExtensionObjectPtr {
    var class_name = godot.api.godot.stringName(class_name_text);
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &class_name);
    return godot.api.godot.classdb_construct_object.?(&class_name);
}

fn constructBuiltin(comptime T: type, comptime variant_type: godot.c.GDExtensionVariantType) T {
    var value: T = std.mem.zeroes(T);
    godot.api.godot.variant_get_ptr_constructor.?(variant_type, 0).?(&value, null);
    return value;
}

fn bind(class_name_text: [:0]const u8, method_name_text: [:0]const u8, hash: i64) godot.c.GDExtensionMethodBindPtr {
    var class_name = godot.api.godot.stringName(class_name_text);
    var method_name = godot.api.godot.stringName(method_name_text);
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &method_name);
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &class_name);
    return godot.api.godot.classdb_get_method_bind.?(&class_name, &method_name, hash);
}

fn setMesh(instance: MeshInstance3D, mesh: Mesh) void {
    const method = bind("MeshInstance3D", "set_mesh", 194775623);
    var mesh_ptr: godot.c.GDExtensionObjectPtr = mesh.object.ptr;
    const args = [_]godot.c.GDExtensionConstTypePtr{@ptrCast(&mesh_ptr)};
    godot.api.godot.object_method_bind_ptrcall.?(method, instance.object.ptr, &args, null);
}

fn log(message: [*:0]const u8) void {
    godot.log.errMsg("avocado", message, .{
        .function = @src().fn_name,
        .file = @src().file,
        .line = @src().line,
        .editor_notify = false,
    });
}

const Avocado = struct {
    object: godot.c.GDExtensionObjectPtr,
    impulse_timer: f64,
    alloc: std.mem.Allocator = std.heap.c_allocator,

    rest_vertices: std.ArrayList(Vector3) = .empty,
    cur_vertices: std.ArrayList(Vector3) = .empty,
    indices: std.ArrayList(i32) = .empty,
    surface_vertex_counts: std.ArrayList(usize) = .empty,
    vertex_upload_buffers: std.ArrayList(PackedByteArray) = .empty,
    soft_body: soft_mesh.SoftMesh = .{},
    simulation_params: SoftBodySimulationParams = .{
        .simulation_precision = 5,
        .total_mass = 1.0,
        .linear_stiffness = 0.01,
        .pressure_coefficient = 0.0,
        .damping_coefficient = 0.08,
        .drag_coefficient = 0.0,
        .gravity = .{},
        .max_visual_acceleration = 20.0,
        .rest_shape_stiffness = 0.25,
    },
    visual_acceleration_scale: f32 = 0.015,
    last_global_position: Vector3 = .{},
    last_global_velocity: Vector3 = .{},
    has_motion_state: bool = false,
    physics_ready: bool = false,

    pub fn init(object: godot.c.GDExtensionObjectPtr) Avocado {
        return .{ .object = object, .impulse_timer = 0.0 };
    }

    pub fn deinit(self: *Avocado) void {
        self.rest_vertices.deinit(self.alloc);
        self.cur_vertices.deinit(self.alloc);
        self.indices.deinit(self.alloc);
        self.surface_vertex_counts.deinit(self.alloc);
        for (self.vertex_upload_buffers.items) |*buffer| buffer.destroy();
        self.vertex_upload_buffers.deinit(self.alloc);
        self.soft_body.deinit(self.alloc);
        log("deinit called");
    }

    fn asNode(self: *Avocado) godot.Node {
        return godot.Node.init(self.object);
    }

    fn asSoftBody(self: *Avocado) SoftBody3D {
        return SoftBody3D.init(self.object);
    }

    fn asMeshInstance(self: *Avocado) MeshInstance3D {
        return MeshInstance3D.init(self.object);
    }

    fn asNode3D(self: *Avocado) godot.Node3D {
        return godot.Node3D.init(self.object);
    }

    fn ready(self: *Avocado) callconv(.c) void {
        // The editor may instantiate scene nodes while loading/inspecting scenes.
        // Do not crawl mesh data there; native crashes kill the whole editor.
        if (Engine.singleton().is_editor_hint()) return;

        log("READY RAN");
        const node = self.asNode();
        node.set_physics_process(true);
        node.set_process(true);
        var processing_msg_buf: [100]u8 = undefined;
        const processing_msg = std.fmt.bufPrintZ(&processing_msg_buf, "processing: {}, physics processing: {}", .{ node.is_processing(), node.is_physics_processing() }) catch "failed to format processing";
        log(processing_msg);

        const mesh_instance = self.asMeshInstance();
        const mesh = mesh_instance.get_mesh();

        if (mesh.isNull()) {
            log("mesh is null; skipping vertex cache");
            return;
        }

        const surface_count = mesh.get_surface_count();
        const dynamic_mesh = ArrayMesh.init(constructObject("ArrayMesh"));

        const buf = &self.rest_vertices;

        var surface_i: i64 = 0;
        while (surface_i < surface_count) : (surface_i += 1) {
            var arrays = mesh.surface_get_arrays(surface_i);
            defer arrays.destroy();

            var empty_blend_shapes: godot.Array = .{ .value = constructBuiltin(godot.types.Array, godot.c.GDEXTENSION_VARIANT_TYPE_ARRAY) };
            defer empty_blend_shapes.destroy();
            var empty_lods = constructBuiltin(godot.types.Dictionary, godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY);
            defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY, &empty_lods);
            dynamic_mesh.add_surface_from_arrays(
                3,
                arrays,
                empty_blend_shapes,
                empty_lods,
                mesh_array_flag_use_dynamic_update,
            );

            var vertices = arrays.vertices();
            defer vertices.destroy();

            const vertex_count = vertices.size();
            self.surface_vertex_counts.append(self.alloc, @intCast(vertex_count)) catch {
                const msg = "failed to append surface vertex count";
                log(msg);
                @panic(msg);
            };

            var i: i64 = 0;
            while (i < vertex_count) : (i += 1) {
                const p = vertices.get(i);
                buf.append(self.alloc, p) catch {
                    const msg = "failed to append rest vertex";
                    log(msg);
                    @panic(msg);
                };
            }
        }

        setMesh(mesh_instance, Mesh.init(dynamic_mesh.object.ptr));

        self.soft_body = soft_mesh.build(self.alloc, self.rest_vertices.items, self.surface_vertex_counts.items, self.simulation_params) catch {
            log("failed to build soft mesh");
            return;
        };
        self.cur_vertices.appendSlice(self.alloc, self.rest_vertices.items) catch {
            log("failed to initialize current vertices");
            return;
        };

        const crypto = Crypto.init(constructObject("Crypto"));
        defer godot.api.godot.object_destroy.?(crypto.object.ptr);
        for (self.surface_vertex_counts.items) |vertex_count| {
            var upload_buffer = crypto.generate_random_bytes(@intCast(vertex_count * @sizeOf(Vector3)));
            self.vertex_upload_buffers.append(self.alloc, upload_buffer) catch {
                upload_buffer.destroy();
                log("failed to initialize vertex upload buffer");
                return;
            };
        }

        self.last_global_position = self.asNode3D().get_global_position();
        self.last_global_velocity = .{};
        self.has_motion_state = true;
        self.physics_ready = true;

        var count_msg_buf: [160]u8 = undefined;
        const msg = std.fmt.bufPrintZ(
            &count_msg_buf,
            "mesh vertices={d}, soft nodes={d}, links={d}, faces={d}",
            .{
                self.rest_vertices.items.len,
                self.soft_body.particles.items.len,
                self.soft_body.links.items.len,
                self.soft_body.faces.items.len,
            },
        ) catch {
            log("failed to format lattice count");
            return;
        };
        godot.log.errMsg("avocado", msg, .{
            .function = @src().fn_name,
            .file = @src().file,
            .line = @src().line,
            .editor_notify = false,
        });
    }

    fn uploadMeshVertices(self: *Avocado) void {
        const mesh = self.asMeshInstance().get_mesh();
        if (mesh.isNull()) return;

        const array_mesh = ArrayMesh.init(mesh.object.ptr);
        var vertex_offset: usize = 0;
        for (self.surface_vertex_counts.items, 0..) |vertex_count, surface_i| {
            const end = vertex_offset + vertex_count;
            if (end > self.cur_vertices.items.len or surface_i >= self.vertex_upload_buffers.items.len) return;

            const bytes = std.mem.sliceAsBytes(self.cur_vertices.items[vertex_offset..end]);
            var packed_bytes = &self.vertex_upload_buffers.items[surface_i];
            if (packed_bytes.size() != @as(i64, @intCast(bytes.len))) return;
            for (bytes, 0..) |byte, i| packed_bytes.set(@intCast(i), byte);

            array_mesh.surface_update_vertex_region(@intCast(surface_i), 0, packed_bytes.*);
            vertex_offset = end;
        }
    }

    fn stepSimulation(self: *Avocado, delta: f64) void {
        if (!self.physics_ready) return;

        const dt = @as(f32, @floatCast(delta));
        if (dt <= 0.0) return;

        const global_position = self.asNode3D().get_global_position();
        const params = self.simulation_params;
        if (self.has_motion_state) {
            const velocity = vec3Scale(vec3Sub(global_position, self.last_global_position), 1.0 / dt);
            const acceleration = vec3Scale(vec3Sub(velocity, self.last_global_velocity), 1.0 / dt);
            // The visual solver needs a non-uniform acceleration field to deform;
            // a uniform force only translates all mesh nodes together.
            soft_mesh.applyVisualAcceleration(
                &self.soft_body,
                acceleration,
                self.visual_acceleration_scale,
                @floatCast(self.simulation_params.max_visual_acceleration),
            );
            self.last_global_velocity = velocity;
        }
        self.last_global_position = global_position;
        self.has_motion_state = true;

        const before_y = if (self.soft_body.particles.items.len > 0) self.soft_body.particles.items[0].x.y else 0.0;

        soft_mesh.step(&self.soft_body, params, delta);

        if (self.cur_vertices.items.len != self.soft_body.raw_to_particle.items.len) {
            self.cur_vertices.resize(self.alloc, self.soft_body.raw_to_particle.items.len) catch {
                log("failed to resize current vertices");
                return;
            };
        }

        soft_mesh.writeVertices(&self.soft_body, self.cur_vertices.items);

        self.uploadMeshVertices();

        self.impulse_timer += delta;
        if (self.impulse_timer >= 1.0) {
            self.impulse_timer = 0.0;
            var msg_buf: [160]u8 = undefined;
            const msg = std.fmt.bufPrintZ(
                &msg_buf,
                "sim y: particle {d}->{d}, vertex0 y={d}",
                .{ before_y, if (self.soft_body.particles.items.len > 0) self.soft_body.particles.items[0].x.y else 0.0, if (self.cur_vertices.items.len > 0) self.cur_vertices.items[0].y else 0.0 },
            ) catch "failed to format sim y";
            log(msg);
        }
    }

    fn physicsProcess(self: *Avocado, delta: f64) callconv(.c) void {
        self.stepSimulation(delta);
    }

    fn process(self: *Avocado, delta: f64) callconv(.c) void {
        self.stepSimulation(delta);
    }

    fn updateMeshVertices(self: *Avocado) void {
        _ = self;
    }

    pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
        var ready_name = godot.api.godot.stringName("_ready");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
        var physics_name = godot.api.godot.stringName("_physics_process");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &physics_name);
        var process_name = godot.api.godot.stringName("_process");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &process_name);

        if (stringNameEqual(name, &ready_name)) return @ptrCast(@constCast(&ready));
        if (stringNameEqual(name, &physics_name)) return @ptrCast(@constCast(&physicsProcess));
        if (stringNameEqual(name, &process_name)) return @ptrCast(@constCast(&process));
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
        const self: *Avocado = @ptrCast(@alignCast(instance.?));

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&ready)))) {
            ready(self);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&physicsProcess)))) {
            const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
            physicsProcess(self, delta.*);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&process)))) {
            const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
            process(self, delta.*);
            return;
        }
    }
};

fn stringNameEqual(a: godot.c.GDExtensionConstStringNamePtr, b: godot.c.GDExtensionConstStringNamePtr) bool {
    const evaluator = godot.api.godot.variant_get_ptr_operator_evaluator.?(
        godot.c.GDEXTENSION_VARIANT_OP_EQUAL,
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
    ).?;
    var out: u8 = 0;
    evaluator(a, b, &out);
    return out != 0;
}

fn initialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    godot.class.NativeClass(Avocado, "MeshInstance3D", "Avocado").register();
}

fn deinitialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    _ = level;
}

pub export fn avocado_extension_init(
    get_proc_address: godot.c.GDExtensionInterfaceGetProcAddress,
    library: godot.c.GDExtensionClassLibraryPtr,
    initialization: [*c]godot.c.GDExtensionInitialization,
) godot.c.GDExtensionBool {
    return godot.extension.entry(
        get_proc_address,
        library,
        initialization,
        .scene,
        initialize,
        deinitialize,
    );
}
