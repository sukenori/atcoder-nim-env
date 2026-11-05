-- atcoder-nim-env/.nvim.lua: このプロジェクト専用の Neovim 設定

-- この .nvim.lua があるフォルダを、プロジェクトの場所(project_root)とする
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

-- .nvim/ の中の syntax や indent などを、標準のものより優先して読み込ませる
vim.opt.runtimepath:prepend(project_root .. "/.nvim")

-- 保存したことのない Nim ファイルを開いたら、その場でディスクに作る(make・LSP・nph はディスク上のファイルを必要とするため)
vim.api.nvim_create_autocmd("FileType", {
  -- 何度読み込んでも重複しないよう、グループを作り直す
  group = vim.api.nvim_create_augroup("AtcoderNimStrictBuffer", { clear = true }),
  -- Nim ファイルだけが対象
  pattern = "nim",
  callback = function(ev)
    -- このバッファのファイルの場所を取得する
    local fname = vim.api.nvim_buf_get_name(ev.buf)
    -- 名前が無いバッファは作れないので、エラーを出して終わる
    if fname == "" then
      vim.notify("エラー: Nim バッファを開くときは、ファイル名を指定してください", vim.log.levels.ERROR)
      return
    end
    -- すでにディスクにあるファイルなら、何もしない
    if vim.fn.filereadable(fname) == 1 then return end
    -- 保存先のフォルダが無ければ、途中のフォルダも含めて作る
    vim.fn.mkdir(vim.fn.fnamemodify(fname, ":p:h"), "p")
    -- そのバッファの中で、メッセージを出さずに保存する
    vim.api.nvim_buf_call(ev.buf, function() vim.cmd("silent! write") end)
  end,
})

-- nph による自動整形を登録する
require("atcoder-nim.format").setup()
-- Nim の言語サーバー(nimlangserver)の設定を登録する
require("atcoder-nim.lsp").setup(project_root)
-- make の実行用キー(<Leader>c/s/u/d/b/p/a)を登録する
require("atcoder-nim.make_runner").setup({ project_root = project_root })
-- 復習コマンド(:CpSuggest / :CpArchive / :CpHistory / :CpOpenAnswer)を登録する
require("atcoder-nim.review").setup(project_root)
-- 自分が過去に書いた行を、補完候補に出すソースを登録する
require("atcoder-nim.line_rg").setup(project_root)
-- 過去解答の検索、ライブラリの挿入、スニペットの検索(<Leader>fa / fi / fs)を登録する
require("atcoder-nim.telescope_cp").setup(project_root)

-- プロジェクト専用のスニペットを読み込む(LuaSnip 形式と、VS Code と共有する形式の両方)
require("plugins.luasnip").load({
  lua = { project_root .. "/.nvim/snippets/lua" },
  vscode = { project_root .. "/.nvim/snippets/vscode" },
})

-- スワップファイルを作らない(復元はできなくなるが、起動時の W325 警告も出ない)
vim.opt.swapfile = false
