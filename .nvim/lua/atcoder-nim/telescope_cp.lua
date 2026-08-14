-- atcoder-nim.telescope_cp — 競プロ資産を横断するための3つのTelescope入口
--
--   <leader>fa  cp-solved-log を live_grep する（読み取り専用。実例を読むだけ）
--   <leader>fi  cp-nim-lib / nim-acl からファイルを選び、
--               include / import 文を現在バッファへ挿入する
--   <leader>fs  snippet を fuzzy 検索して、現在カーソル位置へ展開する
--
-- .nvim/scope_dirs.txt はもう使わない。
-- 検索対象のリポジトリはここで直接パスを組み立てる。

local M = {}

-- cp-nim-lib / cp-solved-log / nim-acl は atcoder-nim-env と同じ階層に
-- sibling directory として置く運用なので、project_root の一つ上から辿る。
local function sibling(project_root, name)
  return vim.fn.fnamemodify(project_root, ":h") .. "/" .. name
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
  -- 例: "h w" -> "(?=.*h)(?=.*w)"
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
    return table.concat(lookaheads, "")
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
      "-P",              -- PCRE2を有効化（先読みを使うために必須）
      "-e", pattern,
      "--glob", "*.nim",
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
        ordinal = rel,
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
        ordinal = rel .. " atcoder/" .. name,
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
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = collect_library_entries(cp_nim_lib_root, nim_acl_root)
  local bufnr = vim.api.nvim_get_current_buf()

  pickers.new({
    -- 標準のfile previewerを使う。
    -- entry_maker が path を top-level で返してさえいれば、
    -- Telescopeが自動でファイル内容を読み、シンタックスハイライトも
    -- telescope.setup(defaults.preview.treesitter.disable) の設定に従ってくれる
    -- （nimはtreesitterを試みず、従来通り syntax/nim.vim で色付けされる）。
    previewer = conf.file_previewer({}),
  }, {
    prompt_title = "Include / Import library",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
          -- previewerがファイル内容を読むために必要。
          -- これが無いと previewer を足しても中身が表示されない。
          path = entry.path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        vim.schedule(function()
          add_declaration_once(bufnr, selection.value.declaration)
        end)
      end)
      return true
    end,
  }):find()
end

-- ============================================================
-- <leader>fs: snippetをfuzzy検索して展開する
-- ============================================================

local function snippet_ordinal(snip)
  local desc = snip.dscr or ""
  if type(desc) == "table" then
    desc = table.concat(desc, " ")
  end
  return table.concat({ snip.trigger or "", snip.name or "", desc }, " ")
end

local function snippet_display(snip)
  return string.format("%-24s %s", snip.trigger or "", snip.name or "")
end

local function snippet_previewer()
  local previewers = require("telescope.previewers")

  return previewers.new_buffer_previewer({
    title = "Snippet preview",
    define_preview = function(self, entry, _)
      local snip = entry.value
      local lines = {}

      -- 上段: name / description（判断材料としての説明）
      table.insert(lines, "Name: " .. (snip.name or snip.trigger or ""))
      table.insert(lines, "")

      local desc = snip.dscr or {}
      if type(desc) == "string" then
        desc = { desc }
      end
      if #desc > 0 then
        vim.list_extend(lines, desc)
      else
        table.insert(lines, "(no description)")
      end

      -- 区切り線を挟んでから、下段に実物（body）を出す
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")

      local ok, docstring = pcall(function()
        return snip:get_docstring()
      end)
      if ok and docstring then
        vim.list_extend(lines, docstring)
      else
        table.insert(lines, "(preview unavailable)")
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      -- bodyはNimコードなので、Nim構文で色付けする。
      -- treesitter.lua で highlight.disable = { "nim" } 済みのため、
      -- ここも自動的に treesitter ではなく syntax/nim.vim で色付けされる。
      vim.bo[self.state.bufnr].filetype = "nim"
    end,
  })
end

local function search_snippets()
  local luasnip = require("luasnip")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local snippets = luasnip.get_snippets(vim.bo.filetype) or {}

  pickers.new({
    previewer = snippet_previewer(),
  }, {
    prompt_title = "Nim snippets",
    finder = finders.new_table({
      results = snippets,
      entry_maker = function(snip)
        return {
          value = snip,
          display = snippet_display(snip),
          ordinal = snippet_ordinal(snip),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        vim.schedule(function()
          luasnip.snip_expand(selection.value)
        end)
      end)
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
    search_solved_log(cp_solved_log_root)
  end, { desc = "過去解答を検索（読み取り専用）" })

  vim.keymap.set("n", "<leader>fi", function()
    search_library(cp_nim_lib_root, nim_acl_root)
  end, { desc = "ライブラリを検索してinclude/importを挿入" })

  vim.keymap.set("n", "<leader>fs", search_snippets, { desc = "snippetを検索して展開" })
end

return M