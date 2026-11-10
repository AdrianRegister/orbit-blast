# Game Design Document - Orbit Blast

## Game concept and vision

An Escape Velocity clone. Trade, explore, and fight across star systems in a dangerous galaxy inhabited by warring factions. 2D, top-down gameplay.

## Target audience and platform

For fans of the original Escape Velocity series. To be played on desktop computer. Playable using mouse and keyboard. Single player only.

## Core gameplay loop

Each system will contain planets, moons or space spations (inhabited nodes). Some systems will be uninhabited. Players will be able to land on inhabited nodes and access the mission computer. Mission computers will have different types of missions - exploration, scouting, cargo delivery, and combat (pirate hunting / bounty hunting). These missions will reward credits. Credits can be used to repair or upgrade the player's ship, purchase new ships, and buy cargo.
Systems are governed by culturally and politically-opposed factions. Gaining reputation with one faction can result in better prices and greater access to faction-specific items.

**Goals:**

- Short term: establish basic income through simple, easy missions.
- Medium term: purchase more capable ships and upgrades to take on more difficult missions, and engage with faction politics.
- Long term: become a major player in the galaxy! Influence faction politics, build an industrial empire, or become a legendary freelancer.

## Game mechanics and systems

**Movement:** Multidirectional, using the arrow keys. Inertia will be implemented.
**Interaction:** Ships will interact with their environment by moving over them (landing on planets, boarding other ships) or by engaging in combat.
**Resources:** Ships carry fuel, shields, armor, and cargo space. Fuel is used to travel between systems. Shields and armor are used for combat. Cargo space is used for trading and cargo delivery. Ships can refuel on inhabited nodes.
**Combat:** Ships can be armed with projectile weapons. These have a finite range and attack power. Some special weapons can bypass shields entirely. Ships will fire on each other, reducing shields and eventually armor. When a ship has no more armor remaining, it will begin to suffer direct hull damage. Once hull integrity reaches zero, the ship will be destroyed. Shields will regenerate over time, but armor and hull damage will have to be repaired in shipyards on inhabited nodes.
**Trading:** Inhabited nodes will have trading floors, where goods can be bought and sold. Certain nodes will offer higher or lower prices for certain goods. Over time, wars and military actions (blockading, invasions, bombardment) between factions will cause spikes in supply and demand, which in turn will greatly affect price.
**Exploration**: Systems very far away from the galactic core are unexplored. Unexplored systems will require being mapped by the player, which will require specific exploration equipment (high-performance sensors and astro-location). The player can receive payment for mapping these systems from interested factions. Some systems may contain rare resources, and will be more valuable than others. These resources are TBD.
**Asset construction:** The player will be able to build their own industrial facilities, like gas harvesting, mining, drilling, and manufacturing. These facilities can be built in space or on inhabited nodes. Facilities will be built using industrial resources (TBD), require upkeep and maintenance, and will generate credits based on their productivity. Productivity will be affected by certain events. This entire section is subject to development progress and TBC.

## World, setting and narrative

The game takes place in the Milky Way galaxy. The setting and narrative is TBD.

## Art direction and audio

**Visual style:** 2D aesthetic with sprites. Heavily influenced by Escape Velocity.
**Sound:** Weapon noises, engine hum, background noise on inhabited nodes all influenced by Escape Velocity.
**Color palette:** TBD, but each faction will have a different color scheme.

## User interface and user experience

Player - node interaction will be through clickable menus. Player - ship interaction will typically be combat. The main user interface will closely resemble Escape Velocity. The player ship is in the middle of the screen, and will fly through the system. 20% of the right-hand side of the screen will be used by the game interface, containing system map, ship resources, mission log, faction reputation, and credits.

## Technical design and development scope

The game will be built using Godot Engine and Claude Code. Due to the 2D, top-down gameplay and sprite assets, the hardware requirements will be low. The game will be written in GDScript.

### Prototype features

**Core features:** Movement, interaction, resources, trading.
**Later features:** Exploration, combat, asset construction.
