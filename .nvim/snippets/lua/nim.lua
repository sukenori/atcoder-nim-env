local ls = require("luasnip")
local c, sn, i, t, f = ls.choice_node, ls.snippet_node, ls.insert_node, ls.text_node, ls.function_node

return {
  s("header", {
    t('include "template.nim"'),
  }),
}