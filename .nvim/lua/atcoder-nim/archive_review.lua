-- Finalized filenames are the source of truth. No network calls or review DB.
local M = {}
M.config = { archive_dir = vim.fn.getcwd() .. "/archive" }
local verdicts = {
  AC = true, ["AC+"] = true, WA = true, TLE = true,
  RE = true, CE = true, MLE = true, OLE = true, IE = true,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.parse_filename(name)
  local id, y, mo, d, h, mi, s, suffix = name:match(
    "^(.+)_(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)(.-)%.nim$"
  )
  if id then
    local at = os.time({ year = tonumber(y), month = tonumber(mo),
      day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    if not at or os.date("%Y-%m-%d_%H-%M-%S", at)
        ~= table.concat({ y, mo, d }, "-") .. "_" .. table.concat({ h, mi, s }, "-") then
      return nil
    end
    local verdict = suffix:match("^_([A-Z]+%+?)$")
    if suffix ~= "" and not verdicts[verdict] then return nil end
    return { problem_id = id, saved_at = at, kind = "snapshot",
      verdict = verdict, assisted = verdict == "AC+", name = name }
  end
  local canonical = name:match("^([%w_]+)%.nim$")
  if canonical then
    return { problem_id = canonical, kind = "canonical", name = name }
  end
end

function M.scan_archive(dir)
  dir = dir or M.config.archive_dir
  if vim.fn.isdirectory(dir) ~= 1 then return {} end
  local entries = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" then
      local e = M.parse_filename(name)
      if e and (e.kind == "canonical" or e.verdict) then
        e.path = dir .. "/" .. name
        entries[#entries + 1] = e
      end
    end
  end
  table.sort(entries, function(a, b)
    if a.kind ~= b.kind then return a.kind == "canonical" end
    if a.saved_at ~= b.saved_at then return a.saved_at > b.saved_at end
    return a.name < b.name
  end)
  return entries
end

function M.canonical_path(problem_id, dir)
  local path = (dir or M.config.archive_dir) .. "/" .. problem_id .. ".nim"
  if vim.fn.filereadable(path) == 1 then return path end
end

function M.is_assisted(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil, "Cannot read source: " .. path end
  for _, line in ipairs(lines) do
    if line:match("^%s*#%+") then return true end
  end
  return false
end

function M.collect_ac(entries)
  local groups = {}
  for _, e in ipairs(entries) do
    if e.kind == "snapshot" and (e.verdict == "AC" or e.verdict == "AC+") then
      groups[e.problem_id] = groups[e.problem_id] or {}
      table.insert(groups[e.problem_id], {
        at = e.saved_at, archive_path = e.path, assisted = e.verdict == "AC+",
      })
    end
  end
  for _, acs in pairs(groups) do
    table.sort(acs, function(a, b)
      if a.at ~= b.at then return a.at < b.at end
      return a.archive_path < b.archive_path
    end)
  end
  return groups
end

local function base_gap(acs)
  if #acs >= 2 then return acs[#acs].at - acs[#acs - 1].at end
end

function M.build_queue(groups)
  local ids = vim.tbl_keys(groups)
  table.sort(ids)
  local total, count = 0, 0
  for _, id in ipairs(ids) do
    local gap = base_gap(groups[id])
    if gap then total, count = total + gap, count + 1 end
  end
  local fallback = count > 0 and total / count or nil
  local queue = {}
  for _, id in ipairs(ids) do
    local acs = groups[id]
    local latest = acs[#acs]
    local own_gap = base_gap(acs)
    local gap = own_gap or fallback
    if latest and gap then
      queue[#queue + 1] = {
        problem_id = id, latest_ac_at = latest.at,
        assisted = latest.assisted, base_gap = gap,
        used_fallback = own_gap == nil, ac_count = #acs,
        recommend_at = latest.at + gap * (latest.assisted and 0.5 or 2),
      }
    end
  end
  table.sort(queue, function(a, b)
    if a.recommend_at ~= b.recommend_at then return a.recommend_at < b.recommend_at end
    return a.problem_id < b.problem_id
  end)
  return queue
end

function M.suggest(opts)
  opts = opts or {}
  local groups = M.collect_ac(M.scan_archive(opts.archive_dir))
  local queue = M.build_queue(groups)
  if #queue == 0 and next(groups) then
    return {}, "AC間隔の平均を計算できません。ACが2回以上ある問題が必要です"
  end
  return queue, nil
end
return M
