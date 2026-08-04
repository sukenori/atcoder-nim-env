-- atcoder-nim-env/.nvim.lua — プロジェクトローカル設定

-- .nvim.lua 自身の絶対パスを取得
local source = debug.getinfo(1, "S").source
-- source は "@/絶対パス/.nvim.lua" という形式なので、先頭の @ を除く
local this_file = source:sub(2)
-- .nvim.lua が置かれているディレクトリをプロジェクトルートとして取得する
local project_root = vim.fn.fnamemodify(this_file, ":p:h")

-- プロジェクトローカル Neovim runtime の場所
local project_nvim_dir = project_root .. "/.nvim"

-- .nvim 下にある atcoder-nim-env 専用のファイル群を Neovim 標準やプラグインのものより優先して読み込ませる
-- syntax/ indent/ は自動で読み込まれる
vim.opt.runtimepath:prepend(project_nvim_dir)

-- Make、LSP、nph との連携を確実にするため、Nim バッファは必ず「名前」と「ディスク上の実体」を保証する
-- "AtcoderNimStrictBuffer" という名前の自動コマンドのグループを作成する
-- { clear = true } を指定すると、Neovimの再読み込みしても設定が重複して登録されない
local strict_buf_group = vim.api.nvim_create_augroup("AtcoderNimStrictBuffer", { clear = true })

-- 自動コマンド（特定のイベントが発生したときに実行される処理）を登録
vim.api.nvim_create_autocmd("FileType", {
    -- 先ほど作成したグループにこのコマンドを入れる
    group = strict_buf_group,
    pattern = "nim",

    -- イベントが発火した際に実行されるコールバック関数
    -- 引数 ev には、バッファ番号などイベントに関する情報が入っている
    callback = function(ev)
      -- 今回イベントが発生した対象のバッファ番号（ID）を取得
      local bufnr = ev.buf
      -- そのバッファが現在も有効（削除されたり壊れたりしていない）かを確認し、無効なら処理を終了
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      -- そのバッファに付けられているファイル名（フルパス）を取得
      local fname = vim.api.nvim_buf_get_name(bufnr)

      -- ファイル名が指定されていない場合
      if fname == "" then
        -- vim.notify はNeovimの通知機能です。エラーレベル（ERROR）で警告メッセージを出します。
        vim.notify("エラー: Nim バッファを開くときは、ファイル名を指定してください", vim.log.levels.ERROR)
        -- これ以上下の処理（保存など）は行わずに終了
        return
      end

      -- ファイルがディスク上に存在し、読める状態にない場合
      if vim.fn.filereadable(fname) == 0 then

        -- パスの文字列操作（":p" はフルパス化、":h" はヘッド、末尾のファイル名を取り除いたディレクトリ部分の取得）
        local dir = vim.fn.fnamemodify(fname, ":p:h")
        -- そのディレクトリがディスク上に存在しない場合
        if vim.fn.isdirectory(dir) == 0 then
          -- "p" オプション付きで、途中の親ディレクトリも含めて一気に作成
          vim.fn.mkdir(dir, "p")
        end
        -- 指定したバッファ(bufnr)にコンテキストを一時的に切り替えて関数を実行
        vim.api.nvim_buf_call(bufnr, function()
          -- 画面にメッセージを出さずに強制的にディスクへ保存（書き込み）を行う
          pcall(vim.cmd, "silent! write")
        end)
      end
    end,
})

-- nph によるフォーマット設定を読み込む
require("atcoder-nim.format").setup()

-- Nim LSP（nimlangserver）の project-local 設定を読み込む
require("atcoder-nim.lsp").setup(project_root)

-- AtCoder 操作用 make 実行ラッパーとキーマップを読み込む
require("atcoder-nim.make_runner").setup({ project_root = project_root })

-- プロジェクト専用スニペットを snippets/ から読み込む
-- ここで「lua記法(LuaSnip専用)とvscode記法(*.code-snippets、VS Codeと共有)の
-- 両方を読む」という atcoder-nim-env 固有の構造を明示的に指定する。
-- 読み込み処理自体は nvim/lua/plugins/luasnip.lua 側の汎用ローダーに委ねる。
require("plugins.luasnip").load({
  lua = { project_root .. "/.nvim/snippets/lua" },
  vscode = { project_root .. "/.nvim/snippets/vscode" },
})

-- cmp.lua の line_rg 補完（インサートモード補完）の検索対象を nim ファイルに絞る
vim.g.user_line_rg_file_glob = "*.nim"

-- Telescope live_grep の検索対象を nim ファイルに絞る
vim.g.user_telescope_file_glob = "*.nim"

-- swapファイルを作らないと未保存編集は復元できないが、起動時のswapファイルを無視したというW325の警告も出ない
vim.opt.swapfile = false
