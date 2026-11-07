# Azeroth Survivors addons

Core Comforts and Run History are addons for [Azeroth Survivors](https://azerothsurvivors.app/).

## Core Comforts

Boss and guardian health bars, with debuffs and an estimate of damage over time. The same estimate is drawn on the target frame. Guardian timers, and minimap pins for guardians and caches. The action bar shows the seconds left on each spell. Character stats can show more decimal places. Every option can be turned on or off. `/cc` opens the window.

### Direction arrows, tally, and jewelry

Direction arrows for a cache and a guardian. The cache arrow shows how many you can open. When every guardian is dead, the arrow turns blue and shows the time until the next one. Kill count, gold, and caches. The cache number turns green when you can afford one and red when you cannot. Equipped jewelry is shown above the bar.

![Direction arrows, tally line, and equipped jewelry](screenshots/hud.png)

<table>
<tr>
<td width="50%" align="center" valign="top">
<h3>Minimap</h3>
<p>Minimap icons for guardians and caches. A guardian shows as alive, in combat, or dead. A dead one shows a countdown when it is close to coming back. The icons scale with the minimap zoom.</p>
<img src="screenshots/minimap.png" alt="Minimap pins for guardians and caches" width="100%">
</td>
<td width="50%" align="center" valign="top">
<h3>Boss list</h3>
<p>Upcoming bosses, and the gear they drop. A mark shows whether you already own that piece, based on the armory collection in the addon.</p>
<img src="screenshots/boss-list.png" alt="Boss list with owned drops marked" width="100%">
<h3>Guardian timers</h3>
<p>Each row shows whether that guardian is alive, in combat, or how long until it returns. A last line can show how many caches are on the map.</p>
<img src="screenshots/guardians.png" alt="Guardian timers" width="100%">
</td>
</tr>
<tr>
<td width="50%" align="center" valign="top">
<h3>Kills, experience, and gold per minute</h3>
<p>Kills, experience, and gold per minute, and how many enemies are alive.</p>
<img src="screenshots/rates.png" alt="Kills, experience, and gold per minute" width="100%">
</td>
<td width="50%" align="center" valign="top">
<h3>Boss timer and health bars</h3>
<p>Boss timer, drawn as a progress bar. Boss health bars with debuffs, and an estimate of the damage over time. The same estimate is drawn on the target's health bar.</p>
<img src="screenshots/boss-bars.png" alt="Boss timer and boss health bars" width="100%">
<img src="screenshots/target-frame.png" alt="Damage over time estimate on the target frame" width="100%">
</td>
</tr>
</table>

### Options

Each option can be turned on or off. Caches you can buy is under UI, just below kills, gold, and cache, and it starts on. Action bar cooldowns starts on: whole seconds left on each spell, yellow under 5 seconds and red under 1 second. Stat places, under Decimals, sets the decimal places on the character panel. It starts at the game's own rounding.

![Core Comforts options](screenshots/options.jpg)

### Armory

Gear from each map and boss. It updates when you get a drop. The addon cannot read your current collection, but you can edit the collection and check the items you already owned before installing it. It also shows your total marks, and the marks collected this run.

![Armory, with owned pieces checked](screenshots/armory.jpg)

## Run History

Saves each run and compares kills per minute by class, map, difficulty, and spec. New runs also store the date and time. Solo and co-op runs are listed apart. `/history` opens the window. Options are in that window.

### Run list

Filter by solo or co-op, and by class, map, and difficulty. Switch between endless, the full run, and a mid-run snapshot, and between the average pace and the last minute. Each new run shows its date and time. The minimum length hides shorter runs, from 0 to 16 minutes.

![Run list, with solo, class, map, and difficulty filters](screenshots/history.jpg)

### Party

A co-op run lists each boss fight, with every member's damage and share. The total shows each member's level and their share of the party's damage.

![Party boss fights and each member's share of the damage](screenshots/history-party.png)

### Run details

Date and time, pace for the whole run and the last minute, kills, gold, and the highest hit.

![Run details, with pace, kills, and the highest hit](screenshots/history-stats.png)

### Spells, jewelry, and damage

Character stats. Spells, with the total upgrades for each one, and jewelry, with what the piece does while equipped. Damage done, and each ability's share of that damage.

![Spells, with the total upgrades for each one](screenshots/history-build.png)

![Jewelry, and each ability's share of the damage](screenshots/history-damage.png)

### Damage taken and pickups

Damage taken, with each source's share, and pickups with the increase from that rank.

![Damage taken and pickups over time](screenshots/history-pickups.png)

## What's new

Core Comforts 0.4. The boss arrow turns gold and says Alive while a guardian is up. When every guardian is dead, it points at the lair that fills first, turns blue, and shows the time left. If several fill at the same time, it points at the closest of those. The guardian list can show how many caches are on the map, in red when none are left. The cache arrow can show how many you can open. That number is the smaller of what your gold can pay for and what is on the map, and (0) is red. These start on.

Run History 0.4. The list can show solo runs or co-op runs. It opens on co-op while you are in a party, and on solo otherwise. A co-op run saves the roster, each member's level and build, and each member's share of the party damage. Upgrade lines appear only when the meter saved the real text.

Runs saved before this version stay in the list. A co-op run from before this version has no roster. A dash means that detail was not recorded.

## Install

On Windows and Linux, copy the `CoreComforts` folder, the `RunHistory` folder, or both into `benilla-config/AddOns/` next to the game. The addons load on the next world entry.

In the browser client, open Options, then AddOns, and install a zip of one addon folder. The zip should contain that folder itself (`CoreComforts` or `RunHistory`), not an extra parent folder.

Saved settings stay on your computer. They are not part of this repository.
