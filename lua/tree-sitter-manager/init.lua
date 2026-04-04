local M = {}
local repos = require("tree-sitter-manager.repos")
local languages = vim.tbl_keys(repos)
table.sort(languages)

local src = debug.getinfo(1, "S").source
local abs = src:sub(1, 1) == "@" and vim.fn.fnamemodify(src:sub(2), ":p") or ""
local PLUGIN_ROOT = abs ~= "" and vim.fn.fnamemodify(abs, ":h:h:h") or vim.fn.stdpath("config")

local footer = " [i] Install  [x] Remove  [r] Refresh  [q] Close "

local cfg = {
    parser_dir = vim.fn.stdpath("data") .. "/site/parser",
    query_dir = vim.fn.stdpath("data") .. "/site/queries",
}

local function ext()
    local sys = vim.uv.os_uname().sysname
    return sys:match("Windows") and ".dll" or sys:match("Darwin") and ".dylib" or ".so"
end

local function ppath(l) return cfg.parser_dir .. "/" .. l .. ext() end
local function sh(c) return vim.system({ "sh", "-c", c }, { text = true }):wait().code == 0 end

function M.setup(opts)
    cfg = vim.tbl_deep_extend("force", cfg, opts or {})
    vim.fn.mkdir(cfg.parser_dir, "p")
    vim.fn.mkdir(cfg.query_dir, "p")

    local parser_parent = vim.fn.fnamemodify(cfg.parser_dir, ":h")
    local query_parent = vim.fn.fnamemodify(cfg.query_dir, ":h")
    local rtp = vim.opt.rtp:get()

    if not vim.tbl_contains(rtp, parser_parent) then vim.opt.rtp:prepend(parser_parent) end
    if not vim.tbl_contains(rtp, query_parent) then vim.opt.rtp:prepend(query_parent) end

    vim.api.nvim_create_user_command("TSManager", function()
        M.open()
    end, { nargs = 0, desc = "Open Tree-sitter Parsers Manager" })

    local installed_ft = {}
    for _, lang in ipairs(languages) do
        if vim.uv.fs_stat(ppath(lang)) then
            table.insert(installed_ft, lang)
        end
    end
    if #installed_ft > 0 then
        vim.api.nvim_create_autocmd('FileType', {
            pattern = installed_ft,
            callback = function() vim.treesitter.start() end,
            desc = 'Auto-enable treesitter for installed parsers'
        })
    end
end

local function install(lang)
    local repo = repos[lang]
    if not repo then return vim.notify("Unknown: " .. lang, 3) end

    local tmp = vim.fn.tempname()
    vim.notify("⬇ " .. lang)
    if not sh(string.format('git clone --depth 1 "%s" "%s"', repo, tmp)) then return vim.notify("Clone fail", 3) end
    if not sh(string.format('cd "%s" && tree-sitter generate && tree-sitter build -o "%s"', tmp, ppath(lang))) then
        return vim.notify("Build fail", 3)
    end
    vim.fn.delete(tmp, "rf")

    local s = PLUGIN_ROOT .. "/runtime/queries/" .. lang
    local d = cfg.query_dir .. "/" .. lang
    if vim.uv.fs_stat(s) then
        vim.fn.mkdir(d, "p")
        local ok = sh(string.format('cp -a "%s/." "%s/" 2>&1', s, d))
        if not ok then vim.notify("⚠ cp failed for " .. lang, vim.log.levels.WARN) end
    else
        vim.notify("⚠ Queries not found: " .. s, vim.log.levels.WARN)
    end
    vim.notify("✓ " .. lang)
end

local function remove(lang)
    if vim.uv.fs_stat(ppath(lang)) then vim.uv.fs_unlink(ppath(lang)) end
    local qd = cfg.query_dir .. "/" .. lang
    if vim.uv.fs_stat(qd) then vim.fn.delete(qd, "rf") end
    vim.notify("✕ " .. lang)
end

local function render(buf)
    local lines = { " 🌳  Tree-sitter Parser Manager ", " ────────────────────────────────" }
    for _, l in ipairs(languages) do
        table.insert(lines, string.format("   %-12s  %s", l, vim.uv.fs_stat(ppath(l)) and "✅" or "❌"))
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

function M.open()
    local max_w = #footer
    for _, l in ipairs(languages) do max_w = math.max(max_w, #("   " .. l .. "  ✅")) end

    local w = math.max(max_w + 4, 40)
    local h = math.min(#languages + 6, vim.o.lines - 4)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = w,
        height = h,
        style = "minimal",
        border = "rounded",
        row = math.floor((vim.o.lines - h) / 2),
        col = math.floor((vim.o.columns - w) / 2),
        title = footer,
        title_pos = "center"
    })
    render(buf)

    local close_fn = function() vim.api.nvim_win_close(win, true) end
    vim.keymap.set("n", "q", close_fn, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set("n", "<Esc>", close_fn, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set("n", "r", function() render(buf) end, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set("n", "i", function() M._act("install") end, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set("n", "x", function() M._act("remove") end, { buffer = buf, noremap = true, silent = true })
end

function M._act(action)
    local lang = vim.api.nvim_get_current_line():match("^%s*(%w+)")
    if not lang or not repos[lang] then return end
    if action == "install" then
        install(lang)
    elseif action == "remove" then
        remove(lang)
    end
    render(vim.api.nvim_get_current_buf())
end

return M
