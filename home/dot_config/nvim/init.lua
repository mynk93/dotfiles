-- Neovim as a code *reader*.
--
-- Zed stays $EDITOR. This config exists for the one thing Zed structurally
-- cannot do: programmable folding. Zed's folds are indentation-derived with a
-- hardcoded `⋯` placeholder, so a wrapped call and a wrapped parameter list
-- are indistinguishable and a collapsed fold can never show its contents.
-- Neovim exposes both hooks — fold boundaries and the folded placeholder —
-- so both are fixed here. See reader.folding (nvim-ufo) and reader.foldtext.
--
-- Deliberately no LSP, no completion, no formatter. Reading only; editing
-- happens in Zed. Keep it that way — every plugin added here is a thing that
-- breaks on a machine where you only wanted to read a file.

vim.g.mapleader = ","

-- ── Reading surface ────────────────────────────────────────────────────────
local o = vim.opt
o.number, o.relativenumber = true, true   -- matches the .vimrc this replaces
o.cursorline   = true
o.scrolloff    = 3
o.mouse        = "a"
o.clipboard    = "unnamedplus"
o.termguicolors = true
o.signcolumn   = "no"                     -- no diagnostics here, reclaim the gutter
o.wrap         = false
o.ignorecase, o.smartcase = true, true
o.splitright, o.splitbelow = true, true
o.undofile     = true

-- Blank out the fold trailing-dot fill so the virt-text handler controls the
-- whole line.
o.fillchars:append({ fold = " " })

-- ── Folding ────────────────────────────────────────────────────────────────
-- Owned by reader.folding (nvim-ufo). Only the fill char stays here, because
-- it is a display detail rather than a folding decision.

-- ── Plugins (vim.pack, built into 0.12 — no bootstrap script) ──────────────
vim.pack.add({
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
  { src = "https://github.com/ibhagwan/fzf-lua" },                  -- files / grep / symbols
  { src = "https://github.com/lewis6991/gitsigns.nvim" },           -- gutter + blame
  { src = "https://github.com/Mofiqul/dracula.nvim" },              -- colorscheme
  { src = "https://github.com/nvim-lualine/lualine.nvim" },         -- statusline
  { src = "https://github.com/Bekaboo/dropbar.nvim" },              -- breadcrumbs winbar
  { src = "https://github.com/folke/snacks.nvim" },                 -- indent / dim / dashboard
  { src = "https://github.com/kevinhwang91/promise-async" },        -- ufo dependency
  { src = "https://github.com/kevinhwang91/nvim-ufo" },             -- folding engine
  { src = "https://github.com/luukvbaal/statuscol.nvim" },          -- fold column + signs
  { src = "https://github.com/folke/flash.nvim" },                  -- cursor jumps
  { src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" }, -- in-buffer md
  { src = "https://github.com/3rd/image.nvim" },                    -- kitty-protocol images
  { src = "https://github.com/3rd/diagram.nvim" },                  -- mermaid in the buffer
})

require("fzf-lua").setup({
  "default",
  winopts = { preview = { layout = "vertical" }, border = "rounded" },
})
require("gitsigns").setup({ current_line_blame = false })

require("reader.ui")
require("reader.lsp")
require("reader.folding")
require("reader.markdown")
require("reader.diagrams")

-- nvim-treesitter's main branch does not start parsing on its own, so without
-- this the foldexpr has no tree to read and every fold level comes back 0.
vim.api.nvim_create_autocmd("FileType", {
  desc = "reader: start tree-sitter and hand folding to it",
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match)
    if not lang then
      return
    end
    -- No parser is not an error here: ufo's provider chain already falls back
    -- to indent folds, so do not also force foldmethod and fight it.
    pcall(vim.treesitter.start, ev.buf, lang)
  end,
})

-- ── Keymaps ────────────────────────────────────────────────────────────────
-- zr / zm step the fold level by one — the relative control that absolute
-- fold-at-level-N can't express. zR / zM go all the way. za toggles one.
local map = vim.keymap.set
local fzf = require("fzf-lua")

-- Finding things. These are the zed muscle memory: cmd-p, cmd-shift-f,
-- cmd-shift-o, mapped onto a leader that works without a modifier reach.
map("n", "<leader>p", fzf.files,           { desc = "find: files" })
map("n", "<leader>/", fzf.live_grep,       { desc = "find: grep in project" })
map("n", "<leader>b", fzf.buffers,         { desc = "find: open buffers" })
map("n", "<leader>o", fzf.lsp_document_symbols,  { desc = "find: symbols in file" })
map("n", "<leader>O", fzf.lsp_workspace_symbols, { desc = "find: symbols in project" })
map("n", "<leader>r", fzf.resume,          { desc = "find: reopen last picker" })

-- Navigating code. gd/gr/K are the three that matter for reading.
map("n", "gd", fzf.lsp_definitions,  { desc = "go to definition" })
map("n", "gr", fzf.lsp_references,   { desc = "find references" })
map("n", "gi", fzf.lsp_implementations, { desc = "go to implementation" })
map("n", "K",  vim.lsp.buf.hover,    { desc = "hover docs" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end,  { desc = "next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, { desc = "prev diagnostic" })
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "show diagnostic" })

-- Folding keymaps live in reader.folding, next to the ufo setup they drive.

-- Cursor jumps: `s` then two characters puts the cursor anywhere on screen.
-- Replaces the search-then-n dance for short-range movement.
map({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "jump to location" })
map({ "n", "x", "o" }, "S", function() require("flash").treesitter() end, { desc = "select syntax node" })

-- Jumplist: <C-o> back, <C-i> forward. Native, listed only as documentation —
-- this is the equivalent of zed's ctrl-- / pane::GoBack.

-- Quick fold-state readout, for when a fold does something surprising.
vim.api.nvim_create_user_command("FoldWhy", function()
  local l = vim.fn.line(".")
  vim.notify(("line %d  foldlevel=%s  closed=%s  method=%s")
    :format(l, vim.fn.foldlevel(l), vim.fn.foldclosed(l), vim.wo.foldmethod))
end, { desc = "reader: explain the fold under the cursor" })
