local defaults, colorIds, colorLabels
local values = {}
local draft = {}
local configPath
local position = 1
local editing = false
local message


local function init(defaultValues, ids, labels)
  defaults, colorIds, colorLabels = defaultValues, ids, labels
  for _, id in ipairs(colorIds) do
    values[id] = defaults[id]
  end

  -- The model file stays the same when its display name is changed.
  local info = model.getInfo()
  if info and info.filename and info.filename ~= "" then
    local filename = info.filename
    if not string.find(filename, "[^%w_.-]") then
      configPath = "colors_" .. filename .. ".txt"
    end
  end
  if not configPath then
    return
  end
  local file = io.open(configPath, "r")
  if not file then
    return
  end
  local data = io.read(file, 160) or ""
  io.close(file)
  for id, value in string.gmatch(data, "(%d+)=([%-]?%d+)") do
    id, value = tonumber(id), tonumber(value)
    if defaults[id] and value >= -1024 and value <= 1024 then
      values[id] = value
    end
  end
end


local function getValue(id)
  return values[id]
end


local function open(colorPosition)
  for _, id in ipairs(colorIds) do
    draft[id] = values[id]
  end
  position = colorPosition
  editing = false
  message = nil
end


local function save()
  if not configPath then
    message = "No model ID"
    return false
  end
  local file = io.open(configPath, "w")
  if not file then
    message = "Save failed"
    return false
  end
  local data = ""
  for _, id in ipairs(colorIds) do
    data = data .. tostring(id) .. "=" .. tostring(draft[id]) .. "\n"
  end
  local ok = io.write(file, data)
  io.close(file)
  if not ok then
    message = "Save failed"
    return false
  end
  for _, id in ipairs(colorIds) do
    values[id] = draft[id]
  end
  return true
end


local function draw()
  lcd.clear()
  local large = LCD_H > 96
  local left = large and math.floor(LCD_W / 2) - 140 or 0
  local top = large and 55 or 0
  local rowHeight = large and 30 or 12
  local width = large and 280 or LCD_W
  lcd.drawText(left, top, message or "Color tuner")
  local first = math.max(1, math.min(position - 2, #colorIds - 1))
  for row = 1, 3 do
    local item = first + row - 1
    local y = top + row * rowHeight
    local flags = 0
    if item == position then
      lcd.drawFilledRectangle(left, y, width, rowHeight, SOLID)
      flags = INVERS
    end
    if item <= #colorIds then
      lcd.drawText(left + 2, y + 1, colorLabels[item], flags)
      local text = tostring(draft[colorIds[item]])
      if item == position and editing then
        text = "<" .. text .. ">"
      end
      lcd.drawText(left + width - (large and 85 or 48), y + 1, text, flags)
    else
      lcd.drawText(left + 2, y + 1, "Save & back", flags)
    end
  end
  lcd.drawText(left, top + rowHeight * 4 + (large and 5 or 7),
    editing and "ENT:OK MENU:reset" or "ENT:edit EXIT:cancel")
end


local function run(event, preview)
  local changed = false
  if event == EVT_EXIT_BREAK then
    if editing then
      editing = false
    else
      return true
    end
  elseif event == EVT_ENTER_BREAK then
    if position == #colorIds + 1 then
      if save() then
        return true
      end
    else
      editing = not editing
      changed = true
    end
  elseif event == EVT_MENU_BREAK and position <= #colorIds then
    draft[colorIds[position]] = defaults[colorIds[position]]
    changed = true
  elseif editing then
    local step = 0
    if event == EVT_VIRTUAL_INC then
      step = 5
    elseif event == EVT_VIRTUAL_DEC then
      step = -5
    elseif event == EVT_VIRTUAL_INC_REPT then
      step = 20
    elseif event == EVT_VIRTUAL_DEC_REPT then
      step = -20
    end
    if step ~= 0 then
      local id = colorIds[position]
      draft[id] = math.max(-1024, math.min(1024, draft[id] + step))
      changed = true
    end
  else
    if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT then
      position = math.min(#colorIds + 1, position + 1)
      changed = true
    elseif event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT then
      position = math.max(1, position - 1)
      changed = true
    end
  end
  if changed then
    message = nil
    if position <= #colorIds then
      preview(draft[colorIds[position]])
    end
  end
  draw()
  return false
end


return { init=init, getValue=getValue, open=open, run=run }
