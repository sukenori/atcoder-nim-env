-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.getcwd()


-- このプロジェクト専用のスニペットを .nvim/snippets から読み込む
local snippet_dir = env_dir .. "/.nvim/snippets"
require("luasnip.loaders.from_lua").load({ paths = { snippet_dir } })


-- dotfiles の cmp.lua で使われる ripgrep の検索対象指定用グローバル変数
vim.g.user_line_rg_file_glob = "*.nim"