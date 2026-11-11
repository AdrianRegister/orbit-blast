## Future architecture consideration: faction wars

Faction wars will be one of the final major systems implemented. Do not implement wars, combat or military operations now. However, consider the following planned mechanics when designing the current faction, territory, reputation and event architecture.

### Strategic simulation

- Each star system will have a `military_value`, calculated from the combined military contributions of its planets and stations.
- Individual locations contribute different values according to their infrastructure. Shipyards, outfitters, military installations and industrial settlements contribute significantly; resort worlds contribute very little.
- Each faction will have a mutable `military_strength`, initially derived from the total military value of its owned systems.
- Military strength must accommodate both permanent changes from territorial gains/losses and temporary changes from fleet casualties, readiness and recovery.

### Territory

- Settlement ownership must be tracked independently for each inhabited planet or station.
- System control should be derived from settlement ownership rather than being an inseparable property of the system.
- A system containing settlements belonging to multiple factions becomes contested.
- Capturing the sole settlement in a system transfers system ownership. Capturing settlements in multi-settlement systems can create contested territory and prolonged frontlines.

### Wars and military operations

Factions at war will select strategically valuable border systems for military campaigns.

Operations will include:

- Blockades and bombardments.
- Infrastructure raids.
- Ground assaults and settlement invasions.
- Large fleet engagements.

Defending factions will mobilise fleets according to their available military strength. Fleet battles will have casualties and temporary effects on operational military strength. Successful ground assaults can transfer settlement ownership.

### Events and player participation

- War declarations, military operations, fleet engagements, territorial changes and peace negotiations must be publishable as Godot signals.
- Maintain persistent galactic event history independently of transient signals.
- Bars and holonews will present information about wars and their progress.
- The player will eventually be able to join wars as a mercenary pilot or fleet captain, or receive recruitment offers from factions when their reputation is sufficiently high.

### Diplomacy

Factions will eventually evaluate when to declare war, continue fighting or sue for peace based on territorial objectives, relative military strength, losses and strategic value.

Peace treaties may include territorial concessions, financial tribute, exchanges of systems and ceasefires.

### Design requirement for the current implementation

Keep the current faction and reputation architecture compatible with these future systems. In particular:

- Keep faction definitions separate from individual settlement ownership.
- Keep faction-to-faction relationships separate from player reputation.
- Make military value and military strength possible to calculate and update without redesigning faction data.
- Keep event publishing and persistent event history extensible.
- Ensure save/load can eventually accommodate changing territory and persistent galaxy-wide events.

Do not build speculative war functionality or add unnecessary complexity now. Identify the architectural decisions and interfaces that should be established in the current implementation, and explain how they will support the future war simulation.
