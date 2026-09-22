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
    -- window, which reads as a bar rather than a heading.
    width = "block",
    min_width = 60,
  },

  code = {
    width = "block",
    min_width = 60,
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

-- Toggle when you need the raw source for a whole file rather than one line.
vim.keymap.set("n", "<leader>m", "<cmd>RenderMarkdown toggle<cr>",
  { desc = "markdown: toggle rendering" })
