-- atcoder-nim.review: 隣の cp-solved-log に溜まった提出の記録から、復習する順番を提案する
-- 状態は cp-solved-log のルートのファイル名だけ。問題ID_日時_判定.nim の形
-- 提供するコマンド: :CpSuggest(復習の推薦順)、:CpArchive(全記録)、:CpHistory(今の問題の履歴)、:CpOpenAnswer(昇格した解答を開く)

-- このモジュールの公開テーブルを用意する
local M = {}

-- 判定として認める文字列(AC+ は、ヒントや解説を見て解いた AC)
local verdicts = {
  AC = true, ["AC+"] = true, WA = true, TLE = true,
  RE = true, CE = true, MLE = true, OLE = true, IE = true,
}

-- 保存先(cp-solved-log)の場所と、プロジェクトの場所(setup で入れる)
local archive_dir, project_root

-- ファイル名を読み取って、内容を表にして返す(対象外のファイル名なら nil)
local function parse_filename(name)
  -- 「問題ID_年-月-日_時-分-秒」+「判定の部分」+ ".nim" の形に分ける
  local id, y, mo, d, h, mi, s, suffix = name:match("^(.+)_(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)(.-)%.nim$")
  if id then
    -- 日時を秒数(時刻の値)に変える
    local at = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    -- 存在しない日時(13月など)は、変換し直すと元の文字列と合わないので、対象外にする
    if os.date("%Y-%m-%d_%H-%M-%S", at) ~= ("%s-%s-%s_%s-%s-%s"):format(y, mo, d, h, mi, s) then return nil end
    -- 判定の部分("_AC" など)から、判定の文字列を取り出す
    local verdict = suffix:match("^_([A-Z]+%+?)$")
    -- 判定の部分があるのに、認めた判定でなければ対象外にする
    if suffix ~= "" and not verdicts[verdict] then return nil end
    -- 提出の記録として返す
    return { problem_id = id, saved_at = at, kind = "snapshot", verdict = verdict, name = name }
  end
  -- 日時の無い「問題ID.nim」は、昇格した解答として扱う
  local canonical = name:match("^([%w_]+)%.nim$")
  if canonical then return { problem_id = canonical, kind = "canonical", name = name } end
  -- どちらでもなければ nil を返す
end

-- cp-solved-log を調べ、昇格した解答と、判定の付いた提出を新しい順に並べて返す
local function scan_archive()
  -- フォルダが無ければ空にする
  if vim.fn.isdirectory(archive_dir) ~= 1 then return {} end
  -- 結果を貯める表
  local entries = {}
  -- フォルダ内のファイルを1つずつ調べる
  for name, kind in vim.fs.dir(archive_dir) do
    -- ファイル名を読み取る
    local e = kind == "file" and parse_filename(name)
    -- 昇格した解答か、判定の付いた提出だけを残す(判定待ちのものは除く)
    if e and (e.kind == "canonical" or e.verdict) then
      e.path = archive_dir .. "/" .. name
      table.insert(entries, e)
    end
  end
  -- 昇格した解答を先に、次に提出を新しい順に、同じ時刻ならファイル名順に並べる
  table.sort(entries, function(a, b)
    if a.kind ~= b.kind then return a.kind == "canonical" end
    if a.saved_at ~= b.saved_at then return a.saved_at > b.saved_at end
    return a.name < b.name
  end)
  return entries
end

-- 問題ごとに AC(AC+ を含む)の時刻を、古い順に並べて返す
local function collect_ac(entries)
  -- 問題ID -> AC の一覧
  local groups = {}
  -- 提出の記録のうち AC のものだけを、問題ごとに集める
  for _, e in ipairs(entries) do
    if e.kind == "snapshot" and (e.verdict == "AC" or e.verdict == "AC+") then
      groups[e.problem_id] = groups[e.problem_id] or {}
      table.insert(groups[e.problem_id], { at = e.saved_at, path = e.path, assisted = e.verdict == "AC+" })
    end
  end
  -- 各問題の AC を、古い順(同じ時刻ならファイルの場所順)に並べる
  for _, acs in pairs(groups) do
    table.sort(acs, function(a, b)
      if a.at ~= b.at then return a.at < b.at end
      return a.path < b.path
    end)
  end
  return groups
end

-- 直近2回の AC の間隔(秒)を返す(AC が1回しか無ければ nil)
local function base_gap(acs)
  if #acs >= 2 then return acs[#acs].at - acs[#acs - 1].at end
end

-- 復習する日時を計算し、早い順に並べて返す
-- 間隔は直近2回の AC の間隔。1回しか AC が無い問題は、他の問題の間隔の平均で代用する
-- 自力で解いた AC なら間隔の2倍、ヒントを見た AC+ なら半分後に復習する
local function build_queue(groups)
  -- 問題IDを並べる
  local ids = vim.tbl_keys(groups)
  table.sort(ids)
  -- 間隔を持つ問題の平均を求める
  local total, count = 0, 0
  for _, id in ipairs(ids) do
    local gap = base_gap(groups[id])
    if gap then total, count = total + gap, count + 1 end
  end
  local fallback = count > 0 and total / count or nil
  -- 問題ごとに、復習する日時を求める
  local queue = {}
  for _, id in ipairs(ids) do
    local acs = groups[id]
    local latest = acs[#acs]
    local gap = base_gap(acs) or fallback
    -- 間隔が決められない問題は、提案に含めない
    if gap then
      table.insert(queue, {
        problem_id = id, ac_count = #acs, assisted = latest.assisted,
        recommend_at = latest.at + gap * (latest.assisted and 0.5 or 2),
      })
    end
  end
  -- 復習する日時が早い順に並べる(同じなら問題ID順)
  table.sort(queue, function(a, b)
    if a.recommend_at ~= b.recommend_at then return a.recommend_at < b.recommend_at end
    return a.problem_id < b.problem_id
  end)
  return queue
end

-- 今のバッファの問題IDを返す(分からなければ nil)
local function current_problem_id()
  -- 復習から開いたバッファには、問題IDが記録してある
  if vim.b.cp_problem_id then return vim.b.cp_problem_id end
  -- 無ければ、ファイル名から読み取る(cp-solved-log のファイルを開いているとき)
  local parsed = parse_filename(vim.fn.expand("%:t"))
  return parsed and parsed.problem_id
end

-- 一覧の検索画面を開く。select を渡すと、Enterで選んだ項目に対して実行する。preview が true ならファイルを表示する
local function picker(title, entries, select, preview)
  -- 項目が無ければ、知らせて終わる
  if #entries == 0 then
    vim.notify("表示する項目がありません")
    return
  end
  -- 必要なTelescopeのモジュールを読み込む
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  -- 検索画面を作って開く
  require("telescope.pickers").new({}, {
    prompt_title = title,
    -- 上から順に表示する(並べ替えはしない)
    sorting_strategy = "ascending",
    finder = require("telescope.finders").new_table({
      results = entries,
      -- 項目1件を、Telescopeが扱う形に変える
      entry_maker = function(e) return { value = e, display = e.name, ordinal = e.name, path = e.path } end,
    }),
    -- 空白区切りの語がすべて含まれる項目だけを残し、順番は変えない
    sorter = require("telescope.sorters").new({
      scoring_function = function(_, prompt, line)
        for word in prompt:lower():gmatch("%S+") do
          if not line:lower():find(word, 1, true) then return -1 end
        end
        return 1
      end,
    }),
    -- ファイルの中身を表示するかどうか
    previewer = preview and require("telescope.config").values.file_previewer({}) or false,
    -- Enterを押した時の動作を差し替える
    attach_mappings = function(bufnr)
      if select then
        actions.select_default:replace(function()
          -- 選ばれた項目が無ければ何もしない
          local entry = state.get_selected_entry()
          if not entry then return end
          -- 画面を閉じてから、選んだ項目を処理する
          actions.close(bufnr)
          vim.schedule(function() select(entry.value) end)
        end)
      end
      return true
    end,
  }):find()
end

-- work/問題ID.nim を開く(無ければ、template.nim を読み込むだけの内容で作る)
local function open_work(id)
  -- 対応する問題IDの形(abc123a など)でなければ開かない
  if not id:match("^[a-z]+%d+[a-z]$") then
    vim.notify("対応していない問題ID: " .. id, vim.log.levels.WARN)
    return
  end
  -- work フォルダを用意する
  local dir = project_root .. "/work"
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. id .. ".nim"
  -- ファイルがまだ無く、バッファにも読み込まれていなければ、新規に作る
  local is_new = not vim.uv.fs_stat(path) and vim.fn.bufloaded(path) == 0
  -- ファイルを開き、問題IDを記録する
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.b.cp_problem_id = id
  -- 新規なら、template.nim を読み込むだけの内容にして保存する
  if is_new then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'include "template.nim"', "" })
    vim.cmd.write()
  end
end

-- 昇格した解答(cp-solved-log/問題ID.nim)を、縦に分割して開く
local function open_canonical()
  -- 今の問題IDを調べる
  local id = current_problem_id()
  if not id then return end
  -- 昇格した解答のファイルの場所
  local path = archive_dir .. "/" .. id .. ".nim"
  -- 無ければ、知らせて終わる
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify(id .. " のPromote版はありません")
    return
  end
  -- 縦に分割して開き、問題IDを記録する
  vim.cmd.vsplit(vim.fn.fnameescape(path))
  vim.b.cp_problem_id = id
end

-- :CpSuggest: 復習する日時が早い順に問題を並べ、選ぶと work/ で開く
local function suggest_picker()
  -- 提出の記録から、復習の順番を作る
  local groups = collect_ac(scan_archive())
  local queue = build_queue(groups)
  -- AC の記録はあるのに、間隔が決められる問題が1つも無い場合は、理由を知らせる
  if #queue == 0 and next(groups) then
    vim.notify("AC間隔の平均を計算できません。ACが2回以上ある問題が必要です", vim.log.levels.WARN)
    return
  end
  -- 一覧に表示する文字列(問題ID、復習する日時、AC か AC+ か、AC の回数)を作る
  for _, e in ipairs(queue) do
    e.name = ("%s  %s  %s  AC x%d"):format(e.problem_id, os.date("%Y-%m-%d %H:%M:%S", math.floor(e.recommend_at)), e.assisted and "AC+" or "AC", e.ac_count)
  end
  -- 選ぶと、その問題を work/ で開く
  picker("CP 復習推薦順", queue, function(e) open_work(e.problem_id) end, false)
end

-- :CpArchive: cp-solved-log の全記録を表示する
local function archive_picker()
  picker("CP Archive", scan_archive(), nil, true)
end

-- :CpHistory: 今の問題の記録だけを表示する
local function history_picker()
  -- 今の問題IDを調べる
  local id = current_problem_id()
  if not id then
    vim.notify("問題IDを特定できません", vim.log.levels.WARN)
    return
  end
  -- 全記録から、この問題のものだけを選んで表示する
  picker(id .. " の履歴", vim.tbl_filter(function(e) return e.problem_id == id end, scan_archive()), nil, true)
end

-- .nvim.lua から呼ぶ入口。コマンドを登録する
function M.setup(root)
  -- 提出・昇格と同じ、隣の cp-solved-log を復習の参照先にする
  project_root = root
  archive_dir = vim.fn.fnamemodify(root, ":h") .. "/cp-solved-log"
  -- コマンドを登録する(読み込み直しても上書きできるよう force を付ける)
  vim.api.nvim_create_user_command("CpSuggest", suggest_picker, { force = true })
  vim.api.nvim_create_user_command("CpArchive", archive_picker, { force = true })
  vim.api.nvim_create_user_command("CpHistory", history_picker, { force = true })
  vim.api.nvim_create_user_command("CpOpenAnswer", open_canonical, { force = true })
end

-- 公開テーブルを返す
return M
