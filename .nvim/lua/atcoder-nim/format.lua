-- atcoder-nim.format: Nim ファイルを nph で自動整形する
-- 整形のタイミング: インサートモードを抜けたとき、保存の直前、:NimFormat を実行したとき

-- このモジュールの公開テーブルを用意する
local M = {}

-- バッファ bufnr のファイルを nph で整形する。skip_presave が true なら、事前の保存はしない
local function format_nim(bufnr, skip_presave)
  -- Nim ファイルでなければ何もしない
  if vim.bo[bufnr].filetype ~= "nim" then return end
  -- 整形の最中(事前の保存で再び呼ばれた場合など)なら何もしない
  if vim.b[bufnr].nim_formatting then return end
  -- ファイルの場所を取得する(名前の無いバッファは整形できない)
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then return end

  -- 整形中の印を付ける
  vim.b[bufnr].nim_formatting = true
  -- カーソルとスクロールの位置を覚えておく
  local view = vim.fn.winsaveview()

  -- nph はディスク上のファイルを整形するので、未保存の変更があれば先に静かに保存する
  if vim.bo[bufnr].modified and not skip_presave then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end)
  end

  -- nph でファイルを整形する
  vim.fn.system({ "nph", file })
  if vim.v.shell_error ~= 0 then
    -- 失敗したら警告を出す
    vim.notify("Nim format failed: nph", vim.log.levels.WARN)
  else
    -- 成功したら、書き換えられたファイルをバッファに読み込み直す
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! checktime") end)
    -- カーソルとスクロールの位置を戻す
    vim.fn.winrestview(view)
  end

  -- 整形中の印を外す
  vim.b[bufnr].nim_formatting = false
end

-- .nvim.lua から呼ぶ入口。自動整形と :NimFormat を登録する
function M.setup()
  -- 何度読み込んでも重複しないよう、グループを作り直す
  local group = vim.api.nvim_create_augroup("AtcoderNimAutoFormat", { clear = true })
  -- インサートモードを抜けたときに整形する(.nim ファイルだけが対象)
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group, pattern = "*.nim",
    callback = function(ev) format_nim(ev.buf) end,
  })
  -- 保存の直前に整形する(すでに保存中なので、事前の保存はしない)
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group, pattern = "*.nim",
    callback = function(ev) format_nim(ev.buf, true) end,
  })
  -- :NimFormat で、いつでも手動で整形できるようにする
  vim.api.nvim_create_user_command("NimFormat", function() format_nim(vim.api.nvim_get_current_buf()) end,
    { desc = "Format current Nim file using nph" })
end

-- 公開テーブルを返す
return M
