 Progressive roadmap

 Phase 1: Establish the rigid-body proxy

 Before implementing deformation, make the undeformed object physically correct.

 ### Shape choices

 For the visual blob, use an ellipsoid made from:

 - an icosphere, ideally, or
 - a subdivided sphere.

 An icosphere is attractive because its triangles are relatively uniform and it has less troublesome pole topology.

 Godot does not provide a native EllipsoidShape3D. Reasonable collision proxies are:

 1. SphereShape3D — most stable, but only accurate for round blobs.
 2. CapsuleShape3D — suitable for a vertically elongated blob.
 3. ConvexPolygonShape3D — generated from a low-resolution ellipsoid, providing the closest approximation.

 Do not nonuniformly scale a sphere collision node. Godot does not reliably support scaled physics shapes. Build the desired convex shape at its actual dimensions.

 ### Validation gate

 At the end of this phase:

 - The visual and collision proxy occupy approximately the same volume.
 - The blob visually touches the floor when its collider touches.
 - It falls, rolls, and sleeps normally.
 - A modest PhysicsMaterial.bounce produces predictable rigid-body rebound.
 - No custom mesh updates exist yet.

 This separates basic Godot setup from soft-body work.

 ────────────────────────────────────────────────────────────────────────────────

 Phase 2: Prove the dynamic mesh pipeline

 Before writing a simulator, implement a manually controlled squash.

 For example, expose a temporary scalar squash value and deform every rest vertex along the Y axis:

 ```text
   axial scale     = 1 - squash
   transverse scale = 1 / sqrt(axial scale)
 ```

 The transverse scale approximately preserves volume because:

 ```text
   axial × transverse² = 1
 ```

 Conceptually, for an arbitrary squash axis n:

 ```text
   p' = transverse * p
        + (axial - transverse) * n * dot(p, n)
 ```

 This produces compression along n and expansion perpendicular to it.

 ### Important mesh requirements

 - Keep the actual index buffer.
 - Do not infer triangles from vertex-array order.
 - Keep immutable rest vertices.
 - Generate a private dynamic ArrayMesh.
 - Update positions.
 - Update normals using the real triangle indices.
 - Preserve materials.
 - Ensure the AABB accommodates the maximum deformation.

 ### Validation gate

 A key press or inspector value should:

 - squash the blob substantially,
 - bulge it sideways,
 - return exactly to the original shape at zero,
 - retain correct lighting,
 - and never alter the rigid collider.

 If this does not work, there is no reason to introduce springs yet.

 ────────────────────────────────────────────────────────────────────────────────

 Phase 3: Add one damped jello oscillator

 You do not initially need particles to create a convincing jello effect.

 Represent deformation with one scalar displacement and velocity:

 ```text
   deformation
   deformation_velocity
 ```

 Advance them with a damped harmonic oscillator:

 ```text
   acceleration = -ω² * deformation
                  - 2ζω * deformation_velocity

   deformation_velocity += acceleration * dt
   deformation          += deformation_velocity * dt
 ```

 Where:

 - ω controls wobble frequency,
 - ζ controls damping,
 - ζ < 1 gives an underdamped, oscillating response.

 An impact excites it by changing deformation_velocity:

 ```text
   deformation_velocity += impact_strength
 ```

 Use the deformation value as the squash parameter from Phase 2.

 ### Why start here?

 This teaches the essential concepts without mesh-particle complexity:

 - fixed timestep integration,
 - damping,
 - oscillation frequency,
 - impulse response,
 - stability,
 - volume-preserving deformation,
 - and separation between rigid and cosmetic state.

 For a stylized blob, this may already be enough.

 ### Validation gate

 - Clicking the blob makes it oscillate.
 - The effect is identical at 30, 60, and 144 render FPS.
 - It returns to rest.
 - It does not accumulate energy.
 - The simulator runs only once per physics tick.

 ────────────────────────────────────────────────────────────────────────────────

 Phase 4: Introduce mouse impulses

 Raycast from the camera through the mouse position.

 When the ray hits the blob:

 1. Obtain the world hit position and normal.
 2. Apply a Godot rigid-body impulse at the hit position.
 3. Send the same event to the cosmetic simulator.

 Conceptually:

 ```text
   Rigid input:
       body.apply_impulse(world_impulse, offset_from_body_origin)

   Visual input:
       excite(local_impulse, local_hit_position, local_hit_normal)
 ```

 Convert vectors and positions into the rigid body’s local frame before passing them to the visual simulator.

 The advantage here is that the impulse is known exactly. There is no need to infer it from velocity changes yet.

 Applying it away from the center should:

 - move the rigid body,
 - rotate it,
 - and visually wobble it.

 ### Validation gate

 - Center clicks produce mostly linear motion and symmetric squash.
 - Off-center clicks produce rigid rotation and asymmetric visual response.
 - Stronger clicks produce stronger deformation.
 - The visual response remains bounded.

 ────────────────────────────────────────────────────────────────────────────────

 Connecting Godot collisions to visual deformation

 Phase 5: Treat rigid-body velocity changes as excitation

 Your velocity-change idea is sound for driving the cosmetic simulation.

 Momentum and impulse are related by:

 ```text
   J = m Δv
 ```

 A rough collision impulse estimate is:

 ```text
   predicted_velocity =
       previous_velocity + gravity * dt + known_forces * dt / mass

   collision_delta_velocity =
       current_velocity - predicted_velocity

   estimated_impulse =
       mass * collision_delta_velocity
 ```

 This is substantially better than taking the second derivative of the node’s position.

 However, use it only:

 - at fixed physics ticks,
 - from the rigid body’s physics state,
 - with gravity and expected forces removed,
 - and above a small impact threshold.

 Otherwise ordinary gravity and damping will constantly excite the blob.

 ### Better source: Godot contact information

 When available, prefer PhysicsDirectBodyState3D contact data:

 - contact impulse,
 - contact point,
 - contact normal,
 - local velocity at the contact.

 This is more informative than center-of-mass velocity alone.

 The appropriate Godot integration point is the rigid body’s _integrate_forces(state) callback or equivalent native force-integration callback. It provides a coherent physics snapshot rather than relying on child
 callback ordering.

 Configure contact reporting:

 ```text
   contact_monitor = true
   max_contacts_reported > 0
 ```

 You should still verify exactly when contact data becomes available because some contact information may effectively describe the latest completed physics step.

 ### Excitation event

 Define a clean interface such as:

 ```text
   JelloExcitation
   - impulse_local
   - contact_point_local
   - contact_normal_local
   - angular_velocity_change_local
 ```

 The visual solver should receive events. It should not independently inspect global transforms.

 ### Validation gate

 Drop the blob from several heights:

 - Free fall produces no deformation.
 - First contact produces a squash.
 - Larger drop heights produce stronger squash.
 - Resting contact does not continually re-trigger it.
 - Rigid bounce and visual recovery remain synchronized.

 ────────────────────────────────────────────────────────────────────────────────

 Clarifying the “one-way” issue

 There are two different directions involved.

 Godot physics → visual simulation

 Your velocity-change idea addresses this direction:

 ```text
   Rigid collision impulse → cosmetic deformation
 ```

 That is the most important coupling for this architecture and is enough for a convincing result.

 Visual simulation → Godot physics

 True feedback would be:

 ```text
   Stored cosmetic spring energy → impulse applied to RigidBody3D
 ```

 Monitoring Δv alone does not provide this feedback; it observes what Godot already did.

 For the first several phases, I recommend deliberately leaving visual-to-rigid feedback out.

 Use Godot’s PhysicsMaterial.bounce for physical rebound and use the measured collision impulse to excite the visual wobble. This avoids double-counting energy.

 ────────────────────────────────────────────────────────────────────────────────

 Phase 6: Optional fake feedback

 Only add this after the one-way version feels good.

 A simple implementation could:

 1. Detect the start of a collision.
 2. Record incoming normal velocity.
 3. Let Godot resolve the collision.
 4. Apply one bounded extra impulse along the contact normal if more rebound is desired.

 For a static floor, a rough extra impulse is:

 ```text
   J_extra ≈ mass * desired_restitution * abs(incoming_normal_velocity)
 ```

 But there are hazards:

 - Applying it every contact frame causes energy explosions.
 - Applying it after Godot’s own bounce can double-count restitution.
 - For collisions with another dynamic body, applying an impulse to only the blob violates momentum conservation.
 - A delayed rebound can launch the body after it is no longer visibly compressed.

 Therefore the progression should be:

 1. Godot restitution only.
 2. Visual deformation driven by contact impulse.
 3. Only then experiment with bounded feedback.
 4. Treat it as gameplay/art direction, not physically correct soft-body coupling.

 For most cosmetic hybrids, step 2 is the desired stopping point.

 ────────────────────────────────────────────────────────────────────────────────

 Increasing visual complexity without particles

 Before implementing a lattice, you can add a few deformation modes.

 Phase 7: Multiple procedural modes

 Maintain separate damped oscillators for:

 - vertical squash,
 - X shear,
 - Z shear,
 - tilt/bend,
 - perhaps a radial “breathing” mode.

 Each mode has:

 - displacement,
 - velocity,
 - frequency,
 - damping,
 - a predefined vertex-deformation function.

 An impact at a particular point projects onto the relevant modes.

 This is a form of reduced-order or modal deformation. It is:

 - cheap,
 - stable,
 - easy to tune,
 - and often more controllable than a particle simulation.

 For a single blob, this may produce a better result than hundreds of springs.

 ### Validation gate

 - Top impacts mostly excite squash.
 - Side impacts excite lateral shear.
 - Off-center impacts excite tilt.
 - Modes decay independently.
 - The center remains aligned with the rigid body.

 ────────────────────────────────────────────────────────────────────────────────

 Only then: build a lattice solver

 Phase 8: Cosmetic PBD/XPBD lattice

 If procedural modes become too limiting, replace or augment them with a small control lattice.

 A reasonable first lattice is:

 ```text
   3×3×3 or 4×4×4 control points
 ```

 Do not simulate every render vertex. Simulate a low-resolution control cage and bind render vertices to it.

 ### Lattice constraints

 At minimum, include:

 1. Structural links
    Neighbors along X, Y, and Z.

 2. Shear links
    Diagonals across each cell face.

 3. Body diagonals or bending links
    Prevent the grid from folding freely.

 4. Shape-matching constraint
    Pulls the cage toward the ellipsoidal rest shape.

 5. Volume constraint
    Prevents compression from simply collapsing the blob.

 Axial links alone are not sufficient for a solid.

 ### Local-frame anchoring

 Because the rigid body owns translation and rotation, the lattice should describe only deformation relative to it.

 You need to remove uncontrolled rigid modes from the lattice by one of:

 - pinning the central control point,
 - fixing the lattice center and orientation,
 - subtracting center-of-mass translation after each step,
 - or using global shape matching against the local rest cage.

 Otherwise the cosmetic mesh can drift away from its rigid parent.

 ### Render binding

 Precompute a binding for every render vertex:

 - cell coordinates,
 - eight trilinear weights.

 Each frame:

 ```text
   render_vertex =
       weighted sum of the cell’s eight lattice points
 ```

 Because this is a free-form deformation cage, the render mesh’s UV seams and duplicate vertices are much less troublesome. Duplicate render vertices naturally receive the same position if their bindings are
 equal.

 ### Solver order

 A typical fixed tick is:

 1. Consume queued excitation events.
 2. Integrate particle velocities.
 3. Predict positions.
 4. Solve links and volume constraints for several iterations.
 5. Apply shape matching.
 6. Reconstruct velocities from corrected positions.
 7. Apply damping.
 8. Remove unwanted center/orientation drift.
 9. Deform render vertices.
 10. Recalculate normals.

 XPBD is preferable eventually because its stiffness is less timestep-dependent, but classic PBD is simpler for the first version.

 ### Validation gate

 Test the lattice without Godot collisions first:

 - Rest state remains perfectly stationary.
 - A synthetic local impulse causes oscillation.
 - The lattice returns to rest.
 - Volume stays within an acceptable percentage.
 - No component is disconnected.
 - Behavior is similar with different physics tick rates.
 - No NaNs occur under extreme test impulses.

 Then connect the already-proven collision excitation events.

 ────────────────────────────────────────────────────────────────────────────────

 Phase 9: Add the hand

 A moving physical hand is best introduced only after click interaction works.

 Possible design:

 ```text
   HandRoot (AnimatableBody3D)
   ├── CollisionShape3D
   └── HandVisual
 ```

 AnimatableBody3D is generally appropriate for a physics-aware object whose motion you control. Move it through physics-tick targets rather than teleporting it unpredictably during idle rendering.

 When the hand contacts the blob:

 - Godot pushes the RigidBody3D.
 - The same rigid-body contact-observation pipeline excites the cosmetic simulation.
 - No hand-specific jello code should be necessary.

 If the hand is only a cursor-like interaction tool, raycast and apply point impulses exactly as in the mouse phase before adding physical collision.

 ────────────────────────────────────────────────────────────────────────────────

 Recommended implementation separation

 Even when writing this in Zig, keep the solver independent from Godot.

 ```text
   extension/src/
   ├── jello_core.zig       # Oscillator/lattice, no Nodes
   ├── jello_mesh.zig       # Rest mesh and render bindings
   ├── jello_body.zig       # RigidBody3D adapter/contact collection
   └── jello_visual.zig     # MeshInstance3D adapter/upload
 ```

 The core should accept plain data:

 ```text
   step(dt)
   excite(event)
   write_deformed_vertices(output)
 ```

 This lets you unit-test physics without starting Godot.

 Useful automated checks include:

 - triangle indices are in range,
 - topology is connected,
 - rest state produces no motion,
 - deformation preserves the center,
 - volume error remains bounded,
 - energy decays when damping is enabled,
 - results are reasonably timestep-independent,
 - large impulses remain finite.

 Debug rendering of control points, links, contact normals, and impulse magnitudes will also save considerable time.

 ────────────────────────────────────────────────────────────────────────────────

 Recommended stopping points

 You do not need to commit immediately to the most complex version.

 ### Milestone A: convincing basic POC

 - Rigid ellipsoid proxy.
 - Procedural volume-preserving squash.
 - One damped oscillator.
 - Mouse impulses.
 - Godot bounce.

 ### Milestone B: convincing game-ready blob

 - Contact impulse extraction.
 - Multiple procedural deformation modes.
 - Correct normals and point-dependent effects.
 - Hovered hand interaction.

 ### Milestone C: educational soft-body project

 - PBD/XPBD lattice.
 - Shear, volume, and shape-matching constraints.
 - Render-vertex cage binding.
 - Optional controlled visual-to-rigid feedback.

 I would start with Milestone A. It establishes the complete interaction loop while remaining small enough that every line has an understandable purpose.

 Suggested learning references

 In approximately this order:

 1. Damped harmonic oscillator and semi-implicit Euler integration.
 2. Müller et al., Meshless Deformations Based on Shape Matching.
 3. Müller et al., Position Based Dynamics.
 4. Macklin et al., XPBD: Position-Based Simulation of Compliant Constrained Dynamics.
 5. Godot’s RigidBody3D._integrate_forces and PhysicsDirectBodyState3D contact APIs.

 The key principle is: do not begin by recreating SoftBody3D. First build a controlled squash oscillator connected correctly to a rigid body. Introduce lattice physics only once you can identify a visual
 limitation that the simpler model cannot express.

