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

You will also need `modal` for the configuration (and *optionally** its utilities):

```lua
local modal = require "plugins.modal"
local modal_utils = require "plugins.modal.utils" -- **OPTIONAL** utilities
```
 
#### Define modes

The first thing to do is to define the modes names and which should be your default mode (the one that will be active when starting lite-xl or opening a file etc).

```lua
config.plugins.modal.modes = { "Move", "Edit" , "Jump"} -- List of modes (3 modes for the example but any number of mode is supproted)
config.plugins.modal.base_mode = "Move" -- DEFAULT MODE (used when starting lite-xl or opening a file)
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
config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only -- to navigate
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only -- to navigate but quickly
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough -- to edit your file
```

*Note* that in the `on_key_passtrought` mode you can use the default `lite-xl` shortcuts.


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

To do so you can use **3 different syntaxes** (why? IDK), below some equivalences:


| Modal        | Lite              | Compact       |
| :----------- | :---------------- | :------------ |
| `<space>f`   | `space f`         | `space f`     |
| `<space>F`   | `space shift+f`   | `space S+f`   |
| `C-f`        | `ctrl+f`          | `C+f`         |
| `F<.>`       | `shfit+f $`       | `S+f $`       |
| `<space>wQ`  | `space w shfit+q` | `space w S+q` | 

Notes that modal work with combination of keys (e.g. `ctrl+f`) and sequences (e.g `space f`) as well as combination of the two.

The sequences can be as long as wish but **the first combination matched will be executed.**

A combination can have any key as argument `<.>` in the `modal` style or `$` in the other style: in the table for example `modal` will match any `F` followed by a key stroke.
This can be useful when a command need a character as argument (for example move to the next `<.>`).

In the rest of the documentation I will use the **compact** syntax (that in my opinion is the best one).

```lua
-- config.plugins.modal.keymaps.YOUR_MODE = YOUR_KEYMAP
config.plugins.modal.keymaps.Normal = {  -- configure keymap of mode [Normal]
  -- ["SEQUENCE_TO_MATCH"] = callback/"COMMAND"/{callback/"COMMAND"...} -- you can mix both callback and command
  ["e"] = modal.go_to_mode("Edit"), -- change mode to [Edit]
  ["j"] = modal.go_to_mode("Jump"), -- change mode to [Jump] 
  ["right"] = "doc:move-to-next-char", -- move right
  ["left"] = "doc:move-to-previous-char", -- move left
  ["up"] = "doc:move-to-previous-line", -- move up
  ["down"] = "doc:move-to-next-line", -- move down
}

config.plugins.modal.keymaps.Edit = { -- configure keymap of mode [Edit]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["C+S+;"] = "core:find-command", -- open command bar
  ["C+S+/"] = "modal:help", -- open modal help
} -- NOTE that this mode is passtrought so you can use the lite-xl **default shortcuts as well**

config.plugins.modal.keymaps.Jump = { -- configure keymap of mode [Jump]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode 
  ["e"] = modal.go_to_mode("Edit"), -- go to mode [Edit]
  ["right"] = { "doc:select-none", "doc:select-to-next-word-end" }, -- jump to next word end
  ["left"] = { "doc:select-none", "doc:select-to-previous-word-start" }, -- jump to previous word start
  ["up"] = { "doc:select-none", "doc:move-to-previous-line", "doc:move-to-end-of-line", "doc:select-to-previous-word-start" }, -- jump to last word of previous line
  ["down"] = { "doc:select-none", "doc:move-to-next-line", "doc:move-to-start-of-line", "doc:select-to-next-word-end" }, -- jump to first word of next line
}
```

Two important features can be seen in this example:

1. to each binding is possible to assign:
    1. a callback function
    2. a command as a string
    3. a list of a mix of callbacks and commands (in this case the actions will be executed sequentially) 
2. different modes can bind same sequences to different action (e.g. `right` in `Normal` and `Jump`)

It is also possible to use intermediate tables to store common bindings and reuse them between modes:
 
```lua
local common_bindings = {
  ["S+;"] = "core:find-command", -- open command bar
  ["space S+/"] = "modal:help", -- show modal help
  ["space q"] = "root:close", -- close tab}
}

config.plugins.modal.keymaps.Normal = modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Normal) -- add common binds
config.plugins.modal.keymaps.Jump = modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Jump) -- add common binds
```

##### Numbers/Digits

Numbers can not be used in keystrokes as they are used as modifiers to repeat a certain number of times the action.

For example `10 left` will execute 10 times the action binded to the `left` stroke.

##### Helpers

It is possible to have helpers to show what sequence match what the user is typing. 
In the example `space` is used once with `S+/` (`?`) and once with `q` so can be useful to remember to the user
the possibilites using an helper.

```lua

-- helper definition
local common_helpers = {
  -- ["SUB_SEQUENCE"] = { 
  --   {"REST_OF_SEQUENCE", "DESCRIPTION"}, 
  --   ...
  -- }
  ["space"] = {
    {"S+/", "show help"},
    {"q", "close document"},
  }
}

-- config.plugins.modal.helpers.YOUR_MODE = YOUR_HELPERS
config.plugins.modal.helpers.Normal = common_helpers -- set helpers
config.plugins.modal.helpers.Jump = common_helpers -- set helpers
```

The helper will be shown when the current sequence match the sub-sequence defined.

It is possible to disable *helpers* setting `config.plugins.modal.show_helpers = false` (default is `true`).

##### Load binding

**NOTE THIS STEP IS MANDATORY**

To finalise your configuration you **have** to laod your bindings in the internal `modal` representation (this will also load your helpers, if any):

```lua
-- local kb_model = require "plugins.modal.bindings_models.YOUR_CHOICE"
local kb_model = require "plugins.modal.bindings_models.compact"
modal.load_bindings(kb_model) -- store the keybindings and helpers in the internal representation
```

This step is mandatory in order to allow multiple keybinding syntaxes.

#### UI

`modal` includes few UI elements: the helper and a simple status bar. 
Both are configurable.

##### Helper Style

The style can be configure as follow:

| Field                     |      Default       | Comment                 |
| :------------------------ | :----------------: | :---------------------- |
| `style.helper.background` |    `#000000C8`     | helper background color |
| `style.helper.text`       |    `#FFFFFFDC`     | helper text color       |
| `style.helper.padding`    |         10         | helper internal padding |
| `style.helper.margin`     |         10         | helper external margin  |
| `style.helper.alignement` | `modal.align.LEFT` | helper alignement       |

##### Status-bar

`lite-modal` provide a simple status widget positioned on the bottom left of the `lite-xl` status bar.
This widget can contains the following information:

- The current mode, enabled by default and configurable in the variable `config.plugins.modal.status_bar.mode` (boolean)
- The current keystroke, enabled by default and configurable in the variable `config.plugins.modal.status_bar.strokes` (boolean)

The status bar by default shows the current state and the current sequence but can be configured:

```lua
-- config.plugins.modal.status_bar.mode = true -- show current mode (default is true)
config.plugins.modal.status_bar.strokes = false -- disable current strokes in status bar
modal.set_status_bar() -- update statusbar
```

#### Utilities

`modal` comes with an utilities library with common action and function useful for advanced configuration, this is found in `plugins.modal.utils`

In the example the `concat` function is used but if you have a look to the `hx` or `vi` preset you will see many other examples.

Additionally methods are documented in the library.

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

## New commands

Two commands are added to lite-xl:

- `modal:redo` that redo the last executed command (N times if a number modifier is specified, a la vi)
- `modal:help` to show the current keymap active



