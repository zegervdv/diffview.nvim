local config = require("diffview.config")
local logger = require("diffview.logger")
local utils = require("diffview.utils")

local M = {}

---@class hgContext
---@field toplevel string Path to the top-level directory of the working tree.
---@field dir string Path to the .hg directory.

local bootstrap = {
  done = false,
  ok = false,
  version_string = nil,
  version = {},
  target_version_string = nil,
  target_version = {
    major = 4, -- TODO: check minimal version
    minor = 0,
    patch = 0,
  },
}

---Ensure that the configured hg binary meets the version requirement.
local function run_bootstrap()
  bootstrap.done = true
  local msg

  local out, code = utils.system_list(
    vim.tbl_flatten({ config.get_config().hg_cmd, "version" })
  )

  if code ~= 0 or not out[1] then
    msg = "Could not run `hg_cmd`!"
    logger.error(msg)
    utils.err(msg)
    return
  end

  bootstrap.version_string = out[1]:match("Mercurial Distributed SCM %(version (%S+)%)")

  if not bootstrap.version_string then
    msg = "Could not get hg version!"
    logger.error(msg)
    utils.err(msg)
    return
  end

  -- Parse hg version
  local v, target = bootstrap.version, bootstrap.target_version
  bootstrap.target_version_string = ("%d.%d.%d"):format(target.major, target.minor, target.patch)
  local parts = vim.split(bootstrap.version_string, "%.")
  v.major = tonumber(parts[1])
  v.minor = tonumber(parts[2])
  v.patch = tonumber(parts[3]) or 0

  local vs = ("%08d%08d%08d"):format(v.major, v.minor, v.patch)
  local ts = ("%08d%08d%08d"):format(target.major, target.minor, target.patch)

  if vs < ts then
    msg = (
      "hg version is outdated! Some functionality might not work as expected, "
      .. "or not at all! Target: %s, current: %s"
    ):format(
      bootstrap.target_version_string,
      bootstrap.version_string
    )
    logger.error(msg)
    utils.err(msg)
    return
  end

  bootstrap.ok = true
end

---Execute a hg command synchronously.
---@param args string[]
---@param cwd_or_opt? string|utils.system_list.Opt
---@return string[] stdout
---@return integer code
---@return string[] stderr
---@overload fun(args: string[], cwd: string?)
---@overload fun(args: string[], opt: utils.system_list.Opt?)
function M.exec_sync(args, cwd_or_opt)
  if not bootstrap.done then
    run_bootstrap()
  end

  return utils.system_list(
    vim.tbl_flatten({ config.get_config().hg_cmd, args }),
    cwd_or_opt
  )
end

function M.toplevel(path)
  local out, code = M.exec_sync({ 'root' })
  if code ~= 0 then
    return nil
  end
  return out[1] and vim.trim(out[1])
end

---Verify that a given git rev is valid.
---@param toplevel string
---@param rev_arg string
---@return boolean ok, string[] output
function M.verify_rev_arg(toplevel, rev_arg)
  local out, code = M.exec_sync({ "log", "--template", "node", '--rev', rev_arg }, {
    context = "hg.utils.verify_rev_arg()",
    cwd = toplevel,
  })
  return code == 0 and (out[2] ~= nil or out[1] and out[1] ~= ""), out
end

---@param toplevel string
---@param path_args string[]
---@param lflags string[]
---@return boolean
local function is_single_file(toplevel, path_args, lflags)
  if lflags and #lflags > 0 then
    local seen = {}
    for i, v in ipairs(lflags) do
      local path = v:match(".*:(.*)")
      if i > 1 and not seen[path] then
        return false
      end
      seen[path] = true
    end

  elseif path_args and toplevel then
    return #path_args == 1
        and not utils.path:is_dir(path_args[1])
        and #M.exec_sync({ "files", "--", path_args }, toplevel) < 2
  end

  return true
end


---@param toplevel string
---@param log_opt LogOptions
---@return boolean ok, string description
function M.file_history_dry_run(toplevel, log_opt)
  local single_file = is_single_file(toplevel, log_opt.path_args, log_opt.L)
  local log_options = config.get_log_options(single_file, log_opt)

  local options = vim.tbl_map(function(v)
    return vim.fn.shellescape(v)
  end, prepare_fh_options(toplevel, log_options, single_file).flags) --[[@as vector ]]

  local description = utils.vec_join(
    ("Top-level path: '%s'"):format(utils.path:vim_fnamemodify(toplevel, ":~")),
    log_options.rev_range and ("Revision range: '%s'"):format(log_options.rev_range) or nil,
    ("Flags: %s"):format(table.concat(options, " "))
  )

  log_options = utils.tbl_clone(log_options) --[[@as LogOptions ]]
  log_options.max_count = 1
  options = prepare_fh_options(toplevel, log_options, single_file).flags

  local context = "git.utils.file_history_dry_run()"
  local cmd

  if #log_options.L > 0 then
    -- cmd = utils.vec_join("-P", "log", log_options.rev_range, "--no-ext-diff", "--color=never", "--pretty=format:%H", "-s", options, "--")
    -- NOTE: Running the dry-run for line tracing is slow. Just skip for now.
    return true, table.concat(description, ", ")
  else
    cmd = utils.vec_join("log", log_options.rev_range, "--pretty=format:%H", "--name-status", options, "--", log_options.path_args)
  end

  local out, code = M.exec_sync(cmd, {
    cwd = toplevel,
    debug_opt = {
      context = context,
      no_stdout = true,
    },
  })

  local ok = code == 0 and #out > 0

  if not ok then
    logger.lvl(1).s_debug(("[%s] Dry run failed."):format(context))
  end

  return ok, table.concat(description, ", ")
end

return M
