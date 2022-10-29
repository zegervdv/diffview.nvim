local lazy = require("diffview.lazy")

local DiffView = lazy.access("diffview.scene.views.diff.diff_view", "DiffView") ---@type DiffView|LazyModule
local FileHistoryView = lazy.access("diffview.scene.views.file_history.file_history_view", "FileHistoryView") ---@type FileHistoryView|LazyModule
local Rev = lazy.access("diffview.vcs.rev", "Rev") ---@type Rev|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type ERevType|LazyModule
local StandardView = lazy.access("diffview.scene.views.standard.standard_view", "StandardView") ---@type StandardView|LazyModule
local arg_parser = lazy.require("diffview.arg_parser") ---@module "diffview.arg_parser"
local config = lazy.require("diffview.config") ---@module "diffview.config"
local vcs = lazy.require("diffview.vcs") ---@module "diffview.vcs"
local logger = lazy.require("diffview.logger") ---@module "diffview.logger"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local api = vim.api

---@type PathLib
local pl = lazy.access(utils, "path")

local M = {}

---@type View[]
M.views = {}

function M.diffview_open(args)
  local default_args = config.get_config().default_args.DiffviewOpen
  local argo = arg_parser.parse(vim.tbl_flatten({ default_args, args }))
  local rev_arg = argo.args[1]

  logger.info("[command call] :DiffviewOpen " .. table.concat(vim.tbl_flatten({
    default_args,
    args,
  }), " "))

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.post_args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  local opts = adapter:diffview_options(args)

  ---@type DiffView
  local v = DiffView({
    git_ctx = adapter,
    rev_arg = rev_arg,
    path_args = adapter.ctx.path_args,
    left = opts.left,
    right = opts.right,
    options = opts.options,
  })

  if not v:is_valid() then
    return
  end

  table.insert(M.views, v)
  logger.lvl(1).s_debug("DiffView instantiation successful!")

  return v
end

---@param range? { [1]: integer, [2]: integer }
---@param args string[]
function M.file_history(range, args)
  local default_args = config.get_config().default_args.DiffviewFileHistory
  local argo = arg_parser.parse(vim.tbl_flatten({ default_args, args }))
  local rel_paths

  logger.info("[command call] :DiffviewFileHistory " .. table.concat(vim.tbl_flatten({
    default_args,
    args,
  }), " "))

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  rel_paths = vim.tbl_map(function(v)
    return v == "." and "." or pl:relative(v, ".")
  end, adapter.ctx.path_args)

  local log_options = adapter:file_history_options(range, rel_paths, args)

  if log_options == nil then
    utils.err('Failed to create log options for file_history')
  end

  ---@type FileHistoryView
  local v = FileHistoryView({
    git_ctx = adapter,
    log_options = log_options,
  })

  if not v:is_valid() then
    return
  end

  table.insert(M.views, v)
  logger.lvl(1).s_debug("FileHistoryView instantiation successful!")

  return v
end

---@param view View
function M.add_view(view)
  table.insert(M.views, view)
end

---@param view View
function M.dispose_view(view)
  for j, v in ipairs(M.views) do
    if v == view then
      table.remove(M.views, j)
      return
    end
  end
end

---Close and dispose of views that have no tabpage.
function M.dispose_stray_views()
  local tabpage_map = {}
  for _, id in ipairs(api.nvim_list_tabpages()) do
    tabpage_map[id] = true
  end

  local dispose = {}
  for _, view in ipairs(M.views) do
    if not tabpage_map[view.tabpage] then
      -- Need to schedule here because the tabnr's don't update fast enough.
      vim.schedule(function()
        view:close()
      end)
      table.insert(dispose, view)
    end
  end

  for _, view in ipairs(dispose) do
    M.dispose_view(view)
  end
end

---Get the currently open Diffview.
---@return View?
function M.get_current_view()
  local tabpage = api.nvim_get_current_tabpage()
  for _, view in ipairs(M.views) do
    if view.tabpage == tabpage then
      return view
    end
  end

  return nil
end

function M.tabpage_to_view(tabpage)
  for _, view in ipairs(M.views) do
    if view.tabpage == tabpage then
      return view
    end
  end
end

---Get the first tabpage that is not a view. Tries the previous tabpage first.
---If there are no non-view tabpages: returns nil.
---@return number|nil
function M.get_prev_non_view_tabpage()
  local tabs = api.nvim_list_tabpages()
  if #tabs > 1 then
    local seen = {}
    for _, view in ipairs(M.views) do
      seen[view.tabpage] = true
    end

    local prev_tab = utils.tabnr_to_id(vim.fn.tabpagenr("#")) or -1
    if api.nvim_tabpage_is_valid(prev_tab) and not seen[prev_tab] then
      return prev_tab
    else
      for _, id in ipairs(tabs) do
        if not seen[id] then
          return id
        end
      end
    end
  end
end

function M.update_colors()
  for _, view in ipairs(M.views) do
    if view:instanceof(StandardView.__get()) then
      ---@cast view StandardView
      if view.panel:buf_loaded() then
        view.panel:render()
        view.panel:redraw()
      end
    end
  end
end

return M
