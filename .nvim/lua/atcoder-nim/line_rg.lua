-- atcoder-nim.line_rg: 「自分が過去に書いた行」を補完候補として出す、nvim-cmp 用のソース
-- 検索対象は、このプロジェクトと、隣に置いた cp-solved-log の .nim ファイル

-- このモジュールの公開テーブルを用意する
local M = {}

-- 補完ソースの本体(検索対象のフォルダは setup で入れる)
local source = { search_paths = {} }

-- 補完を開始する文字列の範囲: 空白以外の文字から、カーソル位置まで
function source:get_keyword_pattern()
  return [[\S.*]]
end

-- 補完候補を作る。request は入力の状況、callback は結果を返す関数
function source:complete(request, callback)
  -- 行頭からカーソルまでの文字列のうち、補完の開始位置以降を取り出し、前後の空白を除く
  local input = vim.trim(request.context.cursor_before_line:sub(request.offset))
  -- 入力が空なら、候補なしで終わる(空のまま検索すると全行に一致してしまう)
  if input == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- 実行する rg のコマンドを組み立てる
  local cmd = {
    "rg",
    -- 入力を正規表現ではなく、ただの文字列として検索する(記号が含まれても壊れない)
    "-F",
    -- 見出しとファイル名を出さず、見つかった行の本文だけを受け取る
    "--no-heading", "--no-filename",
    -- 入力がすべて小文字なら大文字小文字を区別せず、大文字を含むなら区別する
    "--smart-case",
    -- 色付けのための特殊文字を出さない
    "--color=never",
    -- .gitignore の対象(work/ など)も検索する
    "--no-ignore",
    -- Nim ファイルだけを対象にする
    "--glob", "*.nim",
    -- 検索する文字列
    input,
  }
  -- 検索するフォルダを末尾に加える
  vim.list_extend(cmd, self.search_paths)

  -- 呼び出しのたびに番号を進める(古い検索の結果が、新しい入力の結果を上書きするのを防ぐ)
  self.generation = (self.generation or 0) + 1
  local my_generation = self.generation

  -- rg を非同期で実行し、終わったら結果を候補にして返す
  vim.system(cmd, { text = true }, function(obj)
    -- 画面に関わる処理は、メインの流れに戻してから行う
    vim.schedule(function()
      -- 検索中に別の補完が始まっていたら、この古い結果は捨てる
      if my_generation ~= self.generation then return end

      -- 候補を貯める表と、重複を防ぐための表
      local items, seen = {}, {}
      -- rg の出力を1行ずつ調べる
      for line in (obj.stdout or ""):gmatch("[^\r\n]+") do
        -- 前後の空白を除く
        local text = vim.trim(line)
        -- 入力より長く、入力で始まり、まだ候補にない行だけを加える
        if #text > #input and vim.startswith(text, input) and not seen[text] then
          seen[text] = true
          table.insert(items, { label = text, insertText = text, kind = require("cmp").lsp.CompletionItemKind.Text })
        end
      end
      -- 候補を返す
      callback({ items = items, isIncomplete = false })
    end)
  end)
end

-- .nvim.lua から呼ぶ入口。project_root はこのプロジェクトの場所
function M.setup(project_root)
  -- nvim-cmp を読み込む
  local cmp = require("cmp")
  -- 検索するフォルダは、このプロジェクトと、同じ階層にある cp-solved-log
  source.search_paths = { project_root, vim.fn.fnamemodify(project_root, ":h") .. "/cp-solved-log" }
  -- cp-solved-log が無ければ、検索対象から外す
  if vim.fn.isdirectory(source.search_paths[2]) ~= 1 then table.remove(source.search_paths) end

  -- "line_rg" という名前で nvim-cmp に登録する
  cmp.register_source("line_rg", setmetatable({}, { __index = source }))
  -- Nim ファイルでの補完元を、スニペット、過去の行、LSP の順にする
  -- (filetype 指定なので、最初から Nim ファイルを開いて起動した場合も取りこぼさない)
  cmp.setup.filetype("nim", {
    sources = cmp.config.sources({ { name = "luasnip" }, { name = "line_rg" }, { name = "nvim_lsp" } }),
  })
end

-- 公開テーブルを返す
return M
