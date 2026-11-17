# Godot Craft

> **Unofficial fan project.** This is not an official Minecraft product. It is not affiliated with, approved by, endorsed by, or associated with Mojang Studios or Microsoft.

Created by [Sarju88](https://github.com/Sarju88). This is an independent Godot 4.7 recreation of the creative building experience in [Minecraft Classic](https://classic.minecraft.net/).

Open Godot's Project Manager, choose **Import**, and select the `project.godot` file in this folder. Open the project and press **F5**. The game starts in a generated world.

| Control | Action |
| --- | --- |
| WASD, mouse, Space | Move, look, jump |
| Right mouse | Switch between removing and placing |
| Left mouse | Remove or place in the current mode |
| Middle mouse | Pick the pointed-at block |
| B | Choose from the 32-block palette |
| 1–9 or mouse wheel | Select a hotbar slot |
| Enter and R | Save your current location and return to it |
| F | Cycle render distance |
| T and Tab | Chat and LAN player list |
| Escape | Game menu |

The game reads block and interface textures from the locally installed Minecraft Java client. It looks in the standard Java Edition versions directory, preferring a nearby historical release when available. **Options → Textures** lets you point it at another client JAR, including a custom launcher installation. Texture files are read into memory at launch. If there is no usable local client JAR, the game starts with flat colors.

For multiplayer, use **Escape → Multiplayer → Share world on LAN**. Other players on the same network can choose **Join LAN world** and enter the host's LAN IP address. The host uses UDP 25565. This build uses its own LAN protocol and level generator. Browser invite links, exact seed reproduction, and Minecraft save or server compatibility are outside this build. World changes last for the current session.

## Development

The current build is based on Classic's creative gameplay. The long-term goal is to recreate more of Java Edition 26.3 in Godot. Treat gameplay observations as the reference for new implementations. Keep Mojang's code, binaries, extracted assets, and local Minecraft installations outside the repository.

## License and third-party assets

The project's original code is available under the [MIT License](LICENSE). You may download, modify, and redistribute it. Keep the copyright notice crediting **Sarju88** and the MIT permission notice in all distributed copies or substantial portions.

Minecraft and its assets belong to their respective rights holders. This repository does not include Minecraft client JARs or extracted Minecraft textures. When configured, the game reads textures from a locally installed Java client at runtime. The MIT license does not grant rights to Minecraft or its assets. See the [Minecraft Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines) and [Minecraft EULA](https://www.minecraft.net/en-us/eula).

Pixelify Sans is included under the [SIL Open Font License](art/OFL-PixelifySans.txt).
