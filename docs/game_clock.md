# The Game Clock

Time in Orbit Blast is a whole number of **days** since the game began. It does not run in real time: it moves only when something spends it.

## What spends time

| Action | Days |
|---|---|
| A jump | `max(1, round(fuel cost * days_per_fuel_unit))` (0.1 per fuel unit) |
| Landing at a settlement | `days_per_landing` (1) |

With the default settings every link in the galaxy takes 1 to 8 days (the longest, Sol to Kerella, is 83 fuel and takes 8). Keep the longest link at **10 days or less**: wars will run on this calendar and the player must be able to reach a front in time. `clock_test.gd` fails if any link takes more.

Both values are exports on the `Clock` node in `scenes/main.tscn` (`days_per_fuel_unit`, `days_per_landing`). They are not in `EconomyConfig` because the clock is shared by systems other than the economy (contract deadlines and wars later).

## API (`scripts/time/game_clock.gd`)

- `day: int`
- `advance(days, reason)`: moves time on and emits `day_advanced(day, elapsed)`. Zero and negative amounts are ignored.
- `jump_days(fuel_cost)`: how many days a jump costs.
- Signal `clock_reset`: the day was replaced (a loaded save or a new game).

`Main` calls `advance` from `jump_to()` and from a handler connected to `DockingManager.docked` **before** the settlement screen opens, so the screen shows the day's figures. The day is shown at the right of the top bar (`TopBar.set_day()`).

## Who uses it

- **Markets** read `day` when they are read and catch up on the days that passed ([economy.md](economy.md)). They do not listen to `day_advanced`, so time passing costs nothing.
- **Damage** recovers by the day, worked out from the stored day when it is read ([system_classes.md](system_classes.md)).
- **Zones** use it to decide when a conquered critical system becomes a centre of power (`establish_days`).
- **The target panel** refreshes when a day passes, so recovering damage shows.
- **Contract deadlines** (not built): add a `deadline_day` to `Contract`, compare with `clock.day`, and fail the contract on `day_advanced`.
- **Wars** (not built): can listen to `day_advanced` to progress operations.

## Saving

An optional `clock` section (`{"day": n}`), registered before `economy` so markets see the right day when they load. A save without it starts at day 0.
