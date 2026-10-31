# session.hx

A project-local session manager for Helix's experimental Steel runtime, inspired by
[nvim-possession](https://github.com/jedrzejboczar/nvim-possession).

Sessions save the file-backed buffers currently open in Helix. They are stored as
`.helix/sessions/<name>.scm`, so a project's sessions can be inspected, shared, or
ignored alongside the rest of its local Helix state.

## Installation

Install the Steel-enabled Helix fork and package manager described in its
[Steel guide](https://github.com/mattwparas/helix/blob/steel-event-system/STEEL.md),
then install this repository:

```sh
forge pkg install --git https://github.com/sohunpatel/session.hx.git
```

Load it from `~/.config/helix/helix.scm`:

```scheme
(require "session-hx/session.scm")
```

## Commands

| Command | Description |
| --- | --- |
| `:session-create <name>` | Save open file-backed buffers under `<name>`. Existing sessions are replaced. |
| `:session-load <name>` | Open a saved session's files in vertical splits. This adds to the current layout. |
| `:session-delete <name>` | Delete a saved session. |
| `:session-list` | Display saved session names in Helix's status line. |

Session names must not be empty or contain `/`, `\`, or `..`.

## Keybindings

The commands can be bound using the Steel keymap helper:

```scheme
(require (only-in "helix/keymaps.scm" keymap))

(keymap (global)
        (normal (space (s (s ":session-create work")
                          (l ":session-load work")
                          (d ":session-delete work")))))
```
