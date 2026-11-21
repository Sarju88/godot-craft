# Godot Craft

> **Unofficial fan project.** This is not an official Minecraft product. It is not affiliated with, approved by, endorsed by, or associated with Mojang Studios or Microsoft.

Created by [Sarju88](https://github.com/Sarju88). This is an independent Godot 4.7 recreation of the creative building experience in [Minecraft Classic](https://classic.minecraft.net/).

Open Godot's Project Manager, choose **Import**, and select the `project.godot` file in this folder. Open the project and press **F5**. The game opens at the title menu. Choose **Singleplayer → Classic Sandbox** for the original creative world, or **Singleplayer → Create World** to name a world, enter a numeric or text seed, and pick a map size. Leave the seed blank for a random world. Saved Survival worlds appear in the Survival menu.

New Survival worlds are 128 blocks tall, with coastal lowlands, dry patches, ridges, cherry groves, and deeper caverns. Existing worlds retain their original terrain. Survival uses a 20 Hz movement simulation, timed mining, pickups, inventory, equipment, crafting, and smelting. Block edits, health, equipment, items, and nearby mobs persist in the world save.

In Survival, hold left mouse to mine or click to attack. Right mouse places blocks, opens crafting stations, or uses equipment. Press **E** for the inventory and recipe list. Use a recipe's tooltip to see its ingredients. Upgrade from wooden to stone picks to harvest iron ore. A furnace and coal turn raw iron into ingots. You can carry a station or use a placed one nearby. The world pauses while the inventory is open, so close it to let smelting advance. Hold right mouse and release with a bow selected to shoot. An equipped shield blocks from the front after a short wind-up.

Grazers spawn during the day, and melee and ranged enemies spawn at night. Death drops carried and equipped items for recovery after respawn.

| Control | Action |
| --- | --- |
| WASD, mouse, Space | Move, look, jump |
| Right mouse | Switch between removing and placing (Classic) |
| Left mouse | Remove or place in the current mode (Classic) |
| Middle mouse | Pick the pointed-at block (Classic) |
| B | Block palette (Classic), inventory (Survival) |
| Left Ctrl, Left Shift | Sprint and sneak (Survival) |
| 1–9 or mouse wheel | Select a hotbar slot |
| Enter and R | Save your current location and return to it (Classic) |
| F | Cycle render distance |
| T and Tab | Chat and LAN player list |
| Escape | Game menu |

The game reads block and HUD textures, including health hearts, from the locally installed Minecraft Java client. It looks in the standard Java Edition versions directory and prefers Minecraft 26.3. It uses the client’s block textures, compatible HUD and button sprites, and a plains tint sampled from the grass and foliage colormaps. Liquids currently display the first animation frame. **Options → Textures** lets you point it at another client JAR, including a custom launcher installation. The title screen projects all six faces from the locally cached 1.20.2 cherry-grove panorama when available. Footsteps, block-edit sounds, and optional music are read from the launcher’s asset indexes and object cache. Minecraft assets load into memory at runtime. If there is no usable local client JAR, the game starts with flat colors.

For Classic multiplayer, start a Classic world and use **Escape → Multiplayer → Share world on LAN**. Other players on the same network can choose **LAN Multiplayer → Join LAN world** from the title menu and enter the host's LAN IP address. The host uses UDP 25565. This build uses its own LAN protocol and level generator. Browser invite links, exact seed reproduction, and Minecraft save or server compatibility are outside this build. Classic world changes last for the current session.

## Development

The current Survival build has finite maps, on-demand chunk meshing, approximate cave lighting and day/night, item progression through iron, and three original mob types. Java 26.3 is the behavior reference. Streamed terrain generation, local light propagation, structures, dimensions, hunger, a wider item and entity catalog, and Java save and network compatibility are separate milestones. Keep Mojang's code, binaries, extracted assets, and local Minecraft installations outside the repository.

## License and third-party assets

The project's original code is available under the [MIT License](LICENSE). You may download, modify, and redistribute it. Keep the copyright notice crediting **Sarju88** and the MIT permission notice in all distributed copies or substantial portions.

Minecraft and its assets belong to their respective rights holders. This repository does not include Minecraft client JARs or extracted Minecraft textures. When configured, the game reads textures from a locally installed Java client at runtime. The MIT license does not grant rights to Minecraft or its assets. See the [Minecraft Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines) and [Minecraft EULA](https://www.minecraft.net/en-us/eula).

Pixelify Sans is included under the [SIL Open Font License](art/OFL-PixelifySans.txt).
