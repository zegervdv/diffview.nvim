local config = require("diffview.config")
local logger = require("diffview.logger")
local utils = require("diffview.utils")

local M = {}

function M.setup(parent)
  M.exec_sync = parent.exec_sync
  M.handle_co = parent.handle_co
end

function M.get_command()
  return config.get_config().hg_cmd
end

function M.run_bootstrap()
  local out, code = utils.system_list(
    vim.tbl_flatten({ config.get_config().hg_cmd , "version"})
  )

  if code ~= 0 or not out[1] then
    msg = "Could not run `hg_cmd`"
    logger.error(msg)
    utils.err(msg)
    return
  end

  -- TODO: check for a minimal version
end

---@param toplevel string
---@param log_opt LogOptions
---@return boolean ok, string description
function M.file_history_dry_run(toplevel, log_opt)
  -- TODO: implement
  return true, {}
end

---Derive the top-level path of the working tree of the given path.
---@param path string
---@return string?
function M.toplevel(path)
  local out, code = M.exec_sync({ "root" }, path)
  if code ~= 0 then
    return nil
  end
  return out[1] and vim.trim(out[1])
end

---Get the path to the .hg directory.
---@param path string
---@return string|nil
function M.root_dir(path)
  local out, code = M.exec_sync({"root"}, path)
  if code ~= 0 then
    return nil
  end
  return out[1] and vim.trim(out[1])
end

return M
