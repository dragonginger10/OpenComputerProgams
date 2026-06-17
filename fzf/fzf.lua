local component = require("component")
local event     = require("event")
local keyboard  = require("keyboard")
local term      = require("term")
local gpu       = component.gpu

-- === Terminal size ===
local function get_term_height()
  local _, h = gpu.getResolution()
  return h - 2
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
  for line in io.lines() do
    lines[#lines + 1] = line
  end
  return lines
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

-- === Render ===
local function render(query, matches, cursor, height, total)
  local w = gpu.getResolution()
  local visible = math.min(#matches, height)

  for i = 1, visible do
    if i == cursor then
      gpu.setBackground(0xFFFFFF)
      gpu.setForeground(0x000000)
    else
      gpu.setBackground(0x000000)
      gpu.setForeground(0xFFFFFF)
    end
    local line = "> " .. matches[i].line
    if #line > w then line = line:sub(1, w) end
    gpu.set(1, i, line .. string.rep(" ", w - #line))
  end

  -- clear leftover lines from a previous longer match list
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  for i = visible + 1, height do
    gpu.set(1, i, string.rep(" ", w))
  end

  -- status line
  gpu.setForeground(0x00FF00)
  local status = string.format("  %d/%d", #matches, total)
  gpu.set(1, height + 1, status .. string.rep(" ", w - #status))

  -- prompt
  gpu.setForeground(0xFFFFFF)
  local prompt = "> " .. query
  if #prompt > w then prompt = prompt:sub(1, w) end
  gpu.set(1, height + 2, prompt .. string.rep(" ", w - #prompt))
end

-- === Read a keypress via OC events ===
local function readkey()
  local _, _, char, code = event.pull("key_down")
  if code == keyboard.keys.enter  then return "\r" end
  if code == keyboard.keys.back   then return "\127" end
  if code == keyboard.keys.up     then return "UP" end
  if code == keyboard.keys.down   then return "DOWN" end
  if code == keyboard.keys.escape then return "ESC" end
  if char == 3                    then return "\3" end  -- Ctrl-C
  if char and char >= 32          then return string.char(char) end
  return nil
end

-- === Main ===
local function main()
  local lines = read_lines()

  local old_fg = gpu.getForeground()
  local old_bg = gpu.getBackground()
  term.clear()

  local height  = get_term_height()
  local query   = ""
  local cursor  = 1
  local matches = filter(lines, query)

  render(query, matches, cursor, height, #lines)

  while true do
    local key = readkey()

    if key == "\r" or key == "\n" then
      break
    elseif key == "\3" or key == "ESC" then
      gpu.setForeground(old_fg)
      gpu.setBackground(old_bg)
      term.clear()
      os.exit(1)
    elseif key == "\127" or key == "\8" then
      query = query:sub(1, -2)
      matches = filter(lines, query)
      cursor = 1
    elseif key == "UP" then
      cursor = math.max(1, cursor - 1)
    elseif key == "DOWN" then
      cursor = math.min(#matches, cursor + 1)
    elseif key and #key == 1 and key:byte() >= 32 then
      query = query .. key
      matches = filter(lines, query)
      cursor = 1
    end

    render(query, matches, cursor, height, #lines)
  end

  gpu.setForeground(old_fg)
  gpu.setBackground(old_bg)
  term.clear()

  if matches[cursor] then
    io.write(matches[cursor].line .. "\n")
  end
end

main()
