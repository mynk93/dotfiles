-- Folding, via nvim-ufo.
--
-- ufo replaces the raw foldexpr/foldtext pair with a provider chain and a
-- virtual-text handler. Two reasons it is worth the dependency here:
--
--   1. fold_virt_text_handler receives the first line as highlighted chunks,
--      so the collapsed line keeps its syntax colours (see reader.foldtext).
--   2. The provider chain falls back cleanly: lsp -> treesitter -> indent,
--      per buffer, so a file whose language has no parser still folds.
--
-- It does NOT replace after/queries/python/folds.scm. ufo's treesitter
-- provider resolves folds via get_query(lang, 'folds'), the same path that
-- picks up our `;; extends` file — so the slog fold query carries over.

local ufo = require("ufo")
local foldtext = require("reader.foldtext")

-- ufo drives fold state itself and needs foldlevel parked high; the reading
-- state is reached with closeFoldsWith below, not with foldlevelstart.
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true
vim.o.foldcolumn = "1"

ufo.setup({
  open_fold_hl_timeout = 0,               -- no flash on open; this is a reader
  fold_virt_text_handler = foldtext.handler,
  provider_selector = function(_, filetype, _)
    -- basedpyright advertises no foldingRangeProvider, so the lsp provider
    -- would return nothing for python and cost a round trip. Go straight to
    -- treesitter, and let ufo fall back to indent where no parser exists.
    if filetype == "" then
      return ""
    end
    return { "treesitter", "indent" }
  end,
})

-- Open a file at "definitions visible, their internals folded" — the state
-- that took a keystroke per function in zed. Deferred because ufo needs the
-- buffer's fold ranges computed before it can close to a level.
vim.api.nvim_create_autocmd("BufWinEnter", {
  desc = "reader: open files collapsed to definitions",
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" then
      return
    end
    vim.defer_fn(function()
      pcall(ufo.closeFoldsWith, 1)
    end, 120)
  end,
})

local map = vim.keymap.set
map("n", "zR", ufo.openAllFolds,  { desc = "fold: open all" })
map("n", "zM", ufo.closeAllFolds, { desc = "fold: close all" })
map("n", "zr", ufo.openFoldsExceptKinds, { desc = "fold: open one level" })
map("n", "zm", ufo.closeFoldsWith,       { desc = "fold: close one level" })
map("n", "<leader>z", function() ufo.closeFoldsWith(1) end,
  { desc = "fold: back to definitions" })

-- Peek inside a fold without opening it; falls through to hover if closed.
map("n", "zp", function()
  if not ufo.peekFoldedLinesUnderCursor() then
    vim.lsp.buf.hover()
  end
end, { desc = "fold: peek contents" })
