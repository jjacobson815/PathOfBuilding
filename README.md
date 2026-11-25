# Path of Building (Qt6/QML Port)

**Current Release: [`v2.68.1-qt.1`](https://github.com/jjacobson815/PathOfBuilding/releases/tag/v2.68.1-qt.1)** (based on Path of Building Community `v2.68.1` calc engine)

A native **Qt6 / QML** desktop port of [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding), an offline build planner for Path of Exile. It replaces the legacy SimpleGraphic runtime with a C++/Qt6 host and GPU scene-graph passive tree renderer while embedding the unchanged LuaJIT (GC64) calculation engine.

## Download (`v2.68.1-qt.1`)

Head over to the [GitHub Releases](https://github.com/jjacobson815/PathOfBuilding/releases) page to download:
* **Windows Installer:** `PathOfBuilding-Qt-Setup-2.68.1-qt.1.exe` (NSIS installer with Start Menu / Desktop shortcuts and `pob://` URI handler)
* **Windows Portable ZIP:** `PathOfBuilding-Qt-Portable-2.68.1-qt.1.zip` (self-contained folder; extract and run `pob-qt.exe`)

> **Release Notes (v1):**
> * **Unsigned binaries:** v1 installers and executables are not yet Authenticode-signed. Windows SmartScreen may show a warning on first launch (*More info → Run anyway*).
> * **Shared build folder:** Builds and `Settings.xml` are shared with legacy PoB in `Documents/Path of Building` for zero-friction migration. Avoid running legacy PoB and `pob-qt` at the same time.
> * **Update notifications:** Checks `jjacobson815/PathOfBuilding` GitHub Releases asynchronously on startup (and via **About → Check for Updates**) and opens the release page in your browser.
> * **Deferred to v1.1:** In-app trade site search / `"Buy similar"` tooling is deferred to post-v1.

### Features
* Comprehensive offence + defence calculations:
  * Calculate your skill DPS, damage over time, life/mana/ES totals and much more!
  * Can factor in auras, buffs, charges, curses, monster resistances and more, to estimate your effective DPS
  * Also calculates life/mana reservations
  * Shows a summary of character stats in the side bar, as well as a detailed calculations breakdown tab which can show you how the stats were derived
  * Supports all skills and support gems, and most passives and item modifiers
    * Throughout the program, supported modifiers will show in blue and unsupported ones in red
  * Full support for minions
  * Support for party play and support builds
* Passive skill tree planner (Qt Quick GPU Scene Graph):
  * Ships all 39+ passive tree versions (including modern WebP ascendancy/bloodline art)
  * Support for jewels including radius/conversion, cluster jewels, and Timeless Jewel finder
  * Alternate path tracing, node power heat map, spec management, and fast incremental node allocation
  * Fully integrated with the offence/defence calculations; see exactly how each node will affect your character!
  * Can import PathOfExile.com and PoEPlanner.com passive tree links; links shortened with PoEURL.com also work
* Skill planner:
  * Add any number of main or supporting skills to your build
  * Supporting skills (auras, curses, buffs) can be toggled on and off
  * Automatically applies Socketed Gem modifiers from the item a skill is socketed into
  * Automatically applies support gems granted by items
* Item planner:
  * Add items from in game by copying and pasting them straight into the program!
  * Automatically adds quality to non-corrupted items
  * Fully integrated with the offence/defence calculations; see exactly how much of an upgrade a given item is!
  * Contains a searchable database of all uniques that are currently in game (and some that aren't yet!)
    * You can choose the modifier rolls when you add a unique to your build
    * Includes all league-specific items and legacy variants
  * Features an item crafting system:
    * You can select from any of the game's base item types
    * You can select prefix/suffix modifiers from lists
    * Custom modifiers can be added, with Master, Essence, Enchant, Anoint, Corrupt, and Crucible modifiers available
  * Also contains a database of rare item templates:
    * Allows you to create rare items for your build to approximate the gear you will be using
    * Choose which modifiers appear on each item, and the rolls for each modifier, to suit your needs
    * Has templates that should cover the majority of builds
* Other features:
  * Import passive tree, items, and skills from existing characters (account import & OAuth)
  * Share builds with other users via build codes, external share hosts, and `pob://` links
  * Configuration, Calcs Breakdown, Notes, Party, and Loadouts tabs
  * Lightweight async GitHub Releases update notifications (`--dev` or `POB_DEV_MODE=1` enables engine dev mode / ModCache regen)

## Building from Source

* **Windows (MSYS2 MinGW64):**
  ```bash
  cmake -S app -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release
  PATH="/c/msys64/mingw64/bin:$PATH" ninja -C build-win
  bash app/deploy-win-standalone.sh        # creates self-contained dist/
  bash app/installer/build-installer.sh    # creates dist-installer/PathOfBuilding-Qt-Setup-*.exe
  ```
* **Linux:**
  ```bash
  bash tools/linux-selftest.sh
  ```

## Changelog
You can find the full upstream version history [here](CHANGELOG.md), and Qt port progress in [port-plan/STATUS.md](port-plan/STATUS.md).

## Contribute
You can find instructions on how to contribute code and bug reports [here](CONTRIBUTING.md).

## Licence
[MIT](https://opensource.org/licenses/MIT)

For 3rd-party licences, see [LICENSE](LICENSE.md).
The licencing information is considered to be part of the documentation.
