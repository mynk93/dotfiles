-- Visual chrome.
--
-- Split out from init.lua because styling churns and folding does not; keeping
-- them apart means a theme experiment can't break the reader.
--
-- Terminal font and palette are NOT here — they belong to Ghostty, which cmux
-- embeds. See ~/.config/ghostty/config.

require("dracula").setup({
  italic_comment = true,
  -- Transparent so Ghostty's Dracula background shows through; one source of
  -- truth for the background colour instead of two that drift apart.
  transparent_bg = true,
})
vim.cmd.colorscheme("dracula")

-- ── Statusline ─────────────────────────────────────────────────────────────
require("lualine").setup({
  options = {
    theme = "dracula-nvim",
    globalstatus = true,                 -- one bar, not one per split
    section_separators = "",
    component_separators = "|",
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff" },
    lualine_c = { { "filename", path = 1 } },
    lualine_x = { { "diagnostics", sources = { "nvim_lsp" } }, "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
})

-- ── Breadcrumbs ────────────────────────────────────────────────────────────
-- proagent › state_loop › handle — the context you lose when a file is folded
-- and you have scrolled away from the def line.
require("dropbar").setup({})

-- ── Indent guides, scrollbar, dimming, dashboard ──────────────────────────
require("snacks").setup({
  indent = { enabled = true, animate = { enabled = false } },
  scroll = { enabled = false },          -- smooth scroll fights trackpad feel
  dim = { enabled = true },              -- inactive splits recede
  statuscolumn = { enabled = false },    -- statuscol.nvim owns this; see below
  dashboard = {
    enabled = true,
    preset = {
      keys = {
        { icon = " ", key = "p", desc = "Find file",    action = ":lua Snacks.dashboard.pick('files')" },
        { icon = " ", key = "/", desc = "Grep project", action = ":lua Snacks.dashboard.pick('live_grep')" },
        { icon = " ", key = "r", desc = "Recent",       action = ":lua Snacks.dashboard.pick('oldfiles')" },
        { icon = " ", key = "q", desc = "Quit",         action = ":qa" },
      },
    },
  },
  bigfile = { enabled = true },          -- disable TS/LSP on huge files
  quickfile = { enabled = true },
  explorer = { enabled = true },         -- project tree; see keymaps below
  picker = {
    enabled = true,
    sources = {
      explorer = {
        auto_close = false,              -- keep the tree open while reading
        layout = { preset = "sidebar", preview = false },
      },
    },
  },
})

-- ── Project navigation ─────────────────────────────────────────────────────
-- `nvim .` or `nvim <dir>` opens the explorer on that directory rather than
-- netrw, so a directory argument behaves like opening a project.
vim.api.nvim_create_autocmd("VimEnter", {
  desc = "reader: open a directory argument as a project tree",
  callback = function()
    local arg = vim.fn.argv(0)
    if type(arg) == "string" and arg ~= "" and vim.fn.isdirectory(arg) == 1 then
      vim.cmd.cd(arg)
      vim.cmd.bdelete()
      require("snacks").explorer()
    end
  end,
})

local map = vim.keymap.set
map("n", "<leader>e", function() require("snacks").explorer() end,
  { desc = "project: toggle file tree" })
map("n", "<leader>E", function() require("snacks").explorer.reveal() end,
  { desc = "project: reveal current file in tree" })

-- Move between open files without the picker.
map("n", "]b", "<cmd>bnext<cr>",     { desc = "buffer: next" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "buffer: previous" })
map("n", "<leader><leader>", "<cmd>buffer#<cr>", { desc = "buffer: last used" })
map("n", "<leader>x", function() require("snacks").bufdelete() end,
  { desc = "buffer: close, keep the split" })

-- ── Status column ──────────────────────────────────────────────────────────
-- The gutter: fold markers, signs, line numbers. statuscol rather than the
-- snacks equivalent because its fold segment is click-aware and understands
-- ufo's fold state, which is what we actually fold with.
local builtin = require("statuscol.builtin")
require("statuscol").setup({
  relculright = true,
  segments = {
    { sign = { name = { "Diagnostic" }, maxwidth = 1, auto = true } },
    { text = { builtin.lnumfunc, " " }, click = "v:lua.ScLa" },
    { sign = { namespace = { "gitsigns" }, maxwidth = 1, colwidth = 1, auto = false },
      click = "v:lua.ScSa" },
    { text = { builtin.foldfunc, " " }, click = "v:lua.ScFa" },
  },
})

-- ── Borders ────────────────────────────────────────────────────────────────
vim.o.winborder = "rounded"
