# Lite MODAL

A fully customizable modal editing experience for Lite Xl

![](intro.gif)


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

So I like modes and I like to custumize my editor at my will, that's why this plugin does not come with any
pre-defined setup (even if there are a few examples/configurations for who want to try) and can be configured
and expanded almost at any level.

## Configuration

The configuration of the modal experience can be done via the follow parameters:

| Field                                   |           Default           | Comment                                                   |
| :-------------------------------------- | :-------------------------: | :-------------------------------------------------------- |
| `config.plugins.modal.base_mode`        |            `nil`            | default mode when opening a new document/session          |
| `config.plugins.modal.modes`            |            `{}`             | enumerate all the possible modes available                |
| `config.plugins.modal.keymaps`          |            `{}`             | table containing keymaps for each available mode          |
| `config.plugins.modal.on_key_callbacks` |            `{}`             | table containing `on_key_pressed` callbacks for each mode |
| `config.plugins.modal.carets`           |            `{}`             | carets styles for each mode                               |
| `config.plugins.modal.helpers`          |            `{}`             | available command helpers per mode                        |
| `config.plugins.modal.show_helpers`     |           `true`            | enable or disable command helper                          |
| `config.plugins.modal.status_bar`       | `{mode=true, strokes=true}` | configure the status bar widget                           |

Additionally the helper styling can be changed:

| Field                     |      Default       | Comment                 |
| :------------------------ | :----------------: | :---------------------- |
| `style.helper.background` |    `#000000C8`     | helper background color |
| `style.helper.text`       |    `#FFFFFFDC`     | helper text color       |
| `style.helper.padding`    |         10         | helper internal padding |
| `style.helper.margin`     |         10         | helper external margin  |
| `style.helper.alignement` | `modal.align.LEFT` | helper alignement       |

### Key bindings

To define key bindings an extension to standard lite-xl syntax in order to implement the possibility to concatenate
multiple keystrokes:

- `KEY` is a single key binding
- `MOD+KEY` means that the key `KEY` is pressed while modifier `MOD` is active, e.g. `ctrl+tab`
- `KEY_A KEY_B` is a sequence of two strokes of `KEY_A` and `KEY_B`, e.g. `d d`

#### Any key catcher

`modal` support the option to catch any keystroke, but with the condition to be the last keystroke of a sequence.
The key is then stored, and your user function can use it to do action linked to the key, for example jump to the next matching character

In both `modal` and `lite-xl` syntax to match any character use `<.>` placeholder.

#### Numbers/Digits

Numbers can not be used in keystrokes as they are used as modifiers to repeat a certain number of times the action.

For example `10 ctrl+/` will execute 10 times the action linked to the `ctrl+/` sequence.

#### Equivalences Syntaxes

Below some equivalent representation with previous version

| Modal        | Lite              | Compact       |
| :----------- | :---------------- | :------------ |
| `<space>f`   | `space f`         | `space f`     |
| `<space>F`   | `space shift+f`   | `space S+f`   |
| `C-f`        | `ctrl+f`          | `C+f`         |
| `F<.>`       | `shfit+f $`       | `S+f $`       |
| `<space>wQ`  | `space w shfit+q` | `space w S+q` | 

### Configuration details

It is possible to configure any number of modes in the `modal.modes` table, for example:

```lua
config.plugins.modal.modes = {"NORMAL", "INSERT", "VISUAL"}
```

Then you should decide which mode is the base/default mode for example:

```lua
config.plugins.modal.base_mode = "NORMAL"
```

Then decide which kind of `on_key_pressed` call back to use (_or define your owns_):

```lua
config.plugins.modal.on_key_callbacks.NORMAL = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INSERT = modal.on_key_passthrough
config.plugins.modal.on_key_callbacks.VISUAL = modal.on_key_command_only
```

The callback `on_key_command_only` will only register the keystrokes and execute
the matched commands but will not forward the strokes to `lite-xl`. This will allow to
reproduce most modal editing stuff.

The callback `on_key_passtrought` will register the keystrokes and execute commands (if matched)
and will pass the strokes to `lite-xl`, usefull for _editing_ modes.

You can define your own logics if you want something different.

Lastly you have to define the keymaps for the different modes:

```lua
config.plugins.modal.keymaps.NORMAL = {
  ["i"] = modal.go_to_mode("INSERT"), -- function call back
  ["v"] = modal.go_to_mode("VISUAL"),
  ["u"] = "doc:undo",
  ["left"] = {"doc:move-to-previous-char", "dialog:previous-entry"},
  ["j"] = "doc:move-to-next-line",
  ["space f"] = "core:open-file",
  ["shift+p"] = "jp", -- other sequence
  -- .....
}
config.plugins.modal.keymaps.INSERT = {
  ["escape"] = modal.go_to_mode("NORMAL"),
}
-- ...
```

Each sequence can execute one or more commands, the commands can be functions or string.
If it is a string and it match another sequence, the sequence command is executed, otherwise
it will execute as a `lite-xl` command.

Optionally it is possible to configure additional features:

```lua
-- define BAR caret
config.plugins.modal.carets.NORMAL = modal.caret_style.BAR

-- helper definition
config.plugins.modal.helpers.NORMAL = {
  ["space"] = {
    {"f", "open file picker"},
    {"shift+p", "open project picker"},--...
  }
}
```

For more detailed example please look at [lite-modal-hx](https://codeberg.org/Mandarancio/lite-modal-hx) preset.

#### Status bar

`lite-modal` provide a simple status widget positioned on the bottom left of the `lite-xl` status bar.
This widget can contains the following information:

- The current mode, enabled by default and configurable in the variable `config.plugins.modal.status_bar.mode` (boolean)
- The current keystroke, enabled by default and configurable in the variable `config.plugins.modal.status_bar.strokes` (boolean)

If you want to disable one or more of this widgets simply configure in your `init.lua`:

```lua
local config = require "core.config"
local modal = require "plugins.modal"


config.plugins.modal.status_bar.mode = true -- enable mode widget (not needed, just for example)
config.plugins.modal.status_bar.strokes = false -- disable strokes widget
modal.set_status_bar() -- apply the changes
```

## Commands

Two commands are added to lite:

- `modal:redo` that redo the last executed command (N times if a number modifier is specified, a la vi)
- `modal:help` to show the current keymap active

## Presets

### Simple Preset

Below a simple example of a demo configuration that you can simply paste in your `init.lua`:

```lua
local config = require "core.config"
local modal = require "plugins.modal"

config.plugins.modal.status_bar.strokes = false
modal.set_status_bar()

config.plugins.modal.modes = { "Move", "Edit", "Jump" }
config.plugins.modal.base_mode = "Move"

config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only

config.plugins.modal.keymaps.Move = {
  ["e"] = modal.go_to_mode("Edit"),
  ["j"] = modal.go_to_mode("Jump"),
  ["right"] = "doc:move-to-next-char",
  ["left"] = "doc:move-to-previous-char",
  ["up"] = "doc:move-to-previous-line",
  ["down"] = "doc:move-to-next-line",
  ["shift+."] = "core:find-command",
  ["space shift+/"] = "modal:help",
}

config.plugins.modal.keymaps.Edit = {
  ["escape"] = modal.go_to_mode("Move"),
  ["ctrl+shift+p"] = "core:find-command",
  ["ctrl+shift+/"] = "modal:help",
}

config.plugins.modal.keymaps.Jump = {
  ["escape"] = modal.go_to_mode("Move"),
  ["e"] = modal.go_to_mode("Edit"),
  ["right"] = { "doc:select-none", "doc:select-to-next-word-end" },
  ["left"] = { "doc:select-none", "doc:select-to-previous-word-start" },
  ["up"] = { "doc:select-none", "doc:move-to-previous-line", "doc:move-to-end-of-line", "doc:select-to-previous-word-start" },
  ["down"] = { "doc:select-none", "doc:move-to-next-line", "doc:move-to-start-of-line", "doc:select-to-next-word-end" },
  ["shift+."] = "core:find-command",
  ["space shift+/"] = "modal:help",
}
```

### Helix Preset

For an almost full replica of the [Helix](helix-editor.com) modal experience please use the [lite-modal-hx](https://codeberg.org/Mandarancio/lite-modal-hx) preset.
