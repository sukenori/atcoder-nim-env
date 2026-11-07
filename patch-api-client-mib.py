# online-judge-tools の AtCoder 用コードを書き換える。AtCoder のメモリ制限が KiB / MiB 表記になったため
# Docker のビルド時に一度だけ実行される(Dockerfile から呼ばれる)

# ファイルの場所を扱うモジュール
import pathlib
# 書き換える対象の、online-judge-tools の AtCoder 用モジュール
import onlinejudge.service.atcoder as module

# 書き換える対象のファイルの場所
path = pathlib.Path(module.__file__)
# ファイルの中身を文字列として読み込む
source = path.read_text(encoding="utf-8")

# すでに書き換え済み("MiB" が含まれる)なら、何もせず終わる
if "elif tds[3].text.endswith(' MiB')" in source:
    print("already patched:", path)
    raise SystemExit(0)

# 書き換えの一覧。各項目は(元のコード, 新しいコード)の組
edits = [
    # 1つ目: メモリ制限を読み取る正規表現に、単位 KiB と MiB を加える
    (
        "r'^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB)'",
        "r'^(メモリ制限|Memory Limit): ([0-9.]+) (KiB|MiB|KB|MB)\\b'",
    ),
    # 2つ目: 読み取った単位が KiB と MiB のときの、バイト数の計算を加える
    (
        "        elif memory_limit_unit == 'MB':\n"
        "            memory_limit_byte = int(float(memory_limit_value) * 1000 * 1000)\n"
        "        else:\n",
        "        elif memory_limit_unit == 'MB':\n"
        "            memory_limit_byte = int(float(memory_limit_value) * 1000 * 1000)\n"
        "        elif memory_limit_unit == 'KiB':\n"
        "            memory_limit_byte = int(float(memory_limit_value) * 1024)\n"
        "        elif memory_limit_unit == 'MiB':\n"
        "            memory_limit_byte = int(float(memory_limit_value) * 1024 * 1024)\n"
        "        else:\n",
    ),
    # 3つ目: 問題一覧の表の、メモリ制限の末尾が KiB と MiB のときの、バイト数の計算を加える
    (
        "        elif tds[3].text.endswith(' MB'):\n"
        "            memory_limit_byte = int(float(utils.remove_suffix(tds[3].text, ' MB')) * 1000 * 1000)  # TODO: confirm this is MB truly, not MiB\n"
        "        else:\n",
        "        elif tds[3].text.endswith(' MB'):\n"
        "            memory_limit_byte = int(float(utils.remove_suffix(tds[3].text, ' MB')) * 1000 * 1000)  # TODO: confirm this is MB truly, not MiB\n"
        "        elif tds[3].text.endswith(' KiB'):\n"
        "            memory_limit_byte = int(float(utils.remove_suffix(tds[3].text, ' KiB')) * 1024)\n"
        "        elif tds[3].text.endswith(' MiB'):\n"
        "            memory_limit_byte = int(float(utils.remove_suffix(tds[3].text, ' MiB')) * 1024 * 1024)\n"
        "        else:\n",
    ),
]

# 元のコードがちょうど1か所だけ見つかる場合に限り、書き換える
for old, new in edits:
    # 見つからない、または複数見つかる場合は、想定と違うので何も書き換えずに止める
    if source.count(old) != 1:
        raise SystemExit("想定したコードと一致しません。変更しません: " + old[:60])
    # 見つかった1か所を、新しいコードに置き換える
    source = source.replace(old, new, 1)

# 書き換えた内容をファイルに保存する
path.write_text(source, encoding="utf-8")
# 書き換えたことを表示する
print("patched:", path)