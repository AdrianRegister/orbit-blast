# Factions and reputation

How factions are defined, how the player's reputation with them works, how it changes, how other systems use it, and the Factions screen. For who owns which settlement and contested systems see [galaxy.md](galaxy.md) section 15; for contracts see [missions.md](missions.md); for saving see [save-system.md](save-system.md). The wars system that will sit on top of this is sketched in `wars_system.md`.

---

## 1. Faction definitions

A faction is one `Faction` resource in `resources/factions/` (`scripts/resources/faction.gd`). Everything specific to a faction is data there, nothing is in code:

| Field | Meaning |
|---|---|
| `id` | Permanent (`faction_1`). Content and saves refer to it. Compare factions by id |
| `display_name` | "Federation". The only place the name is written |
| `primary_colour`, `secondary_colour` | Identity colours (the Federation: dark yellow taken from its ship sprites, and white) |
| `description`, `political_identity`, `background` | Text shown on the Factions screen |
| `military_strength` | An arbitrary number for now; it will be computed from territory and fleets (see `wars_system.md`) |
| `capital_system` | The id of the faction's capital system (Federation: `sol`), or empty. Must be an inhabited system whose class can be a centre of power. Zones are measured from it; see [system_classes.md](system_classes.md) |
| `relations` | `FactionRelation` entries: how this faction regards another (`attitude` -100 to 100, `at_war`) |

To add a faction, add a `.tres` with a new id. `ContentRegistry.factions()` finds it and the Factions screen lists it. **Relations belong to pairs of factions and have nothing to do with the player's reputation**; today there are none (one faction). Like ownership, a runtime layer for relations (changed by wars while playing, and saved) will be added with the wars system; the data shape is here.

**Territory.** The Federation owns every system now in the galaxy (`data/galaxy/galaxy_map.json`).

---

## 2. Reputation

`ReputationManager` (`scripts/reputation/reputation_manager.gd`, a node in `main.tscn`, no Autoload) holds the player's reputation with each faction, from -100 to +100. A new player is neutral (0) with everyone. A faction that is not in the data (including one added later) is neutral, so adding factions needs no change here.

The scale and wording are one resource, `resources/reputation/standings.tres` (`ReputationStandings`, `ReputationLevel`): the minimum, maximum, starting value and the level names with their lower bounds. Today: Hated (-100), Hostile (-80), Unfriendly (-60), Wary (-40), Neutral (-20 to 19), Favourable (20), Friendly (40), Trusted (60), Honoured (80). Change the thresholds or names there.

API: `get_reputation(faction)`, `get_standing(faction)`, `change(faction, amount, reason)` (clamped; emits `reputation_changed` and, when the name changes, `standing_changed`), `meets(faction, minimum)`.

---

## 3. How reputation changes

Reputation is about **military service and hostile acts**. Civilian contracts never change it.

- **Contracts.** A `Contract` has `reputation_change` (default 0, set per contract) and `reputation_applied`. `ReputationManager.apply_contract()` is connected to `ContractManager.contract_completed`. It changes the **issuing faction's** reputation by `reputation_change` only if the contract is `MILITARY`, then sets `reputation_applied`, so it applies once (also across saving and loading). A civilian contract is ignored whatever number it carries. The generator and the existing civilian contract types do not use it. Military contracts will set `authority = MILITARY` and `reputation_change`.
- **Hostile acts.** `HostileActionType` resources (`resources/reputation/hostile_actions/`: attack a ship, destroy a ship, attack a settlement, piracy) hold the penalty for each kind of act. When combat exists it calls `report_hostile_action(type, victim_faction, event_id)`; the same `event_id` is only counted once. For an act in space against an unaffiliated civilian, `report_hostile_action_in_system(type, system_id, event_id)` charges the faction that controls the system (a contested or unclaimed system charges nobody). Nothing calls these yet.

---

## 4. Consequences (the foundation)

Other systems read reputation only through `ReputationManager`:

- **Contract eligibility.** `Contract.required_reputation` (default -100 = no requirement). `ContractManager.check_accept()` returns `REPUTATION_TOO_LOW` ("YOUR REPUTATION WITH THIS FACTION IS TOO LOW") if the player's reputation with the issuing faction is below it. Nothing sets a requirement yet, so nothing is restricted today.
- Which military contracts are offered, access to faction-controlled locations and services, and prestigious opportunities will use the same `meets()` and the standing name.
- **Not done on purpose:** reputation does not touch market prices or any economy modifier.

---

## 5. The Factions screen

A **FACTIONS** button in the top bar across the space view (the 80% not taken by the HUD panel), or the **F** key, opens `FactionScreen` (`scenes/ui/faction_screen.tscn`, same conventions as the galaxy map: it pauses the game, F or Esc or BACK closes it). The left list is built from the factions it is given. The details show the name, description, colour swatches, military strength, the player's reputation (standing, the number and a -100 to +100 bar in the faction colour), political identity, background, territory (systems controlled and known to the player, settlements, contested systems) and relations. The top bar (`scenes/ui/top_bar.tscn`) is a row of buttons; another screen is another button.

---

## 6. Saving

An optional `reputation` section `{"values": {faction id: int}}` with only the factions whose reputation is not 0. Older saves have none and load neutral. Unknown faction ids and values off the scale are rejected. Contracts also save `reputation_change`, `reputation_applied` and `required_reputation` (optional on load).

---

## 7. Tests

`scripts/tests/reputation_test.gd` (every standing boundary, clamping, civilian contracts changing nothing, military awards once, hostile acts once, relations independent of reputation, the eligibility check, saving) and `scripts/tests/faction_screen_test.gd` (the button and F key, the details, a second faction, closing, the top bar).
