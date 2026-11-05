# MJurnal

A personal **monster & loot journal** for **World of Warcraft: WoW Forever**.

MJurnal records every monster you kill and every corpse you loot, and turns it into detailed statistics: drop rates, expected kills per drop, dry streaks, gold per corpse, damage, XP and more. Everything comes from what *you* have killed, looted and seen. There is no external database.

The journal works both ways:

- **Monster journal**: pick a monster and see everything it has dropped for you.
- **Loot journal**: pick an item and see every monster that dropped it, and which one is the best source.

## Features

### Per monster
- Kills (account-wide, per character, solo/group), corpses looted, empty corpses, unlooted kills
- Gold: total, average per corpse, min/max, chance to drop gold
- Vendor value of loot and **total value per corpse**, for comparing farm spots
- Loot table per item:
  - drops, quantity, **drop rate** (with a 95% confidence interval on hover)
  - **1 in X**, corpses since the last drop, corpses needed for a **50% / 90% / 99%** chance
  - longest dry streak and a **luck** score, plus an overdue highlight when a dry streak gets unlikely
- Skinning, herbalism, mining and pick pocket, kept separate from normal drops
- Time to kill, total combat time, deaths caused ("nemesis")
- Damage dealt by you and your group, damage per kill (about its health), damage taken and its hardest-hitting abilities
- XP and reputation from kills, level ranges, level difference
- Zones and subzones, kill hotspots (click to set a map waypoint)
- Kills per day for the last 30 days, best day, best session

### Per item
- Times looted, total quantity, average stack, vendor value earned
- Every source monster with its own rate, plus fishing (per zone), containers and chests
- First and last time looted (when, which character, from what)

### Overview & history
- Totals, this session, today, last 7 and 30 days, all time, plus per-hour rates for the session
- Top lists: most killed, best farm, fastest kills, hardest hitters, nemesis, rarest drops, luckiest drops, most overdue
- Breakdowns by creature type, classification, zone, character and item quality
- History log of notable drops, milestones, rares spotted or killed, and deaths

### Convenience
- Search and sorting in both journals, with click-through between monsters and items
- **Key binding** to open the journal on the NPC under your mouse
- Minimap button (draggable), addon compartment entry and a LibDataBroker launcher
- A short MJurnal line on NPC and item tooltips
- Chat alerts for rare drops, kill milestones, new entries and rare monsters
- Fades while you move (like the world map) and stays fully visible under the mouse

## Installation

1. Download or clone this repository.
2. Put the folder in your WoW Forever AddOns folder and name it `MJurnal`:
   ```
   World of Warcraft\_forever_\Interface\AddOns\MJurnal\MJurnal.toc
   ```
3. Start the game (or `/reload`) and make sure MJurnal is enabled in the AddOns list.

## Usage

| Action | How |
| --- | --- |
| Open / close the journal | Minimap button, `/mj`, or a key binding |
| Open the journal on the NPC under your mouse | Key binding *Open journal for mouseover NPC* |
| Search monsters (falls back to loot) | `/mj <text>` |
| Search loot | `/mj loot <text>` |
| Overview / history tab | `/mj overview`, `/mj history` |
| This session's numbers in chat | `/mj session` |
| Settings | Right-click the minimap button, the gear in the journal, or `/mj options` |
| All commands | `/mj help` |

Key bindings are under **Esc → Options → Keybindings → AddOns → MJurnal**.

Toggle commands: `/mj tooltip`, `/mj itemtooltip`, `/mj alerts`, `/mj milestones`, `/mj minimap`, `/mj fade`. Use `/mj fade <percent>` to set the opacity while moving, and `/mj debug` to print every detected kill and loot.

**Tip:** turn on enemy nameplates (`V` by default). MJurnal sees deaths through nameplates as well as your target, so kills are caught even when you don't target the mob.

## How it works

WoW Forever runs with the Midnight addon restrictions: addons **cannot read the combat log** (`COMBAT_LOG_EVENT_UNFILTERED` is restricted and its reader lives in the secure-only `C_CombatLogSecure`). MJurnal therefore builds its data from the APIs that are open.

### Kills
- A hostile NPC that is in combat with you or your group (threat or target), and not tapped by someone else, counts as a kill when it is seen dead. It is seen through your target, mouseover, focus or nameplates.
- If that is missed, two fallbacks catch the kill: the "*X dies, you gain N experience*" message and looting the corpse.

### Loot
- Every loot window is split per corpse with `GetLootSourceInfo`, so AoE loot is attributed correctly. A corpse is only counted once.
- Corpses with no loot are detected through `UNIT_LOOT`/`CanLootUnit` and counted as **empty corpses**.
- **Drop rates are per corpse**: looted + confirmed empty. Kills you never looted don't dilute the numbers.

### Damage
- Damage comes from Blizzard's built-in damage meter API (`C_DamageMeter`), the same source Details! uses on Forever.
- Its values are secret during combat, so each fight is read a few seconds after it ends.
- The data is aggregated per monster type per fight, not per individual hit, so killing blows and single biggest hits are not available.

### Limitations
- A mob that dies out of sight (no target, no nameplate), gives no XP and is never looted cannot be detected.
- Quest items are marked with **(Q)**. Their rate only counts corpses looted while you were on the quest, so it looks lower than it really is.
- In instances, the game may hide unit identities (secret values). MJurnal then skips what it can't read instead of guessing.

## Data

Data is stored with WoW's **SavedVariables**, account-wide, in:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\MJurnal.lua
```

- The game writes the file on logout and `/reload`, so a crash loses data back to the last save.
- The file is plain Lua text. Copy it to back up your journal.
- Only raw counts are stored. Rates and probabilities are calculated when you open the journal.
- The file grows with the number of different monsters and items, not with the number of kills.

## Project layout

```
MJurnal.toc            Addon metadata and load order
Bindings.xml           Key bindings
Core.lua               Namespace, events, saved variables + migrations, formatting, slash commands
Journal.lua            All writes to the database (kills, loot, gathering, XP, deaths)
Stats.lua              Pure calculations: rates, confidence intervals, lists, rankings
Milestones.lua         History log, milestones and chat alerts
Tooltip.lua            NPC and item tooltip lines
Tracker/Units.lua      Kill detection from unit tokens, player deaths
Tracker/Loot.lua       Loot window parsing, gathering, pick pocket, fishing
Tracker/Progress.lua   XP and reputation from chat messages
Tracker/Damage.lua     Damage per monster type from C_DamageMeter
UI/                    Journal window, views, widgets, settings, minimap button
```

### Development

- Interface version: `16001` (WoW Forever).
- The API reference for this client is Blizzard's generated documentation, mirrored in the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).
- For quick iteration, link the repository into the AddOns folder so `/reload` picks up changes (Windows, run in PowerShell):
  ```powershell
  New-Item -ItemType Junction -Path "<WoW>\_forever_\Interface\AddOns\MJurnal" -Target "<path to this repo>"
  ```
- Turn on `/console scriptErrors 1` in-game to see Lua errors, and use `/mj debug` to watch kill and loot detection.
