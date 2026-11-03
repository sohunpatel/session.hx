# session.hx

A session manager for Helix's experimental Steel runtime, inspired by
[nvim-possession](https://github.com/jedrzejboczar/nvim-possession).

Sessions save the file-backed buffers currently open in Helix. They are stored in the
shared XDG data directory: `$XDG_DATA_HOME/helix/sessions` or, when
`XDG_DATA_HOME` is unset, `~/.local/share/helix/sessions`. The most recently saved
session for a project is loaded automatically when Helix starts from that project's
directory.

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
| `:session-load <name>` | Open a saved session's files without changing the layout. |
| `:session-delete <name>` | Delete a saved session. |
| `:session-list` | Display saved session names in Helix's status line. |
| `:session-autoload` | Load the most recently saved session for the current project. |

Session names must not be empty or contain `/`, `\`, or `..`.

## Automatic loading

Creating or updating a session places it first in the shared session store for its
current working directory. When Helix starts in that directory without file
arguments, the plugin loads the most recently saved session automatically. Starting
Helix with a file, such as `hx main.rs`, skips automatic loading. While a session is
active, opening or closing a file-backed buffer updates it in the shared store. No
`init.scm` conditionals are needed. The active session name is shown on the right
side of the status bar.

## Keybindings

The commands can be bound using the Steel keymap helper:

```scheme
(require (only-in "helix/keymaps.scm" keymap))

(keymap (global)
        (normal (space (s (s ":session-create work")
                          (l ":session-load work")
                          (d ":session-delete work")))))
```
