# TODO
## Features
- [ ] Sword trail
    - [x] Mesh
    - [x] Shader
    - [ ] Only show during swing (use registered method for this for when the oneshot ends)
- [ ] Hit animation effects (ragdoll?)
- [ ] Weapon / item attachment
- [ ] HP / dmg
- [ ] Rigging / animation reuse
- [ ] UI / menu
- [ ] Sound

- [ ] ECS through single node and rendered through renderserver
- [ ] Single entity interactions with other Nodes

## Bugs

# DONE
- [x] Add another oneshot with a different filter for when character is moving
- [x] Swing animation needs to decouple from legs when there is movement input
- [x] Swing should modify movement speed when on ground
- [x] Sheathing / unsheathing should be filtered
- [x] Sheathing / unsheathing should be interruptable
- [x] Weapon attachment
    - [x] Unsheathed position
    - [x] Sheathed position
    - [x] Add weapon sheathing / unsheathing animation in tree
    - [x] Equip transition
- [x] Attack animation (or just extra interactivity)
- [x] Turn animation
    - [x] Add turn animation for feet during turn
- [x] Clean up extension leaks
- [x] Camera placement adjustment
- [x] Restore easy test setup
- [x] Multi-client set up
- [x] Add aiming blending
- [x] Add camera shake during sprinting 
- [x] Proper controller for character input / animation
- [x] Standardize camera placement?
- [x] Humanoid model
- [x] Find a better place to perform class level resource instantiation (i.e. things that are common to all instances)
- [x] Move character script to extension
- [x] Model a proper jello
- [x] Grass shader
- [x] Particle system
    - [x] add bubbles
    - [x] move particles onto jello_demo and spawn one for each impact
    - [x] bubbles popping
- [x] Contact point sensitive compression
- [x] Clean up
- [x] Proper nodes set up
- [x] Call class deinit on free (this is a change that is needed on the binding)
- [x] Disect extensions
- [x] Homegrown simplified simulations
