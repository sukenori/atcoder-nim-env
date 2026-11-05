#!/usr/bin/env bash
# 初回セットアップ: ユーザー名の登録、Tailscale、関連リポジトリの取得、sudo の許可設定、コンテナの起動を行う

# エラー、未定義の変数、パイプの途中の失敗があれば、そこで止める
set -euo pipefail

# このスクリプトのあるフォルダ(atcoder-nim-env)へ移動する
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 今のユーザー名とグループ名
CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"

# 指定したフォルダの中で、所有者が今のユーザーでないものを、今のユーザーに戻す
fix_ownership() {
  find "$1" \( ! -user "$CURRENT_USER" -o ! -group "$CURRENT_GROUP" \) -exec sudo chown "$CURRENT_USER:$CURRENT_GROUP" {} +
}

# 過去に root で実行した名残があれば、このフォルダの所有者を戻す
fix_ownership "$SCRIPT_DIR"

# AtCoder のユーザー名を、まだ登録していなければ登録する
if [[ ! -s .atcoder-user ]]; then
  # 環境変数 ATCODER_USER があればそれを使う
  username="${ATCODER_USER:-}"
  # 英数字とアンダースコアだけのユーザー名になるまで繰り返す
  while [[ ! "$username" =~ ^[A-Za-z0-9_]+$ ]]; do
    # 対話できない状態なら、環境変数で指定するよう伝えて終わる
    if [[ ! -t 0 ]]; then
      echo "AtCoderユーザー名をATCODER_USERで指定してください" >&2
      exit 1
    fi
    # ユーザー名を入力してもらう
    read -r -p "AtCoderユーザー名: " username
  done
  # ユーザー名をファイルに保存する
  printf '%s\n' "$username" > .atcoder-user
fi

# Tailscale が無ければインストールする
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
# すでに Tailnet に登録済みなら、再認証せずに SSH だけ有効にする
if sudo tailscale ip -4 >/dev/null 2>&1; then
  sudo tailscale set --ssh
# 初回だけ、認証用の URL が表示されるので、ブラウザで開いて承認する
else
  sudo tailscale up --ssh --accept-dns=false --hostname=wsl
fi

# コンテナから呼ぶ、ブラウザ起動用のスクリプトを実行できるようにする
chmod +x publish-open-url.sh open-windows-url.sh bundle.sh

# 関連リポジトリを、隣のフォルダに取得する(すでにあれば最新にする)
for repo in cp-nim-lib cp-solved-log nim-acl; do
  # あれば、所有者を直してから最新にする
  if [[ -d "../$repo/.git" ]]; then
    fix_ownership "../$repo"
    git -C "../$repo" pull --ff-only
  # 無ければ、GitHub から取得する
  else
    git clone "https://github.com/sukenori/$repo.git" "../$repo"
  fi
done

# 作業用のフォルダを作る
mkdir -p work test

# sudo のパスワード入力なしで、指定した行を /etc/sudoers.d/<名前> に書き込む関数(標準入力から受け取る)
allow_sudo() {
  # 標準入力の内容をファイルに書く
  sudo tee "/etc/sudoers.d/$1" > /dev/null
  # 読み取り専用の権限にする(sudoers の決まり)
  sudo chmod 0440 "/etc/sudoers.d/$1"
}
# attach.sh が使う nsenter を、パスワードなしで実行できるようにする
echo "$CURRENT_USER ALL=(root) NOPASSWD: /usr/bin/nsenter" | allow_sudo nsenter
# attach.sh が使うコンテナの起動と状態の確認を、パスワードなしで実行できるようにする
{
  echo "$CURRENT_USER ALL=(root) NOPASSWD:SETENV: /usr/bin/docker compose up -d atcoder-nim"
  echo "$CURRENT_USER ALL=(root) NOPASSWD: /usr/bin/docker inspect --format {{.State.Pid}} atcoder-nim"
} | allow_sudo atcoder-attach
# 提出用にまとめたコード(bundled.txt)の読み出しを、パスワードなしで実行できるようにする
echo "$CURRENT_USER ALL=(root) NOPASSWD: /usr/bin/docker exec --user dev atcoder-nim /bin/cat /workspace/atcoder-nim-env/bundled.txt" | allow_sudo atcoder-copy-bundled

# コンテナ内のユーザーを、今のユーザーと同じ UID と GID にするため、docker compose に渡す
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"
# コンテナを作り直して起動する(必要な環境変数は sudo を通して渡す)
sudo --preserve-env=DEV_UID,DEV_GID,TS_AUTHKEY docker compose up -d --build atcoder-nim
