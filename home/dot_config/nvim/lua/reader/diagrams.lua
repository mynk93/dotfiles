-- Inline diagram rendering.
--
-- render-markdown highlights a ```mermaid fence but never draws it. This
-- renders the diagram to a PNG and displays it in the buffer over the Kitty
-- graphics protocol, which Ghostty implements and cmux passes through
-- (verified with `chafa /tmp/kitty-test.png`).
--
-- mermaid-cli drives a headless browser. It defaults to a puppeteer-managed
-- Chrome that must be downloaded separately and is version-pinned to the mmdc
-- build — it broke immediately on a version skew. Point it at the Chrome
-- already installed instead: no second browser, no pin to drift.

-- diagram.nvim shells out to `mmdc` directly, so the puppeteer config file
-- cannot be passed through. puppeteer honours this env var instead, which
-- also fixes mmdc anywhere else it is invoked.
vim.env.PUPPETEER_EXECUTABLE_PATH =
  vim.env.PUPPETEER_EXECUTABLE_PATH
  or "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

require("image").setup({
  backend = "kitty",
  processor = "magick_cli",   -- ImageMagick CLI; avoids the magick luarock
  integrations = {},          -- diagram.nvim drives rendering, not the built-ins
  max_width_window_percentage = 80,
  window_overlap_clear_enabled = true,
  editor_only_render_when_focused = true,
  tmux_show_only_in_active_window = true,
})

require("diagram").setup({
  integrations = {
    require("diagram.integrations.markdown"),
  },
  renderer_options = {
    mermaid = {
      theme = "dark",         -- matches dracula better than the default
      background = "transparent",
      scale = 2,              -- retina; the default renders soft
    },
  },
})

vim.keymap.set("n", "<leader>D", function()
  require("diagram").show_diagram_hover()
end, { desc = "diagram: render under cursor" })
