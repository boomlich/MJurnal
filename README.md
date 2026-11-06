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
  - **average quantity per corpse** (every unit of a stack counts) and how often each amount dropped, plus the corpses needed for 10 / 20 of an item
  - **1 in X**, corpses since the last drop, corpses needed for a **50% / 90% / 99%** chance
  - longest dry streak and a **luck** score, plus an overdue highlight when a dry streak gets unlikely
- **Quest drops** in their own table: items that only drop while a quest needs them get a rate per corpse looted *while the quest wanted them*, with a "needed now" marker
- Skinning, herbalism, mining and pick pocket, kept separate from normal drops
- Time to kill, total combat time
- Deaths: times it killed you (killing blow from the death recap) or was attacking you, kills per death, share of fights lost, its killing abilities and biggest killing blow, your level and the number of enemies on you, plus recent deaths
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
- Top lists: most killed, best farm, fastest kills, hardest hitters, rarest drops, luckiest drops, most overdue
- Deaths: kills per death, current and best kill streak, time alive, deaths per day, recent deaths with killing blow, nemesis list, deaths by zone and what killed you (including falling, drowning and other environment deaths)
- Breakdowns by creature type, classification, zone, character and item quality
- History log of notable drops, milestones, rares spotted or killed, and deaths

### Characters & categories
- **Character filter** (top right of the journal): show every character, one character or any mix of them. Lists, monster and item pages, the overview and the history all follow it; tooltips and chat alerts always use the whole account.
- **Categories** next to the search box: monsters by creature type (Beast, Humanoid...) or classification (Elite, Rare...), loot by item type (Weapon, Trade Goods...) and subtype (Armor: Cloth / Leather / Mail / Plate, Weapon: One-Handed Swords, Staves...) or quest items. "All" shows the full list as before.

### Convenience
- Search and sorting in both journals, with click-through between monsters and items
- **Key binding** to open the journal on the NPC under your mouse
- Minimap button (draggable), addon compartment entry and a LibDataBroker launcher
- A short MJurnal line on NPC and item tooltips
- Chat alerts for rare drops, kill milestones, new entries and rare monsters
- Fades while you move (like the world map) or are in combat, and stays fully visible under the mouse

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

Toggle commands: `/mj tooltip`, `/mj itemtooltip`, `/mj alerts`, `/mj milestones`, `/mj minimap`, `/mj fade`, `/mj combatfade`. Use `/mj fade <percent>` to set the opacity while moving or in combat, and `/mj debug` to print every detected kill and loot.

**Tip:** turn on enemy nameplates (`V` by default). MJurnal sees deaths through nameplates as well as your target, so kills are caught even when you don't target the mob.

## How it works

WoW Forever runs with the Midnight addon restrictions: addons **cannot read the combat log** (`COMBAT_LOG_EVENT_UNFILTERED` is restricted and its reader lives in the secure-only `C_CombatLogSecure`). MJurnal therefore builds its data from the APIs that are open.

### Kills
- A hostile NPC that is in combat with you or your group (threat or target), and not tapped by someone else, counts as a kill when it is seen dead. It is seen through your target, mouseover, focus or nameplates.
- If that is missed, two fallbacks catch the kill: the "*X dies, you gain N experience*" message and looting the corpse.

### Loot
- Every loot window is split per corpse with `GetLootSourceInfo`, so AoE loot is attributed correctly. A corpse is only counted once.
- Corpses with no loot are detected through `UNIT_LOOT`/`CanLootUnit` and counted as **empty corpses**. In a group this only happens with free-for-all loot: with other loot methods a corpse someone else has the rights to looks empty too, so unlooted corpses are left out instead.
- **Drop rates are per corpse**: looted + confirmed empty. Kills you never looted don't dilute the numbers.
- The drop rate is the chance that a corpse has the item at all. When a corpse drops several (a stack of 3, or the same item in two slots), every unit counts towards the quantity and the **per corpse** average.

### Damage
- Damage comes from Blizzard's built-in damage meter API (`C_DamageMeter`), the same source Details! uses on Forever.
- Its values are secret during combat, so each fight is read a few seconds after it ends.
- The data is aggregated per monster type per fight, not per individual hit, so killing blows and single biggest hits are not available.

### Quest drops
- The loot window marks quest items (`isQuestItem`) and items that start a quest (`questID`). Items that start a quest drop regardless, so they are normal drops.
- For other quest items, MJurnal checks your quest log (`C_QuestLog.GetQuestObjectives`) on every corpse. A corpse only counts for that item's rate while an unfinished objective needs it.
- If a quest item ever drops while no quest needs it, it is a general drop (some crafting goods are flagged too). It moves to the normal loot table automatically.

### Deaths
- When you die, MJurnal first guesses the killer from the enemies targeting you.
- A moment later it reads Blizzard's death recap (`C_DeathRecap`, the "what killed me" window) and credits whoever landed the killing blow. The other attackers count as "attacking".

### Limitations
- A mob that dies out of sight (no target, no nameplate), gives no XP and is never looted cannot be detected.
- Quest drops are matched to your quest log by item name. If an objective's text doesn't contain the item name, the item is treated as a general drop.
- Quest drops looted before this feature existed have no on-quest corpse count, so their rate starts from the first drop recorded after it.
- In instances, the game may hide unit identities (secret values). MJurnal then skips what it can't read instead of guessing.

## Data

Data is stored with WoW's **SavedVariables**, account-wide, in:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\MJurnal.lua
```

- The game writes the file on logout and `/reload`, so a crash loses data back to the last save.
- The file is plain Lua text. Copy it to back up your journal.
- Only raw counts are stored. Rates and probabilities are calculated when you open the journal.
- Every number is stored per character, so the journal can be filtered by character. When several characters are combined, counts are added up; "corpses since the last drop" uses the character that saw the item most recently.
- Journals from before per-character data (v0.1) are converted on the first load: all older numbers go to the character with the most kills.
- The file grows mainly with the number of different monsters and items, not with the number of kills. Per-monster daily kill counts add a little per day played, and the history log keeps the latest ~5000 events.

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
