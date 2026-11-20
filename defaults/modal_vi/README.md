# MODAL VI

Simplistic configuration to imitate a basic `vim` configuration

In NORMAL mode, press `Space` then `g` to open Go To Line. Enter a line
number and press Enter to jump there.

Press `Space e` to list editor commands, including `Space e s` for Settings
and `Space e l` for the log. `Space l` lists language server commands.
For example, `Space l g d` jumps to a definition and `Space l f` formats
the document with the optional LSP plugin.

In NORMAL mode, `H`, `M`, and `L` move to the first nonblank character
of the top, middle, or bottom visible line. In VISUAL mode, the same keys
extend the selection from its anchor. Use `3H` for the third line from the
top or `3L` for the third from the bottom. Each wrapped line counts once.

In NORMAL mode, type `d` to delete, `c` to change, or `y` to yank, then
type a motion. All three copy the affected text to the clipboard. Change
also enters INSERT so you can type the replacement.

| Keys | Effect |
| --- | --- |
| `dw` | Delete to the start of the next word, including intervening spaces. At the end of a line, keep the newline. |
| `cw` | Change the rest of the current word and keep the spaces after it. |
| `d$` | Delete from the cursor through the end of the line. |
| `y2w` | Copy two words. |
| `2d3w` | Delete six words. Counts before and after the operator multiply. |
| `cc`, `dd`, `yy` | Change, delete, or yank whole lines. |

The supported motions are `h j k l` and the arrows, `w W b B e E`,
`0 ^ $ g_`, `gg G`, `H M L`, and `f F t T` followed by a character.
Use `iw` for the inner word or `aw` to include adjacent space. The uppercase
forms `iW` and `aW` treat punctuation as part of the word. These objects also
work in VISUAL mode. Press Escape or switch views to cancel a pending operator.

Use `p` to put a whole-line yank below the cursor or `P` to put it above.
For example, `yyp` duplicates the current line from any column. A characterwise
yank goes after or before the cursor character.

Press `v` to select characters, move to either end of the desired text, then
press `d` to delete, `y` to yank, or `c` to change the selection. Both ends
are included, even when moving backwards. Starting on the `b` in `abcde`,
`vlc` removes `bc` and enters INSERT. Type `X` and press Escape for `aXde`.

Use `V` for **VISUAL LINE**. It selects the entire current line. For example,
`V2jy` yanks the current line and the next two, and `Vj>` indents two lines.

Use `Ctrl+v` for **VISUAL BLOCK**. Move with `h j k l` or the arrow keys to
select a rectangle. For example, `Ctrl+v`, `2j`, `l`, `d` deletes two columns
from three lines. Yank with `y`, then use `p` or `P` in NORMAL to put the
rows back as a rectangle. A count before the put repeats it horizontally.

In a block, `c` changes the selection, `I` inserts at its left edge, and `A`
appends at its right edge. Type once across the selected rows and press Escape
to return to one cursor. `I` skips rows that end before the block. `A` pads
short rows with spaces. Use `$` before `A` to append at each line's own end.

Press `v`, `V`, or `Ctrl+v` during a selection to switch its shape while
keeping its anchor. Press the current shape's key again, or Escape, to leave
Visual mode. In line and block selections, `o` swaps ends. In a block, `O`
swaps the horizontal corners.

In NORMAL mode, `.` repeats the last change at the cursor, including text
entered in INSERT. On `cat cat`, `cwdog<Esc>w.` produces `dog dog`.
Moving or yanking between edits preserves the change available to repeat.
