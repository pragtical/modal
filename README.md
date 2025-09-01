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


## How to install

You can use [lpm](https://github.com/lite-xl/lite-xl-plugin-manager) to install the latest version included in the
[lite-xl-plugins](https://github.com/lite-xl/lite-xl-plugins).

Otherwise simply clone the repo in your `lite-xl/plugins` folder as `modal`:

On linux:

```
cd .config/lite-xl/plugins/
git clone https://codeberg.org/Mandarancio/lite-modal.git modal
```

**However once installed you will need to configure it or at least select one of the defaults provided**

## How to use 

Once installed you have to configure it at your will, for doing so there are at least 2 possibilities:
 1. Use one of the provided default [*quick and easy*]
 2. Configure your own modal configuration [*more work*]

### Defaults

The defaults are stored in the [defaults](defaults/) folder.
Currently there are the following defaults

 1. [dummy](defaults/modal_dummy/) is a simple configuration to be used as an example
 2. [hx](default/modal_hx/) is the most complete default and imitate the helix keybinding and functionalities
 3. [vi](default/modal_vi/) is an ok default that imitate a basic vim configuration 

To use any of this you have to edit your lite-xl [init.lua](https://lite-xl.com/user-guide/configuration/) by
simply adding the following line:

```lua
require "plugins.modal.defaults.modal_DEFAULT"
```

Where (obviusly) `DEFAULT` is the default you want to use (`dummy`, `hx` or `vi`).

Find more informations about each defaults in their own `README.md`.


### Manual Configuration

If you want to personalise your experience you can manully configure `modal` (or extend/modify any of the defaults).

You can define your configuration directly in the lite-xl [`init.lua`](https://lite-xl.com/user-guide/configuration/) or 
you can create an external file in your configuration folder and include it using `requre "YOUR_FILE"` inside the 
lite-xl configuration file (as is done for the default presets).

All the configuration of the plugin is stored in the *standard* `config` module so the first thing to do is to load it (if it is not already done):

```lua
local config = require "core.config"
```

**Note** that if you are using lite-xl configuration file is probably already loaded.

Then all the configurations will be done inside the `config.plugins.modal` table.

You will also need `modal` for the configuration:

```lua
local modal = require "plugins.modal"
```
 
#### Define modes

The first thing to do is to define the modes names and which should be your default mode (the one that will be active when starting lite-xl or opening a file etc).

```lua
config.plugins.modal.modes = { "NOR", "INS" , "JMP"} -- List of modes (3 modes for the example but any number of mode is supproted)
config.plugins.modal.base_mode = "NOR" -- DEFAULT MODE (used when starting lite-xl or opening a file)
```

Now for each mode you can/have to do a number of choices:
 1. which interaction mode to use (basically what to do when you type)
 2. *optionally* which caret style use
 3. define keybindings
 4. *optionally* define helpers

The **interaction mode** (`on_key_callbacks`) specifies to modal what to do when you press a key, there are 2 defaults interaction modes:
 1. `modal.on_key_command_only`: keys will only be used to match your keybinding and not to directly edit your files
 2. `modal.on_key_passtrought`: keys will be used to match your keybinding and to edit your file (basically what lite-xl does already)

You can also define your own interaction mode, but this is outside the scope of this documentation.

```lua
-- config.plugins.modal.on_key_callbacks.YOUR_MODE = modal.on_key_YOUR_CHOICE
config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only -- to navigate
config.plugins.modal.on_key_callbacks.JMP = modal.on_key_command_only -- to navigate but quickly
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passthrough -- to edit your file
```

The **caret stye** is optional, if not defined the standard lite-xl caret will be used, 2 caret styles are defined:

 1. `modal.caret_style.NORMAL` the standard vertical thin line of lite-xl
 2. `modal.caret_style.BAR` a big block covering the full size of a letter

```lua
-- config.plugins.modal.carets.YOUR_MODE = modal.caret_style.YOUR_CHOICE
config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.JMP = modal.caret_style.BAR
-- default is NORMAL (e.g. INS will use NORMAL)
```

#### Keybinding

The next big step in the configuration of the `modal` is to define the keybinding for each mode.



#### Helpers

#### Utils

#### UI


#### Finalisation

**NOTE THIS STEP IS MANDATORY**

To finalise your configuration you **have** to laod your bindings in the internal `modal` representation (this will also load your helpers, if any):

```lua
-- local kb_model = require "plugins.modal.bindings_models.YOUR_CHOICE"
local kb_model = require "plugins.modal.bindings_models.compact"
modal.load_bindings(kb_model) -- store the keybindings and helpers in the internal representation
```

This step is mandatory in order to allow multiple keybinding syntaxes.

## Configuration table

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

Mandatory step is `modal.load_bindings(BINDING_MODEL)`

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

Two commands are added to lite-xl:

- `modal:redo` that redo the last executed command (N times if a number modifier is specified, a la vi)
- `modal:help` to show the current keymap active



