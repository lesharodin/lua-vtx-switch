local script = assert(loadScript("/SCRIPTS/TOOLS/lvtxrc.lua"))()

local function run(event)
  -- Telemetry screens leave on long RTN; short RTN must keep drawing.
  script.run(event, true)
  return 0
end

return { run=run, init=script.init}
