## ADR 011: Audio Architecture — AudioManager Autoload + SoundConfig + AudioEmitterComponent

**Date:** 2026-04-08
**Status:** Accepted
**Related:** [ADR 007 (bus)](007-events-bus-discipline.md), [ADR 009 (resources)](009-resources-hot-reload-strategy.md)

## Context

Pre-refactor the game had **no audio**. The brainstorm scoped in a minimum-viable audio layer: sound-effect emission on gameplay events (hit, explosion, dash, mine arm/drop, cannon fire) and background music that survives scene transitions.

The open design questions:

1. **Autoload or service node?** Music persistence across scenes strongly suggests an autoload.
2. **Who emits sound events?** The entity (Ship) directly? The component that caused the event (HealthComponent on damage)? A bus signal?
3. **How are sounds referenced?** Magic string IDs, enum values, Resource file paths?
4. **Where does the audio stream-to-ID mapping live?** Hard-coded in AudioManager, or a data-driven Resource lookup?
5. **Positional audio?** 2D attenuation or UI-style fire-and-forget?

Appendix A of the parent plan evaluated **A5 — move AudioManager out of autoload** as a possible scope cut. A5 was **rejected** explicitly because music persistence across main-menu → gameplay → game-over requires an owner that outlives the scene tree. A service Node in `main.tscn` would get freed on scene transition; an autoload does not.

## Decision

### 1. `AudioManager` is an autoload

Registered third in the autoload order (`Events → GameState → AudioManager → KeybindsManager`). Owns:

- A pool of `AudioStreamPlayer2D` instances for positional sound effects.
- A dedicated `AudioStreamPlayer` (non-positional) for music.
- The sound-id → `AudioStream` mapping.

AudioManager subscribes to `Events.sound_requested(sound_id, pos)` in its own `_ready()` and plays the matching stream.

### 2. `SoundConfig.tres` — Resource-driven sound lookup

Rather than hard-coding `match sound_id:` in AudioManager, a `SoundConfig` Resource holds the id-to-stream mapping:

```gdscript
class_name SoundConfig
extends Resource

@export var sounds: Dictionary = {}    # StringName → AudioStream
```

`AudioManager._ready()` loads a default `SoundConfig.tres` and resolves `sound_id` lookups through the dictionary. New sounds are added by dropping an `AudioStream` into the inspector — no code change, no `match` branch to edit.

### 3. Bus signal: `sound_requested(sound_id: StringName, pos: Vector2)`

**`sound_id: StringName`, not `name: String`.** The parameter is `StringName` because:

- **No shadowing of `Node.name`.** `name` is a built-in; using it as a parameter name shadows the node property, which caused silent bugs elsewhere in the codebase (Research Delta #16 in the parent plan).
- **StringName interning.** `&"player_hit"` is interned at parse time, so the per-emit cost is a hash compare rather than a string copy.

The signal is published from:
- **Entity roots** (Ship, EnemyShip) via their local AudioEmitterComponents.
- **AudioEmitterComponent directly** (see below — this is one of the two component exceptions to the "components don't touch the bus" rule).

### 4. AudioEmitterComponent — local subscriber + direct bus publisher

Each entity hosts an `AudioEmitterComponent` that subscribes to the entity root's local signals:

```gdscript
# Ship root wires its AudioEmitterComponent:
_audio_emitter.connect_signals(self)

# AudioEmitterComponent subscribes:
func connect_signals(ship: Ship) -> void:
    ship.damaged.connect(_on_damaged)
    ship.dash_started.connect(_on_dash_started)
    # ...

func _on_damaged(_amount: int, _source: Node) -> void:
    Events.sound_requested.emit(&"player_hit", global_position)
```

**This is the designated exception** to the ADR 007 rule that "components do not touch the bus directly." Routing through Ship root would add a one-line forwarder per signal with zero decoupling benefit — AudioEmitterComponent is a **terminal output** component, not a state-owning one. HitFeedbackComponent has the same exception for the same reason.

### 5. Positional audio via `AudioStreamPlayer2D`

Sound effects use `AudioStreamPlayer2D` so the game's existing 2D positional attenuation works out of the box. `sound_requested(sound_id, pos)` carries the world-space position; AudioManager sets the player's position before playing.

**Music is non-positional** — a single `AudioStreamPlayer` node on AudioManager plays the background track.

### 6. Music persists across scene transitions

Because AudioManager is an autoload, its child `AudioStreamPlayer` (music) is never freed when `get_tree().change_scene_*` runs. Transitions that need a music change call `AudioManager.play_music(id)` and the new track crossfades; transitions that don't need one (game-over screen overlay, for example) leave the music playing.

### 7. One-shot SFX pool

For multiple simultaneous sound effects (e.g., five enemies exploding at once), AudioManager maintains a small pool of `AudioStreamPlayer2D` nodes and round-robins across them. Pool size is documented at the top of `audio_manager.gd`; start small (8) and raise if clipping occurs.

## Consequences

**Positive:**
- **Music persistence is structurally guaranteed.** An autoload survives every scene transition — we don't have to remember to preserve a music player manually.
- **Data-driven sound additions.** Dropping a new `.ogg` into `assets/audio/` and registering it in `SoundConfig.tres` adds a sound with zero GDScript changes.
- **Publishers don't care about audio backends.** `Events.sound_requested.emit(&"player_hit", pos)` works whether AudioManager is using a single stream player, a pool, or external middleware.
- **AudioEmitterComponent is reusable.** Ship, EnemyShip, and future entities get sound effects by adding one component and connecting its local subscriptions.
- **`StringName` sound IDs** prevent typos AND avoid per-emit allocations — a misspelled `&"player_hit"` would fail the `SoundConfig` lookup, but the interning catches it at the call site.

**Negative:**
- **SoundConfig is a Dictionary**, which means typos in sound IDs fail silently at lookup time (return null stream → no sound plays, no error). Mitigation: AudioManager emits `push_warning("SoundConfig missing entry for: %s" % sound_id)` on a null lookup.
- **AudioEmitterComponent is the second ADR 007 exception** (HitFeedbackComponent is the first). The exception is narrow and documented, but it's an exception.
- **Pool exhaustion is possible.** If 20 explosions fire simultaneously and the pool has 8 slots, 12 sounds are dropped. Pool size is a tuning parameter; when a playtester reports missing sounds we'll raise it.
- **No audio ducking** — dashing doesn't attenuate music, damage hit doesn't duck SFX. Deferred to post-Phase-11.
- **SFX positional attenuation** depends on `AudioStreamPlayer2D`'s built-in `max_distance` / `attenuation` exports. Tuning is per-stream; a designer has to set reasonable values on each `AudioStream` Resource.

## Alternatives Considered

**AudioManager as a service Node in `main.tscn`.** Rejected (A5). Music would stop on scene transitions. Keeping AudioManager in-scene would also complicate access — every publisher would need a reference.

**Hard-coded `match sound_id:` in AudioManager.** Rejected. Adding a new sound would require a GDScript edit; designers couldn't add audio without a programmer.

**Resource per sound (`PlayerHitSound.tres`, `CannonFireSound.tres`).** Rejected as over-granular. Each sound having its own `.tres` means every component needs an `@export var hit_sound: AudioStream` slot. A single `SoundConfig.tres` dictionary is less ceremony.

**Enum for sound IDs instead of StringName.** Considered. Enum is type-safe but adds a new file (`sound_ids.gd`) and forces every caller to `preload` it. StringName with interning is approximately as fast, more ergonomic, and doesn't require the extra import.

**Components emit to AudioManager directly, bypassing the bus.** Rejected. Bus-through gives us one canonical publish path (ADR 007) and lets future systems (logging, mute toggle, accessibility captions) subscribe without having to touch every component.

**Spatial audio via `AudioListener2D`.** The camera is the implicit listener; `AudioStreamPlayer2D` handles attenuation relative to it. A dedicated `AudioListener2D` Node gets added only if the attenuation behavior needs tweaking (e.g., during freeze-frame).
