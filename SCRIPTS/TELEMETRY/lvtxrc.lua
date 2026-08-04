local script = assert(loadScript("/SCRIPTS/TOOLS/lvtxrc.lua"))()

local function run(event)
  script.run(event)
  return 0
end

return { run=run, init=script.init}
