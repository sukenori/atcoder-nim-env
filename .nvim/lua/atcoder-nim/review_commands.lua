
-- .nvim/lua/atcoder-nim/review_commands.lua
--
-- archive_review.lua の計算結果を Telescope pickerとユーザーコマンドとして公開する。

local review = require("atcoder-nim.archive_review")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

local M = {}

--- 表示整形 -------------------------------------------------------------

local function format_relative(now, at)
  local diff = at - now
  local sign = diff <= 0 and "期限超過" or "予定"
  local abs = math.abs(diff)

  local days = math.floor(abs / 86400)
  local hours = math.floor((abs % 86400) / 3600)

  if days > 0 then
    return string.format("%s %d日%d時間", sign, days, hours)
  end

  local minutes = math.floor((abs % 3600) / 60)
  return string.format("%s %d時間%d分", sign, hours, minutes)
end

local function format_duration(seconds)
  local days = seconds / 86400
  if days >= 1 then
    return string.format("%.1f日", days)
  end
  local hours = seconds / 3600
  if hours >= 1 then
    return string.format("%.1f時間", hours)
  end
  return string.format("%d分", math.floor(seconds / 60))
end

--- :CpSuggest -------------------------------------------------------------
--
-- 復習推薦キューをTelescopeで表示する。
-- 選択すると、その問題IDのwork用バッファを開く(新規または既存)。

function M.suggest_picker(opts)
  opts = opts or {}

  local queue, err = review.suggest(opts)

  if err then
    vim.notify("CpSuggest: " .. err, vim.log.levels.WARN)
    return
  end

  if #queue == 0 then
    vim.notify("復習候補になる問題がありません", vim.log.levels.INFO)
    return
  end

  local now = os.time()

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 10 },  -- 状態
      { width = 16 },  -- 残り時間
      { width = 12 },  -- 問題ID
      { width = 6 },   -- 自力/他力
      { width = 10 },  -- AC回数
      { remaining = true }, -- 基準間隔
    },
  })

  local function make_display(entry)
    local item = entry.value
    local status = item.recommend_at <= now and "期限超過" or "予定"

    return displayer({
      status,
      format_relative(now, item.recommend_at),
      item.problem_id,
      item.assisted and "他力" or "自力",
      string.format("AC×%d", item.ac_count),
      string.format(
        "基準間隔 %s%s",
        format_duration(item.base_gap),
        item.used_fallback and "(平均値)" or ""
      ),
    })
  end

  pickers
    .new(opts, {
      prompt_title = "CP復習キュー (次に解くべき問題)",
      finder = finders.new_table({
        results = queue,
        entry_maker = function(item)
          return {
            value = item,
            display = make_display,
            ordinal = item.problem_id,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection then
            M.open_work(selection.value.problem_id)
          end
        end)

        map("i", "<C-o>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            M.open_canonical(selection.value.problem_id)
          end
        end)

        return true
      end,
    })
    :find()
end

--- :CpArchive -------------------------------------------------------------
--
-- archive全件を一覧表示する(判定はAtCoder履歴と都度照合)。

function M.archive_picker(opts)
  opts = opts or {}

  local dir = opts.archive_dir or review.config.archive_dir
  local entries = review.scan_archive(dir)

  if #entries == 0 then
    vim.notify("archiveにファイルがありません", vim.log.levels.INFO)
    return
  end

  local oldest = entries[1].saved_at
  local submissions, err = review.fetch_submissions(nil, math.max(0, oldest - 60))

  local verdict_by_path = {}

  if submissions then
    local ac_by_problem = review.match_and_collect_ac(entries, submissions, opts)
    for _, acs in pairs(ac_by_problem) do
      for _, ac in ipairs(acs) do
        verdict_by_path[ac.archive_path] = ac.assisted and "AC(他力)" or "AC(自力)"
      end
    end
  else
    vim.notify("CpArchive: 提出履歴を取得できませんでした (" .. tostring(err) .. ")", vim.log.levels.WARN)
  end

  -- 新しい順に表示
  table.sort(entries, function(a, b) return a.saved_at > b.saved_at end)

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 19 },
      { width = 12 },
      { width = 10 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    local item = entry.value
    return displayer({
      os.date("%Y-%m-%d %H:%M:%S", item.saved_at),
      item.problem_id,
      verdict_by_path[item.path] or "未照合",
      vim.fn.fnamemodify(item.path, ":t"),
    })
  end

  pickers
    .new(opts, {
      prompt_title = "CP Archive (全履歴)",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(item)
          return {
            value = item,
            display = make_display,
            ordinal = item.problem_id .. " " .. os.date("%Y-%m-%d", item.saved_at),
            path = item.path,
          }
        end,
      }),
      previewer = conf.file_previewer(opts),
      sorter = conf.generic_sorter(opts),
    })
    :find()
end

--- :CpHistory -------------------------------------------------------------
--
-- 現在バッファの問題IDに絞ってarchiveを表示する。

function M.history_picker(opts)
  opts = opts or {}

  local bufname = vim.api.nvim_buf_get_name(0)
  local problem_id = vim.fn.fnamemodify(bufname, ":t:r")

  if vim.b.cp_problem_id then
    problem_id = vim.b.cp_problem_id
  end

  if not problem_id or problem_id == "" then
    vim.notify("現在のバッファから問題IDを特定できません", vim.log.levels.WARN)
    return
  end

  local dir = opts.archive_dir or review.config.archive_dir
  local all_entries = review.scan_archive(dir)

  local entries = vim.tbl_filter(function(e)
    return e.problem_id == problem_id
  end, all_entries)

  if #entries == 0 then
    vim.notify(problem_id .. " の履歴はありません", vim.log.levels.INFO)
    return
  end

  table.sort(entries, function(a, b) return a.saved_at > b.saved_at end)

  local submissions = review.fetch_submissions(
    nil,
    math.max(0, entries[#entries].saved_at - 60)
  )

  local verdict_by_path = {}
  if submissions then
    local ac_by_problem = review.match_and_collect_ac(entries, submissions, opts)
    for _, acs in pairs(ac_by_problem) do
      for _, ac in ipairs(acs) do
        verdict_by_path[ac.archive_path] = ac.assisted and "AC(他力)" or "AC(自力)"
      end
    end
  end

  pickers
    .new(opts, {
      prompt_title = problem_id .. " の履歴",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(item)
          local label = string.format(
            "%s  %s",
            os.date("%Y-%m-%d %H:%M:%S", item.saved_at),
            verdict_by_path[item.path] or "未照合"
          )
          return {
            value = item,
            display = label,
            ordinal = label,
            path = item.path,
          }
        end,
      }),
      previewer = conf.file_previewer(opts),
      sorter = conf.generic_sorter(opts),
    })
    :find()
end

--- 補助コマンド ------------------------------------------------------------

function M.open_work(problem_id)
  -- 既存の work 作成/オープンロジックがあるならそちらに委譲する。
  -- ここでは最小実装として、workディレクトリのファイルを開くだけにする。
  local work_dir = vim.g.atcoder_nim_work_dir or (vim.fn.getcwd() .. "/work")
  local path = work_dir .. "/" .. problem_id .. ".nim"
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M.open_canonical(problem_id)
  local dir = review.config.archive_dir
  local path = review.canonical_path(problem_id, dir)

  if not path then
    vim.notify(problem_id .. " の正解コード(canonical)はまだありません", vim.log.levels.INFO)
    return
  end

  vim.cmd.vsplit(vim.fn.fnameescape(path))
end

--- ユーザーコマンド定義 -----------------------------------------------------

function M.setup(opts)
  review.setup(opts and opts.review or {})

  vim.api.nvim_create_user_command("CpSuggest", function()
    M.suggest_picker({})
  end, { desc = "CP: 復習推薦キューを表示" })

  vim.api.nvim_create_user_command("CpArchive", function()
    M.archive_picker({})
  end, { desc = "CP: archive全件を表示" })

  vim.api.nvim_create_user_command("CpHistory", function()
    M.history_picker({})
  end, { desc = "CP: 現在問題のarchive履歴を表示" })
end

return M
