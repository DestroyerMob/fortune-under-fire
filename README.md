# Fortune Under Fire

Fortune Under Fire is an early Godot 3D board-game prototype. The current work
focuses on the board route, entity movement, local turn flow, and camera
presentation before networking is added.

## Current systems

- The 11×11 and 13×13 boards build a clockwise, ordered array of `Plot` nodes.
- The board tracks each entity's plot index, sums its two dice, wraps movement,
  emits `past_start(entity)` when appropriate, and resolves the landing plot.
- `GameCamera` can smoothly switch between any human or AI-controlled entity.
- The camera follows the active entity from outside its board segment, using
  fixed inward edge views and diagonal 45-degree corner views.
- Entities have an explicit board-height offset, and the test scene uses soft
  directional shadows, ambient occlusion, and AgX tone mapping for depth.
- Plot resources populate both boards with eight coloured property groups and
  four card plots.
- Card plots award their configured card to the landing entity's hand.
- `GameManager` runs a dynamic one-to-four participant turn order, round count,
  human dice input, AI turns, defeat skipping, and match completion.
- Entities begin each match with 100 health and 200 money.
- The game opens on a main menu with a two-to-four-player setup. Player 1 is
  human-controlled and every remaining participant is AI-controlled.
- The game HUD exposes Roll Dice and End Turn actions and reports the active
  round, participant, and latest dice result.

## Camera

The camera is target-agnostic: it follows the entity whose turn is being shown,
not a node assumed to be the player. `GameManager` hands each active entity to
the local camera with:

```gdscript
game_camera.focus_turn_target(active_entity)
```

The target's registered plot selects one of eight stable views: four cardinal
directions for the board edges and four 45-degree diagonals for its corners. The
camera translates with the entity along an edge without rotating, then smoothly
turns 45 degrees at each edge/corner transition. Orthographic projection, fixed
follow distance, and fixed elevation keep plot scale stable. Optional moving
distance, angle, and zoom settings remain available, but dynamic movement
framing is disabled by default.

The camera maintains a separate smoothed focal point, so instantaneous gameplay
state changes do not make the view snap directly to the destination plot.

`CameraSettings.TargetMode.ALL_TURNS` follows every human and NPC turn. This is
also the correct mode for spectating a fully AI game.
`CameraSettings.TargetMode.LOCAL_PLAYER_ONLY` keeps the camera on the account's
local entity. The lower-level `track_target()` method deliberately ignores that
preference for cutscenes and spectator controls.

Camera settings are local presentation preferences. They should be saved with
the local account/profile and must not be synchronized as authoritative match
state. The default resource is `res://resources/default_camera_settings.tres`;
an account settings system can duplicate it and replace the camera's `settings`
resource with the saved profile values.

## Movement

Movement is owned by the board so human players, NPCs, and remote players all
use the same route and wrapping rules:

```gdscript
var dice_values := entity._roll()
var destination_index := await board.move_entity(entity, dice_values)
```

In the game scene, pressing Space or selecting Roll Dice triggers the `roll_dice`
input action. `GameManager` rolls for the active human and sends the result
through this board movement API. Once movement finishes, End Turn advances to
the next participant.

The board emits `past_start(entity)` once for every completed lap before it runs
the destination plot's `on_land(entity)` behaviour. The future Start plot logic
can connect to this signal without being built into generic movement code.

Entities tween through every intermediate plot instead of teleporting to the
destination. Step duration is calculated from world distance; longer gaps use a
higher travel speed and take proportionally less extra time. The default speed
is intentionally relaxed at `5.0` world units per second.

`plot_passed(entity, plot, index)` fires only for intermediate plots.
`plot_landed(entity, plot, index)` and the plot's `on_land(entity)` run only once
the entity physically reaches its final destination. Pass effects can interrupt
the remaining route with `board.stop_entity_movement(entity)`, allowing future
traps to freeze an entity as it crosses their plot. `movement_started`,
`movement_interrupted`, and `movement_finished` expose the wider lifecycle to
UI, audio, and turn-management code. An entity cannot begin another roll while
its current movement is active.

## Match and turns

`GameManager` owns the participant list and match lifecycle. The exported
`participants` array defines turn order and accepts between one and four unique
`Entity` nodes, so the manager does not depend on nodes being named `Player1`,
`Player2`, and so on. It sanitizes invalid or duplicate entries and caps the
match at four participants.

At match start, the manager resets each entity, registers it with the board,
starts round one, and tells the camera to focus on the active entity. Pressing
Space rolls only for the active human participant. The manager awaits the full
board movement and landing resolution, then waits for End Turn before advancing.
`EntityType.AI` participants automatically roll after the configurable
`ai_roll_delay` and end their turn as soon as their movement resolves.

The principal lifecycle signals are `match_started`, `round_started`,
`turn_started`, `dice_rolled`, `roll_finished`, `turn_finished`, `turn_skipped`,
and `match_finished`. Defeated participants are skipped, and the match finishes
when one participant remains. `play_active_turn(dice_values)` is also available
for tests and future authoritative multiplayer logic where validated dice should
be supplied rather than generated locally; `request_end_turn()` performs the
shared end-turn validation.

Each entity has configurable `max_health` and `starting_money`, defaulting to
100 and 200. Runtime values are exposed as `health` and `money` and reset at the
beginning of a match. Use `take_damage()`, `heal()`, `add_money()`, and
`spend_money()` instead of changing them directly so UI can react to the
`health_changed`, `money_changed`, and `defeated` signals.

## Property groups and card plots

Plot behaviour and presentation are data-driven. Each `Plot` references a
`PlotData` resource, while property plots additionally reference one shared
`PropertyGroupData` resource. The shared group owns its colour and current
value, so every property in that group updates together. The raised `Top` mesh
uses that colour; the lower mesh keeps the single shared board-base material.

The initial groups are:

| Group | Value |
| --- | ---: |
| Ironworks | 100 |
| Verdant Ward | 125 |
| Ember Quarter | 150 |
| Royal Foundry | 175 |
| Arcane Reach | 200 |
| Tidal Bastion | 225 |
| Crimson Court | 250 |
| Obsidian Crown | 300 |

Group resources live in `res://resources/property_groups/`. Future effects such
as a completed-set damage bonus should be added to `PropertyGroupData`, then
read by the combat or ownership system. This keeps the bonus out of individual
plot nodes and ensures the entire set shares one authoritative value.

Each side of the 13×13 board contains five properties, one gold card plot, then
five properties from the next group. The 11×11 version uses groups of four with
the same central card plot.

Card selection and card ownership are separate:

- `CardSelector.deck` is an exported `Array[CardData]` containing the cards that
  a card plot may award. The current shared tactics deck contains four starter
  cards. Repeating an entry in this array acts as simple draw weighting.
- `Entity.hand` is a `Dictionary[CardData, int]`. Each key is the card resource
  and its value is the quantity that entity currently holds, so duplicate draws
  increment a count instead of adding duplicate array entries.

Landing on a card plot asks its selector for a random card, calls
`Entity.add_card()`, and emits both `Entity.card_added` and `Plot.card_awarded`
for future UI and turn logic. `CardSelector.draw_card()` also accepts a seeded
`RandomNumberGenerator`; authoritative multiplayer match logic should provide
that RNG or replicate the selected card result. Network save payloads should use
`CardData.card_id` and quantity rather than attempting to transmit Resource keys
directly. The starter card effects themselves remain placeholders.

## Planned match structure

These are wider design requirements that remain beyond the current local turn
manager:

- A match supports one to four participants.
- Each participant can independently be a human player or an NPC.
- Supported combinations include one human against three NPCs, mixed multiplayer
  and NPC matches, four human players, and fully AI-controlled games.
- Human multiplayer will eventually support remote players. Match rules and turn
  results should be authoritative and separate from each client's local camera.
- Matches can be free-for-all or team-based.
- Team membership belongs to participant/match data rather than the `Entity`
  movement or camera code.
- Remote multiplayer must make match actions authoritative and synchronize
  validated turn results to every client.

Keeping participant control type, teams, turn rules, and camera preferences
separate allows the same match simulation to run locally, over multiplayer, or
without any human players.
