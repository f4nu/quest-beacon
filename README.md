# Quest Beacon

WoW: Forever addon.

- **Compass bar** at the top of the screen with a pin for every tracked quest, at its direction, with the distance in yards. Quests behind you sit at the nearer edge. Hover a pin for the quest and its next objective, click it to navigate there.
- **World marker** on the quest the game navigates to: quest, next objective, distance. It replaces the game's own diamond.
- **Nearest first**: the game navigates to the nearest tracked quest and switches as you move. Picking a quest yourself (in the quest tracker, on the compass, or with the key binding) holds it until it leaves your quest log, or you turn `/qb auto` off and on.

Locations are the game's own quest areas. A quest the game has no location for gets no pin.

The game projects only one point into the 3D world for addons, so only one quest at a time gets a world marker. The compass covers the rest. It turns with your character, not the camera.

## Commands

- `/qb compass`: compass on/off
- `/qb marker`: world marker on/off
- `/qb auto`: navigate to the nearest tracked quest on/off
- `/qb next`: navigate to the next tracked quest by distance (also a key binding under AddOns)
- `/qb move`: unlock the compass to drag it, again to lock

QuestMaster also picks which quest the game navigates to. Running both, turn off one of the two world markers.
