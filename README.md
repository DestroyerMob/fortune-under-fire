# Fortune Under Fire

Fortune Under Fire is an early Godot 3D board-game prototype. The current work
focuses on the board route, entity movement, local turn flow, and camera
presentation before networking is added.

The living source-of-truth for system ownership, dependency rules, event flows,
and extension checklists is [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Update
it whenever a subsystem boundary or public contract changes.

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
- Every ownable plot has its own rent value and buy price, independently of its
  shared colour group.
- Landing on an unowned property creates a Buy/Decline decision in a menu
  anchored above the plot. The same menu asks trespassers to pay rent on owned
  properties and transfers it to the owner after confirmation.
- Owned properties display a persistent flag and label using their owner's
  entity colour and display name.
- Passing the green Start plot pays an entity the combined base rent of all
  properties they own, plus any Apartments and Casino activations. Each owned
  Bank separately credits interest to its stored balance.
- Card plots award their configured card to the landing entity's hand.
- Card plots use a shared parchment-ivory surface so they remain distinct from
  every saturated property group.
- `GameManager` is the stable command facade and owns match/turn validation;
  dedicated property-action, building-effect, AI-policy, and presentation
  systems handle their own responsibilities behind it.
- Entities begin each match with 100 health and 1,200 money.
- The game opens on a clean 2D main menu with its right-hand stage reserved for
  a future 3D background animation. Play opens the two-to-four-participant
  setup; Settings exposes saved camera and developer preferences. Any number of
  match seats can be local humans on one device; remaining seats are AI.
- Multi-human turns begin immediately and atomically switch health, funds,
  deeds, building controls, set powers, cards, camera context, and the shared
  Roll/End Turn action to that player. The persistent turn label names the
  human who currently has control.
- The game HUD exposes one Turn Action button that changes from Roll Dice to
  End Turn after rolling. The compact top-left status displays health and
  funds, the active turn sits at the top centre, and the latest dice result is
  right-aligned directly above the turn action. Property interactions appear
  separately above the affected in-world plot instead of using HUD hints.
- The local player's deeds live in a low-profile left-edge rail. Only their
  colour-coded tabs remain visible until hovered, when a deed slides out and
  previews its board plot. With no selection, leaving eases the camera back to
  the active player. Clicking selects exactly one deed as the default camera
  anchor until the local player's turn ends; clicking that deed again deselects
  it and restores the active player as the default anchor.
- The right-side plot panel shows construction choices for an empty selected
  property, then becomes a building manager once it is built. A selected Bank
  exposes its stored balance and turn-only deposit/withdraw controls.

## Camera

The camera is target-agnostic: it follows the entity whose turn is being shown,
not a node assumed to be the player. `TurnCameraController` reacts to the
authoritative `turn_started` result and hands that entity to the local camera:

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

Camera settings are local presentation preferences and are not synchronized as
authoritative match state. The Settings menu saves follow-all-turns and dynamic
movement choices to `user://settings.cfg`. `GameScreen` duplicates
`res://resources/default_camera_settings.tres` and applies those preferences
before starting each match.

## Movement

Movement is owned by the board so human players, NPCs, and remote players all
use the same route and wrapping rules:

```gdscript
var dice_values := entity.roll_dice()
var destination_index := await board.move_entity(entity, dice_values)
```

In the game scene, Space and the single Turn Action button share the
`turn_action` input path. Before the active entity rolls, the action is labelled
Roll Dice and starts movement. After movement finishes, the same action changes
to End Turn and advances to the next participant.

Developer options are off by default and can be enabled from Settings. While
enabled, pressing `C` during an active human turn grants that active player one
random card from the tactics deck and shows a compact confirmation. The input
routes through `GameManager.debug_grant_random_card()`, so it cannot grant to an
AI, a defeated entity, or an inactive participant.

The board emits `past_start(entity)` once for every completed lap after awarding
base property income and lap-building bonuses, but before destination landing.

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

## Properties and rent

Property groups provide shared presentation and a legacy default value, while
each concrete `Plot` node owns its economic settings. `base_rent` is the income
that property generates when its owner passes Start, `tower_rent` is the
modified amount charged to an enemy when the property has a Hotel, and
`buy_price` is the amount required to claim it. Tower rent defaults to twice the
base rent and can be overridden per plot. This lets adjacent plots in the same
colour group have different economics on both board sizes.

An unowned property emits a purchase offer when landed on. Human players decide
through the plot's hovering world menu; AI entities buy when they can afford the
listed price and otherwise decline. End Turn remains available: using it with
an unanswered offer declines the purchase automatically. A successful purchase
deducts the price, records the owner, and reveals that owner's colour-coded 3D
flag and name above the property.

Trespassers can confirm a Pay Rent action in the same plot-anchored menu. They
can also use End Turn directly, which settles the pending rent before advancing.
The full plot rent is transferred to its owner. If that mandatory payment takes
the payer below zero carried cash, the payer is eliminated for debt. End Turn
remains invalid before the active entity rolls unless they play Fold Early from
their hand.

The South-East route origin uses its own green `Start` plot resource. Each time
an entity wraps onto it, the board sums `get_base_rent()` for every property
owned by that entity, activates Apartments and Casinos, and adds the combined
total to their balance. Hotels do not alter this lap income; they affect enemy
landing rent only.

The main runtime APIs and signals are `request_property_purchase(entity,
should_purchase)`, `request_rent_payment(entity)`, `property_purchase_offered`,
`property_purchase_resolved`, `rent_payment_required`, and `rent_paid`.

## Buildings

Each owned property has one construction site. Selecting its deed opens the
contextual building palette on the right side of the screen; deselecting the
deed hides it. After construction, that palette becomes a contextual plot and
building manager. Construction and management are available to the active owner
while movement and landing actions are idle. Construction costs money
immediately and permits only one base building per plot. AI participants buy
from the same eight definitions after claiming a property when they can afford
one.

The initial buildings cover separate economic, damage, and support activation
models:

| Building | Cost | Base effect |
| --- | ---: | --- |
| Apartments | $140 | Adds $40 whenever the owner passes Start |
| Hotel | $180 | Charges the plot's configured tower rent on enemy landing |
| Casino | $160 | Rolls 1–6 and pays $15 for each point whenever the owner passes Start |
| Bank | $200 | Stores carried cash and credits 10% interest to that Bank whenever its owner passes Start |
| Gun Tower | $120 | Deals 18 damage when an opponent lands on its plot |
| Artillery Battery | $190 | Deals 12 support damage when an opponent lands on an owned property within five plots |
| Tesla Coil | $170 | Deals 8 damage per connected coil when its plot is landed on; coils connect within four plots |
| Medic Tower | $150 | Charges no rent and heals only its owner for 10 when they land on it |

Building definitions are `BuildingData` resources under
`res://resources/buildings/`. `GameManager.request_construct_building()` is the
authoritative construction path. `building_constructed` and the typed
`building_effect_resolved(BuildingActivation)` expose results for animation,
audio, save, and multiplayer replication. `building_activated` remains a
temporary positional compatibility signal. Upgrade trees are intentionally
deferred until these base activation loops have been play-tested.

Bank balances are authoritative property state and stay separate from the
owner's carried cash. The owner may deposit or withdraw only during their own
idle turn. Interest is credited to the stored Bank balance, not to carried cash,
and Bank funds never automatically cover rent or debt.

Money gained from completing a lap or collecting rent appears as a compact,
world-space amount above the affected entities. Rent also shows the payer's
loss, while local balance changes pulse as an inline delta beside Funds so
off-camera income remains visible. Damage buildings pulse when firing and their
targets briefly flash with a small damage amount. Every entity carries a slim,
colour-coded health bar above its piece. The camera holds on rent payers and
damage or healing targets while their result resolves, then follows the next
turn normally. The UI uses “roll 1–6” instead of
tabletop dice notation such as `d6`.

## Match and turns

`GameManager` owns the participant list and match lifecycle. The exported
`participants` array defines turn order and accepts between one and four unique
`Entity` nodes, so the manager does not depend on nodes being named `Player1`,
`Player2`, and so on. It sanitizes invalid or duplicate entries and caps the
match at four participants.

At match start, the manager resets each entity, registers it with the board,
and starts round one. The local `TurnCameraController` follows the resulting
active entity. Pressing Space rolls only for the active human participant. The manager awaits the full
board movement and landing resolution, then waits for End Turn before advancing.
`AiTurnController` submits normal public commands for `EntityType.AI`
participants after the configurable `ai_roll_delay`.

The principal lifecycle signals are `match_started`, `round_started`,
`turn_started`, `dice_rolled`, `roll_finished`, `turn_finished`, `turn_skipped`,
and `match_finished`. Defeated participants are skipped, and the match finishes
when one participant remains; that last participant wins. An entity loses when
health reaches zero or carried money becomes negative. Zero money is safe, and
stored Bank balances do not prevent debt defeat. `play_active_turn(dice_values)` is also available
for tests and future authoritative multiplayer logic where validated dice should
be supplied rather than generated locally; `request_end_turn()` performs the
shared end-turn validation.

Each entity has configurable `max_health` and `starting_money`, defaulting to
100 and 1,200. Runtime values are exposed as `health` and `money` and reset at the
beginning of a match. Use `take_damage()`, `heal()`, `add_money()`, and
`spend_money()` for voluntary changes and `pay_obligation()` for mandatory
payments that may create debt, so UI can react to the
`health_changed`, `money_changed`, and `defeated` signals.

## Property groups and card plots

Plot behaviour and presentation are data-driven. Each `Plot` references a
`PlotData` resource, while property plots additionally reference one shared
`PropertyGroupData` resource. The shared group owns its colour and legacy
default value; each concrete plot can override its own rent and purchase price.
The raised `Top` mesh uses the group colour; the lower mesh keeps the single
shared board-base material.

The main-board groups and their global complete-control powers are:

| Group | Value | Complete-control power |
| --- | ---: | --- |
| Ironworks | 100 | Industrial Efficiency |
| Verdant Ward | 125 | Living Ward |
| Tidal Bastion | 225 | Guided Current |
| Arcane Reach | 200 | Intelligence Network |
| Obsidian Crown | 300 | Sovereign Claim |
| Crimson Court | 250 | Tribute |
| Ember Quarter | 150 | Overcharge |
| Royal Foundry | 175 | Masterwork Commission |

Group resources live in `res://resources/property_groups/`. `PropertyGroupData`
declares each power; `SetBonusSystem` derives complete control and owns its
turn/lap uses. See `docs/PROPERTY_SETS.md` for the board order, intended rules,
and implementation status.

Each side of the 13×13 board contains five properties, one gold card plot, then
five properties from the next group. From Start the sides are Ironworks →
Verdant Ward, Tidal Bastion → Arcane Reach, Obsidian Crown → Crimson Court, and
Ember Quarter → Royal Foundry. The 11×11 scene remains a legacy compact board;
it cannot complete the new five-property control condition.

Card selection and card ownership are separate:

- `CardSelector.deck` is an exported `Array[CardData]` containing the cards that
  a card plot may award. The current shared tactics deck contains three playable
  cards. Repeating an entry in this array acts as simple draw weighting.
- `Entity.hand` is a `Dictionary[CardData, int]`. Each key is the card resource
  and its value is the quantity that entity currently holds, so duplicate draws
  increment a count instead of adding duplicate array entries.

Landing on a card plot asks its selector for a random card, calls
`Entity.add_card()`, and emits both `Entity.card_added` and `Plot.card_awarded`
so the bottom hand updates immediately. Portrait cards use the colour stored in
their `CardData` resource (or a stable ID-derived fallback), with a type banner,
quantity, title, suit panel, printed rule, and interaction footer. The hand
rests mostly below the screen as a row of narrow coloured tabs and slides up only
while that occupied area is hovered. A card is played by dragging it—not by
clicking. Self-cast cards are released near the centre; cards whose data targets
properties are released over an ownable board plot. These targets have no
on-screen drop-zone panels. Every held card stays draggable. Releasing a card
asks gameplay authority whether it can activate now: rejected attempts animate
back into the hand, while accepted cards settle into their target and fly off
screen before the effect resolves.

The first playable deck contains:

- **Fold Early:** end the active turn before rolling.
- **Overtime:** after a roll, grant one additional roll in the same turn.
- **Hospital Run:** move forward along the real route to the nearest built Medic
  Tower. Crossing Start awards normal lap income and the destination still runs
  its ordinary owner-only Medic activation. Each player can successfully use
  Hospital Run only once per round; rejected extra attempts remain in hand.

`CardSelector.draw_card()` also accepts a seeded
`RandomNumberGenerator`; authoritative multiplayer match logic should provide
that RNG or replicate the selected card result. Network save payloads should use
`CardData.card_id` and quantity rather than attempting to transmit Resource keys
directly.

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
