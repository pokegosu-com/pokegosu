# Design

How PokeGosu looks, reads and behaves. The tokens live in [libs/ts/ui/theme.css](libs/ts/ui/theme.css); this says when to use each.

## Principles

- **The Pokémon is the point.** The interface is neutrals and one blue, so the sprites, levels and type dots are what the eye lands on. If a screen looks colourful, the colour should come from Pokémon data, not from the chrome.
- **Numbers are data.** Dex numbers, levels, token counts and versions are set in the mono face with tabular figures. Words are in the sans face.
- **One accent for one thing at a time.** `accent` marks the next action or the current thing: the primary button, the partner's outline, a progress fill, a link. Two primary buttons side by side usually means one should be quiet.
- **Outlines, not fills.** Cards and lists are drawn with a 1px `line` on `surface`, with no shadows. `surface-raised` is for wells inside them, such as a code block, never for the card itself. A sprite stands on `surface` with no well behind it.

## Words

The apps are in Korean. Write the way the games talk to a trainer: plainly and briefly.

- One language per page. A Korean page shows no English beside the Korean: no English names, no English labels. Product names such as PokeGosu Coder and Claude Code stay as they are.
- Names keep their capitals: PokeGosu, PokeGosu Coder, PokeGosu Pokédex, PokeGosu 계정. Never lowercase them, even in a logo spot.
- The Pokémon a trainer is raising now is their 파트너, never 메인.
- Buttons are the action, as short as the games put it: 알 받기, 부화시키기, 파트너로, 진화, 로그인. No trailing period.
- Lines about a Pokémon use the games' plain declarative: "적성에 맞는다", "매우 적성에 맞는다". Lines to the trainer use 합니다체: "아직 기록이 없습니다".
- Numbers read `No.025`, `Lv.16`, `12,480 토큰` when exact, and `12.5K` when compact, with the exact count beside it or in a `title`.
- Emoji only where the games have a symbol: ✨ for a shiny Pokémon, 🎀 for a ribbon. Never as decoration.

## Colour

| Token                      | Use                                                                                                   |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `surface`                  | The page. Also the text on an `accent` fill.                                                          |
| `surface-raised`           | Wells on the page: code, bar tracks, the selected segment's ground. Never behind a sprite.            |
| `ink`                      | Text, names, numbers, headings.                                                                       |
| `muted`                    | Secondary text on `surface`: labels, section headings, hints, links at rest.                          |
| `accent`                   | The primary button, the partner's outline, progress fills, links, the focus ring. Never a large fill. |
| `line`                     | Card outlines, dividers and list rules. Never the only edge of a control.                             |
| `line-strong`              | Inputs and quiet buttons, and a card's outline on hover. It holds 3:1 on `surface`.                   |
| `danger`, `danger-surface` | An error, as text alone or in a notice on its fill.                                                   |
| `mark-blue`, `mark-red`    | The six box marks, and nothing else.                                                                  |
| `ribbon-surface`           | Behind a ribbon's name.                                                                               |
| `sparkle`                  | The sparkles around a shiny Pokémon's artwork as it hops.                                             |
| `provider-*`               | Each coding agent in usage charts, always with a legend naming it.                                    |
| `type-*`                   | A type's colour, only ever as the dot beside its name.                                                |

Every colour has a dark value, chosen by `prefers-color-scheme`. Text holds 4.5:1 on its ground in both themes; `mark-blue` falls short on white and is kept as the games have it, so a mark always carries its state in its `aria-label` as well.

## Type

- IBM Plex Sans KR (400, 500, 600) for words and IBM Plex Mono (400, 500) for numbers, loaded from Google Fonts by `<Fonts />` in each layout, as `font-sans` and `font-mono`.
- A page has one `h1`: 36px on the landing page, 30px for a Pokémon's name on its own page, 24px for other page titles. Headings are 600 with `tracking-tight`.
- Section headings inside a page are 14px, 500, in `muted`: 요일별, 진화, 기록.
- The interface runs at 14px; hints and small print at 12px.

## Layout

- Every app page, its top bar included, is `max-w-wide` (64rem) with a 24px side gutter, so the left edge stays put between sections. Single-task pages, such as sign-in and device approval, are `max-w-task` (24rem) and centred.
- Sections are 32 to 40px apart; cards in a grid 8 to 12px.
- A list of Pokémon is a grid of small tiles with the 96px pixel sprite at its own size, never scaled up, shrinking only where the grid is too narrow for it: 6 across in the box, 8 across in a pokedex. One Pokémon on its own page gets its large render, from Pokémon HOME, in a 192px slot.
- Running text inside a wide page stays under about 40rem.
- Mobile layouts come later; nothing is designed for them yet beyond grids that wrap.

## Shape

- Radii: 4px for chips and ribbons, 6px for buttons, inputs and notices, 8px for cards and lists, full for bars and dots.
- Borders are 1px. The partner's card or tile takes `accent` for its outline; nothing else has a coloured border.

## States

- Hover: a clickable card's outline goes from `line` to `line-strong`; a link from `muted` to `ink`.
- Focus: a 2px `accent` outline, offset 2px, on everything interactive.
- Disabled: 50% opacity. A button waiting on the server is disabled and keeps its label.
- Motion: numbers count up as tokens land, and bars ease their width. Under `prefers-reduced-motion` they jump to their value.

## Icons

There is no icon set. Sprites come from pokedex-web: in a list, the 96px pixel front sprite, and the egg, both with `image-rendering: pixelated`; on a Pokémon's own page, its Pokémon HOME render, through `Artwork`. HOME's is the one large style with every Pokémon, its shiny and, where she looks different, its female; a form HOME never held takes the official artwork instead. The marks are the glyphs ● ▲ ■ ♥ ★ ◆, arrows are → and ←. The only drawn icons are the menu (three lines), the pencil that edits a value in place, and the Poké Ball that marks a pokedex entry the trainer has caught, all in `currentColor` with 1.5px strokes, and the four-pointed sparkle around a shiny Pokémon's artwork. PokeGosu's own icon is a Poké Ball in a trainer's cap. It is drawn in `ink`, light and dark, from `@pokegosu/ui/icon`: as the favicon, and beside PokeGosu at the top of the app drawer. An icon-only button has an `aria-label` and a `title`.

## Components

Shared pieces live in `@pokegosu/ui`. Reach for them before drawing the same thing again.

| Import                   | What it is                                                                                                                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@pokegosu/ui/app-shell` | `AppHeader`: the top bar with the menu button, the app's full name and its sections, and the app drawer it opens. Each app's layout places it once.                                                                                            |
| `@pokegosu/ui/apps`      | Where each app lives, and the order the drawer and the landing page list them.                                                                                                                                                                 |
| `@pokegosu/ui/artwork`   | `Artwork`: a Pokémon's large render in the 192px slot. It idles, hops when it appears, is pointed at or pressed, and sparkles if shiny; with reduced motion it stands still.                                                                   |
| `@pokegosu/ui/pokemon`   | `TypeChip` (a type's name beside its dot), `ProgressBar`, `PokemonTile` (a small sprite, a name and one line of data, the whole tile a link), and `CaughtMarks` (✨ then the ball, at a pokedex entry's top right, for the trainer signed in). |
| `@pokegosu/ui/fonts`     | `<Fonts />`, for each layout's `<head>`.                                                                                                                                                                                                       |
| `@pokegosu/ui/icon`      | `PokeGosuIcon`, the Poké Ball in a trainer's cap, in the colour of the text around it; `faviconUrl`, the same drawing for each layout's `metadata.icons`; and `CaughtIcon`, the ball alone, thin, for `CaughtMarks`.                           |

## Behaviour

**Moving around.** Each app has a top bar: a menu button, the app's full name, and its sections, the current one in `ink`. The name is not a link: the first section is home. The menu button opens a drawer from the left listing PokeGosu Pokédex, then PokeGosu Coder, and 계정 at the bottom. The drawer is the only way between apps and to the account; top bars link to neither. A page below a list starts with ← and that list's name.

**Every screen has four states.** Design each before it ships.

| State   | What shows                                                                                                     |
| ------- | -------------------------------------------------------------------------------------------------------------- |
| Loading | The page's shape, or 불러오는 중… in `muted` for a single line. Never a lone spinner.                          |
| Empty   | A heading that says what is missing, and the one next step as a link or a command to copy. Never a blank list. |
| Error   | A notice in `danger` on `danger-surface` above whatever did load, saying what failed and what to do.           |
| Ready   | The summary first (the partner, the last 24 hours' tokens), then the detail.                                   |

**Actions.**

- The action the game is waiting for is the primary button; housekeeping, such as 파트너로, is quiet.
- Nothing irreversible happens in one press. Retiring a device asks inside its row; a page never uses the browser's `confirm()`.
- A button disables while its request is out, and the page updates in place when it lands. A failure is said under the buttons and leaves things as they were.
- Buttons stay hidden while a level is still counting up, so nothing is pressed on a level the bar has not reached.

**Reading.** Pair every bar with the number it draws. Right-align numbers in lists. A Pokémon's name links to its page wherever it appears.
