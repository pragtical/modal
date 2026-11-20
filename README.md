# MODAL

A fully customizable modal editing experience for Pragtical

## Principles

### Modal editor

A modal editor is a text editor that has different **modes** that define how the user interact with
the editor and its content.

The list of modal editor is long (maybe to long), few of them are listed below:
 - Ex
 - VI
 - VIM
 - NeoVIM
 - Kakoune
 - Xi
 - Helix

Most of this editors have a *normal* mode where the user can navigate and manipulate the text
and at least a *insert* mode where the user can edit/enter text as in non modal editors.

### But why

When developing code I spend a good fraction of time navigating the code, jumping trought definition and references, files
and so on.

While using standard short cut and the mouse could make the job, I find that using non-editing modes makes it
much better:
 1. More ergonomical: no mouse involved, almost infinite combination of strokes for each action etc
 2. Faster: my hands are always ready to type
 3. Universal: almost everywhere I can find a modal text editor (at least vi) and I can use it without being lost

Please note that these are my opinion and I am not trying to convince you!

I like modes and I like to customize my editor. The plugin starts with Vi bindings,
and you can change the preset or define your own modes and shortcuts.


## How to install

Install `modal` from the [Pragtical plugin repository](https://github.com/pragtical/plugins)
with [ppm](https://github.com/pragtical/plugin-manager).

```sh
ppm install modal
```

For a manual install, copy this repository's contents into `USERDIR/plugins/modal/`.
On Linux, the default location is `~/.config/pragtical/plugins/modal/`.

## How to use

Modal editing starts enabled with the **Vi** preset. Press `i` to type and
`Escape` to return to NORMAL. Choose another preset under
**Settings → Plugins → Modal → Preset**. While modal editing is on, every open
document switches to the new preset’s starting mode immediately. While editing
is off, the choice takes effect the next time you enable it. Choose **Custom**
to restore your Lua configuration, or ordinary typing if you defined no modes.

| Preset | Starting mode | Enter text | Return to the starting mode |
| --- | --- | --- | --- |
| [Helix](defaults/modal_hx/) | NORMAL | `i` | Escape |
| [Vi](defaults/modal_vi/) | NORMAL | `i` | Escape |
| [Example](defaults/modal_example/) | MOVE | `e` | Escape |

Turn off **Settings → Plugins → Modal → Enable Modal Editing** to use ordinary
Pragtical editing. You can also click the current mode in the status bar and
press Enter on `modal:toggle` to switch editing for the current session.
The Settings checkbox saves your choice for future launches. If the preset
stays the same, turning modal editing back on resumes each open document’s
mode with a fresh key sequence.

To start with ordinary editing from your Lua configuration, set
`config.plugins.modal.enabled = false` in your user module.

The same settings panel controls key helpers, mode notifications and their timing,
and the mode and keystroke indicators in the status bar. These options apply immediately.

### Using a preset from Lua

You can also load a preset in Pragtical's user module. For example, to load Helix:

```lua
require "plugins.modal.defaults.modal_hx"
```

Use `modal_vi` or `modal_example` for the other presets. A Lua configuration that
sets `config.plugins.modal.base_mode` takes precedence at startup. You can
still switch presets from Settings and return to that configuration with **Custom**.

### Manual Configuration

If you want to personalise your experience you can manully configure `modal` (or extend/modify any of the defaults).

You can define your configuration directly in your Pragtical [`init.lua`](https://pragtical.dev/docs/user-guide/configuration) or
you can create an external file in your configuration folder and include it using `require "YOUR_FILE"` inside the
Pragtical configuration file (as is done for the default presets).

All the configuration of the plugin is stored in the *standard* `config` module so the first thing to do is to load it (if it is not already done):

```lua
local config = require "core.config"
```

**Note** that Pragtical’s default user configuration already loads `config`.

Then all the configurations will be done inside the `config.plugins.modal` table.

You will also need `modal` for the configuration (and *optionally** its utilities):

```lua
local modal = require "plugins.modal"
local modal_utils = require "plugins.modal.utils" -- **OPTIONAL** utilities
```

#### Define modes

The first thing to do is to define the modes names and which should be your default mode (the one that will be active when starting Pragtical or opening a file etc).

```lua
---Mode IDs used by this example preset.
config.plugins.modal.modes = { "Move", "Edit", "Jump" }
---Mode given to newly opened documents.
config.plugins.modal.base_mode = "Move"
```

Now for each mode you can/have to do a number of choices:
 1. which interaction mode to use (basically what to do when you type)
 2. *optionally* which caret style use
 3. define keybindings
 4. *optionally* customize the key helper captions

The **interaction mode** (`on_key_callbacks`) specifies to modal what to do when you press a key, there are 2 defaults interaction modes:
 1. `modal.on_key_command_only`: keys will only be used to match your keybinding and not to directly edit your files
 2. `modal.on_key_passthrough`: keys will be used to match your keybinding and to edit your file (basically what Pragtical does already)

You can also define your own interaction mode, but this is outside the scope of this documentation.

```lua
-- config.plugins.modal.on_key_callbacks.YOUR_MODE = modal.on_key_YOUR_CHOICE
config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough
```

*Note* that in the `on_key_passthrough` mode you can use the default Pragtical shortcuts.


The **caret stye** is optional, if not defined the standard Pragtical caret will be used, 2 caret styles are defined:

 1. `modal.caret_style.NORMAL` the standard vertical thin line of Pragtical
 2. `modal.caret_style.BAR` a big block covering the full size of a letter

```lua
-- config.plugins.modal.carets.YOUR_MODE = modal.caret_style.YOUR_CHOICE
config.plugins.modal.carets.Move = modal.caret_style.BAR
config.plugins.modal.carets.Jump = modal.caret_style.BAR
-- Edit uses the default vertical caret.
```

#### Keybinding

When writing a Lua keymap, choose how to spell the shortcuts. The modules in
`bindings_models/` translate those spellings into the key sequences Pragtical
uses. The Helix preset uses `modal` notation, and Vi and Example use `compact`.
Use `pragtical` if you prefer to write native key names directly. Each row
below describes the same keystrokes in all three notations.

| Modal        | Pragtical         | Compact       |
| :----------- | :---------------- | :------------ |
| `<space>f`   | `space f`         | `space f`     |
| `<space>F`   | `space shift+f`   | `space S+f`   |
| `C-f`        | `ctrl+f`          | `C+f`         |
| `F<.>`       | `shift+f $`       | `S+f $`       |
| `<space>wQ`  | `space w shift+q` | `space w S+q` |

Notes that modal work with combination of keys (e.g. `ctrl+f`) and sequences (e.g `space f`) as well as combination of the two.
Choose `modal`, `pragtical`, or `compact` when you [load your bindings](#load-binding).

The sequences can be as long as wish but **the first combination matched will be executed.**

A combination can have any key as argument `<.>` in the `modal` style or `$` in the other style: in the table for example `modal` will match any `F` followed by a key stroke.
This can be useful when a command need a character as argument (for example move to the next `<.>`).

In the rest of the documentation I will use the **compact** syntax (that in my opinion is the best one).

```lua
-- config.plugins.modal.keymaps.YOUR_MODE = YOUR_KEYMAP
config.plugins.modal.keymaps.Move = {  -- configure keymap of mode [Move]
  -- A sequence can run a callback, a command ID, or an ordered list of both.
  ["e"] = modal.go_to_mode("Edit"), -- change mode to [Edit]
  ["j"] = modal.go_to_mode("Jump"), -- change mode to [Jump]
  ["right"] = "doc:move-to-next-char", -- move right
  ["left"] = "doc:move-to-previous-char", -- move left
  ["up"] = "doc:move-to-previous-line", -- move up
  ["down"] = "doc:move-to-next-line", -- move down
}

---Edit mode also accepts native Pragtical shortcuts.
config.plugins.modal.keymaps.Edit = {
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["C+S+;"] = "core:find-command", -- open command bar
  ["C+S+/"] = "modal:help", -- open modal help
}

config.plugins.modal.keymaps.Jump = { -- configure keymap of mode [Jump]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["e"] = modal.go_to_mode("Edit"), -- go to mode [Edit]
  -- jump to next word end
  ["right"] = { "doc:select-none", "doc:select-to-next-word-end" },
  -- jump to previous word start
  ["left"] = { "doc:select-none", "doc:select-to-previous-word-start" },
  -- jump to last word of previous line
  ["up"] = {
    "doc:select-none", "doc:move-to-previous-line",
    "doc:move-to-end-of-line", "doc:select-to-previous-word-start"
  },
  -- jump to first word of next line
  ["down"] = {
    "doc:select-none", "doc:move-to-next-line",
    "doc:move-to-start-of-line", "doc:select-to-next-word-end"
  },
}
```

Two important features can be seen in this example:

1. to each binding is possible to assign:
    1. a callback function
    2. a command as a string
    3. a list of a mix of callbacks and commands (in this case the actions will be executed sequentially)
2. different modes can bind same sequences to different action (e.g. `right` in `Move` and `Jump`)

It is also possible to use intermediate tables to store common bindings and reuse them between modes:

```lua
local common_bindings = {
  ["S+;"] = "core:find-command", -- open command bar
  ["space S+/"] = "modal:help", -- show modal help
  ["space q"] = "root:close", -- close tab
}

config.plugins.modal.keymaps.Move =
  modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Move)
config.plugins.modal.keymaps.Jump =
  modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Jump)
```

##### Numbers/Digits

Numbers can not be used in keystrokes as they are used as modifiers to repeat a certain number of times the action.

For example `10 left` will execute 10 times the action binded to the `left` stroke.

Wrap a callback with `modal.with_count(function(count) ... end)` to receive the
prefix once. The count defaults to 1. The Vi preset uses this for `3H`, which
jumps to the third visible line.

##### Helpers

In NORMAL mode, press `Space` to see the next keys in the active preset.
In both Vi and Helix, `e` opens the **Editor** group and `s` opens Settings.
Use `Space e l` for the log, `Space w` for windows, or `Space l` for the
optional LSP plugin. The same LSP shortcuts work in Vi’s characterwise
VISUAL mode and Helix’s SELECT mode.

| After `Space l` | Language server actions |
| --- | --- |
| `a` · `c` · `f` | Code action · Complete · Format document |
| `g d` · `g i` · `g r` | Go to definition · Go to implementation · Find references |
| `k` · `K` | Symbol information · Open symbol information in a tab |
| `h` · `H` | Signature help · Call hierarchy |
| `r` | Rename the selected symbol |
| `s` · `S` | Document symbols · Find workspace symbol |
| `d` · `D` | Document diagnostics · All diagnostics |
| `t d` · `t s` · `t a` | Toggle diagnostic annotations · Toggle symbols tree · Enable tree auto-hide |
| `v s` · `v x` · `v r` | Start · Stop · Restart language servers |

The popup reads the current mode’s bindings whenever a sequence is incomplete.
A `+` marks a group with more keys, and `<char>` means to type a character.
Press Escape to cancel. If the list spans several pages, use Page Up, Page
Down, or the mouse wheel over the popup. Explicit bindings for those keys
take precedence.

Custom keymaps also get a popup. To give an action or group your own caption,
add a helper in the same notation as the keymap. For example, with the compact
binding model, these captions label two existing shortcuts.

```lua
config.plugins.modal.helpers.Move = {
  ["space"] = {
    { "S+/", "Show keymap" },
    { "q", "Close document" },
  },
}
```

The overlay is enabled by default and appears immediately. In the Modal plugin
settings, **Show Keymap Overlay** turns it on or off and **Keymap Overlay Delay**
sets the wait in seconds. Use `modal:toggle-keymap-overlay` to change overlay
visibility for the current session. In Lua, set
`config.plugins.modal.show_helpers` and `config.plugins.modal.key_helper_delay`.

##### Load binding

**NOTE THIS STEP IS MANDATORY**

To finalise your configuration you **have** to laod your bindings in the internal `modal` representation (this will also load your helpers, if any):

```lua
-- local kb_model = require "plugins.modal.bindings_models.YOUR_CHOICE"
local kb_model = require "plugins.modal.bindings_models.compact"
-- store the keybindings and helpers in the internal representation
modal.load_bindings(kb_model)
```

This step is mandatory in order to allow multiple keybinding syntaxes.

#### UI

`modal` includes few UI elements: the helper and a simple status bar.
Both are configurable.

##### Helper Style

The style can be configure as follow:

| Field                     |      Default       | Comment                 |
| :------------------------ | :----------------: | :---------------------- |
| `style.helper.background` |    `style.background2`     | helper background color |
| `style.helper.text`       |    `style.text`     | helper text color       |
| `style.helper.padding`    |         10         | helper internal padding |
| `style.helper.margin`     |         10         | helper external margin  |
| `style.helper.alignement` | `modal.align.LEFT` | helper alignement       |

##### Status-bar

`modal` provides a widget at the bottom left of the Pragtical status bar.
This widget can contains the following information:

- The current mode, enabled by default and configurable in the variable `config.plugins.modal.status_bar.mode` (boolean)
- The current keystroke, enabled by default and configurable in the variable `config.plugins.modal.status_bar.strokes` (boolean)

The status bar by default shows the current state and the current sequence but can be configured:

```lua
-- config.plugins.modal.status_bar.mode = true -- show current mode (default is
-- true)
-- disable current strokes in status bar
config.plugins.modal.status_bar.strokes = false
modal.set_status_bar() -- update statusbar
```

#### Utilities

`modal` comes with an utilities library with common action and function useful for advanced configuration, this is found in `plugins.modal.utils`

In the example the `concat` function is used but if you have a look to the `hx` or `vi` preset you will see many other examples.

Custom modes can use `modal.selection` to select whole lines or a rectangle.
Pass the moving corner and anchor as 1-based document lines and byte columns.
Both corners are inclusive. For example, this binding selects a rectangle
from the current caret through the same display column on the next line.

```lua
local block = require "plugins.modal.block"
config.plugins.modal.keymaps.Move.b = function()
  local view = modal_utils.get_dv()
  local line, col = view.doc:get_selection()
  local next_line = math.min(line + 1, #view.doc.lines)
  local cell = block.cells(view.doc, line, col)
  modal.selection.set(view, "block", {
    anchor_line = line, anchor_col = col,
    line = next_line, col = block.at(view.doc, next_line, cell),
  })
end
```

Use `"line"` for whole lines. To extend a selection, update the corners
returned by `modal.selection.get(view)` and pass them back to `set`.
`modal.selection.release(view)` restores a single native selection between
the two corners. For motions relative to the viewport,
`modal_utils.visible_line(view, "bottom", 2)` returns the second visible
document line from the bottom, counting a wrapped line once.

## Configuration table

The configuration of the modal experience can be done via the follow parameters:

| Field                                   |           Default           | Comment                                                   |
| :-------------------------------------- | :-------------------------: | :-------------------------------------------------------- |
| `config.plugins.modal.enabled`          |           `true`             | enable modal editing across documents                     |
| `config.plugins.modal.preset`           |           `"vi"`             | selected preset (`vi`, `hx`, `example`, or `custom`)           |
| `config.plugins.modal.base_mode`        |            `nil`            | default mode when opening a new document/session          |
| `config.plugins.modal.modes`            |            `{}`             | enumerate all the possible modes available                |
| `config.plugins.modal.keymaps`          |            `{}`             | table containing keymaps for each available mode          |
| `config.plugins.modal.select_cursor` | `{}` | Select the grapheme under the cursor in each enabled mode. |
| `config.plugins.modal.on_key_callbacks` |            `{}`             | table containing `on_key_pressed` callbacks for each mode |
| `config.plugins.modal.carets`           |            `{}`             | carets styles for each mode                               |
| `config.plugins.modal.helpers`          |            `{}`             | custom key helper captions per mode                        |
| `config.plugins.modal.show_helpers`     |           `true`            | enable or disable command helper                          |
| `config.plugins.modal.key_helper_delay` |            `0`              | seconds before the keymap overlay appears                 |
| `config.plugins.modal.status_bar`       | `{mode=true, strokes=true}` | configure the status bar widget                           |

Mandatory step is `modal.load_bindings(BINDING_MODEL)`

Additionally the helper styling can be changed:

| Field                     |      Default       | Comment                 |
| :------------------------ | :----------------: | :---------------------- |
| `style.helper.background` |    `style.background2`     | helper background color |
| `style.helper.text`       |    `style.text`     | helper text color       |
| `style.helper.padding`    |         10         | helper internal padding |
| `style.helper.margin`     |         10         | helper external margin  |
| `style.helper.alignement` | `modal.align.LEFT` | helper alignement       |

## Commands

- `modal:toggle` switches modal editing on or off for the current session.
- `modal:toggle-keymap-overlay` shows or hides key suggestions for this session.
- `modal:help` shows the active mode’s keymap.
- `modal:scroll-help-up` and `modal:scroll-help-down` scroll one row with
  **Up** and **Down** while the keymap help tab has focus.
- `modal:redo` repeats the last modal command. The Vi preset binds `.` to
  repeat the last edit, including replacement text entered in INSERT. In
  Helix, `.` repeats the last insertion.

Click the mode indicator for a searchable list of available `modal:` commands.
You can also run `modal:toggle` from Pragtical’s **Find Command** picker when the indicator is hidden.
