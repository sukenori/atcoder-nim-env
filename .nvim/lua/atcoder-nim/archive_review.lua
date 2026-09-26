
-- .nvim/lua/atcoder-nim/archive_review.lua
--
-- archiveディレクトリのファイル名とAtCoder提出履歴だけから、
-- 毎回その場で復習キューを再計算するモジュール。
-- 永続的な状態(DB、リネーム、フラグファイル)は一切持たない。

local M = {}

--- 設定 -------------------------------------------------------------

M.config = {
  archive_dir = vim.fn.getcwd() .. "/archive",
  atcoder_username = vim.g.atcoder_nim_username or vim.env.ATCODER_USER,
  -- archiveスナップショット保存時刻から見て、対応する提出とみなす時間窓(秒)
  match_window_before = 30,
  match_window_after = 1800,
  -- AtCoder提出履歴を遡って取得する期間(秒)。全期間見たいなら十分大きく。
  lookback_seconds = 3 * 365 * 24 * 60 * 60,
  -- 自力/他力フラグの検出に読む先頭行数
  assisted_scan_lines = 20,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- ユーティリティ -----------------------------------------------------

local function read_lines(path, limit)
  local ok, lines = pcall(vim.fn.readfile, path, "", limit)
  if not ok then
    return {}
  end
  return lines
end

--- ファイル名の解析 ----------------------------------------------------
--
-- archive/abc473d_2026-09-01_10-00-00.nim
--   -> { problem_id = "abc473d", saved_at = <unix>, kind = "snapshot" }
--
-- archive/abc473d.nim
--   -> { problem_id = "abc473d", kind = "canonical" }

local SNAPSHOT_PATTERN =
  "^(.+)_(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)%.nim$"

local CANONICAL_PATTERN = "^([%w_]+)%.nim$"

function M.parse_filename(name)
  local id, y, mo, d, h, mi, s = name:match(SNAPSHOT_PATTERN)

  if id then
    local at = os.time({
      year = tonumber(y),
      month = tonumber(mo),
      day = tonumber(d),
      hour = tonumber(h),
      min = tonumber(mi),
      sec = tonumber(s),
    })

    return {
      problem_id = id,
      saved_at = at,
      kind = "snapshot",
    }
  end

  local canonical_id = name:match(CANONICAL_PATTERN)
  if canonical_id then
    return {
      problem_id = canonical_id,
      kind = "canonical",
    }
  end

  return nil
end

--- archive走査 ---------------------------------------------------------
--
-- 戻り値: { {problem_id, saved_at, path, kind}, ... }  (snapshotのみ、時刻昇順)

function M.scan_archive(dir)
  dir = dir or M.config.archive_dir
  local entries = {}

  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok or not iter then
    return entries
  end

  for name, filetype in iter do
    if filetype == "file" then
      local parsed = M.parse_filename(name)

      if parsed and parsed.kind == "snapshot" then
        parsed.path = dir .. "/" .. name
        table.insert(entries, parsed)
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.saved_at < b.saved_at
  end)

  return entries
end

function M.canonical_path(problem_id, dir)
  dir = dir or M.config.archive_dir
  local path = dir .. "/" .. problem_id .. ".nim"

  if vim.fn.filereadable(path) == 1 then
    return path
  end

  return nil
end

--- AtCoder提出履歴の取得 -------------------------------------------------
--
-- AtCoder Problems API (kenkoooo.com) を使用。
-- 短時間の連続アクセスは避けるため、呼び出し側でセッション内キャッシュすること。

function M.fetch_submissions(username, from_second)
  username = username or M.config.atcoder_username

  if not username or username == "" then
    return nil, "atcoder_username が設定されていません"
  end

  local url = string.format(
    "https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions?user=%s&from_second=%d",
    username,
    from_second or 0
  )

  local result = vim.fn.system({ "curl", "-s", "-m", "10", url })

  if vim.v.shell_error ~= 0 then
    return nil, "提出履歴の取得に失敗しました: curlエラー"
  end

  local ok, decoded = pcall(vim.json.decode, result)
  if not ok or type(decoded) ~= "table" then
    return nil, "提出履歴のJSON解析に失敗しました"
  end

  return decoded, nil
end

--- スナップショットと提出履歴の照合 ---------------------------------------
--
-- 各問題ごとに、archiveスナップショット(saved_at昇順)と、
-- AtCoderの提出(epoch_second昇順、同一問題ID)を貪欲に対応付ける。
-- 対応した提出が "AC" のスナップショットだけを AC情報として残す。
--
-- 戻り値: { [problem_id] = { {at, archive_path, assisted}, ... 昇順 }, ... }

function M.match_and_collect_ac(entries, submissions, opts)
  opts = opts or {}
  local before = opts.match_window_before or M.config.match_window_before
  local after = opts.match_window_after or M.config.match_window_after

  -- 問題IDごとにグループ化
  local entries_by_problem = {}
  for _, e in ipairs(entries) do
    entries_by_problem[e.problem_id] = entries_by_problem[e.problem_id] or {}
    table.insert(entries_by_problem[e.problem_id], e)
  end

  local subs_by_problem = {}
  for _, s in ipairs(submissions or {}) do
    -- AtCoder Problems API の言語表記に "Nim" を含むものだけを対象にする
    if type(s.language) == "string" and s.language:find("Nim") then
      subs_by_problem[s.problem_id] = subs_by_problem[s.problem_id] or {}
      table.insert(subs_by_problem[s.problem_id], s)
    end
  end

  for _, list in pairs(subs_by_problem) do
    table.sort(list, function(a, b)
      return a.epoch_second < b.epoch_second
    end)
  end

  local result = {}

  for problem_id, snaps in pairs(entries_by_problem) do
    table.sort(snaps, function(a, b)
      return a.saved_at < b.saved_at
    end)

    local subs = subs_by_problem[problem_id] or {}
    local used = {}
    local acs = {}

    for _, snap in ipairs(snaps) do
      local best_idx, best_diff = nil, nil

      for i, sub in ipairs(subs) do
        if not used[i] then
          local diff = sub.epoch_second - snap.saved_at

          if diff >= -before and diff <= after then
            if best_diff == nil or diff < best_diff then
              best_idx, best_diff = i, diff
            end
          end
        end
      end

      if best_idx then
        used[best_idx] = true
        local sub = subs[best_idx]

        if sub.result == "AC" then
          table.insert(acs, {
            at = sub.epoch_second,
            archive_path = snap.path,
            assisted = M.is_assisted(snap.path),
          })
        end
      end
    end

    if #acs > 0 then
      table.sort(acs, function(a, b) return a.at < b.at end)
      result[problem_id] = acs
    end
  end

  return result
end

--- 自力/他力判定 --------------------------------------------------------
--
-- ファイル先頭付近に "#+" で始まる行があれば他力(assisted)とみなす。

function M.is_assisted(path)
  local lines = read_lines(path, M.config.assisted_scan_lines)

  for _, line in ipairs(lines) do
    if line:match("^%s*#%+") then
      return true
    end
  end

  return false
end

--- 推薦アルゴリズム -----------------------------------------------------
--
-- 問題ごとの直近AC間隔(base_gap)を求め、
-- 直近ACが自力なら2倍、他力なら半分にした値を、
-- 直近AC時刻に足したものを次回推薦時刻(recommend_at)とする。
-- AC回数が1回だけの問題は、他問題のbase_gapの平均を用いる。

local function base_gap(acs)
  if #acs < 2 then
    return nil
  end
  return acs[#acs].at - acs[#acs - 1].at
end

local function mean(values)
  if #values == 0 then
    return nil
  end
  local total = 0
  for _, v in ipairs(values) do
    total = total + v
  end
  return total / #values
end

function M.build_queue(ac_by_problem)
  local gaps = {}
  for _, acs in pairs(ac_by_problem) do
    local g = base_gap(acs)
    if g then
      table.insert(gaps, g)
    end
  end

  local fallback = mean(gaps)

  local queue = {}

  for problem_id, acs in pairs(ac_by_problem) do
    local latest = acs[#acs]
    local gap = base_gap(acs) or fallback

    if gap == nil then
      -- 全問題がAC1回だけの場合はフォールバックも存在しないため対象外
      goto continue
    end

    if latest.assisted then
      gap = gap / 2
    else
      gap = gap * 2
    end

    table.insert(queue, {
      problem_id = problem_id,
      latest_ac_at = latest.at,
      assisted = latest.assisted,
      base_gap = base_gap(acs) or fallback,
      used_fallback = base_gap(acs) == nil,
      recommend_at = latest.at + gap,
      ac_count = #acs,
    })

    ::continue::
  end

  table.sort(queue, function(a, b)
    return a.recommend_at < b.recommend_at
  end)

  return queue
end

--- エントリーポイント ---------------------------------------------------
--
-- archiveを走査し、AtCoder提出履歴を取得・照合し、推薦キューを返す。
-- 副作用(ファイル書き込み等)は一切ない。

function M.suggest(opts)
  opts = opts or {}
  local dir = opts.archive_dir or M.config.archive_dir

  local entries = M.scan_archive(dir)
  if #entries == 0 then
    return {}, "archiveにスナップショットがありません"
  end

  local oldest = entries[1].saved_at
  local from_second = math.max(0, oldest - 60)

  local submissions, err = M.fetch_submissions(
    opts.atcoder_username or M.config.atcoder_username,
    from_second
  )

  if not submissions then
    return {}, err
  end

  local ac_by_problem = M.match_and_collect_ac(entries, submissions, opts)
  local queue = M.build_queue(ac_by_problem)

  return queue, nil
end

return M
