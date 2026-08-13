-- atcoder-nim/lsp.lua — プロジェクトローカルで Nim LSP (nimlangserver) の設定を管理する
local M = {}


-- project_root を呼び出し側（.nvim.lua）から受け取る
function M.setup(project_root)
  -- このプロジェクトで既に初期化済みなら二重起動しない
  if vim.g.atcoder_project_nim_lsp_initialized then
    return
  end
  vim.g.atcoder_project_nim_lsp_initialized = true


  -- 既存のハンドラ（コントローラー）（orig）を受け取り、それをラップした新しい関数を返す関数
  local function wrap_handler(orig)
    return function(err, result, ctx, config)
      -- イベントを送信してきた LSP クライアントの情報を取得（エラー防止のため、ctx と ctx.client_id の存在を確認）
      local client = ctx
        and ctx.client_id
        and vim.lsp.get_client_by_id(ctx.client_id)

      -- 以下の条件をすべて満たした場合、nimlangserver からの Info 通知とみなして、元のハンドラに渡さず終了する
      if client
        and client.name == "nim_langserver" -- 送信元が nim_langserver である
        and result -- サーバーからの結果（メッセージ本体）が存在する
        and result.type == vim.lsp.protocol.MessageType.Info -- メッセージの種類が "Info" である
      then
        return
      end

      -- 上記の条件に当てはまらない（エラーや別のサーバーからの通知など）場合は、元のハンドラに引数を渡す
      if orig then
        orig(err, result, ctx, config)
      end
    end
  end


  -- Neovim の画面右下のポップアップ通知（showMessage）の処理を、ラップした関数で上書きする
  vim.lsp.handlers["window/showMessage"] =
    wrap_handler(vim.lsp.handlers["window/showMessage"])


  -- Neovim の内部ログへの記録（logMessage）も、同様にラップした関数で上書きする
  vim.lsp.handlers["window/logMessage"] =
    wrap_handler(vim.lsp.handlers["window/logMessage"])


  -- ============================================================
  -- nim_langserver 限定の追加キーマップ・コマンド
  -- dotfiles側 lsp.lua の汎用キーマップ（K, gd, gD, gr, gi, <Leader>rn,
  -- <Leader>ca, [d, ]d）はそのまま生きるので、ここでは重複させない。
  -- ============================================================
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("AtCoderNimLspExtras", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= "nim_langserver" then
        return
      end


      -- キーマップに共通して渡す設定。
      -- buffer = ev.buf により、Nim LSP が接続されたバッファでのみ有効になる。
      local opts = { buffer = ev.buf, silent = true }


      -- ==========================================================
      -- Nim LSP の追加キーマップ一覧
      --
      -- gy          : 型定義元へジャンプ
      -- <Leader>ls  : 現在のファイル内のシンボル一覧
      -- <Leader>lw  : プロジェクト全体のシンボル検索
      -- <C-s>       : シグネチャヘルプ
      -- <Leader>lf  : フォーマット
      -- <Leader>lm  : カーソル位置にあるマクロを展開
      -- ==========================================================
      local keymaps = {
        -- 型定義元へジャンプ（gdは定義元、gyは型定義元）
        {
          mode = "n",
          lhs = "gy",
          rhs = vim.lsp.buf.type_definition,
          desc = "Nim: 型定義元へ移動",
        },

        -- 現在のファイル内のシンボル一覧（プロシージャ・マクロ・型などのアウトライン）
        {
          mode = "n",
          lhs = "<Leader>ls",
          rhs = vim.lsp.buf.document_symbol,
          desc = "Nim: ファイル内シンボル一覧",
        },

        -- プロジェクト全体のシンボルをファジー検索
        {
          mode = "n",
          lhs = "<Leader>lw",
          rhs = vim.lsp.buf.workspace_symbol,
          desc = "Nim: ワークスペースシンボル検索",
        },

        -- 関数呼び出し中に引数のシグネチャを手動表示（挿入モードでも使えるように）
        {
          mode = { "n", "i" },
          lhs = "<C-s>",
          rhs = vim.lsp.buf.signature_help,
          desc = "Nim: シグネチャヘルプ",
        },

        -- nphを使ったドキュメントフォーマット
        {
          mode = "n",
          lhs = "<Leader>lf",
          rhs = function()
            vim.lsp.buf.format({ async = true })
          end,
          desc = "Nim: フォーマット",
        },

        -- カーソル位置にあるマクロを展開する。
        -- "l" は LSP、"m" は macro を表すため <Leader>lm としている。
        {
          mode = "n",
          lhs = "<Leader>lm",
          rhs = "<Cmd>NimMacroExpand<CR>",
          desc = "Nim: マクロ展開",
        },
      }


      -- 上の keymaps テーブルを順番に読み、すべてバッファローカルキーマップとして登録する
      for _, map in ipairs(keymaps) do
        vim.keymap.set(map.mode, map.lhs, map.rhs, {
          buffer = opts.buffer,
          silent = opts.silent,
          desc = map.desc,
        })
      end


      -- カーソル位置のシンボルと同一のものを自動ハイライト
      if client.server_capabilities.documentHighlightProvider then
        local hl_group = vim.api.nvim_create_augroup(
          "AtCoderNimDocHighlight_" .. ev.buf,
          { clear = true }
        )

        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
          group = hl_group,
          buffer = ev.buf,
          callback = vim.lsp.buf.document_highlight,
        })

        vim.api.nvim_create_autocmd("CursorMoved", {
          group = hl_group,
          buffer = ev.buf,
          callback = vim.lsp.buf.clear_references,
        })
      end


      -- マクロ展開
      --
      -- :NimMacroExpand または <Leader>lm を実行すると、
      -- カーソル位置にあるマクロを nimlangserver に展開してもらい、
      -- 結果をフローティングウィンドウに表示する。
      --
      -- nvim_buf_create_user_command を使うことで、このコマンドは
      -- ev.buf の Nim バッファ内だけで有効なバッファローカルコマンドになる。
      vim.api.nvim_buf_create_user_command(ev.buf, "NimMacroExpand", function()
        local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

        -- macroExpand 拡張に渡す展開レベル。
        -- 1 は通常、カーソル位置のマクロを1段階展開する指定。
        params.level = 1


        client.request("extension/macroExpand", params, function(err, result)
          -- LSP のレスポンス処理は非同期なので、UI 操作は vim.schedule 内で行う
          vim.schedule(function()
            if err then
              vim.notify(
                "macroExpandに失敗しました: " .. (err.message or vim.inspect(err)),
                vim.log.levels.WARN
              )
              return
            end


            if not result or not result.content or result.content == "" then
              vim.notify("macroExpandの結果が空です", vim.log.levels.INFO)
              return
            end


            -- 展開結果を行ごとに分割し、Nim のシンタックスハイライト付きの
            -- フローティングウィンドウとして表示する
            vim.lsp.util.open_floating_preview(
              vim.split(result.content, "\n", { plain = true }),
              "nim",
              { border = "rounded" }
            )
          end)
        end, ev.buf)
      end, {
        desc = "Nim: マクロ展開",
        -- LSP の再接続時にも同名コマンドを安全に再定義できるようにする
        force = true,
      })
    end,
  })


  -- "nim_langserver" という名前で、LSPサーバーの起動方法や設定を Neovim に登録
  vim.lsp.config("nim_langserver", {
    cmd = { "nimlangserver" },

    -- これが無いと、.nim ファイルを開いても自動起動しない
    filetypes = { "nim" },

    -- nimlangserver に渡す設定
    settings = {
      nim = {
        autoCheckFile = true, -- 開いているファイルのエラーチェックを自動で行う
        autoCheckProject = false, -- プロジェクト全体のチェックは重いので無効にする
        checkOnSave = false, -- `nim check` コマンドによる保存時のチェックは無効にする
        useNimCheck = false, -- `nim check` ではなく、LSP 組み込みの機能(nimsuggest)を使う
        notificationVerbosity = "warning", -- サーバー側でも、Info レベル以下の細かい通知を出さないようにする
      },
    },


    -- この LSP を「どのフォルダを基準に動かすか」決める関数
    root_dir = function(bufnr, on_dir)
      -- バッファのファイル名（フルパス）を取得
      local fname = vim.api.nvim_buf_get_name(bufnr)

      -- まだディスクに保存されていない空のバッファや、実在しないファイルの場合、クラッシュ防止で起動をキャンセルする
      if fname == "" or vim.fn.filereadable(fname) ~= 1 then
        return
      end

      -- さもなければ project_root（例: /atcoder-nim-env）で確定
      on_dir(project_root)
    end,
  })


  -- 上で登録した "nim_langserver" の設定を有効化し、Nim ファイルを開いたときに自動で LSP が立ち上がるようにする
  vim.lsp.enable("nim_langserver")


  -- .nvim.lua 読み込み時点で既に開かれている Nim バッファに対しても、LSP を確実に接続させる
  vim.schedule(function()
    pcall(vim.cmd.doautoall, "nvim.lsp.enable FileType")
  end)
end


return M