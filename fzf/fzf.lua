#!/usr/bin/env lua

-- === Terminal handling ===
local function raw_on()
  os.execute("stty raw -echo 2>/dev/null")
end

local function raw_off()
  os.execute("stty sane 2>/dev/null")
end

local function get_term_height()
  local h = io.popen("tput lines"):read("*n")
  return (h or 24) - 2  -- reserve 2 lines for prompt + status
end

-- === Fuzzy match (subsequence) ===
local function fuzzy_match(str, pattern)
  if pattern == "" then return true, 0 end
  local score = 0
  local pi = 1
  local lower_str = str:lower()
  local lower_pat = pattern:lower()

  for si = 1, #lower_str do
    if lower_str:sub(si, si) == lower_pat:sub(pi, pi) then
      -- bonus for consecutive or start-of-word
      score = score + 1
      pi = pi + 1
      if pi > #lower_pat then return true, score end
    end
  end
  return false, 0
end

-- === Read all stdin lines ===
local function read_lines()
  local lines = {}
  -- read from stdin (piped input)
  for line in io.lines() do
    lines[#lines + 1] = line
  end
  return lines
end

-- === ANSI helpers ===
local ESC = "\27"
local function clear_screen() io.write(ESC .. "[2J" .. ESC .. "[H") end
local function move_to(r, c) io.write(ESC .. string.format("[%d;%dH", r, c)) end
local function color(code) io.write(ESC .. "[" .. code .. "m") end
local function reset_color() io.write(ESC .. "[0m") end

-- === Render ===
local function render(query, matches, cursor, height)
  clear_screen()
  local visible = math.min(#matches, height)

  -- draw matches (bottom-up like fzf, or top-down for simplicity)
  for i = 1, visible do
    move_to(i, 1)
    if i == cursor then
      color("7")  -- inverse
      io.write("> " .. matches[i].line)
      reset_color()
    else
      io.write("  " .. matches[i].line)
    end
  end

  -- prompt line at bottom
  move_to(height + 1, 1)
  color("32")
  io.write(string.format("  %d/%d", #matches, #matches))
  reset_color()
  move_to(height + 2, 1)
  io.write("> " .. query)
  io.flush()
end

-- === Filter ===
local function filter(lines, query)
  local results = {}
  for _, line in ipairs(lines) do
    local ok, score = fuzzy_match(line, query)
    if ok then
      results[#results + 1] = { line = line, score = score }
    end
  end
  table.sort(results, function(a, b) return a.score > b.score end)
  return results
end

-- === Read a keypress ===
local function readkey()
  local c = io.read(1)
  if c == ESC then
    local seq = io.read(1)
    if seq == "[" then
      local code = io.read(1)
      if code == "A" then return "UP" end
      if code == "B" then return "DOWN" end
    end
    return "ESC"
  end
  return c
end

-- === Main ===
local function main()
  -- Redirect stdin: read piped data, then reopen tty for keyboard
  local lines = read_lines()
  io.input(io.open("/dev/tty", "r"))
  io.output(io.open("/dev/tty", "w"))

  local height = get_term_height()
  local query = ""
  local cursor = 1
  local matches = filter(lines, query)

  raw_on()
  render(query, matches, cursor, height)

  while true do
    local key = readkey()

    if key == "\r" or key == "\n" then         -- Enter: select
      break
    elseif key == "\3" or key == "ESC" then    -- Ctrl-C / Esc: abort
      raw_off(); clear_screen()
      os.exit(1)
    elseif key == "\127" or key == "\8" then   -- Backspace
      query = query:sub(1, -2)
      matches = filter(lines, query)
      cursor = 1
    elseif key == "UP" then
      cursor = math.max(1, cursor - 1)
    elseif key == "DOWN" then
      cursor = math.min(#matches, cursor + 1)
    elseif key and #key == 1 and key:byte() >= 32 then  -- printable
      query = query .. key
      matches = filter(lines, query)
      cursor = 1
    end

    render(query, matches, cursor, height)
  end

  raw_off()
  clear_screen()

  -- Output selection to real stdout
  if matches[cursor] then
    local out = io.open("/dev/stdout", "w")
    out:write(matches[cursor].line .. "\n")
    out:close()
  end
end

main()
