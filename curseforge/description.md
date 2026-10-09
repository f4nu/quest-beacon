# Quest Beacon

**Every tracked quest on a compass bar. The nearest one marked in the world.**

No more opening the map to see where to go next.

![Compass](https://raw.githubusercontent.com/f4nu/quest-beacon/main/screenshots/compass_1.jpg)

## Features

- **Compass bar**: a pin for every tracked quest at its real direction, with the distance. Turns with your character.
- **World marker**: stands on the quest you're heading to, with its name, next objective and distance. Replaces the game's diamond.
- **Nearest first**: navigation switches to the closest quest as you move. Pick one yourself and it sticks until it's done.
- **Click to go**: click a pin to navigate there. Right-click to skip that quest and go to the next nearest.
- **Grouping**: quests close together share one pin with a count. Hover for the list, nearest first.
- **Tells quests apart at a glance**: yellow "?" ready to turn in, dungeon and raid icons, orange and red for hard quests, same colours as the quest tracker.
- **Stays out of the way**: fades while you swing the camera, hides on flight paths, sits under the rest of the UI.

![World marker](https://raw.githubusercontent.com/f4nu/quest-beacon/main/screenshots/compass_2.jpg)

## Better with QuestieDB

Install [QuestieDB](https://github.com/Questie/QuestieDB) and pins point at the nearest mob, object or NPC the quest actually needs, not just the game's quest area.

## Works with

- QuestieDB (optional, better locations)
- Leatrix Plus and other minimap button collectors
- QuestMaster: also picks the navigated quest, so turn off one of the two world markers

## Setup

Nothing to set up. To change things: `/qb`, the minimap button, or Options → AddOns → Quest Beacon.

| Command | |
|---|---|
| `/qb` | settings |
| `/qb next` | next quest by distance (also a key binding) |
| `/qb move` | unlock the compass to drag it |
| `/qb compass` / `marker` / `auto` | toggle compass, world marker, nearest first |
| `/qb why` | where each quest is believed to be |

## Good to know

The game lets addons place only one point in the 3D world, so only one quest gets a world marker at a time. The compass covers the rest.

## Bugs and ideas

[GitHub issues](https://github.com/f4nu/quest-beacon/issues)
