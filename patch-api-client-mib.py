import pathlib
import onlinejudge.service.atcoder as module

path = pathlib.Path(module.__file__)
source = path.read_text(encoding="utf-8")

if "MiB" in source:
    print("already patched:", path)
    raise SystemExit(0)

edits = [
    (
        "r'^(メモリ制限|Memory Limit): ([0-9.]+) (KB|MB)'",
        "r'^(メモリ制限|Memory Limit): ([0-9.]+) (KiB|MiB|KB|MB)\\b'",
    ),
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

for old, new in edits:
    if source.count(old) != 1:
        raise SystemExit("想定したコードと一致しません。変更しません: " + old[:60])
    source = source.replace(old, new, 1)

path.write_text(source, encoding="utf-8")
print("patched:", path)