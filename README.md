# FostercareBars

Modern action bars for World of Warcraft 1.12.1, with named profiles of what is
on them.

## Features

- **The stock bars as new buttons:** Main (paged by stance, stealth and the bar
  page, as the game does), Bottom Left, Bottom Right, Right, Left and Extra 1, on
  the same action slots and the same keys. Each button redraws only when its
  slot changes: no work every frame.
- **Up to 10 extra bars:** first on the slot pages your class never uses, then
  bars of their own past the 120 action slots. They all hold spells, items,
  macros and equipment sets; drag and drop between any two buttons; each gets its
  keys in Key Bindings.
- **Each button:** cooldown countdown, range and mana colours, reagent counts,
  equipped border, auto-attack flash, macro names, key text, tooltips.
- **Profiles:** save what is on every bar under a name and load it again, also
  from BrainwasherPro when a talent spec changes. An item not in your bags yet is
  placed when it arrives.
- **Layout:** per bar shown, size, buttons per row, spacing and empty buttons;
  Move bars drags them. Hide the gryphons, the bar art, the bag and menu buttons
  and the stance bar.

Everything is on its page in AddOn Options; `/fbars` opens it.

## Requirements

WoW 1.12.1 (build 5875) with **ClassicAPI** loaded.

## Installation

Download `FostercareBars.zip` from the
[latest release](https://github.com/Fostercare5988/FostercareBars/releases/latest),
extract it into `Interface/AddOns` and enable it in the game's AddOns list. The
folder must contain `Interface/AddOns/FostercareBars/FostercareBars.toc`. It
replaces ActionBarProfiles and the action bars of FostercareTweaks before 1.0.0:
turn those off.
