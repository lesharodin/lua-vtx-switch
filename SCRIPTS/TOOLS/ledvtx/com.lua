local msp = assert(loadScript("msp.lua"))()
local elrs = assert(loadScript("elrs.lua"))()

local VTX_MODE_MSP = 1
local VTX_MODE_ELRS = 2

local MSP_VTX_SET_CONFIG = 89
local MSP_EEPROM_WRITE = 250

local isBusy = false
local retryCount = 0
local maxRetries = 4
local retryTimeout = 200
local nextTryTime = 0

local successFlag = false
local failedFlag = false
local transactionActive = false
local mspResult = 1
local elrsResult = 1
local commandSequence = {}
local commandPointer = 0
local currentCommand = {}

local debugButtonState = false

local function getDebugButtonState()
  if debugButtonState then
    debugButtonState = false
    return true
  else 
    return false
  end
end

local function setDebugButtonState()
  debugButtonState = true
end


local function sendCurrentCommand()
  retryCount = retryCount + 1
  if retryCount > maxRetries then
    isBusy = false
    mspResult = -1
    failedFlag = true
    return
  end
  if currentCommand.write then
    msp.write(currentCommand.header, currentCommand.payload)
  else
    msp.read(currentCommand.header, currentCommand.payload)
  end
  nextTryTime = getTime() + retryTimeout
  print(currentCommand.text)
end


local function gotoNextCommand()
  if commandPointer < #commandSequence then
    commandPointer = commandPointer + 1
    currentCommand = commandSequence[commandPointer]
    retryCount = 0
    sendCurrentCommand()
  else
    mspResult = 1
    successFlag = true
    currentCommand = nil
    isBusy = false
  end
end


function processMspReply(cmd, rx_buf)
  local key = getDebugButtonState()
  if (cmd == nil or rx_buf == nil) and not key then
    return
  end
  if isBusy and (key or (cmd == currentCommand.header)) then
    gotoNextCommand()
  end
end


local function startTransmission(commands) 
  commandSequence = commands
  commandPointer = 0
  isBusy = true
  gotoNextCommand()
end


local function prepareVtxCommand(band, channel, power)
  local cmd = {}
  if power < 1 then
    power = 1
  end
  cmd.header = MSP_VTX_SET_CONFIG
  cmd.payload = { (band-1)*8 + (channel-1), 0, power, 0 }
  cmd.write = true
  cmd.text = "Switching VTX"
  return cmd
end


local function prepareSaveCommand()
  local cmd = {}
  cmd.header = MSP_EEPROM_WRITE
  cmd.payload = nil
  cmd.write = false
  cmd.text = "Saving"
  return cmd
end


local function sendVtxConfig(args)
  retryCount = 0
  transactionActive = true
  mspResult = (args.band and args.vtxMode == VTX_MODE_MSP) and 0 or 1
  elrsResult = (args.band and args.vtxMode == VTX_MODE_ELRS) and 0 or 1
  print('Config')
  print('VTX:', args.band, args.channel)
  print('VTX mode:', args.vtxMode)

  local cmd = {}
  if args.band and args.vtxMode == VTX_MODE_ELRS then
    -- VTX config goes to the ELRS TX module; it forwards the change itself.
    elrs.sendVtxConfig(args)
  elseif args.band then
    -- Original path: write VTX directly to Betaflight over MSP.
    cmd[#cmd+1] = prepareVtxCommand(args.band, args.channel, args.power)
  end
  if #cmd > 0 then
    cmd[#cmd+1] = prepareSaveCommand()
  end
  if #cmd > 0 then
    startTransmission(cmd)
  end
end  


local function getStatus()
  local text = nil
  local flag = 0
  local elrsText, elrsEvent = elrs.getStatus()
  if isBusy then 
    if currentCommand then
      text = currentCommand.text .. " (" .. tostring(retryCount) .. ")"
    end
  elseif elrsText then
    text = elrsText
  end

  if elrsEvent ~= 0 then
    elrsResult = elrsEvent
  end
  if failedFlag or mspResult < 0 or elrsResult < 0 then
    flag = -1
    failedFlag = false
    successFlag = false
    transactionActive = false
  elseif transactionActive and mspResult > 0 and elrsResult > 0 then
    flag = 1
    successFlag = false
    transactionActive = false
  elseif successFlag then
    successFlag = false
  end
  return text, flag
end


function comMainLoop(vtxMode)
  if isBusy then
    currentTime = getTime()
    if currentTime > nextTryTime then 
      sendCurrentCommand()
    end
    msp.processTxQ()
    processMspReply(msp.pollReply())
  elseif elrs.isBusy() then
    -- Keep pumping ELRS telemetry while it resolves discovery/read/write.
    elrs.mainLoop()
  else
    if vtxMode == VTX_MODE_ELRS then
      elrs.mainLoop()
    end
  end
end


function cancel()
  isBusy = false
  transactionActive = false
end


return { sendVtxConfig = sendVtxConfig, mainLoop = comMainLoop, getStatus=getStatus,
  cancel=cancel, setDebug=setDebugButtonState, getVtxConfig=elrs.getVtxConfig}
