-- Neovim as a code *reader*.
--
-- Zed stays $EDITOR. This config exists for the one thing Zed structurally
-- cannot do: programmable folding. Zed's folds are indentation-derived with a
-- hardcoded `⋯` placeholder, so a wrapped call and a wrapped parameter list
-- are indistinguishable and a collapsed fold can never show its contents.
-- Neovim exposes both hooks — `foldexpr` (boundaries) and `foldtext`
-- (placeholder) — so both are fixed here.
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

-- Blank out the fold trailing-dot fill so foldtext controls the whole line.
o.fillchars:append({ fold = " " })

-- ── Folding ────────────────────────────────────────────────────────────────
-- Syntax folds, not indent folds: a wrapped parameter list is not a fold,
-- a function body is.
o.foldmethod = "expr"
o.foldexpr   = "v:lua.vim.treesitter.foldexpr()"
o.foldtext   = "v:lua.require'reader.foldtext'.render()"

-- Open at "definitions visible, bodies' internals folded" — the state that
-- took a keystroke-per-function to reach elsewhere.
o.foldlevelstart = 1
o.foldenable     = true

-- ── Plugins (vim.pack, built into 0.12 — no bootstrap script) ──────────────
vim.pack.add({
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})

-- nvim-treesitter's main branch does not start parsing on its own, so without
-- this the foldexpr has no tree to read and every fold level comes back 0.
vim.api.nvim_create_autocmd("FileType", {
  desc = "reader: start tree-sitter and hand folding to it",
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match)
    if not lang then
      return
    end
    if not pcall(vim.treesitter.start, ev.buf, lang) then
      -- No parser for this language: fall back to indent folds rather than
      -- leaving the buffer with an expr that always returns 0.
      vim.api.nvim_set_option_value("foldmethod", "indent", { scope = "local" })
    end
  end,
})

-- ── Keymaps ────────────────────────────────────────────────────────────────
-- zr / zm step the fold level by one — the relative control that absolute
-- fold-at-level-N can't express. zR / zM go all the way. za toggles one.
local map = vim.keymap.set
map("n", "<leader>f", function()                   -- fold every log call
  vim.opt_local.foldlevel = 1
end, { desc = "reader: collapse to definitions" })

map("n", "<leader>F", "zR", { desc = "reader: open everything" })

-- Jumplist: <C-o> back, <C-i> forward. Listed here only as documentation;
-- both are native and need no binding.

-- Quick fold-state readout, for when a fold does something surprising.
vim.api.nvim_create_user_command("FoldWhy", function()
  local l = vim.fn.line(".")
  vim.notify(("line %d  foldlevel=%s  closed=%s  method=%s")
    :format(l, vim.fn.foldlevel(l), vim.fn.foldclosed(l), vim.wo.foldmethod))
end, { desc = "reader: explain the fold under the cursor" })
