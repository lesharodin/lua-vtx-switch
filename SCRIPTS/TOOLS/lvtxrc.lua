chdir("/SCRIPTS/TOOLS/LEDVTXRACE")

local toolName = "TNS|LED & VTX Race|TNE"

local gui = assert(loadScript("gui.lua"))()
local config = assert(loadScript("config.lua"))()
local com = assert(loadScript("com.lua"))()
local tuner = assert(loadScript("tuner.lua"))()

local ITEM_OPTS = 1
local ITEM_LED = 2
local ITEM_VTX = 3
local ITEM_SAVE = 4

local ITEM_POWER = 5
local ITEM_VTX_MODE = 6
local ITEM_BANDS = 7
local ITEM_GV = 8
local ITEM_TUNER = 9

local IDLE=1
local BUSY=2
local DONE=3
local FAIL=4

local VTX_MODE_MSP = 1
local VTX_MODE_ELRS = 2

local BANDS_ANALOG = 1
local BANDS_HDZERO = 2

local colorLabels = { "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Violet", "Magenta" }
local colorIds = { 2, 3, 4, 6, 8, 10, 11, 12 }

local bandNames = { "Band A", "Band B", "Band E", "Fatshark", "Raceband", "Lowband"}
local bandIds = { 1, 2, 3, 4, 5, 6 }

local vtxModeLabels = {"MSP", "ELRS"}
local vtxModeIds = {VTX_MODE_MSP, VTX_MODE_ELRS}

local bandsLabels = {"Analog", "HDZero"}
local bandsIds = {BANDS_ANALOG, BANDS_HDZERO}

local gvLabels = {}
local gvIds = {}
for i = 1, 9 do
  gvLabels[#gvLabels+1] = "GV" .. tostring(i)
  gvIds[#gvIds+1] = i - 1
end

-- GV values for the Betaflight CT palette documented in README.md:
-- color 0 = H0, color 1 = H178, color 2 = H359.
local colorGvValues = {
  [2] = -1024, -- Red, H0
  [3] = -966,  -- Orange, H10
  [4] = -851,  -- Yellow, H30
  [6] = -334,  -- Green, H120
  [8] = 11,    -- Cyan, H180
  [10] = 350,  -- Blue, H240
  [11] = 605,  -- Violet, H285
  [12] = 973   -- Magenta, H350
}

local powerLabels = {}
local powerIds = {}
powerLabels[#powerLabels+1] = "-"
powerIds[#powerIds+1] = 0
for i = 1, 8 do
  powerLabels[#powerLabels+1] = tostring(i)
  powerIds[#powerIds+1] = i
end

local analogChannels = {}
local hdzeroChannels = {}
local channelLabels = {}
local channelIds = {}

local function addChannel(list, band, channel)
  list[#list+1] = {band, channel}
end

for iBand = 1, #bandNames do
  for iCh = 1, 8 do
    addChannel(analogChannels, bandIds[iBand], iCh)
  end
end

for iCh = 1, 8 do
  addChannel(hdzeroChannels, 5, iCh)
end
addChannel(hdzeroChannels, 3, 1)
addChannel(hdzeroChannels, 4, 1)
addChannel(hdzeroChannels, 4, 2)
addChannel(hdzeroChannels, 4, 4)
for iCh = 1, 8 do
  addChannel(hdzeroChannels, 6, iCh)
end

menu = {}

menu[ITEM_LED] = {labels = colorLabels, values = colorIds, pos = 1}
menu[ITEM_VTX] = {labels = channelLabels, values = channelIds, pos = 1}
menu[ITEM_POWER] = {labels = powerLabels, values = powerIds, pos = 1}
menu[ITEM_VTX_MODE] = {labels = vtxModeLabels, values = vtxModeIds, pos = 1}
menu[ITEM_BANDS] = {labels = bandsLabels, values = bandsIds, pos = 1}
menu[ITEM_GV] = {labels = gvLabels, values = gvIds, pos = 9}


local menuPosition = ITEM_LED
local isItemActive = false
local isOptionsMenuActive = false
local isTunerActive = false
local state = IDLE
local vtxConfigVersion = nil
local statusText = nil


local function getVtxMode()
  return menu[ITEM_VTX_MODE].values[menu[ITEM_VTX_MODE].pos]
end


local function getBandsMode()
  return menu[ITEM_BANDS].values[menu[ITEM_BANDS].pos]
end


local function getBandName(band)
  for i = 1, #bandIds do
    if bandIds[i] == band then
      return bandNames[i]
    end
  end
  return "Band " .. tostring(band)
end


local function channelLabel(band, channel)
  if band and channel then
    return getBandName(band) .. " " .. tostring(channel)
  end
  return "   * * * *"
end


local function fillChannelList(currentBand, currentChannel)
  local source = getBandsMode() == BANDS_HDZERO and hdzeroChannels or analogChannels
  channelLabels = {}
  channelIds = {}

  for i = 1, #source do
    local band = source[i][1]
    local channel = source[i][2]
    channelLabels[#channelLabels+1] = channelLabel(band, channel)
    channelIds[#channelIds+1] = {band, channel}
  end

  channelLabels[#channelLabels+1] = "   * * * *"
  channelIds[#channelIds+1] = {nil, nil}

  if currentBand and currentChannel then
    for i = 1, #channelIds do
      if channelIds[i][1] == currentBand and channelIds[i][2] == currentChannel then
        menu[ITEM_VTX].labels = channelLabels
        menu[ITEM_VTX].values = channelIds
        menu[ITEM_VTX].pos = i
        return
      end
    end

    channelLabels[#channelLabels+1] = channelLabel(currentBand, currentChannel)
    channelIds[#channelIds+1] = {currentBand, currentChannel}
    menu[ITEM_VTX].pos = #channelLabels
  end

  menu[ITEM_VTX].labels = channelLabels
  menu[ITEM_VTX].values = channelIds
  if menu[ITEM_VTX].pos > #channelLabels then
    menu[ITEM_VTX].pos = #channelLabels
  end
end


fillChannelList()


local function setAuxLedValue(gvValue)
  local gvIndex = menu[ITEM_GV].values[menu[ITEM_GV].pos]
  model.setGlobalVariable(gvIndex, 0, gvValue)
end


local function setAuxLedColor(color)
  local gvValue = tuner.getValue(color)
  if not gvValue then
    return false
  end
  setAuxLedValue(gvValue)
  return true
end


local function restoreAuxLedColor()
  if not model.getGlobalVariable then
    return false
  end
  local gvIndex = menu[ITEM_GV].values[menu[ITEM_GV].pos]
  local gvValue = model.getGlobalVariable(gvIndex, 0)
  for i = 1, #colorIds do
    if tuner.getValue(colorIds[i]) == gvValue then
      menu[ITEM_LED].pos = i
      return true
    end
  end
  return false
end


local function previewAuxLedColor()
  if menuPosition == ITEM_LED then
    setAuxLedColor(menu[ITEM_LED].values[menu[ITEM_LED].pos])
  end
end


local function saveOptionChange()
  if not isOptionsMenuActive or menuPosition > ITEM_GV then
    return
  end
  if menuPosition == ITEM_BANDS then
    local current = menu[ITEM_VTX].values[menu[ITEM_VTX].pos]
    fillChannelList(current[1], current[2])
  elseif menuPosition == ITEM_GV then
    setAuxLedColor(menu[ITEM_LED].values[menu[ITEM_LED].pos])
  end
  config.save(menu)
end


local function itemIncrease()

  if menu[menuPosition] then
    if menu[menuPosition].pos < #menu[menuPosition].labels then
      menu[menuPosition].pos = menu[menuPosition].pos + 1
      previewAuxLedColor()
      saveOptionChange()
    end
  end
end


local function itemDecrease()
  if menu[menuPosition] then
    if menu[menuPosition].pos > 1 then
      menu[menuPosition].pos = menu[menuPosition].pos - 1
      previewAuxLedColor()
      saveOptionChange()
    end
  end
end


local function menuMoveDown()
  if menuPosition ~= ITEM_SAVE and menuPosition ~= ITEM_TUNER then
    menuPosition = menuPosition + 1
  end
end


local function menuMoveUp()
  if menuPosition ~= 1 and menuPosition ~= ITEM_SAVE+1 then
    menuPosition = menuPosition - 1
  end
end


local function refreshStatus()
  local event
  statusText, event = com.getStatus()
  if statusText then
    state = BUSY
  elseif event == 1 then
    state = DONE
  elseif event == -1 then
    state = FAIL
  end
end


local function drawDisplay()
  if isTunerActive then
    tuner.run(0, setAuxLedValue)
    return
  end
  lcd.clear()
  if isOptionsMenuActive then
    local firstOption = menuPosition - 3
    if firstOption < ITEM_POWER then
      firstOption = ITEM_POWER
    elseif firstOption > ITEM_TUNER - 3 then
      firstOption = ITEM_TUNER - 3
    end
    for row = 1, 4 do
      local item = firstOption + row - 1
      local label = ""
      local offset = nil
      if item == ITEM_POWER then
        label = "Power Level"
      elseif item == ITEM_VTX_MODE then
        label = "VTX Mode"
      elseif item == ITEM_BANDS then
        label = "Bands"
      elseif item == ITEM_GV then
        label = "LED GV"
      end
      if item == ITEM_TUNER then
        gui.drawSmallSelector(row, "Color tuner", ">", menuPosition==item, false)
      else
        gui.drawSmallSelector(row, label, menu[item].labels[menu[item].pos], menuPosition==item, isItemActive, offset)
      end
    end
  else
    
    gui.drawSelector(1, colorLabels[menu[ITEM_LED].pos], menuPosition==ITEM_LED, isItemActive)
    gui.drawSelector(2, channelLabels[menu[ITEM_VTX].pos], menuPosition==ITEM_VTX, isItemActive)

    local btnText = statusText
    btnSelected = (not statusText) and (menuPosition == ITEM_SAVE)
    if not statusText then
      if state == DONE then
        btnText = "Done"
      elseif state == FAIL then
        btnText = "Failed"
      else
        btnText = "Save"
      end
    end
    gui.drawOptions(menuPosition == ITEM_OPTS)
    gui.drawButton(btnText, btnSelected)
  end
  gui.drawStatus()
end


local function applyVtxConfig(config_)
  if not config_ or config_.version == vtxConfigVersion then
    return
  end
  if menuPosition == ITEM_VTX or isItemActive or state ~= IDLE then
    return
  end
  -- Mirror the current TX-module VTX state into the menu without forcing a write.
  fillChannelList(config_.band, config_.channel)
  vtxConfigVersion = config_.version
  if config_.power then
    for i = 1, #powerIds do
      if powerIds[i] == config_.power then
        menu[ITEM_POWER].pos = i
        break
      end
    end
  end
end


local function prepareVtxArgs()
  return {
    band = menu[ITEM_VTX].values[menu[ITEM_VTX].pos][1],
    channel = menu[ITEM_VTX].values[menu[ITEM_VTX].pos][2],
    power = menu[ITEM_POWER].values[menu[ITEM_POWER].pos],
    vtxMode = getVtxMode()
  }
end


local function sendElrsVtxConfig()
  local args = prepareVtxArgs()
  if getVtxMode() ~= VTX_MODE_ELRS or not args.band then
    return
  end
  state = BUSY
  config.save(menu)
  com.sendVtxConfig(args)
end


local function processEnterPress()
  if menuPosition == ITEM_TUNER then
    tuner.open(menu[ITEM_LED].pos)
    setAuxLedColor(menu[ITEM_LED].values[menu[ITEM_LED].pos])
    isTunerActive = true
    return
  end
  if menuPosition == ITEM_OPTS then
    menuPosition = ITEM_SAVE + 1
    isOptionsMenuActive = true
    return
  end
  if menuPosition ~= ITEM_SAVE and menuPosition ~= ITEM_OPTS then
    local wasActive = isItemActive
    isItemActive = not isItemActive
    if wasActive and (menuPosition == ITEM_VTX or menuPosition == ITEM_POWER) then
      sendElrsVtxConfig()
    end
  else
    state = BUSY
    state = DONE -- TODO: remove this line
    config.save(menu)

    local args = prepareVtxArgs()
    setAuxLedColor(menu[ITEM_LED].values[menu[ITEM_LED].pos])
    com.sendVtxConfig(args)
  end
end


local function run_func(event, telemetryScreen)
  com.mainLoop(getVtxMode())
  refreshStatus()
  if isTunerActive then
    if tuner.run(event, setAuxLedValue) then
      isTunerActive = false
      setAuxLedColor(menu[ITEM_LED].values[menu[ITEM_LED].pos])
      drawDisplay()
    end
    return 0
  end
  if getVtxMode() == VTX_MODE_ELRS then
    applyVtxConfig(com.getVtxConfig())
  end
  if state ~= BUSY then
    if isItemActive then
      if event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT then
        itemIncrease()
      else
        if event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_DEC_REPT then
          itemDecrease()
        end
      end
      if event == EVT_EXIT_BREAK then
        isItemActive = false
      end
    else 
      if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT then
        menuMoveDown()
      else
        if event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT then
          menuMoveUp()
        end
      end
      if event == EVT_EXIT_BREAK then
        if isOptionsMenuActive then
          isOptionsMenuActive = false
          menuPosition = ITEM_LED
        elseif not telemetryScreen then
          return -1
        end
      end
    end
  end
  if event == EVT_ENTER_BREAK then
    processEnterPress()
  end
  if event == EVT_MENU_BREAK then
    com.setDebug()
  end
  if event == EVT_EXIT_BREAK then
    com.cancel()
    state = IDLE
  end  
  if ((state == DONE) or (state == FAIL)) and (event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV) then 
    state = IDLE
  end
  drawDisplay()
  return 0
end


local function bg_func()
end


local function init_func()
  config.load_(menu)
  tuner.init(colorGvValues, colorIds, colorLabels)
  restoreAuxLedColor()
  fillChannelList()
end


return { run=run_func, background=bg_func, init=init_func}
