-- Update parsers to latest version (tier 1, stable) or commit (tier 2, unstable)
local util = require("tree-sitter-manager.util")
local parsers = require("tree-sitter-manager.repos")

local M = {}

M.old_parsers = vim.deepcopy(parsers)
M.new_parsers = parsers ---@type table<string,tree_sitter_manager.LanguageSpec>

---Update tree-sitter-manager/repos.lua to newer parser versions
---@return string[] languages that have newer revisions
function M.update()
    local jobs = {} ---@type table<string,AsyncJob>
    local updates = {} ---@type string[]

    -- check for new revisions
    io.write("Updating")
    for name, parser in pairs(parsers) do
        if parser.tier and parser.tier <= 2 and parser.install_info then
            local cmd = parser.tier == 1
                    and {
                        "git",
                        "-c",
                        "versionsort.suffix=-",
                        "ls-remote",
                        "--tags",
                        "--refs",
                        "--sort=v:refname",
                        parser.install_info.url,
                    }
                or { "git", "ls-remote", parser.install_info.url }

            jobs[name] = util.run(cmd, { callback = function() end }) -- empty callback to force-batch calls
        end
    end

    for name, job in pairs(jobs) do
        local status = job:wait(60000)
        if not status.ok then
            io.write("\n" .. name .. " " .. (status.error or "") .. "\n")
        else
            io.write(" " .. name)

            local parser = parsers[name]
            local stdout = vim.split(status.output or "", "\n")
            local sha ---@type string?

            if parser.tier == 1 then
                sha = stdout[#stdout - 1] and stdout[#stdout - 1]:match("v[%d%.]+$")
            else
                local branch = parser.install_info.branch
                local line = vim.iter(stdout):find(function(line)
                    return branch and line:find(vim.pesc(branch))
                end) or stdout[1]
                sha = line and vim.split(line, "\t")[1]
            end

            if sha and sha ~= "" and parser.install_info.revision ~= sha then
                parser.install_info.revision = sha
                table.insert(updates, name)
            end
        end
        io.flush()
    end
    io.write("\n")

    if #updates == 0 then
        io.write("\nAll parsers up to date!\n")
    else
        -- write new parser file
        local header = table.concat({
            "---@class tree_sitter_manager.LanguageSpec",
            "---@field install_info? tree_sitter_manager.InstallInfo Information about how to fetch and build the grammar.",
            "---@field requires? string[] Other languages that are dependencies of this one and must be installed first.",
            "---@field tier? number tier 1 updates to the latest version, tier 2 updates to the latest commit",
            "",
            "---@class tree_sitter_manager.InstallInfo",
            "---@field url string Git URL of the grammar repository.",
            "---@field location? string Sub-directory within the repo where the grammar is stored. Defaults to the name of the language.",
            "---@field revision? string Git revision to check out after cloning. Takes priority over `branch`.",
            "---@field branch? string Git branch to check out after cloning. Ignored if `revision` is set.",
            "---@field generate? boolean Run `tree-sitter generate` before building. Defaults to false.",
            "---@field queries? string Specifies the queries directory in the cloned repo that will be used.",
            "",
            "---@type table<string,tree_sitter_manager.LanguageSpec>",
            "return ",
        }, "\n")
        local parser_file = header .. vim.inspect(parsers)
        if vim.fn.executable("stylua") == 1 then
            parser_file = util.run({ "stylua", "-" }, { stdin = parser_file }):wait().output --[[@as string]]
        end
        util.write_file("lua/tree-sitter-manager/repos.lua", parser_file)
    end

    io.flush()
    return updates
end

function M.finalize(passed)
    -- pass passed list to workflow
    table.sort(passed)
    util.write_file(os.getenv("GITHUB_ENV"), "UPDATED_PARSERS=" .. table.concat(passed, ",") .. "\n", "a")
end

return M
