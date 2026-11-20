# MODAL-hx

Helix style modal editing for Pragtical

## Optional plugins

The preset works with Pragtical’s bundled plugins. Install these extras with
`ppm` to enable their shortcuts.

| Plugin | Shortcuts |
| --- | --- |
| `bracketmatch` | Jump to or select a matching bracket |
| `navigate` | Move backward or forward through cursor history |
| `tab_switcher` | Pick an open tab with Space, then `b` |
| `lsp` | Show symbol information, diagnostics, definitions and references |

## Keymap

Press `Space` in NORMAL mode to see the available groups and commands.
`Space e` opens the Editor group. Press `s` for Settings or `l` for the log.
`Space l` opens the Language Server group. Use `Space l g d` to jump to a
definition or `Space l f` to format the document.

## Editing and selections

NORMAL starts with one character selected. Press `v` to enter SELECT and
extend from that character. Escape returns to NORMAL with the range selected.
Press `;` to collapse each range to its cursor or `,` to keep the primary
selection. Use `C` to copy a selection onto the next line.

From the `o` in `one  two`, `w` selects `one  ` and `e` selects `one`.
The uppercase motions treat punctuation as part of a word. Prefix a motion
with a count, or use `f` and `t` followed by a character to select through
or up to its next occurrence. `F` and `T` search backwards.

Use `s` to select regex matches within each range and `S` to split ranges.
`y` copies the selections. `d` deletes them and `c` changes them in INSERT.
`i` inserts at each selection's start and `a` appends at its end. Press
Escape to finish. A dot repeats the last insertion at the current selections.

Named registers, macros and change-history navigation are among the upstream
commands outside this preset. The help tab shows the bindings available in
Pragtical. [Helix keymap reference](https://docs.helix-editor.com/keymap.html)
