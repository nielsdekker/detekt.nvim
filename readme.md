# Detekt.nvim

A small wrapper around detekt
[detekt/detekt](https://github.com/detekt/detekt). The goal of this plugin is to
run `detekt` whenever a Kotlin file is openend or saved and update the
diagnostics list accordingly.

## Installation

This plugin expects `detekt` to already be installed, see
[detekt/detekt](https://github.com/detekt/detekt) for installation instructions.
Installing the plugin can be done via your favorite package manager.

### mini.deps

A simple install using [mini.deps](https://github.com/echasnovski/mini.deps).

```lua
require("mini.deps").add({
    source = "nielsdekker/detekt.nvim",
    name = "detekt"
})
```

## Configuration

```lua
-- Basic setup
require("detekt").setup()
```

The following example contains all the fields with their default values

```lua
require("detekt").setup({
    --- Will search from the current directory upwards until a file with one of
    --- these names is found. Will stop at the first hit and use that file as
    --- the config.
    config_names = { "detekt.yaml", "detekt.yml" },

    --- When set a search will be done from the current buffer folder upwards
    --- until a file with this name is found. The first hit is used as the
    --- baseline file for detekt.
    baseline_names = nil,

    --- Determines the log level and can be set using one of the
    --- `vim.log.levels.*` values. Use `vim.log.levels.NONE` for no
    --- notifications.
    log_level = vim.log.levels.INFO,

    --- When set the default config of detekt is used for any missing settings.
    build_upon_default_config = true,

    --- Determines the file pattern(s) for which to run detekt.
    file_pattern = { "*.kt" },

    --- Can be used to overwrite the executable for detekt.
    detekt_exec = "detekt",
})
```
