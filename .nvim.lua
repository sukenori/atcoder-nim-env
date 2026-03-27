-- atcoder-nim-env/.nvim.lua プロジェクトローカル設定
-- 素の Neovim で make と Nim LSP を扱う

-- ===========================================================================
-- 1) プロジェクト前提の基本設定
-- ===========================================================================

-- このファイル自身の場所をプロジェクトルートとして扱う
local env_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local project_nvim_dir = env_dir .. "/.nvim"

-- project-local runtime（syntax/ftplugin など）を有効化する。
if vim.fn.isdirectory(project_nvim_dir) == 1 then
  vim.opt.runtimepath:prepend(project_nvim_dir)

  -- 既に開いている Nim バッファにも project-local syntax を即時適用する。
  local function apply_project_nim_syntax(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)) then
      return
    end
    if vim.bo[bufnr].filetype ~= "nim" then
      return
    end
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, "silent! runtime! syntax/nim.vim")
    end)
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    apply_project_nim_syntax(bufnr)
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("AtcoderProjectNimSyntax", { clear = true }),
    pattern = "nim",
    callback = function(ev)
      apply_project_nim_syntax(ev.buf)
    end,
  })
end

-- 同じファイルを複数の Neovim から触るなどで swap 競合 (W325) の警告が起動時のノイズになるので、この project では無効化する
-- ファイルの保全は 保存と Git が前提
vim.opt.swapfile = false

-- ===========================================================================
-- 1.5) project-local 機能をモジュール単位で読み込む
-- ===========================================================================
require("atcoder-nim.format").setup()
require("atcoder-nim.debug").setup({ env_dir = env_dir })

-- このプロジェクト専用のスニペットを .nvim/snippets から読み込む
local function register_project_snippets()
  local ok_loader, loader = pcall(require, "luasnip.loaders.from_lua")
  if not ok_loader then
    vim.notify("LuaSnip loader が読み込めないため project snippet を登録できません", vim.log.levels.WARN)
    return
  end

  local snippet_dir = env_dir .. "/.nvim/snippets"
  if vim.fn.isdirectory(snippet_dir) ~= 1 then
    return
  end

  loader.load({ paths = { snippet_dir } })
end

register_project_snippets()

-- AtCoder 操作用の make 実行ラッパーとキーマップを読み込む
require("atcoder-nim.make_runner").setup({ env_dir = env_dir })

-- Nim LSP 設定は専用モジュールに分離する。
require("atcoder-nim.lsp").setup({ env_dir = env_dir })
