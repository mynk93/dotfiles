-- Language servers, for navigation only.
--
-- The point of an LSP here is go-to-definition, find-references and hover —
-- the things that make a large unfamiliar codebase navigable. Not completion,
-- not formatting, not code actions on save. Writing happens elsewhere.
--
-- Uses the native vim.lsp.config API (0.11+); no lspconfig plugin.

-- basedpyright: navigation and types.
vim.lsp.config("basedpyright", {
  cmd = { "basedpyright-langserver", "--stdio" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
  settings = {
    basedpyright = {
      -- Zed pins this to `standard`; basedpyright's own default of
      -- `recommended` floods an untyped codebase with diagnostics.
      analysis = {
        typeCheckingMode = "standard",
        -- Index the workspace so find-references sees callers in files that
        -- are not open. Costs CPU on a large tree; the whole point here is
        -- finding things, so it earns it.
        diagnosticMode = "workspace",
        inlayHints = { callArgumentNames = false },
      },
    },
  },
})

-- ruff: lint diagnostics. Deliberately no hover/definition — basedpyright
-- owns those, and two servers answering the same request is noise.
vim.lsp.config("ruff", {
  cmd = { "ruff", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "ruff.toml", ".git" },
  on_attach = function(client)
    client.server_capabilities.hoverProvider = false
    client.server_capabilities.definitionProvider = false
  end,
})

vim.lsp.enable({ "basedpyright", "ruff" })

-- Diagnostics: visible but not shouty. This is a reader; a wall of virtual
-- text over every line defeats the purpose.
vim.diagnostic.config({
  virtual_text = false,
  underline = true,
  severity_sort = true,
  signs = { text = { [vim.diagnostic.severity.ERROR] = "E", [vim.diagnostic.severity.WARN] = "W" } },
  float = { border = "rounded", source = true },
})
