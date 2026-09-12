-- atcoder-nim.telescope_cp — 競プロ資産を横断するための3つのTelescope入口
--
--   <leader>fa  cp-solved-log を live_grep する（読み取り専用。実例を読むだけ）
--   <leader>fi  cp-nim-lib / nim-acl からファイルを選び、
--               include / import 文を現在バッファへ挿入する
--   <leader>fs  Snippet（LuaSnip） + StdLib（標準ライブラリ + nim-acl + cp-nim-lib）
--               を fuzzy 検索して、現在カーソル位置へ展開する
--   <C-g>s      <leader>fs と同じ検索を、インサートモードのまま起動する
--
-- UFCS呼び出しの判定は「検索語に . を付けるか」ではなく、
-- 「Telescopeを開いた瞬間、カーソルの直前が . かどうか」で自動判定する。
-- 例:
--   echo a.| で <C-g>s を押し sum を選ぶ  -> echo a.sum()
--   echo | で <C-g>s を押し sum を選ぶ    -> echo sum(x)
--
-- .nvim/scope_dirs.txt はもう使わない。
-- 検索対象のリポジトリはここで直接パスを組み立てる。

local M = {}

local qf_session = require("util.quickfix_session")
-- StdLib候補(標準ライブラリ + nim-acl + cp-nim-lib)を
-- ripgrepで拾い、呼び出しテンプレート文字列に変換するためのヘルパー。
local lib_scan = require("atcoder-nim.nim_lib_scan")

-- cp-nim-lib / cp-solved-log / nim-acl は atcoder-nim-env と同じ階層に
-- sibling directory として置く運用なので、project_root の一つ上から辿る。
local function sibling(project_root, name)
  return vim.fn.fnamemodify(project_root, ":h") .. "/" .. name
end

-- カーソルの直前1文字が "." かどうかを見て、UFCS呼び出しを自動判定する。
-- nvim_win_get_cursor の col は「カーソル位置より前にあるバイト数」なので、
-- line:sub(col, col) がちょうどカーソルの左隣の1文字になる。
local function cursor_is_after_dot()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  return col > 0 and line:sub(col, col) == "."
end

-- スペース区切り語をすべて単純な部分一致(plain find)で判定するAND sorter。
-- fuzzyスコアリング(fzf系)は内部の位置計算がバイト前提のため、
-- マルチバイト文字(日本語)だとバイト数と文字数がズレて判定が不安定になる。
-- plain=trueの部分一致はバイト列としての一致判定なので、
-- 日本語・英字どちらでも安定して動く。
-- search_library / search_snippets の両方で共有する。
local function and_substring_sorter()
  local sorters = require("telescope.sorters")

  return sorters.new({
    scoring_function = function(_, prompt, line)
      if prompt == "" then
        return 1
      end

      local target = line:lower()
      for word in prompt:gmatch("%S+") do
        if not target:find(word:lower(), 1, true) then
          return -1 -- ripgrep側の規約と同じ: 1語でも欠けたら不採用
        end
      end

      return 1
    end,
  })
end

-- ============================================================
-- <leader>fa: 過去解答を読む（read-only）
-- ============================================================

local function setup_readonly_solved_log(solved_log_root)
  -- Telescopeから開いた場合に限らず、どの経路で開いても
  -- cp-solved-log 配下のファイルは誤編集を防ぐため読み取り専用にする。
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = vim.api.nvim_create_augroup("CpSolvedLogReadonly", { clear = true }),
    pattern = solved_log_root .. "/*",
    callback = function(ev)
      vim.bo[ev.buf].readonly = true
      vim.bo[ev.buf].modifiable = false
    end,
  })
end

local function search_solved_log(solved_log_root)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")
  local sorters = require("telescope.sorters")

  -- "h w" のようなスペース区切り入力を、
  -- rg -P 用の AND lookahead パターンに変換する。
  -- 例: "h w" -> "^(?=.*h)(?=.*w)"
  local function build_and_pattern(prompt)
    local words = {}
    for w in prompt:gmatch("%S+") do
      table.insert(words, w)
    end
    if #words == 0 then
      return nil
    end
    local lookaheads = {}
    for _, w in ipairs(words) do
      table.insert(lookaheads, ("(?=.*%s)"):format(w))
    end
    -- 行頭 "^" を付けることで、行内の全列に対する冗長なゼロ幅マッチを1件に収束させる。
    -- これが無いと、同じ行のマッチ可能な列ぶんだけヒットが重複して増える。
    return "^" .. table.concat(lookaheads, "")
  end

  local finder = finders.new_job(function(prompt)
    local pattern = build_and_pattern(prompt)
    if not pattern then
      return nil
    end

    -- 入力のたびにこの関数が呼ばれ、組み立てたコマンド配列を
    -- そのまま外部プロセスとして実行する。戻り値がrgコマンドそのもの。
    return {
      "rg",
      "--vimgrep",
      "--no-heading",
      "--color=never",
      "--smart-case",
      "-P", -- PCRE2を有効化（先読みを使うために必須）
      "-e",
      pattern,
      "--glob",
      "*.nim",
    }
  end, make_entry.gen_from_vimgrep({ cwd = solved_log_root }), nil, solved_log_root)

  pickers.new({}, {
    prompt_title = "Solved log (read-only, AND search)",
    finder = finder,
    previewer = conf.grep_previewer({ cwd = solved_log_root }),
    sorter = sorters.empty(),
  }):find()
end

-- ============================================================
-- <leader>fi: ライブラリを検索して include / import を挿入する
-- ============================================================

local function generic_previewer()
  local previewers = require("telescope.previewers")
  local action_state = require("telescope.actions.state")

  local syntax_by_ext = {
    nim = "nim",
    md = "markdown",
    lua = "lua",
  }

  -- 現在の検索ワードのうち、ファイル本文中で最初にヒットした行番号(1-based)を返す。
  -- 見つからなければ nil。
  local function find_first_hit_line(lines, prompt)
    for word in prompt:gmatch("%S+") do
      local lw = word:lower()
      for i, line in ipairs(lines) do
        if line:lower():find(lw, 1, true) then
          return i
        end
      end
    end
    return nil
  end

  return previewers.new_buffer_previewer({
    title = "File Preview",
    get_buffer_by_name = function(_, entry)
      return entry.path
    end,
    define_preview = function(self, entry, status)
      local path = entry.path
      local lines = vim.fn.readfile(path)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      -- filetype ではなく syntax を使う。FileType autocmdを発火させないため。
      local ext = vim.fn.fnamemodify(path, ":e")
      local syn = syntax_by_ext[ext]
      if syn then
        vim.bo[self.state.bufnr].syntax = syn
      end

      -- markdown の **bold** / _italic_ を隠して見せるのはプレビュー(見る)時だけ。
      if ext == "md" then
        vim.wo[self.state.winid].conceallevel = 2
        vim.wo[self.state.winid].concealcursor = "nc"
      else
        vim.wo[self.state.winid].conceallevel = 0
      end

      -- 検索ワードがファイル本文にヒットしていたら、その行にジャンプする。
      -- ファイル名しかヒットしていない場合は先頭のままにする。
      local prompt = ""
      if status and status.prompt_bufnr and vim.api.nvim_buf_is_valid(status.prompt_bufnr) then
        local ok, picker = pcall(action_state.get_current_picker, status.prompt_bufnr)
        if ok and picker then
          prompt = picker:_get_prompt() or ""
        end
      end

      if prompt ~= "" then
        local target_line = find_first_hit_line(lines, prompt)
        if target_line then
          local bufnr = self.state.bufnr
          local winid = self.state.winid

          -- 1ティック遅らせる。
          -- define_preview 実行直後は、winid がまだ前の選択項目のバッファを
          -- 表示していることがあり、その状態で行番号を指定すると
          -- "Invalid cursor line: out of range" になる（上下を素早く選ぶと発生）。
          vim.schedule(function()
            if not vim.api.nvim_win_is_valid(winid) then
              return
            end
            -- ウィンドウが実際にこのプレビュー用バッファを表示しているかを確認する。
            -- 選択が先に進んでいたら、古いジャンプ予約は捨てる。
            if vim.api.nvim_win_get_buf(winid) ~= bufnr then
              return
            end

            local last_line = math.max(vim.api.nvim_buf_line_count(bufnr), 1)
            local safe_line = math.min(target_line, last_line)

            pcall(vim.api.nvim_win_set_cursor, winid, { safe_line, 0 })
            pcall(vim.api.nvim_win_call, winid, function()
              vim.cmd("normal! zz")
            end)
          end)
        end
      end
    end,
  })
end

-- ファイル内容を検索対象文字列として読み込む。
-- コメント（日本語含む）まで ordinal に混ぜることで、
-- ファイル名だけでは引っかからない「機能名でのあいまい検索」を可能にする。
-- 表示(display)には使わない。検索用の裏側の文字列にだけ使う。
local function read_file_text(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return ""
  end
  return table.concat(lines, " ")
end

-- cp-nim-lib と nim-acl、出どころが違う2つのソースを
-- 一つの候補リストにまとめて検索できるようにする。
-- 選択後にどちらの宣言文を挿入するかは、候補が持つ origin/mode で判定する。
local function collect_library_entries(cp_nim_lib_root, nim_acl_root)
  local entries = {}

  -- --- cp-nim-lib: 自作ライブラリ ---
  -- template.nim は毎回すでに include 済みなので候補から除く。
  if vim.fn.isdirectory(cp_nim_lib_root) == 1 then
    local files = vim.fs.find(function(name)
      return name:match("%.nim$") and name ~= "template.nim"
    end, {
      path = cp_nim_lib_root,
      type = "file",
      limit = math.huge,
    })

    for _, path in ipairs(files) do
      local rel = path:sub(#cp_nim_lib_root + 2) -- 先頭の "/" を含めて除去
      table.insert(entries, {
        path = path,
        display = rel .. "  [cp-nim-lib]",
        ordinal = rel .. " " .. read_file_text(path),
        origin = "cp-nim-lib",
        mode = "include",
        declaration = ('include "%s"'):format(rel),
      })
    end
  end

  -- --- nim-acl: 参照用ローカルコピー（本体 src/ とノート notes/ の両方） ---
  -- 提出時のimport解決には使わないが、検索窓には両方を出し、
  -- どちらを選んでも同じ import atcoder/<name> を挿入する。
  local acl_src = nim_acl_root .. "/src"
  local acl_notes = nim_acl_root .. "/notes"

  local function add_acl_entries(root, origin_label)
    if vim.fn.isdirectory(root) ~= 1 then
      return
    end

    local pattern = origin_label == "nim-acl notes" and "%.md$" or "%.nim$"
    local files = vim.fs.find(function(name)
      return name:match(pattern)
    end, {
      path = root,
      type = "file",
      limit = math.huge,
    })

    for _, path in ipairs(files) do
      local name = vim.fn.fnamemodify(path, ":t:r") -- 拡張子を除いたファイル名
      local rel = path:sub(#root + 2)
      table.insert(entries, {
        path = path,
        display = rel .. ("  [%s]"):format(origin_label),
        ordinal = rel .. " atcoder/" .. name .. " " .. read_file_text(path),
        origin = origin_label,
        mode = "import",
        declaration = ("import atcoder/%s"):format(name),
      })
    end
  end

  add_acl_entries(acl_src, "nim-acl")
  add_acl_entries(acl_notes, "nim-acl notes")

  return entries
end

-- 現在バッファの include / import 群の末尾に一行追加する。
-- 既に同じ宣言があれば何もしない（重複挿入の防止）。
local function add_declaration_once(bufnr, declaration)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for _, line in ipairs(lines) do
    if vim.trim(line) == declaration then
      vim.notify("Already declared: " .. declaration, vim.log.levels.INFO)
      return
    end
  end

  local insert_at = 0
  for i, line in ipairs(lines) do
    if line:match("^%s*include%s+") or line:match("^%s*import%s+") then
      insert_at = i
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { declaration })
end

local function search_library(cp_nim_lib_root, nim_acl_root)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = collect_library_entries(cp_nim_lib_root, nim_acl_root)
  local bufnr = vim.api.nvim_get_current_buf()

  pickers.new({
    previewer = generic_previewer(),
    -- Results : Preview がおおよそ 6:4 になるよう、プレビュー側の幅を明示する。
    layout_strategy = "horizontal",
    layout_config = {
      preview_width = 0.55,
    },
  }, {
    prompt_title = "Include / Import library",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
          -- generic_previewer が entry.path を読むために必要。
          path = entry.path,
        }
      end,
    }),
    sorter = and_substring_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        vim.schedule(function()
          add_declaration_once(bufnr, selection.value.declaration)
        end)
      end)

      -- プレビューのスクロールを明示的に割り当てる
      -- （グローバル設定で上書きされていても、このpickerでは確実に効かせる）。
      map({ "i", "n" }, "<C-d>", actions.preview_scrolling_down)
      map({ "i", "n" }, "<C-u>", actions.preview_scrolling_up)

      return true
    end,
  }):find()
end

-- ============================================================
-- <leader>fs / <C-g>s: Snippet + StdLib を fuzzy検索して展開する
-- ============================================================

-- このpickerに渡す候補は2種類ある。
--   kind = "snippet" … LuaSnipのSnippetオブジェクトそのもの
--   kind = "stdlib"  … ripgrepで拾った関数シグネチャから作った疑似エントリ
--                       （標準ライブラリ + nim-acl + cp-nim-libをまとめてこう呼ぶ）
-- 表示・検索・展開のすべてで、この kind によって処理を分ける。

-- Results の表示は name / description の2カラム固定。
-- description は今後ブロック構文の増加に伴って埋まっていく前提の列なので、
-- 空でも "(no description)" のような代替文字列は入れず、空欄のまま出す。
local entry_display = require("telescope.pickers.entry_display")

local snippet_displayer = entry_display.create({
  separator = " ",
  items = {
    { width = 24 },
    { remaining = true },
  },
})

-- item は LuaSnip の Snippet オブジェクトか、StdLib用の疑似エントリのいずれか。
local function snippet_name_of(item)
  if item.kind == "stdlib" then
    return item.display_name
  end
  return item.name or item.trigger or ""
end

-- LuaSnip の VSCode形式ローダーは、JSON側に description が無いスニペットに対して
-- dscr にスニペット名（≒trigger と同一の文字列）を自動で埋めてしまう。
-- そのため dscr が name / trigger と一致する場合は「実質未設定」とみなし、
-- 空欄として扱う（本当のdescriptionが入っている場合だけ表示する）。
-- StdLib側は元のシグネチャ行そのものをdescriptionとして常に表示する。
local function snippet_description_of(item)
  if item.kind == "stdlib" then
    return item.description
  end

  local desc = item.dscr or ""
  if type(desc) == "table" then
    desc = table.concat(desc, " ")
  end

  local name = snippet_name_of(item)
  local trig = item.trigger or ""

  if desc == name or desc == trig then
    return ""
  end

  return desc
end

local function snippet_ordinal(item)
  if item.kind == "stdlib" then
    return table.concat(
      {
        item.trigger or "",
        item.display_name or "",
        item.description or "",
        item.signature or "",
        item.library or "",
      },
      " "
    )
  end

  return table.concat(
    {
      item.trigger or "",
      snippet_name_of(item),
      snippet_description_of(item),
    },
    " "
  )
end

local function snippet_display(entry)
  local item = entry.value
  return snippet_displayer({ snippet_name_of(item), snippet_description_of(item) })
end

-- 右プレビューを長い行でも折り返して全文見せる。
-- wrap: 折り返し自体を有効化。
-- linebreak: 単語の途中ではなく空白等の区切りで折り返す。
-- breakindent: 折り返し後の行を元の行のインデントに揃える。
-- showbreak: 折り返しで続く行だと視覚的にわかるようにする。
local function enable_preview_wrap(winid)
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].breakindent = true
  vim.wo[winid].showbreak = "↳ "
end

local function snippet_previewer(get_ufcs)
  local previewers = require("telescope.previewers")

  return previewers.new_buffer_previewer({
    title = "Preview",
    define_preview = function(self, entry, _)
      local item = entry.value
      local lines = {}

      -- 上段: Name
      table.insert(lines, "Name: " .. snippet_name_of(item))
      table.insert(lines, "")

      -- 中段: description（未設定なら空欄のまま。trigger を代わりに出さない）
      table.insert(lines, snippet_description_of(item))
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")

      -- 下段: body（プレビューの主役）
      if item.kind == "stdlib" then
        local ufcs = get_ufcs and get_ufcs() or false
        local body = lib_scan.build_snippet_body(item.source_text, { ufcs = ufcs })

        if body then
          table.insert(lines, body)
        elseif ufcs then
          table.insert(lines, "(UFCS不可: レシーバに渡せる引数がありません)")
        else
          table.insert(lines, "(snippet生成に失敗しました)")
        end

        table.insert(lines, "")
        table.insert(lines, item.signature or "")
        table.insert(lines, "")

        if item.library then
          table.insert(lines, "library: " .. item.library)
        end
      else
        local ok, docstring = pcall(function()
          return item:get_docstring()
        end)

        if ok and docstring then
          if type(docstring) == "string" then
            docstring = vim.split(docstring, "\n")
          end
          vim.list_extend(lines, docstring)
        else
          table.insert(lines, "(preview unavailable)")
        end
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      -- filetype ではなく syntax を使う。
      -- filetype を設定すると FileType autocmd が発火し、Nimのftplugin側が
      -- 「ファイル名の無いバッファ」を検知してエラーを出す。
      -- プレビューバッファは常に無名バッファなので、上下移動のたびに
      -- define_preview が呼ばれエラーが積み重なっていた。
      -- syntax なら色付けだけ行われ、FileType autocmd は発火しない。
      vim.bo[self.state.bufnr].syntax = "nim"

      enable_preview_wrap(self.state.winid)
    end,
  })
end

local function normalize_stdlib(item)
  -- source_text を保持しておき、選択時にUFCSかどうかで
  -- build_snippet_body を呼び分けられるようにする。
  local normal_body = lib_scan.build_snippet_body(item.text)
  if not normal_body then
    return nil
  end

  local name = normal_body:match("^([%w_]+)%(") or item.text

  return {
    kind = "stdlib",

    -- 左側リストの名前列
    trigger = name,
    display_name = name,

    -- 右側・左側の説明列に表示する ## コメント本文
    description = item.doc,

    -- 元のNim宣言。右プレビューで確認するため保持する。
    signature = item.text,

    -- UFCS判定時にbuild_snippet_bodyへ渡す元テキスト。
    source_text = item.text,

    -- 通常呼び出し用に確定した本文（UFCS時はここを使わない）。
    snippet_body = normal_body,

    -- 定義位置
    file = item.file,
    lnum = item.lnum,

    -- /home/... のようなフルパスではなく std/strutils 等を表示する
    library = lib_scan.module_label(item.file),
  }
end

-- 展開直後に lsp_signature の引数ガイドを手動で開く。
-- 展開されたテキストの "(" はキー入力イベントではないため、
-- lsp_signatureのトリガー文字監視には引っからない。ここで明示的に呼ぶ。
local function trigger_signature_help()
  vim.schedule(function()
    local ok, lsp_signature = pcall(require, "lsp_signature")
    if ok then
      lsp_signature.toggle_float_win()
    else
      vim.lsp.buf.signature_help()
    end
  end)
end

-- opts.ufcs: Telescopeを開いた瞬間のカーソル直前が "." だったかどうか。
-- true の場合、StdLib候補は「先頭引数を消費済みとして呼ぶ」前提で展開する。
-- 通常のLuaSnip Snippetは元々レシーバの概念を持たないため、
-- UFCSモードでは検索結果から除外し、StdLibだけを候補にする。
local function search_snippets(opts)
  opts = opts or {}
  local ufcs = opts.ufcs == true

  local luasnip = require("luasnip")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- ripgrepで標準ライブラリ + nim-acl + cp-nim-lib を走査し、
  -- 呼び出しテンプレート付きの疑似エントリに変換する。
  local stdlib_items = {}
  for _, raw in ipairs(lib_scan.scan()) do
    local normalized = normalize_stdlib(raw)
    if normalized then
      table.insert(stdlib_items, normalized)
    end
  end

  local results = {}

  if not ufcs then
    local snippets = luasnip.get_snippets(vim.bo.filetype) or {}
    vim.list_extend(results, snippets) -- kind未設定 = 通常のLuaSnip Snippetオブジェクト
  end

  vim.list_extend(results, stdlib_items) -- kind="stdlib"

  pickers.new({
    previewer = snippet_previewer(function()
      return ufcs
    end),
    -- 画面幅を左右半々（Results : Preview = 5:5）にする。
    layout_strategy = "horizontal",
    layout_config = {
      preview_width = 0.5,
    },
  }, {
    prompt_title = ufcs and "Snippet + StdLib  [UFCS]" or "Snippet + StdLib",
    finder = finders.new_table({
      results = results,
      entry_maker = function(item)
        return {
          value = item,
          display = snippet_display,
          ordinal = snippet_ordinal(item),
        }
      end,
    }),
    -- description列が今後日本語で増える前提なので、fuzzy(generic_sorter)ではなく
    -- search_library と同じAND部分一致sorterに揃える。
    sorter = and_substring_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        vim.schedule(function()
          local item = selection.value

          if item.kind == "stdlib" then
            local body = ufcs
              and lib_scan.build_snippet_body(item.source_text, { ufcs = true })
              or item.snippet_body

            if not body then
              vim.notify(
                "UFCSでは呼べません（レシーバに渡せる引数がありません）: " .. item.display_name,
                vim.log.levels.WARN
              )
              return
            end

            luasnip.lsp_expand(body)
          else
            -- 通常のLuaSnip Snippetオブジェクトはそのまま展開する。
            luasnip.snip_expand(item)
          end

          trigger_signature_help()
        end)
      end)

      map({ "i", "n" }, "<C-d>", actions.preview_scrolling_down)
      map({ "i", "n" }, "<C-u>", actions.preview_scrolling_up)

      return true
    end,
  }):find()
end

-- ============================================================
-- setup: .nvim.lua から一行で呼び出すための入口
-- ============================================================

function M.setup(project_root)
  local cp_solved_log_root = sibling(project_root, "cp-solved-log")
  local cp_nim_lib_root = sibling(project_root, "cp-nim-lib")
  local nim_acl_root = sibling(project_root, "nim-acl")

  setup_readonly_solved_log(cp_solved_log_root)

  vim.keymap.set("n", "<leader>fa", function()
    qf_session.save()
    search_solved_log(cp_solved_log_root)
  end, { desc = "過去解答を検索（読み取り専用）" })

  vim.keymap.set("n", "<leader>fi", function()
    qf_session.save()
    search_library(cp_nim_lib_root, nim_acl_root)
  end, { desc = "ライブラリを検索してinclude/importを挿入" })

  -- <leader>fs は path を持たない候補なので qf_session は必須ではないが、
  -- 挙動を統一しておいても害はない
  vim.keymap.set("n", "<leader>fs", function()
    qf_session.save()
    search_snippets({ ufcs = cursor_is_after_dot() })
  end, { desc = "Snippet + StdLibを検索して展開" })

  -- インサートモードのまま同じ検索を起動する。
  -- ノーマルモードに戻さず、書いている途中でそのまま呼べる。
  vim.keymap.set("i", "<C-g>s", function()
    qf_session.save()
    search_snippets({ ufcs = cursor_is_after_dot() })
  end, { desc = "Snippet + StdLibを検索して展開（インサートモード）" })
end

return M