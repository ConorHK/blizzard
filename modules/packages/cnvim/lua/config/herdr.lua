local M = {}

local function run(argv)
    return vim.system(argv, { text = true }):wait()
end

local function where(cwd)
    return vim.fn.fnamemodify(cwd, ":h:t") .. "/" .. vim.fn.fnamemodify(cwd, ":t")
end

-- Pi titles read "<icon> - [name - ]dir".
local function session_name(kind, title)
    if kind ~= "pi" then
        return kind
    end
    return title:gsub("^%S+ %- ", ""):match("^(.+) %- .-$")
end

local function list_agents()
    local r = run({ "herdr", "agent", "list" })
    if r.code ~= 0 then
        return nil, "herdr agent list failed: " .. (r.stderr ~= "" and r.stderr or ("exit " .. r.code))
    end
    local ok, decoded = pcall(vim.json.decode, r.stdout)
    if not ok or type(decoded) ~= "table" then
        return nil, "herdr agent list: unparseable JSON"
    end
    local here = vim.env.HERDR_WORKSPACE_ID
    local out = {}
    for _, a in ipairs((decoded.result or {}).agents or {}) do
        if not here or a.workspace_id == here then
            local agent = {
                pane_id = a.pane_id,
                workspace_id = a.workspace_id,
                tab_id = a.tab_id,
                kind = a.agent or "unknown",
                status = a.agent_status or "unknown",
                -- Spawn cwd goes stale.
                cwd = a.foreground_cwd or a.cwd or "",
                title = a.terminal_title or a.agent or "agent",
            }
            agent.name = session_name(agent.kind, agent.title)
            agent.where = where(agent.cwd)
            table.insert(out, agent)
        end
    end
    return out
end

local status_hl = {
    working = "DiagnosticWarn",
    idle = "DiagnosticOk",
    done = "DiagnosticInfo",
    blocked = "DiagnosticError",
}

local function pad(s, width)
    return s .. string.rep(" ", (width or #s) - #s + 2)
end

local function chunks(agent, widths)
    widths = widths or {}
    local first = agent.name or agent.where
    local ret = {
        { pad(first, widths.first), "SnacksPickerBold" },
        { pad(agent.status, 7), status_hl[agent.status] or "Comment" },
    }
    if agent.tab then
        table.insert(ret, { pad(agent.tab, widths.tab), agent.here and "Special" or "SnacksPickerDir" })
    end
    if agent.name then
        table.insert(ret, { agent.where, "Comment" })
    end
    return ret
end

local function display(agent)
    local text = vim.tbl_map(function(c)
        return c[1]
    end, chunks(agent))
    return vim.trim((table.concat(text, " "):gsub("%s+", " ")))
end

local function tab_labels()
    local ok, decoded = pcall(vim.json.decode, run({ "herdr", "tab", "list" }).stdout or "")
    local labels = {}
    if ok and type(decoded) == "table" then
        for _, t in ipairs((decoded.result or {}).tabs or {}) do
            labels[t.tab_id] = t.label
        end
    end
    return labels
end

-- Show the agent's own screen.
local function preview(ctx)
    local agent = ctx.item.item
    local r = run({ "herdr", "pane", "read", agent.pane_id, "--source", "recent", "--lines", "200" })
    local text = r.code == 0 and r.stdout or "pane read failed"
    ctx.preview:reset()
    ctx.preview:minimal()
    ctx.preview:wo({ wrap = false })
    ctx.preview:set_title(agent.title)
    ctx.preview:set_lines(vim.split(text:gsub("%s+$", ""), "\n"))
    vim.api.nvim_win_set_cursor(ctx.win, { vim.api.nvim_buf_line_count(ctx.buf), 0 })
end

local function pick_agent(list, on_choice)
    if #list == 0 then
        vim.notify("herdr-nvim: no herdr agents found", vim.log.levels.WARN)
        return
    end
    local labels, widths = tab_labels(), { first = 0, tab = 0 }
    for _, a in ipairs(list) do
        a.here = a.tab_id == vim.env.HERDR_TAB_ID
        a.tab = a.here and "this tab" or (labels[a.tab_id] and "tab " .. labels[a.tab_id]) or ""
        widths.first = math.max(widths.first, #(a.name or a.where))
        widths.tab = math.max(widths.tab, #a.tab)
    end
    table.sort(list, function(x, y)
        if x.here ~= y.here then
            return x.here
        end
        return display(x) < display(y)
    end)
    vim.ui.select(list, {
        prompt = "Send to agent",
        format_item = function(a, supports_chunks)
            return supports_chunks and chunks(a, widths) or display(a)
        end,
        snacks = {
            preview = preview,
            layout = { preset = vim.o.columns >= 120 and "ivy" or "vertical" },
        },
    }, function(a)
        if a then
            on_choice(a)
        end
    end)
end

function M.setup()
    if not (vim.env.HERDR_ENV or vim.env.HERDR_TAB_ID) then
        return
    end

    -- Daemon nvim needs these too.
    local agents = require("herdr-nvim.agents")
    agents.list = list_agents
    agents.display = display
    require("herdr-nvim.ui").pick_agent = pick_agent

    -- The sidebar daemon runs setup itself.
    if vim.v.servername:find("herdr%-nvim") then
        return
    end

    require("herdr-nvim").setup({})
end

return M
