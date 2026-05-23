return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- Show dotfiles/dot-directories by default, but keep gitignored files hidden.
        sources = {
          files = { hidden = true, ignored = false },
          explorer = {
            hidden = true,
            ignored = false,
            layout = {
              preset = "sidebar",
              preview = false,
              layout = {
                width = 35,
              },
            },
          },
        },

        -- Use a large picker on normal/wide terminals, but switch to a safer
        -- vertical layout when the terminal is narrow. This avoids picker
        -- overflow/weird rendering after resizing Ghostty.
        layout = {
          preset = function()
            return vim.o.columns >= 120 and "default" or "vertical"
          end,
          layout = {
            width = 0.96,
            height = 0.92,
            min_width = 40,
            min_height = 10,
          },
        },
      },
    },
  },
}
