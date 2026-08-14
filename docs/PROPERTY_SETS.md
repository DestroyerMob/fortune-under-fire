# Property Sets and Control Powers

This is the authoritative design record for the eight five-plot sets. Balance
numbers remain provisional; names, board order, global scope, and ownership of
the mechanics are stable until this document is deliberately revised.

## Board order

The main board contains 48 spaces: 40 properties, four card spaces, and four
corners. Starting at Start and following the movement route, each side follows:

> Corner → five properties → card space → five properties → corner

The sides are:

1. Ironworks → Verdant Ward
2. Tidal Bastion → Arcane Reach
3. Obsidian Crown → Crimson Court
4. Ember Quarter → Royal Foundry

Complete control always grants a player-level power. A set bonus is never
restricted to buildings placed inside its own five plots.

## Control powers

| Set | Power | Intended rule | Current prototype |
| --- | --- | --- | --- |
| Ironworks | Industrial Efficiency | First building or upgrade each turn is substantially cheaper | Playable: 25% off the first construction; upgrades will share this use |
| Verdant Ward | Living Ward | Gain one Ward per lap; optionally spend after an attack to reduce damage and clear its status | Playable foundation: one charge, currently auto-spent to halve the first building attack; statuses/reaction choice pending |
| Tidal Bastion | Guided Current | Once per turn after rolling, change movement by +1 or −1 | Playable with −1, unchanged, and +1 movement choices |
| Arcane Reach | Intelligence Network | Reveal the upcoming roll before pre-roll banking, cards, and other decisions | Playable; the shown dice are authoritative and become the actual roll |
| Obsidian Crown | Sovereign Claim | Once per lap, force eligible enemy land into a compensated hostile auction with owner protection | Control and lap charge implemented; auction resolver and targeting UI pending |
| Crimson Court | Tribute | First property payment from each opponent per lap creates an additional treasury payment | Playable at 20%; the opponent pays only the original amount |
| Ember Quarter | Overcharge | Once per lap, optionally empower one attack-building activation | Playable foundation: one charge, currently auto-spent on the first attack for +50%; activation choice/Burn pending |
| Royal Foundry | Masterwork Commission | At each lap, choose and attach a temporary module to any owned building until the next lap | Control and lap charge implemented; typed module attachment and selection UI pending |

## Future integration contracts

Sovereign Claim must be an auction, not a property-steal command. The owner must
receive the winning proceeds and retain protection such as a reserve, matching
right, or bidding advantage. Highly developed properties must be ineligible.

Masterwork Commission must attach typed temporary state to one Plot/building;
it must not mutate the shared `BuildingData` resource. Initial module candidates:

- Coin Press: one economic building produces 30% more;
- Rangefinder: one support weapon gains route range;
- Reinforced Mechanism: one building cannot be disabled this lap;
- Hair Trigger: one local attack gains an additional trigger;
- Efficient Core: the next activation repeats at reduced strength.

When upgrades and status effects arrive, Industrial Efficiency must share one
turn use across construction and upgrades, while Living Ward must clear only the
status attached by the attack it blocks.

## Visual identities

- Ironworks: exposed steel, smoke, rail lines, and mass-production machinery.
- Verdant Ward: living fortifications, gardens, and defensive growth.
- Tidal Bastion: engineered waterways, sea walls, and guided currents.
- Arcane Reach: observatories, signals, and information infrastructure.
- Obsidian Crown: severe monumental power and controlled territory.
- Crimson Court: wealth, ceremony, patronage, and tribute.
- Ember Quarter: fire-lit streets, glowing masonry, heat vents, and urban
  furnaces—not another conventional factory district.
- Royal Foundry: gilded precision engineering and prestigious one-off works.

In short: Ironworks mass-produces, Ember Quarter weaponises heat, and Royal
Foundry creates masterworks.
