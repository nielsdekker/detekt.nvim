--- @class (exact)detekt.config
--- @field config_names? string[]
--- Defaults to `{ "detekt.yaml", "detekt.yml" }`. Will search from the current
--- directory upwards until a file with one of these names is found. Will stop
--- at the first hit and use that file as the config.
--- @field baseline_names? string[]
--- Defaults to nil, when set a search will be done from the current buffer
--- folder upwards until a file with this name is found. The first hit is used
--- as the baseline file for detekt.
--- @field log_level? integer
--- Default is `vim.log.levels.INFO`. Determines the log level and can be set
--- using one of the `vim.log.levels.*` values. Use `vim.log.levels.NONE` for no
--- notifications
--- @field build_upon_default_config? boolean
--- Default is true, when set the default config of detekt is used for any
--- missing settings.
--- @field file_pattern? string|string[]
--- Default is `"*.kt"`, determines the file pattern(s) for which to run detekt.
--- @field detekt_exec string?
--- Default is `"detekt"` can be used to overwrite the executable for detekt.

--- @class (exact) detekt.cmd_for_buf
--- @field cmd string[]
--- @field tmp_file string
--- @field bufnr integer
--- @field bufname string

local M = {
    _internal = {
        --- The namespace, is needed for diagnostics
        ns = vim.api.nvim_create_namespace("DetektNvim"),
        au_group = vim.api.nvim_create_augroup("DetektNvim", { clear = true }),
        --- @type { [integer]: detekt.cmd_for_buf}
        cmd_cache = {}
    },
    --- @type detekt.config
    _settings = {
        config_names = { "detekt.yaml", "detekt.yml" },
        baseline_names = nil,
        log_level = vim.log.levels.INFO,
        build_upon_default_config = true,
        file_pattern = { "*.kt" },
        detekt_exec = "detekt",
    }
}

--- @param msg string
--- @param level integer
local function notify(msg, level)
    if level >= M._settings.log_level then
        vim.notify("Detekt: " .. msg, level)
    end
end

--- generates the command and caches it. This is done because searching for
--- config files each save is not really needed. This function can throw an
--- error when the command can not be created. For example when the config file
--- couldn't be found.
--- @param bufnr integer
--- @return detekt.cmd_for_buf?, string?
local function generate_cmd(bufnr)
    if M._internal.cmd_cache[bufnr] ~= nil then
        return M._internal.cmd_cache[bufnr], nil
    end

    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local tmp_file = os.tmpname()
    local config_file = vim.fs.find(M._settings.config_names, {
        upward = true,
        type = "file",
        path = vim.fs.dirname(bufname),
    })[1]

    --- @type detekt.cmd_for_buf
    local cmd_for_buf = {
        cmd = {
            M._settings.detekt_exec,
            "-r",
            "sarif:" .. tmp_file,
            "--includes",
            bufname
        },
        tmp_file = tmp_file,
        bufnr = bufnr,
        bufname = bufname
    }

    if M._settings.build_upon_default_config == true then
        table.insert(cmd_for_buf.cmd, "--build-upon-default-config")
    end

    -- Check for breaking changes
    if config_file ~= nil then
        table.insert(cmd_for_buf.cmd, "--config")
        table.insert(cmd_for_buf.cmd, config_file)
    else
        -- Breaking, refuse to run without a config file
        return nil,
            "Config file not found, searched for: {" ..
            table.concat(M._settings.config_names, ", ") .. "}\nStarted at: " .. vim.fs.dirname(bufname)
    end

    --- @type string[]
    local warnings = {}
    if M._settings.baseline_names ~= nil then
        local baseline_file = vim.fs.find(M._settings.baseline_names, {
            upward = true,
            type = "file",
            path = vim.fs.dirname(bufname)
        })[1]
        if baseline_file == nil then
            -- Baseline setup but file not found, this is not necessarily
            -- breaking but should result in a warning
            table.insert(warnings,
                "Baseline file not found, searched for: " .. table.concat(M._settings.baseline_names, ", "))
        else
            table.insert(cmd_for_buf.cmd, "--baseline")
            table.insert(cmd_for_buf.cmd, baseline_file)
        end
    end

    -- And store this in the cache
    M._internal.cmd_cache[bufnr] = cmd_for_buf

    if vim.tbl_count(warnings) > 0 then
        return cmd_for_buf, table.concat(warnings, "\n")
    else
        return cmd_for_buf, nil
    end
end

--- @param tmp_file string
--- @param bufnr integer
--- @return vim.Diagnostic[], string?
local function parse_sarif(tmp_file, bufnr)
    local f = io.open(tmp_file, "r")
    local diagnostics = {}

    if f == nil then
        return diagnostics, "Unable to read the output of detekt stored in: " .. tmp_file
    end

    local sarif_json = f.read(f, "*a")
    local sarif_data = vim.json.decode(sarif_json)

    -- There should only be one run
    for _, v in pairs(sarif_data.runs[1].results) do
        local loc = v.locations[1].physicalLocation.region

        table.insert(diagnostics, {
            bufnr = bufnr,
            lnum = loc.startLine - 1,
            end_lnum = loc.endLine - 1,
            col = loc.startColumn - 1,
            end_col = loc.endColumn - 1,
            message = v.message.text
        })
    end

    return diagnostics, nil
end

local function run_detekt()
    -- Get a temp file to send the results to
    local cmd, cmd_err = generate_cmd(vim.api.nvim_get_current_buf())

    if cmd == nil then
        -- Something broke big time
        notify(cmd_err or "¯\\_(ツ)_/¯", vim.log.levels.ERROR)
        return
    elseif cmd_err ~= nil then
        -- Warnings occurred
        notify(cmd_err, vim.log.levels.WARN)
    end

    notify("Validating " .. cmd.bufname, vim.log.levels.INFO)
    vim.system(cmd.cmd, { text = true }, function(out)
        if out.code == 3 then
            notify("Config invalid " .. out.stderr, vim.log.levels.ERROR)
            return
        end

        local diagnostics, parse_err = parse_sarif(cmd.tmp_file, cmd.bufnr)
        if parse_err ~= nil then
            notify(parse_err, vim.log.levels.ERROR)
            return
        end

        local diagnostics_len = vim.tbl_count(diagnostics)

        vim.schedule(function()
            if diagnostics_len == 0 then
                notify("No issues found", vim.log.levels.INFO)
            else
                notify("Found " .. diagnostics_len .. " issues", vim.log.levels.ERROR)
            end

            vim.diagnostic.set(M._internal.ns, cmd.bufnr, diagnostics, {})
        end)
    end)
end

--- Will setup detekt to listen to any changes in `*.kt` files (_or other files
--- when the `config.file_pattern` value is set_). When such a file is opened or
--- changed `detekt` will trigger and fill the diagnostics list for any found
--- issue.
--- @param config detekt.config
M.setup = function(config)
    config = config or {}
    M._settings.config_names = config.config_names or M._settings.config_names
    M._settings.baseline_names = config.baseline_names or M._settings.baseline_names
    M._settings.log_level = config.log_level or M._settings.log_level
    M._settings.build_upon_default_config = config.build_upon_default_config or M._settings.build_upon_default_config
    M._settings.file_pattern = config.file_pattern or M._settings.file_pattern
    M._settings.detekt_exec = config.detekt_exec or M._settings.detekt_exec

    vim.api.nvim_create_autocmd(
        { "BufAdd", "BufWritePost" },
        {
            group = M._internal.au_group,
            pattern = M._settings.file_pattern,
            callback = run_detekt
        }
    )
end

return M
