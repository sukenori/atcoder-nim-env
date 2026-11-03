local review = require("atcoder-nim.archive_review")
local M = {}
local config = { project_root = nil }

-- Filter without changing the order computed by scan_archive/build_queue.
local function ordered_sorter()
  return require("telescope.sorters").new({
    scoring_function = function(_, prompt, line)
      local text = line:lower()
      for word in prompt:lower():gmatch("%S+") do
        if not text:find(word, 1, true) then return -1 end
      end
      return 1
    end,
  })
end

local function problem_id()
  if vim.b.cp_problem_id then return vim.b.cp_problem_id end
  local parsed = review.parse_filename(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
  return parsed and parsed.problem_id
end

local function picker(title, entries, select, preview)
  if #entries == 0 then
    vim.notify("表示する項目がありません", vim.log.levels.INFO)
    return
  end
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  require("telescope.pickers").new({}, {
    prompt_title = title, sorting_strategy = "ascending",
    finder = require("telescope.finders").new_table({
      results = entries,
      entry_maker = function(e)
        return { value = e, display = e.name, ordinal = e.name, path = e.path }
      end,
    }),
    sorter = ordered_sorter(),
    previewer = preview and conf.file_previewer({}) or false,
    attach_mappings = function(bufnr)
      if select then
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          if not entry then return end
          actions.close(bufnr)
          vim.schedule(function() select(entry.value) end)
        end)
      end
      return true
    end,
  }):find()
end

function M.archive_picker(opts)
  opts = opts or {}
  picker("CP Archive", review.scan_archive(opts.archive_dir), nil, true)
end

function M.history_picker(opts)
  opts = opts or {}
  local id = problem_id()
  if not id then
    vim.notify("問題IDを特定できません", vim.log.levels.WARN)
    return
  end
  local entries = vim.tbl_filter(function(e) return e.problem_id == id end,
    review.scan_archive(opts.archive_dir))
  picker(id .. " の履歴", entries, nil, true)
end

function M.suggest_picker(opts)
  local queue, err = review.suggest(opts or {})
  if err then vim.notify(err, vim.log.levels.WARN); return end
  for _, e in ipairs(queue) do
    e.name = string.format("%s  %s  %s  AC x%d", e.problem_id,
      os.date("%Y-%m-%d %H:%M:%S", math.floor(e.recommend_at)),
      e.assisted and "AC+" or "AC", e.ac_count)
  end
  picker("CP 復習推薦順", queue, function(e) M.open_work(e.problem_id) end, false)
end

function M.open_work(id)
  if type(id) ~= "string" or not id:match("^[a-z]+%d+[a-z]$") then
    vim.notify("対応していない問題ID: " .. tostring(id), vim.log.levels.WARN)
    return
  end
  local dir = config.project_root .. "/work"
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. id .. ".nim"
  local old = vim.fn.bufnr(path)
  local loaded = old ~= -1 and vim.api.nvim_buf_is_loaded(old)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type ~= "file" then
    vim.notify("通常ファイルではありません: " .. path, vim.log.levels.ERROR)
    return
  end
  local initialize = not stat and not loaded
  local ok, err = pcall(function() vim.cmd.edit(vim.fn.fnameescape(path)) end)
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR); return end
  vim.b.cp_problem_id = id
  if initialize then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'include "template.nim"', "" })
    local saved, why = pcall(vim.cmd, "write")
    if not saved then vim.notify(tostring(why), vim.log.levels.ERROR) end
  end
end

function M.open_canonical(id)
  id = id or problem_id()
  if not id then return end
  local path = review.canonical_path(id)
  if not path then
    vim.notify(id .. " のPromote版はありません", vim.log.levels.INFO)
    return
  end
  vim.cmd.vsplit(vim.fn.fnameescape(path))
  vim.b.cp_problem_id = id
end

function M.setup(opts)
  opts = opts or {}
  assert(type(opts.project_root) == "string" and opts.project_root ~= "",
    "review_commands.setup: project_root が必要です")
  config.project_root = vim.fn.fnamemodify(opts.project_root, ":p"):gsub("/+$", "")
  review.setup(vim.tbl_deep_extend("force", {
    archive_dir = config.project_root .. "/archive",
  }, opts.review or {}))
  local commands = {
    CpSuggest = function() M.suggest_picker({}) end,
    CpArchive = function() M.archive_picker({}) end,
    CpHistory = function() M.history_picker({}) end,
    CpOpenAnswer = function() M.open_canonical() end,
  }
  for name, callback in pairs(commands) do
    vim.api.nvim_create_user_command(name, callback, { force = true })
  end
end
return M
