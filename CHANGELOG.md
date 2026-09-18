# Changelog

## v2026.09.17b (2026-09-17)

- Added WoW: Forever (interface 16001) to the supported clients
- Added a client compatibility layer so spell lookups and addon messages work on both the Classic and Forever APIs
- Summon casts are now matched by spell ID instead of the English spell name, so localized clients detect them too

## v2026.09.17a (2026-09-17)

- Fixed chat diagnostic buttons ignoring left-clicks; both mouse buttons now run tests
- Added a log message when combat prevents a diagnostic test

## v2026.09.17 (2026-09-17)

- Added `/trs debug` chat tests for any class or level, with dry-run and live modes
- Added a copyable diagnostic log for chat attempts, summon events, and errors

## v2026.08.29 (2026-08-29)

- Updated Era TOC version to 11509


## v2026.07.07 (2026-07-08)

- Fixed pkgmeta paths after the Src rename so packaging doesn't double-nest the addon, removed the stale nested pkgmeta
- Added dev LUA folder to pkgmeta ignore so users won't get development code
- Updated gitignore, removed gitkeep from ".releases" folder, because that folder doesn't need to be under source control
- Renamed "Src" to "TimbersRaidSummoner" to alllow easier packaging, added testmode functionality for development purposes
- Updated TOC version to 20506
- Added project.yml file
- Added metadata doc file
- Moved files to align with desired file structure

## v2026.03.31

### Added

* Added instructions on how to move the overlay on the overlay itself
* Added button to overlay that opens assignments window
* Added CHANGELOG.md

### Changed

* Refactored file structure

### Fixed

* Fixed .pkgmeta to properly fix the CurseForge packager
