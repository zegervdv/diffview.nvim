local config = require("diffview.config")
local utils = require("diffview.utils")
local async = require("plenary.async")


local M = {}

-- TODO: Find current workspace and load correct adapter
local adapter = require('diffview.vcs.adapters.git.utils')


local bootstrap = {
  done = false,
  ok = false,
}

---Execute a git command synchronously.
---@param args string[]
---@param cwd_or_opt? string|utils.system_list.Opt
---@return string[] stdout
---@return integer code
---@return string[] stderr
---@overload fun(args: string[], cwd: string?)
---@overload fun(args: string[], opt: utils.system_list.Opt?)
function M.exec_sync(args, cwd_or_opt)
  if not bootstrap.done then
    bootstrap.done = true
    adapter.run_bootstrap()
    bootstrap.ok = true
  end

  return utils.system_list(
    vim.tbl_flatten({ adapter.get_command(), args }),
    cwd_or_opt
  )
end

---@param ctx GitContext
---@param log_opt ConfigLogOptions
---@param opt git.utils.FileHistoryWorkerSpec
---@param callback function
---@return fun() finalizer
function M.file_history(ctx, log_opt, opt, callback)
  return adapter.file_history(ctx, log_opt, opt, callback)
end

---@param toplevel string
---@param log_opt LogOptions
---@return boolean ok, string description
function M.file_history_dry_run(toplevel, log_opt)
  return adapter.file_history_dry_run(toplevel, log_opt)
end

---Determine whether a rev arg is a range.
---@param rev_arg string
---@return boolean
function M.is_rev_arg_range(rev_arg)
  return adapter.is_rev_arg_range(rev_arg)
end

---Convert revs to git rev args.
---@param left Rev
---@param right Rev
---@return string[]
function M.rev_to_args(left, right)
  return adapter.rev_to_args(left, right)
end

---Convert revs to string representation.
---@param left Rev
---@param right Rev
---@return string|nil
function M.rev_to_pretty_string(left, right)
  return adapter.rev_to_pretty_string(left, right)
end

---@param toplevel string
---@return Rev?
function M.head_rev(toplevel)
  return adapter.head_rev(toplevel)
end

---Parse two endpoint, commit revs from a symmetric difference notated rev arg.
---@param toplevel string
---@param rev_arg string
---@return Rev? left The left rev.
---@return Rev? right The right rev.
function M.symmetric_diff_revs(toplevel, rev_arg)
  return adapter.symmetric_diff_revs(toplevel, rev_arg)
end

---Derive the top-level path of the working tree of the given path.
---@param path string
---@return string?
function M.toplevel(path)
  return adapter.toplevel(path)
end

---Get the path to the .git directory.
---@param path string
---@return string|nil
function M.root_dir(path)
  -- TODO: Rename
  return adapter.git_dir(path)
end

---@param path string
---@return GitContext?
function M.git_context(path)
  -- TODO: Rename
  return adapter.git_context(path)
end

---@class ConflictRegion
---@field first integer
---@field last integer
---@field ours { first: integer, last: integer, content?: string[] }
---@field base { first: integer, last: integer, content?: string[] }
---@field theirs { first: integer, last: integer, content?: string[] }

---@param lines string[]
---@param winid? integer
---@return ConflictRegion[] conflicts
---@return ConflictRegion? cur_conflict The conflict under the cursor in the given window.
---@return integer cur_conflict_idx Index of the current conflict. Will be 0 if the cursor if before the first conflict, and `#conflicts + 1` if the cursor is after the last conflict.
function M.parse_conflicts(lines, winid)
  return adapter.parse_conflicts(lines, winid)
end

---@return string, string
function M.pathspec_split(pathspec)
  return adapter.pathspec_split(pathspec)
end

function M.pathspec_expand(toplevel, cwd, pathspec)
  return adapter.pathspec_expand(toplevel, cwd, pathspec)
end

function M.pathspec_modify(pathspec, mods)
  local magic, pattern = M.pathspec_split(pathspec)
  return magic .. utils.path:vim_fnamemodify(pattern, mods)
end

---Check if any of the given revs are LOCAL.
---@param left Rev
---@param right Rev
---@return boolean
function M.has_local(left, right)
  return adapter.has_local(left, right)
end

---Strange trick to check if a file is binary using only git.
---@param toplevel string
---@param path string
---@param rev Rev
---@return boolean -- True if the file was binary for the given rev, or it didn't exist.
function M.is_binary(toplevel, path, rev)
  return adapter.is_binary(toplevel, path, rev)
end

---Check if status for untracked files is disabled for a given git repo.
---@param toplevel string
---@return boolean
function M.show_untracked(toplevel)
  return adapter.show_untracked(toplevel)
end

---Get the diff status letter for a file for a given rev.
---@param toplevel string
---@param path string
---@param rev_arg string
---@return string?
function M.get_file_status(toplevel, path, rev_arg)
  return adapter.get_file_status(toplevel, path, rev_arg)
end

---Get diff stats for a file for a given rev.
---@param toplevel string
---@param path string
---@param rev_arg string
---@return GitStats?
function M.get_file_stats(toplevel, path, rev_arg)
  return adapter.get_file_stats(toplevel, path, rev_arg)
end

---Verify that a given git rev is valid.
---@param toplevel string
---@param rev_arg string
---@return boolean ok, string[] output
function M.verify_rev_arg(toplevel, rev_arg)
  return adapter.verify_rev_arg(toplevel, rev_arg)
end

---Get a list of files modified between two revs.
---@param ctx GitContext
---@param left Rev
---@param right Rev
---@param path_args string[]|nil
---@param dv_opt DiffViewOptions
---@param opt git.utils.LayoutOpt
---@param callback function
---@return string[]? err
---@return FileDict?
M.diff_file_list = async.wrap(function(ctx, left, right, path_args, dv_opt, opt, callback)
  adapter.diff_file_list(ctx, left, right, path_args, dv_opt, opt, callback)
end, 7)

M.show = async.wrap(function (toplevel, args, callback)
  adapter.show(toplevel, args, callback)
end, 3)

---Restore a file to the state it was in, in a given commit / rev. If no commit
---is given, unstaged files are restored to the state in index, and staged files
---are restored to the state in HEAD. The file will also be written into the
---object database such that the action can be undone.
---@param toplevel string
---@param path string
---@param kind '"staged"'|'"working"'
---@param commit string
M.restore = async.wrap(function(toplevel, path, kind, commit, callback) 
  adapter.restore(toplevel, path, kind,commit, callback)
end, 5)


adapter.setup(M)

return M
