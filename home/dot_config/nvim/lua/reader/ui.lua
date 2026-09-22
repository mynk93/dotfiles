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
  statuscolumn = { enabled = true },     -- fold column + signs, laid out sanely
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
})

-- ── Borders ────────────────────────────────────────────────────────────────
vim.o.winborder = "rounded"
