-- uartbook.lua - the one piece of the design that TeX macros cannot do cleanly.
--
-- \code{...} typesets VHDL and C++ exactly as they are written in the lectures. \detokenize gets
-- most of the way, but leaves two artifacts that code runs into constantly: it doubles every #, so
-- #include would print as ##include, and it puts a space after every control word, so "\n" would
-- print as "\n ". Both are undone here, and a line break is allowed after a scope operator or a
-- comma, so a name like driver::transport::Interface can break at a :: rather than run into the
-- margin.

local catcode_other = -2

function uartbook_code(s)
  s = s:gsub("#+", "#")
  s = s:gsub("(\\%a+) ", "%1")
  -- \%, \{ and \} are how a literal percent sign or an unbalanced brace has to be written inside
  -- a TeX argument, \# is how a # has to be written in a heading or a caption, and \\ is a
  -- lone backslash.
  s = s:gsub("\\([%%{}#\\])", "%1")
  -- A break is allowed after a :: and after a comma with no space behind it; a comma followed by
  -- a space needs nothing, because the space is a breakpoint already. Each tex.sprint is read as a
  -- line of its own and TeX skips the spaces a line starts with, so no chunk may begin with one.
  local start = 1
  while true do
    local i, j = s:find("::", start, true)
    local k = s:find(",[^ ]", start)
    if k and (not i or k < i) then i, j = k, k end
    if not i then break end
    tex.sprint(catcode_other, s:sub(start, j))
    -- Discouraged rather than free, so a line breaks at a space when it can.
    tex.sprint("\\penalty100 ")
    start = j + 1
  end
  tex.sprint(catcode_other, s:sub(start))
end
