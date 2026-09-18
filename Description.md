# Timber's Raid Summoner

A comprehensive raid summon management addon for WoW Classic Era, Anniversary Edition, and WoW: Forever that provides an interface for easily selecting and coordinating summons of raid members. Summon via a list of raid members, or with the summoning queue. Many more features not seen elsewhere.

To open, type "/trs" or "/timbersraidsummoner". You can also add a keybind for the addon in the "Options > Keybindings > AddOns" menu.

Multiple settings can be managed by clicking the gear icon in the top right of the addon window.

This addon communicates between characters in the same raid/party that also have the addon. In order to see in-progress summons and a decentralized summoning queue, one or more players will need the addon. The more people (especially warlocks) in your group with the addon, the more usefulness you'll get out of the addon.

Characters in the summon queue have a timeout of 5 minutes. Once a character has been sitting in the queue for 5 minutes, all users with the addon will get a message about the user timing out, and the character will be removed from the queue. This prevents stale queues. If you want to manually remove a character from the queue, simply middle click their name. To summon a character in the queue, left click on the name in the queue to target the character, and then right click to begin casting the summon.

<span style="color: #2dc26b;">TBC Compatible:</span> This addon now works with TBC, and while addons can't directly interact with meeting stones, you can use the addon to manually target party/raid members and then right click on the meeting stone to begin the summon. The addon maintains warlock Ritual of Summoning functionality on TBC, as well.

![image](https://media.forgecdn.net/attachments/description/1413838/description_3f867ef2-cf51-422f-babc-3d7b363bb9bc.png)

## Main Interface Features

### Raid Members Panel
- Displays all members of your current raid or party group
- Shows player name, level, and class for each member
- Class colors are displayed for easy identification
- Crown icon displayed for party/raid leader
- **Left-click** a player to target them
- **Right-click** a player to cast Ritual of Summoning on them (summons without sending messages)
- Out-of-range/offline players can be displayed with reduced opacity (configurable)
- Hover tooltip shows player's current zone/subzone location

### Summon Queue Panel
- Displays players who have requested a summon (in chronological order)
- Players are automatically added when they type a keyword (configurable) in raid/party chat
- **Left-click** to target the player
- **Right-click** to summon the player from the queue
- **Middle-click** to remove a player from the queue
- Queue entries automatically expire after 5 minutes

### Avoid Duplicate Summons
- If a character is being summoned, the hover tooltip will show which character is summoning them
- Players being summoned show "Summoning..." status in yellow

### Manual Summon Detection
- Detects when you manually cast Ritual of Summoning (without using the addon UI)
- Automatically broadcasts your summoning status to other addon users
- Other players will see "Summoning..." for your target

### Meeting Stone Support
- Detects Meeting Stone summons for players in the queue
- Tracks summon completion based on channel duration

### Cross-Addon Synchronization
- Summon queue is shared with other raid members who have the addon
- When you join a group, the queue automatically syncs with other addon users
- "Summoning..." status is broadcast to all addon users in real-time
- Players who join mid-summon will see the current summoning status

### Soul Shard Count
- Keep track of how many soul shards you have so you aren't caught off guard
- A count in the top left corner of the addon window shows how many Soul Shards are in your bags

## Keyword Detection

- Automatically detects summon requests in party and raid chat
- Default keywords:
  - `*123` (matches any message containing "123")
- Supports multiple keyword formats:
  - `*keyword` - Matches if the message contains "keyword" anywhere
  - `keyword` - Matches if the entire message equals "keyword" exactly
  - `^pattern` or `$pattern` - Regex pattern matching
- Add, remove, and manage keywords in the settings panel
- "Restore Defaults" button to reset the keywords list

## Notifications

### Sound Notification
- Plays a sound when a player is added to the summon queue
- Can be enabled/disabled in settings
- Test button to preview the sound

### Toast Notification
- Shows a popup notification when a player requests a summon
- Displays the player's name
- Click the toast to open the addon window
- Automatically fades after 5 seconds
- Can be enabled/disabled in settings
- Test button to preview the notification

## Automated Messages

### Raid/Party Message
- Automatically sends a message to raid or party chat when summoning
- Default: "Summoning %s, please help click!"
- `%s` is replaced with the target player's name
- Can be enabled/disabled and customized
- Enabled by default

### Say Message
- Optionally sends a `/say` message when summoning
- Default: "Summoning %s, please help click!"
- Useful for alerting nearby players to help click the portal
- Can be enabled/disabled and customized
- Disabled by default

### Whisper Message
- Optionally whispers the summoned player
- Default: "Summons incoming. Be ready to accept it. If you don't receive it within 30 seconds, let me know!"
- Can be enabled/disabled and customized
- Disabled by default

## Interface Options

### Shaman Class Color
- Choose how Shaman class colors are displayed:
  - **Expansion Default** - Pink in Classic Era, Blue in TBC+
  - **Blue** - Always use blue
  - **Pink** - Always use pink

### Range Opacity
- Adjust the opacity of out-of-range and offline raid members (10% - 100%)
- Helps visually identify who is nearby and summonable
- Default: 50%
- To disable, set to 100%

## Additional Features

### Minimap Button
- Toggle the addon window from the minimap
- Button can be shown/hidden via `/trs minimap` or via the settings panel
- Draggable to any position around the minimap

### Keybinding Support
- Bind a key to toggle the addon window to access it quickly and easily
- Configure in Game Menu > Key Bindings > Timber's Raid Summoner

## Slash Commands

- `/trs` or `/timbersraidsummoner` - Toggle the addon window
- `/trs minimap` - Toggle the minimap button visibility

## Technical Details

- **Supported Game Versions**: WoW Classic Era (1.15.x), TBC Classic (2.5.x), WoW: Forever (1.60.x)
- **SavedVariables**: Settings persist per-account
- **Addon Communication**: Uses addon message channel for cross-player sync
