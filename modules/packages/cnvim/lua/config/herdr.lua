local M = {}

function M.setup()
    if not vim.env.HERDR_ENV then
        return
    end
    -- The sidebar daemon runs setup itself.
    if vim.v.servername:find("herdr%-nvim") then
        return
    end

    require("herdr-nvim").setup({})
end

return M
