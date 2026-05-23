-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Keep splits/floating UI sane when the terminal is resized a lot.
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("user_resize_redraw", { clear = true }),
  callback = function()
    vim.cmd("wincmd =")
    vim.cmd("redraw!")
  end,
})
