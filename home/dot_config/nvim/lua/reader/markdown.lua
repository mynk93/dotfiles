-- In-buffer markdown rendering.
--
-- This repo's docs are markdown-heavy (CLAUDE.md, docs/fbt/*, runbooks), and
-- until now reading them meant leaving the editor for `view` (glow -p). This
-- renders headings, code blocks, tables, callouts and lists in place.
--
-- Complements rather than replaces the existing surfaces:
--   `view file.md`   glow -p, paged, in the shell
--   yazi preview     glow via piper, dracula
--   here             in the buffer, with folds and LSP still available
--
-- glow.nvim is NOT the plugin for this — it is archived upstream.

require("render-markdown").setup({
  -- Show the raw source on the line the cursor is on, rendered everywhere
  -- else. Without this you cannot see the syntax you are about to edit, and
  -- link targets stay permanently hidden.
  anti_conceal = { enabled = true },

  heading = {
    -- Width of the heading background: `block` stops it spanning the whole
    -- window. min_width is deliberately unset — forcing 60 columns turned
    -- every heading into a coloured bar wider than its own text.
    width = "block",
    -- Tint the icon and text, not the whole line. render-markdown's default
    -- H*Bg groups are not derived from the colorscheme and landed on a
    -- bright green against dracula.
    backgrounds = {},
    foregrounds = {
      "RenderMarkdownH1", "RenderMarkdownH2", "RenderMarkdownH3",
      "RenderMarkdownH4", "RenderMarkdownH5", "RenderMarkdownH6",
    },
  },

  code = {
    width = "block",
    -- Language name in the top-right of a fence, so a long block still says
    -- what it is once the opening line has scrolled off.
    language_name = true,
    position = "right",
  },

  -- Tables are the main reason to render in-buffer: a wide markdown table is
  -- unreadable as source and fine once aligned.
  pipe_table = { preset = "round" },

  checkbox = { unchecked = { icon = "󰄱 " }, checked = { icon = "󰱒 " } },
})

-- Heading colours from the dracula palette, brightest at H1 and receding down
-- the levels so nesting depth reads at a glance. Set after the colorscheme
-- loads, and re-applied on any later scheme change.
local function heading_colors()
  local levels = {
    { "RenderMarkdownH1", "#bd93f9" },   -- purple
    { "RenderMarkdownH2", "#8be9fd" },   -- cyan
    { "RenderMarkdownH3", "#50fa7b" },   -- green
    { "RenderMarkdownH4", "#f1fa8c" },   -- yellow
    { "RenderMarkdownH5", "#ffb86c" },   -- orange
    { "RenderMarkdownH6", "#6272a4" },   -- comment blue
  }
  for _, l in ipairs(levels) do
    vim.api.nvim_set_hl(0, l[1], { fg = l[2], bold = true })
  end
  -- Fenced code: a subtle lift off the background, not a slab.
  vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = "#21222c" })
  vim.api.nvim_set_hl(0, "RenderMarkdownCodeInline", { bg = "#21222c", fg = "#f1fa8c" })
end

heading_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = heading_colors })

-- Toggle when you need the raw source for a whole file rather than one line.
vim.keymap.set("n", "<leader>m", "<cmd>RenderMarkdown toggle<cr>",
  { desc = "markdown: toggle rendering" })
