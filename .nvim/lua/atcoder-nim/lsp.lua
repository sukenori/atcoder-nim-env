-- atcoder-nim.lsp: Nim用の言語サーバー(nimlangserver)の設定と、Nim専用のキー割り当てを登録する
-- K、gd、gr、<Leader>rn などの共通のキーは dotfiles 側にあるので、ここでは重複させない

-- このモジュールの公開テーブルを用意する
local M = {}

-- .nvim.lua から project_root(このプロジェクトの場所)を受け取って設定する
function M.setup(project_root)
  -- サーバーからの Info 通知(ポップアップ)を表示しないよう、元の処理を包んで作り直す関数
  local function drop_nim_info(orig)
    -- 元の処理と同じ引数を受け取る新しい処理を返す
    return function(err, result, ctx, config)
      -- この通知を送ってきたサーバーの情報を取得する
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      -- nimlangserver からの Info レベルの通知なら、何も表示せず終わる
      if client and client.name == "nim_langserver" and result and result.type == vim.lsp.protocol.MessageType.Info then
        return
      end
      -- それ以外の通知は、元の処理に渡す
      orig(err, result, ctx, config)
    end
  end
  -- 画面に出る通知(showMessage)と、ログへの記録(logMessage)の両方に適用する
  for _, method in ipairs({ "window/showMessage", "window/logMessage" }) do
    vim.lsp.handlers[method] = drop_nim_info(vim.lsp.handlers[method])
  end

  -- nimlangserver がバッファに接続されたときに、そのバッファだけに設定を加える
  vim.api.nvim_create_autocmd("LspAttach", {
    -- 何度読み込んでも重複しないよう、グループを作り直す
    group = vim.api.nvim_create_augroup("AtCoderNimLspExtras", { clear = true }),
    callback = function(ev)
      -- 接続されたサーバーの情報を取得し、nimlangserver 以外なら何もしない
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= "nim_langserver" then return end

      -- このバッファだけで有効なキー割り当てを登録する関数
      local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, silent = true, desc = "Nim: " .. desc })
      end
      -- gy: 型の定義元へ移動する
      map("n", "gy", vim.lsp.buf.type_definition, "型定義元へ移動")
      -- <Leader>ls: このファイル内のシンボル一覧を出す
      map("n", "<Leader>ls", vim.lsp.buf.document_symbol, "ファイル内シンボル一覧")
      -- <Leader>lw: プロジェクト全体のシンボルを検索する
      map("n", "<Leader>lw", vim.lsp.buf.workspace_symbol, "ワークスペースシンボル検索")
      -- <C-s>: 引数のヒント(シグネチャ)を手動で表示する(インサートモードでも使える)
      map({ "n", "i" }, "<C-s>", vim.lsp.buf.signature_help, "シグネチャヘルプ")
      -- <Leader>lf: ファイル全体を整形する
      map("n", "<Leader>lf", function() vim.lsp.buf.format({ async = true }) end, "フォーマット")
      -- <Leader>lm: カーソル位置のマクロを展開する(下で作る :NimMacroExpand を呼ぶ)
      map("n", "<Leader>lm", "<Cmd>NimMacroExpand<CR>", "マクロ展開")

      -- サーバーが対応していれば、カーソル位置と同じシンボルを自動でハイライトする
      if client.server_capabilities.documentHighlightProvider then
        -- このバッファ専用のグループを作る
        local group = vim.api.nvim_create_augroup("AtCoderNimDocHighlight_" .. ev.buf, { clear = true })
        -- カーソルが止まったら、同じシンボルをハイライトする
        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
          group = group, buffer = ev.buf, callback = vim.lsp.buf.document_highlight,
        })
        -- カーソルが動いたら、ハイライトを消す
        vim.api.nvim_create_autocmd("CursorMoved", {
          group = group, buffer = ev.buf, callback = vim.lsp.buf.clear_references,
        })
      end

      -- :NimMacroExpand: カーソル位置のマクロを展開し、結果を浮かぶウィンドウに表示する
      vim.api.nvim_buf_create_user_command(ev.buf, "NimMacroExpand", function()
        -- カーソル位置の情報を作り、展開の深さを1段階にする
        local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
        params.level = 1
        -- サーバーに展開を依頼する
        client.request("extension/macroExpand", params, function(err, result)
          -- 画面の操作は、通信の返事の中では直接できないので、少し後に回す
          vim.schedule(function()
            -- 失敗したら、理由を表示して終わる
            if err then
              vim.notify("macroExpandに失敗しました: " .. (err.message or vim.inspect(err)), vim.log.levels.WARN)
            -- 結果が空なら、その旨を表示して終わる
            elseif not result or not result.content or result.content == "" then
              vim.notify("macroExpandの結果が空です")
            -- 成功したら、Nimの色付きで、丸い枠のウィンドウに表示する
            else
              vim.lsp.util.open_floating_preview(vim.split(result.content, "\n", { plain = true }), "nim", { border = "rounded" })
            end
          end)
        end, ev.buf)
      -- 再接続のときに同じ名前のコマンドを作り直せるよう、force を付ける
      end, { desc = "Nim: マクロ展開", force = true })
    end,
  })

  -- "nim_langserver" の起動方法と設定を登録する
  vim.lsp.config("nim_langserver", {
    -- 起動するコマンド
    cmd = { "nimlangserver" },
    -- .nim ファイルを開いたときに自動で起動する
    filetypes = { "nim" },
    -- nimlangserver に渡す設定
    settings = {
      nim = {
        -- 開いているファイルのエラーチェックを自動で行う
        autoCheckFile = true,
        -- プロジェクト全体のチェックは重いので行わない
        autoCheckProject = false,
        -- 保存時の nim check は行わない
        checkOnSave = false,
        -- nim check ではなく、LSP 組み込みの機能(nimsuggest)を使う
        useNimCheck = false,
        -- サーバー側でも、警告より細かい通知は出さない
        notificationVerbosity = "warning",
      },
    },
    -- 起動の基準にするフォルダを決める。保存済みのファイルのときだけ project_root を指定する
    root_dir = function(bufnr, on_dir)
      -- バッファのファイルの場所を取得する
      local fname = vim.api.nvim_buf_get_name(bufnr)
      -- 未保存や実在しないファイルでは起動しない
      if fname ~= "" and vim.fn.filereadable(fname) == 1 then on_dir(project_root) end
    end,
  })

  -- 登録した設定を有効にする
  vim.lsp.enable("nim_langserver")
  -- すでに開いている Nim のバッファにも、サーバーを接続させる
  vim.schedule(function() pcall(vim.cmd.doautoall, "nvim.lsp.enable FileType") end)
end

-- 公開テーブルを返す
return M
