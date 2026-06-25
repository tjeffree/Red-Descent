# Red Descent — Endgame Gating Changes

**Status:** implemented (2026-06-25)
**Owner:** design
**Relates to:** GDD §7 (Climax & Endgame), `scripts/endgame.gd`, `scripts/main.gd`, `scripts/game_state.gd`

## Summary

Right now, reaching the bottom of the Ruins shaft and docking at the capsule
terminal **always** launches the endgame cinematic. That's wrong for the
story: the capsule has no power of its own. It runs on the salvaged mother
ship — **the wreckage on the surface — and the capsule can't launch until the
wreckage is completely restored.**

The change: **gate the endgame on the wreckage being fully restored.** If the
rig reaches the capsule terminal before the wreckage is complete, it can't
dock — instead it returns to the surface, with a clear message about *why*
(the capsule is dead until the wreckage is finished).

## Narrative framing (the "what's going on")

The crashed mother ship on the surface is the power source. The capsule at the
bottom of the shaft is the lifeboat — but it's inert until the wreckage can
feed it. So the loop the player now understands:

1. Dive, mine Alloy, recall.
2. Spend Alloy in the hub to **restore the wreckage** (the existing ship-repair
   track — Hull Breach Seal → Comms Array → Nav Computer → Drive Core).
3. Only once the wreckage is **fully restored** does descending to the capsule
   terminal trigger the escape.

If the player reaches the bottom early, the capsule terminal reads as dead.
The rig auto-returns to the surface with a transmission explaining the
wreckage still needs to be restored before the capsule can be powered.

### How the wreckage and the rig sacrifice fit together (resolved)

The existing cinematic has the player sacrifice **the rig's own power** into
the capsule ("Every system you ever bolted on, poured into the capsule"). We
keep that — but the **restored wreckage is what makes the rig capable of
carrying and delivering that charge** in the first place.

The reading: the capsule needs a massive one-shot power transfer, far more than
the rig can hold or conduct on its own. The salvaged systems from the wreckage —
the sealed hull, the comms array, the nav computer, the drive core — are what
let the rig become the conduit: hardened to carry the load, synced to the
capsule, able to make the transfer without burning out before it completes.
Until the wreckage is whole, **the rig physically can't carry the power to the
capsule** — so docking does nothing and the terminal stays dead.

This keeps the rig-sacrifice cinematic exactly as-is (the existing
`endgame.gd`), makes the wreckage restoration a hard, *mechanical* precondition
(not just flavour), and gives the bounce-back message its reason: not "the
capsule isn't ready," but "the rig can't carry the power yet — finish the
wreckage." No cinematic rewrite is required.

## Current behaviour (for reference)

`scripts/main.gd` → `_process_diving()`:

```gdscript
# At the capsule terminal (shaft bottom) docking takes over from recall — this
# begins the endgame (GDD §7): the rig is sacrificed to launch the capsule.
if player.global_position.distance_to(terrain.capsule_position()) < DOCK_RANGE:
    hud.set_return_available(false)
    hud.set_dock_prompt("[E] DOCK — give the capsule the rig's power")
    if Input.is_action_just_pressed("interact"):
        hud.set_dock_prompt("")
        Audio.stop_oneshots()
        Audio.ui("confirm")
        Audio.stop_loops()
        get_tree().change_scene_to_file(ENDGAME_SCENE)
    return
hud.set_dock_prompt("")
```

There is **no check** against wreckage/ship-repair state. The relevant state
already exists in `GameState`:

- `GameState.ship_complete() -> bool` — true only when all four `SHIP_PARTS`
  are repaired.
- `GameState.repaired_count() -> int` and `GameState.ship_progress() -> float`
  — for showing progress in the "not yet" message.

## Required changes

### 1. Gate docking on `ship_complete()` (`scripts/main.gd`)

In `_process_diving()`, split the capsule-terminal branch on
`GameState.ship_complete()`:

- **Wreckage complete** → behaves exactly as today: show the dock prompt, and
  on `interact` change to `ENDGAME_SCENE`.
- **Wreckage NOT complete** → do **not** offer docking. Instead trigger an
  automatic return to the surface with an explanatory banner/transmission, and
  do *not* change to the endgame scene.

Sketch:

```gdscript
if player.global_position.distance_to(terrain.capsule_position()) < DOCK_RANGE:
    hud.set_return_available(false)
    if GameState.ship_complete():
        hud.set_dock_prompt("[E] DOCK — give the capsule the rig's power")
        if Input.is_action_just_pressed("interact"):
            hud.set_dock_prompt("")
            Audio.stop_oneshots()
            Audio.ui("confirm")
            Audio.stop_loops()
            get_tree().change_scene_to_file(ENDGAME_SCENE)
    else:
        _reject_dock()   # capsule is dead — bounce back to the surface
    return
hud.set_dock_prompt("")
```

### 2. The "capsule is dead" return-to-surface (`scripts/main.gd`)

Add a helper that explains the situation and sends the rig home. It should
reuse the existing ascent path so it feels like a recall (ore is still banked —
the run wasn't wasted), but with messaging about the capsule rather than a
voluntary recall.

```gdscript
## Reached the capsule terminal but the wreckage isn't restored yet — the
## capsule has no power. Explain, bank the run, and ascend.
func _reject_dock() -> void:
    hud.set_dock_prompt("")
    hud.set_return_available(false)
    var parts_left := GameState.SHIP_PARTS.size() - GameState.repaired_count()
    GameState.record_run("CAPSULE DEAD — rig can't carry the power", player.ore_collected, player.current_depth, true)
    hud.show_banner(
        "THE CAPSULE WON'T WAKE\n" +
        "The rig can't carry a charge this big — not until the wreckage is whole.\n" +
        "%d ship system(s) still to restore. Ascending...  (+%d alloy)" % [parts_left, player.ore_collected])
    Audio.ui("confirm")   # or a distinct "powerless/denied" cue if one is added
    player.start_ascent()
    _state = "ascending"
    _timer = ASCENT_MAX
```

Decisions baked into the sketch (confirm during implementation):

- **Auto-return with a lingering banner (decided).** The rig auto-ascends on
  arrival — there's nothing to *do* at a dead terminal, so no prompt. The banner
  carries the explanation and stays up through the ascent (which already pauses
  via `ASCENT_PAUSE`).
- **Ore is banked** (`record_run(..., banked = true)`), so the trip down still
  pays out — important, since the player will likely hit the bottom several
  times before the wreckage is done.
- **Run record text** distinguishes this outcome from a normal recall/death in
  the hub's last-run line.

### 3. HUD / approach feedback (optional but recommended)

Without docking available, the player needs to understand *before* arriving why
the terminal won't respond. Options, in priority order:

- **A pre-arrival transmission** (Phase 7 lore system): when the rig first
  enters the Ruins biome with the wreckage incomplete, fire a pilot line like
  *"Even if you reach the capsule, the rig can't carry a charge that big — not
  until the wreckage up top is whole."* Add as a `Lore.TRANSMISSIONS` entry gated
  on `not GameState.ship_complete()`.
- **A terminal hint** while in dock range (handled by the banner in `_reject_dock`).
- **Hub-side signposting:** the ship-repair panel already shows progress; make
  sure it reads as "restore this to escape," not just a stat upgrade. Consider a
  line like "Capsule power: X/4 systems" near the repair track.

### 4. Wreckage visual already tracks restoration (no change needed)

`main.gd._wreckage_stage()` already drives the surface wreck sprite from
`GameState.repaired_count()` / `ship_complete()`, so the surface visibly
rebuilds as the player progresses. This reinforces the gate for free — when the
wreckage finally shows its complete (stage-3) sprite, that's the player's cue
that the capsule will now accept them.

## Edge cases & checks

- **First-completion timing.** `ship_complete()` flips in the hub (on the
  purchase that buys the last part), so by the time a dive starts it's already
  true — no mid-dive flip to worry about. Safe to read once at the terminal.
- **Start-at-depth.** A player can launch near the bottom via the telemetry
  checkpoint. The gate must hold there too — it does, since the check is on
  arrival at `capsule_position()`, not on dive start.
- **`escaped` flag.** Endgame still sets `GameState.escaped` via
  `sacrifice_rig()`. The reject path must **not** set it.
- **Audio.** `_reject_dock` should not call the endgame's `stop_loops` cinematic
  teardown — it stays in the dive, then ascends like a recall. Consider a
  dedicated "denied/powerless" UI cue instead of reusing `confirm`.

## Files to touch

| File | Change |
|------|--------|
| `scripts/main.gd` | Gate the dock branch on `ship_complete()`; add `_reject_dock()`. |
| `scripts/lore.gd` | (Optional) add the "capsule is dead until the wreckage is whole" transmission, gated on incomplete wreckage. |
| `scripts/hud.gd` | (Optional) banner/prompt copy; capsule-power signposting. |
| `scripts/endgame.gd` | Only if Option B (rewrite the power-source framing) is chosen. |
| `docs/Red_Descent_Spec_Addendum.md` | Update the phase/status table once implemented. |

## Acceptance criteria

1. Reaching the capsule terminal with the wreckage **incomplete** does **not**
   start the endgame; the rig returns to the surface with a message naming the
   wreckage as the reason and how many parts remain.
2. Ore collected on that dive is still banked.
3. Reaching the capsule terminal with the wreckage **complete** behaves exactly
   as today (dock prompt → endgame cinematic).
4. The player has at least one piece of feedback (transmission and/or banner)
   explaining the gate, not just a silent non-response.
5. Headless validation passes clean (no parse/runtime errors); a windowed
   harness confirms both the reject-and-ascend and the complete-and-dock paths.
