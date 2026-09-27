# Timber's Raid Summoner

A World of Warcraft addon for Classic Era, TBC Anniversary, and WoW: Forever that provides a comprehensive and feature-packed interface used for summoning entire raids or parties. Born from a need to organize summon requests and raid members running to the instance portal on my summoning alt, I created an addon so powerful that it's the only addon you need as a level 20 warlock when it comes to summoning.

## Features

- List of all characters in the current raid group
- List of summon requests (in chronological order received) in a side panel to the main summoning interface
    - Option to play a sound when someone is added to the list
    - Left click to target the character, right click to summon
        - Holding shift while right clicking turns on "silent mode" where it does the summon, but doesn't send out messages
- Customizable list of keywords automatically add people to the list of summon requests
    - Starts off with anything containing "123", " 123", or " 123 ", can be expanded manually if a person's message didn't work
    - Copy EasySummon's UI for the keyword list: a scrollable list of words with an input field and "Add" button above the list
    - When a person is added to the list, play a sound
    - After 2 minutes of being on the list, the character is automatically removed from the list
        - This needs to persist through "/reload"
    - Can remove a player's name from the list manually without broadcasting their name
        - Maybe by middle clicking their name on the list? Maybe a small "X" button to the right of their name?
- Automatically send a message in `/raid` to let everyone know you're summoning a character, and to help click
    - Message can be customized
    - Default message: "Summoning [[character_name]], please help click!"
- Option to automatically whisper the target of the summon that a summon is coming
    - Message can be customized
    - Default message: "Summons incoming. Be ready to accept it. If you don't receive it within 30 seconds, let me know!"
    - Disabled by default
- (Optional) When you click the button to summon someone, it first checks for 300+ mana; if you don't have at least 300 mana, it will prevent the summon (and messages) from going out, and alert you to the need for mana
    - This might be accomplished by waiting for the cast to start, and if it doesn't start after 1 second, alert the user to low mana
- (Optional) When you begin casting summon, gets number of shards in your bags. After the cast, if the number didn't go down by one, alerts you to a failed summon
    - Might be better accomplished by checking for SPELLCAST_FAILED
- (Optional) Shares summon request list with others in your raid that also have the addon
    - Whenever you join a group, automatically request the updated list from others in the raid/party
    - Removes characters from the shared list the instant you click on the button

## Minimap Button

Left-clicking toggles the addon's summoning interface.

Right-clicking brings up a menu that allows you to select from the following options:

- Show summoning interface
- Hide minimap button

## Slash commands

```/trs``` or ```/timbersraidsummoner``` - Opens addon's summoning interface
```/trs minimap``` - Toggles minimap button visibility

