# Flavour Text and Event Popups

A small reusable system for the short pieces of colour text that accompany game events (a delivery completed, arriving at a settlement, a visit to a spaceport bar, ...), and the popup that shows them. See [missions.md](missions.md) for the first user, delivery contracts.

## 1. Pieces

| Piece | File | Role |
|---|---|---|
| `FlavourPool` | `scripts/resources/flavour_pool.gd` | A Resource holding the interchangeable entries for **one kind of event**; `pick()` returns a random one |
| Pools | `resources/flavour/*.tres` | One file per kind of event, for example `contract_delivery.tres` |
| `EventPopup` | `scenes/ui/event_popup.tscn`, `scripts/ui/event_popup.gd` | Modal box: title, flavour text, "caption / value" detail rows, OK button |

Flavour text is static content, so it follows the project rule for static data: Resources in `resources/`. It is not hard-coded in scripts, and there is no Autoload: whichever code handles an event holds a reference to its pool, as `Main` does for `delivery_flavour`.

## 2. Using it

```gdscript
@export var delivery_flavour: FlavourPool        # assigned in the scene

var text: String = delivery_flavour.pick({"destination": "Mars"})
popup.show_event("DELIVERY COMPLETE", text, [["REWARD", "+12,000 CR"]])
```

- `pick(values)` returns a random entry and replaces `{placeholders}` with the matching keys of `values`; unknown placeholders are left alone, and an empty pool gives an empty string (the popup then simply omits the flavour).
- `show_event(title, flavour, details)` takes `details` as an Array of `[caption, value]` pairs. If a popup is already open, the new event is queued and shown after the player dismisses the current one. OK, Enter or Esc dismisses.

The popup is a layer above the settlement and mission screens, so it works while docked. It only displays what it is given; the event's logic has already happened (for a delivery, the reward is paid before the popup appears).

## 3. Recipe: add flavour for a new kind of event

1. Create `resources/flavour/<event>.tres` of type **FlavourPool** and fill in **Entries** (multi-line text is fine). Use `{name}` placeholders for values the event supplies.
2. In the code that handles the event, add `@export var <event>_flavour: FlavourPool`, assign the file in the scene, and call `pick()` when the event happens.
3. Show it with `EventPopup.show_event()`, or put the text in any other UI.

To add more lines to an existing event, add entries to its `.tres`. To use different text for a particular case (for example mining contracts versus delivery contracts), make a separate pool and pick the pool where the event is handled.

Planned users of the same approach: arriving at settlements, other contract types, spaceport bars.

## 4. Current pools

| File | Used for |
|---|---|
| `resources/flavour/contract_delivery.tres` | A cargo delivery contract completing (3 entries; one uses `{destination}`) |
