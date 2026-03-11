-- ===========================================================================
-- .nvim.lua — atcoder-nim-env 用のプロジェクトローカル設定
--
-- dotfiles 側の init.lua が、このリポジトリをカレントディレクトリにして
-- Neovim を起動したときだけ明示的に読み込む。
-- グローバル設定に持ち込みたくない Nim / AtCoder 専用の設定はここに置く。
-- ===========================================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local env_dir = vim.fn.fnamemodify(script_path, ":p:h")

local function get_make_file()
  local abs = vim.fn.expand("%:p")
  return abs:gsub("^" .. vim.pesc(env_dir) .. "/", "")
end

local function get_tmux_target()
  if vim.env.ATCODER_TMUX_TARGET and vim.env.ATCODER_TMUX_TARGET ~= "" then
    return vim.env.ATCODER_TMUX_TARGET
  end

  if vim.env.TMUX then
    local session = vim.trim(vim.fn.system("tmux display-message -p '#S'"))
    local window = vim.trim(vim.fn.system("tmux display-message -p '#W'"))
    if vim.v.shell_error == 0 and session ~= "" and window ~= "" then
      return string.format("%s:%s.2", session, window)
    end
  end

  return nil
end

local function tmux_send(cmd)
  local target = get_tmux_target()
  if not target then
    print("tmux の出力先 pane を特定できません")
    return
  end
  vim.cmd("write")
  vim.fn.system(string.format("tmux send-keys -t %s '%s' Enter", vim.fn.shellescape(target), cmd))
end

vim.keymap.set("n", "<LocalLeader>c", function()
  tmux_send(string.format("make -C %s build FILE=%s", env_dir, get_make_file()))
end, { silent = true, desc = "AtCoder: コンパイル" })

vim.keymap.set("n", "<LocalLeader>s", function()
  tmux_send(string.format("make -C %s submit-auto FILE=%s", env_dir, get_make_file()))
end, { silent = true, desc = "AtCoder: テスト＋提出" })

vim.keymap.set("n", "<LocalLeader>u", function()
  local url = vim.fn.getreg("+"):gsub("%s+", "")
  if url == "" then
    print("クリップボードが空です")
    return
  end
  tmux_send(string.format("make -C %s submit-url FILE=%s URL=%s", env_dir, get_make_file(), url))
end, { silent = true, desc = "AtCoder: URL 指定で提出" })

vim.keymap.set("n", "<LocalLeader>b", function()
  vim.cmd("write")
  vim.fn.system(string.format("make -C %s bundle FILE=%s", env_dir, get_make_file()))
  local target = env_dir .. "/bundled.txt"
  if vim.fn.filereadable(target) == 1 then
    local lines = vim.fn.readfile(target)
    vim.fn.setreg("+", table.concat(lines, "\n") .. "\n")
    print("バンドル結果をクリップボードにコピーしました")
  else
    print("エラー: " .. target .. " が見つかりません")
  end
end, { silent = true, desc = "AtCoder: バンドル＋コピー" })

local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
if not ok_lspconfig or vim.fn.executable("nimlangserver") ~= 1 then
  return
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if ok_cmp then
  capabilities = vim.tbl_deep_extend(
    "force",
    capabilities,
    cmp_nvim_lsp.default_capabilities()
  )
end

local nim_config = {
  cmd = { "nimlangserver" },
  filetypes = { "nim" },
  root_dir = lspconfig.util.root_pattern("nim.cfg", "*.nimble", ".git"),
  capabilities = capabilities,
}

if vim.lsp.config then
  vim.lsp.config("nim_langserver", nim_config)
  vim.lsp.enable("nim_langserver")
else
  lspconfig.nim_langserver.setup(nim_config)
end