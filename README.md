## Controls

| Action | Input |
|---|---|
| Move | WASD |
| Jump | Space |
| Swap Weapon | Tab |
| Attack | Left Mouse Button |
| Weapon Skill | Q |
| Slow-Mo | Shift |
| Free cursor | Escape |

---

## Features

**Two Weapons**  
Switch between Gun and Sword with Tab. Each weapon has its own primary attack and skill.

**Recoil-Based Movement**  
Firing gun while airborne applies a force in the opposite direction of the shot. Chain shots together to fly across the map.

**Triple Shot (Gun)**  
Loads three bullets one by one. All three must be fired before the window expires or the skill is wasted. Has a cooldown after use.

**Dash (Sword)**  
Lunges forward at high speed, damaging everything in the path. Has a cooldown after use.

**Combo Attack (Sword)**  
Three-hit combo: diagonal slash, horizontal recovery, vertical finisher. Chain hits within the window or the combo resets. A brief recovery pause follows the full combo.

**Slow-Mo**  
Slows down time for a limited duration. Only physics and bullet travel are affected, cooldowns and reloads tick in real time regardless.

**Visible Projectile**  
Bullets are physical objects that travel through the world. In slow-mo, you can actually watch them fly.

**Destructible Objects**  
Objects change color as they take damage: white when healthy, orange when damaged, red when critical.

**Drone Enemy**  
A flying enemy that patrols the area and scans the ground with a rotating detection cone. If the player enters the cone, the drone locks on and dives at full speed. Takes multiple hits to destroy. The cone color indicates its state: green when patrolling, shifting to red as the lock-on completes. Explode and dealing damage in radius on death.

---

## Visual Feedback

**Chromatic Aberration (Dash)**  
A color fringe distortion effect at the screen edges triggers on every dash.

**Hit Stop**  
The game freezes briefly on every successful hit, making attacks feel more impactful.

**Muzzle Flash**  
A burst of light and particles fires from the gun barrel on every shot.

**Screen Flash**  
The screen flashes white briefly when taking damage.

**Heartbeat Effect**  
A red vignette pulses at the screen edges when HP drops below 30%. The pulse speeds up as HP gets lower.

**Particle Effects**  
Sparks burst from the drone and debris puffs from destructibles when hit.

**Screen Shake**  
The camera shakes on drone explosions, electric floor zaps, and hard landings.

---

> **Known issue:** Due to a Compatibility renderer limitation in Godot 4, transparent objects (poison fog, drone cone, healing fountain barrier) may appear invisible while the chromatic aberration shader is active.
