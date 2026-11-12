## Faction wars – proposed design

I would treat faction wars as a galaxy-wide strategic simulation, rather than simply adding combat missions between opposing factions. The important distinction is that the game simulates the war at two levels:

Strategic level: factions make decisions about territory, military resources, diplomacy and campaigns.
Tactical level: fleets engage, settlements are attacked, and the player can participate in individual military operations.

The strategic simulation should continue whether or not the player is present. The player can influence its outcome, but should not be required for wars to progress.

There is also an important architectural consideration: a system can contain settlements belonging to different factions. Consequently, ownership needs to be tracked at settlement level, not just system level.

Military value and military strength
System military value
Each system receives a military_value, calculated from its planets and stations.

Rather than assigning arbitrary values to entire systems, I recommend assigning military-value contributions to individual inhabited locations and their infrastructure.

Illustrative starting values:
Location or infrastructure Contribution
Resort world 1
Small civilian settlement 5
Industrial settlement 15
Agricultural settlement 8
Military installation 25
Station with shipyard 30
Station with outfitter 20
Major shipbuilding and military hub 50+

These are examples, not final balance values. A location could combine several contributions. For example, an industrial planet with a military installation would contribute more than either alone.

The system's value would be:
\[
MV*{system} = \sum MV*{location}
\]

This should be calculated from the system's actual infrastructure, preferably through configurable data rather than hardcoded checks for individual planet names.
Faction military strength
A faction's military strength represents its overall capacity to wage war. It is an abstraction of:

- Military manufacturing and industrial capacity.
- Recruitment and available personnel.
- Training and military experience.
- Logistics and infrastructure.
- Performance and fighting spirit.
  The starting strength should be derived from the military value of all owned systems:
  \[
  MS*{base} = \sum MV*{owned\ systems}
  \]

However, I recommend separating this into two components:

- Structural strength: derived from owned territory and its military value.
- Operational strength: temporarily affected by military losses, readiness, mobilisation and recovery.
  The displayed military_strength can combine both.

This avoids a problem where losing a fleet permanently reduces a faction's strength even though its industrial and recruitment capacity remains intact. It also avoids making territorial ownership the only factor determining military capability.

When territory changes hands, structural strength is recalculated. When fleets suffer losses, operational strength temporarily decreases and can recover over time. 2. Territory and system ownership
This is probably the most important modelling decision.

I recommend three related concepts:

- Settlement ownership: the faction controlling an individual inhabited planet or station.
- System control: the faction that politically or militarily controls the system.
- Contested status: a system in which multiple factions own settlements or are actively fighting for control.
  For systems with one settlement, capturing that settlement transfers system ownership to the victor.

For systems with multiple settlements:

- Capturing one settlement does not automatically transfer the entire system.
- If different factions control settlements, the system becomes contested.
- A contested system can become a frontline where military operations occur repeatedly.
- The system's strategic control should be determined by a clear rule, potentially based on settlement ownership and military value, rather than simply whichever faction captured the last settlement.
  This makes multi-settlement systems strategically interesting and gives the player meaningful opportunities to influence the war.

War and military campaigns

I would model a war as an entity with its own lifecycle and state.

A war should contain:

- Participating factions.
- Declaration date and reason.
- Objectives and territorial ambitions.
- Active campaigns and target systems.
- Current territorial situation.
- Casualties and military losses.
- Diplomatic status and peace negotiations.
- Historical events.
  Border-system selection
  Factions should generally select systems bordering enemy territory for military operations.

The AI should consider:

- Strategic military value.
- Number and importance of settlements.
- Existing military installations and shipyards.
- Proximity to friendly territory.
- Whether the system is already contested.
- Relative military strength.
- Other active campaigns and available forces.
  The AI should not simply attack the highest-value system every time. It should weigh the strategic importance against the likelihood and cost of success.
  Military actions
  I would define a common military-operation model with different operation types:
  Operation Objective Possible outcome
  Blockade Restrict access to a planet or station Reduced trade and supply
  Bombardment Damage infrastructure Reduced military/economic value
  Infrastructure raid Damage shipyards, facilities or installations Reduced system military value
  Ground assault Capture a settlement Change of settlement ownership
  Fleet engagement Defeat defending or attacking fleets Temporary military-strength losses

These should be individual operations belonging to a larger campaign, which in turn belongs to a war.

That hierarchy will be useful for tracking progress and presenting news.
Defensive response and fleet battles
The defending faction should respond to invasions and other major operations.

It can mobilise fleets according to its available operational strength, strategic priorities and the importance of the threatened system.

Fleet engagements should be simulated at a strategic level when the player is not involved. Their outcomes should depend on factors such as:

- Relative fleet strength.
- Military readiness.
- Available reinforcements.
- Location and defensive advantages.
- Existing operational losses.
  The game does not necessarily need to simulate hundreds of individual ships. It can calculate the outcome of a large engagement using an abstract battle model.

If the player participates, the battle can transition into actual gameplay, with the result influencing the strategic simulation.

Events, signals and galaxy-wide news
I strongly recommend an event-driven architecture.

War declarations, military operations, territorial changes, fleet engagements and peace negotiations should generate structured events.

Examples of Godot signals:
signal war_declared(war_id, aggressor_id, defender_id)
signal war_ended(war_id, outcome)
signal military_operation_started(operation_id, system_id)
signal military_operation_completed(operation_id, outcome)
signal settlement_captured(settlement_id, previous_owner, new_owner)
signal system_became_contested(system_id)
signal fleet_engagement_completed(engagement_id, outcome)
signal peace_negotiations_started(war_id)
signal peace_treaty_signed(war_id, treaty_id)

These are illustrative names; the final implementation should follow the project's existing conventions.

I would also maintain a persistent galactic event history. Signals notify interested systems immediately, while the event history provides a reliable source for news, historical records and save/load.

This distinction is important: signals are transient notifications, not a substitute for persistent state.
Bars and holonews
Settlements should provide information about current wars through bars and holonews.

News should be generated from actual simulation events, not independently invented by the UI.

Examples:

- The Federation declares war on another faction.
- A border system comes under blockade.
- A settlement is captured.
- A major fleet is destroyed.
- A system becomes contested.
- A faction begins peace negotiations.
  The amount of information available could depend on location and communication access. For example, local bars might have more detailed information about nearby battles than distant settlements.

Player participation
When wars and military operations are announced, the player should have opportunities to participate.

Two routes:

Mercenary participation

- The player voluntarily joins a faction's war effort.
- They can accept military contracts or missions.
- They might be hired as an escort, fleet support, blockade runner, raider or assault support pilot.
- Their actions influence the outcome of the relevant operation.
  Faction recruitment
- A faction may approach the player if their reputation is sufficiently high.
- This could lead to more important missions or a position commanding a fleet.
- It should feel like recognition of the player's service, not simply another generic contract.
  Participation should be optional. The war continues regardless of the player's decision.

This also provides a natural purpose for the reputation system: high Federation reputation can lead to recruitment, better military assignments and greater trust. 6. Diplomacy and peace
Diplomacy should be a separate system that interacts with wars.

Factions should have strategic objectives and evaluate whether continuing a war is worthwhile.
Declaring war
Possible considerations:

- Relative military strength.
- Territorial ambitions.
- Strategic value of neighbouring systems.
- Existing rivalries and diplomatic relationships.
- Previous territorial losses or provocations.
- Current internal stability and ability to sustain a war.
  A faction should not declare war simply because it has a negative relationship with another faction.
  Suing for peace
  A faction should consider peace when:
- It has lost a significant amount of territory.
- Its operational strength has fallen substantially.
- Its remaining military capacity is insufficient to continue.
- The cost of continuing exceeds the likely benefits.
- It has achieved its original objectives.
  Peace treaties
  Possible terms:
- Return captured systems.
- Cede systems to the victor.
- Pay financial tribute.
- Exchange systems.
- Agree to a ceasefire.
- Accept other diplomatic concessions.
  The AI should evaluate proposed terms according to strategic value, relative strength and the current situation. A faction should not accept an obviously unreasonable treaty simply because it has lost one battle.

Recommended implementation order
I would make this one of the final major systems, as you suggest. It depends on several systems already being in place or developed further.

Faction wars implementation roadmap

1. Foundation – faction and territory architecture

   Establish faction definitions, settlement ownership, system control, contested status, military values and military strength calculations. This should be considered when implementing the current faction/reputation milestone.

2. Military infrastructure and damage

   Add infrastructure condition, damage and recovery. Allow military operations to affect settlement and system military value.

3. War and campaign simulation

   Introduce war entities, objectives, border selection, campaigns, operations and strategic progress.

4. Fleet simulation and engagements

   Add fleet mobilisation, defensive responses, abstract battle resolution, casualties and operational-strength recovery.

5. Invasions and territorial changes

   Implement ground assaults, settlement capture, system ownership changes and contested frontlines.

6. Events and news

   Implement persistent galactic event history, Godot signals, bar news and holonews.

7. Player participation

   Allow the player to join military operations as a mercenary or through faction recruitment. Integrate with military contracts and reputation.

8. Diplomacy and peace

   Implement war declarations, diplomatic evaluation, peace negotiations, tribute and treaty resolution.

9. Balancing and persistence

   Tune the simulation, test long-running wars, ensure save/load reliability and prevent the galaxy from becoming trapped in endless wars or permanently static frontlines.

What to account for now, before implementing wars

The immediate faction and reputation implementation should anticipate these future requirements without implementing the war simulation itself.

### Current system -> Future requirement to accommodate

Faction definitions -> Multiple factions, relationships, territory and military properties
Settlement ownership -> Individual settlements can belong to different factions
System definitions -> Derived military value and contested status
Faction data -> Structural and operational military strength
Reputation -> Military recruitment, faction trust and eligibility
Contracts -> Military operations can generate player missions
Event -> architecture War and military events can be broadcast and recorded
Save/load -> Persistent wars, operations, ownership changes and military state

One particularly important decision: avoid making system ownership an inseparable property of the system itself. Make settlement ownership authoritative, with system control derived from it. That will prevent a difficult refactor when multi-settlement contested systems are introduced.

---

### Status (foundation in place)

Settlement ownership is authoritative and system control is derived from it (`TerritoryManager`, `SystemControl`), with a contested status and the signals `settlement_owner_changed`, `system_control_changed` and `system_became_contested`. Ownership changes are saved in the optional `territory` save section. Not built yet: military value, strength, wars, operations, news. See `docs/galaxy.md` section 15.

### Status (system roles, zones, damage and military value in place)

Phase 2.9 built the read access and the foundations a war needs, without any war: system classes (critical, economic and military centres, military output, rural, frontier), faction zones and centres of power that follow ownership (conquering a capital or critical system makes a mini-core), damage to locations that lowers production and recovers by itself, military value per location and system (`SystemAssessor`), and military goods and markets that anyone can trade. See `docs/system_classes.md` section 11 for where each is read. Still not built: wars, campaigns, operations, blockades, defenders and news.

### Status (ship combat foundations in place)

Phase 3.1 built the ship-level combat a war will rely on, without any war or NPC fighting: weapons and mounts as data, projectiles, the layered damage model (shields, armour, hull), destruction with a `DestructionReport` (victim, attacker, factions, system, day), the player's escape pod, repairs, and a `Combatant` interface that player input and, later, AI and formations drive. `ship_destroyed` and `DestructionReport` are the hook for fleet losses; a ship's stats, defences and loadout are plain data from which a combat rating can be derived for the abstract battle model. NPC ships carry weapons and can be destroyed but never fire. Still not built: NPC combat AI, squadrons and formations, convoys and escorts, fleet engagements, and wars themselves. See `docs/combat.md` section 11.

### Status (faction identity and reputation in place)

Factions carry colours, texts, `military_strength` (arbitrary for now) and `relations` that are separate from the player's reputation; reputation is tracked per faction with a central interface (`ReputationManager.meets`, standings), military contracts can award it, and hostile acts have an integration point. See `docs/factions.md`.
