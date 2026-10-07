# Quest Beacon

A compass bar with every tracked quest, and a marker in the world on the nearest one.

## Compass

- A bar at the top of the screen with a pin for every tracked quest, at its direction, with the distance.
- Quests close together share one pin with a count. Hover it to see every quest in it, nearest first.
- Click a pin to navigate there.
- Right-click a pin to drop that quest and go to the nearest other one. It stays out of nearest-first until you pick it again.
- It turns with your character, and fades while you swing the camera with the left mouse button.

## World marker

- Stands on the quest being navigated to, with the quest name, the next objective and the distance.
- Replaces the game's own diamond, and stays under the rest of the interface.

## Nearest first

Navigation switches to the nearest tracked quest as you move. A quest you pick yourself, in the quest tracker, on the compass or with the key binding, is kept until it leaves your quest log.

## Icons

- Yellow "?": ready to turn in.
- Dungeon or raid icon: a dungeon or raid quest still to do.
- Grey "?": any other quest still to do.

## QuestieDB (optional)

Locations are the game's own quest areas. With QuestieDB installed, the nearest spawn of whatever the quest still needs, or of whoever takes it in, is used instead. Navigation then goes through a map waypoint on that spot.

## Settings

Options → AddOns → Quest Beacon, `/qb`, or the minimap button (left-click: settings, right-click: compass on/off). The button works with minimap button collectors such as Leatrix Plus.

## Commands

- `/qb`: settings
- `/qb compass`, `/qb marker`, `/qb auto`: compass, world marker, nearest-first on or off
- `/qb next`: next tracked quest by distance (also a key binding)
- `/qb move`: unlock the compass to drag it, again to lock
- `/qb why`: where each tracked quest is believed to be

## Notes

- The game places only one point in the 3D world for addons, so only one quest at a time gets a world marker. The compass covers the rest.
- QuestMaster also picks which quest the game navigates to. If you run both, turn off one of the two world markers.
