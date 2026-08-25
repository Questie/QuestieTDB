#!/usr/bin/env lua
-- tools/strip-static.lua
--
-- Strips Static Correction function bodies from a staged package (issue #5).
--
-- Baked artifacts ship whole correction files because the shipping unit is the file and
-- upstream keeps a small Dynamic function beside a large Static one in the same file —
-- splitting the file would fork it and kill the byte-identical re-sync. But the static
-- halves are already folded into the TOC metadata store, so 94-96% of every shipped
-- correction file is data the client parses at login and can never use.
--
-- This tool rewrites the STAGED COPIES only. `src/corrections/` in the repository stays
-- byte-identical to upstream, so `tools/port-corrections.lua` and the CI drift gate keep
-- working — they compare the source tree, never the artifact.
--
-- Safety is layered, and every failure aborts packaging:
--   * a static function must be found exactly once, as a column-0 `function Module:Name(`
--     with a column-0 closing `end` — the upstream style every ported file follows;
--   * the stripped file must still compile (`loadstring`);
--   * every Dynamic and Parameterized function must still be defined after the strip;
--   * the stripped file must behave identically to the original for everything Baked mode
--     uses: the module-level objectiveFirst hints, the set of functions on the module, and
--     the full output (returned table + captured direct writes) of every Dynamic and
--     Parameterized function, executed under the same compat shim and client persona.
--
-- That last check is the mechanical form of issue #5's verification item 1: if a needed
-- module-level side effect ever moves inside a static body, the parity check fails loudly
-- instead of the hint silently disappearing from shipped packages.
--
-- Usage: lua5.1 tools/strip-static.lua <stagedAddonDir> [--quiet]
--   e.g. lua5.1 tools/strip-static.lua .out/stage/QuestieTDB
--
-- Run from the repository root: originals are read from src/corrections/ for the
-- pre-strip identity check and the behavior parity check.

local lib = dofile("generator/lib.lua")
local manifest = dofile("src/corrections/manifest.lua")

--------------------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------------------

local stagedDir, quiet
for _, value in ipairs(arg or {}) do
  if value == "--quiet" then
    quiet = true
  elseif value:sub(1, 2) == "--" then
    error("Unknown option: " .. value, 0)
  elseif stagedDir then
    error("strip-static: exactly one staged addon directory expected", 0)
  else
    stagedDir = value
  end
end
if not stagedDir then
  io.stderr:write("usage: lua5.1 tools/strip-static.lua <stagedAddonDir> [--quiet]\n")
  os.exit(2)
end

local function say(...)
  if not quiet then print(...) end
end

local function fail(message, ...)
  io.stderr:write("strip-static: " .. message:format(...) .. "\n")
  os.exit(1)
end

--------------------------------------------------------------------------------------------
-- Stripping
--------------------------------------------------------------------------------------------

--- Pattern for a top-level definition of one named function, upstream style: column 0,
--- `function <Module>:<Name>(` or `function <Module>.<Name>(`.
local function headerPattern(functionName)
  return "^function%s+[%w_]+%s*[:.]%s*" .. functionName .. "%s*%("
end

--- Whether `lines[index]` opens a top-level definition of `functionName`.
local function isHeader(line, functionName)
  return line:find(headerPattern(functionName)) ~= nil
end

local STUB_BODY = {
  "  -- Static body stripped at package time (tools/strip-static.lua): this correction is",
  "  -- already folded into the TOC metadata store. The repository copy keeps the full",
  "  -- upstream-identical body.",
  "  return {}",
}

--- Replace the body of one top-level static function with the stub, in place.
---@param lines table The file as an array of lines
---@param functionName string
---@param filePath string For error messages
local function stripFunction(lines, functionName, filePath)
  local headerIndex
  for index, line in ipairs(lines) do
    if isHeader(line, functionName) then
      if headerIndex then
        fail("%s defines %s more than once (lines %d and %d) — refusing to guess",
          filePath, functionName, headerIndex, index)
      end
      headerIndex = index
    end
  end
  if not headerIndex then
    fail("%s: static function %s not found as a top-level definition", filePath, functionName)
  end

  local endIndex
  for index = headerIndex + 1, #lines do
    if lines[index]:find("^end%s*$") then endIndex = index break end
    -- A second top-level function before `end` means the closing line was missed.
    if lines[index]:find("^function%s") then
      fail("%s: %s runs into the next function without a column-0 end", filePath, functionName)
    end
  end
  if not endIndex then
    fail("%s: no closing end found for %s", filePath, functionName)
  end

  -- Keep the header and the closing end byte-identical; replace only the body between them.
  local tail = {}
  for index = endIndex, #lines do tail[#tail + 1] = lines[index] end
  for index = #lines, headerIndex + 1, -1 do lines[index] = nil end
  for _, line in ipairs(STUB_BODY) do lines[#lines + 1] = line end
  for _, line in ipairs(tail) do lines[#lines + 1] = line end
end

--- Split file content into lines, asserting the split is lossless so everything outside a
--- stripped body stays byte-identical by construction.
local function toLines(content, filePath)
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  -- The artificial trailing element appears when content already ended in a newline.
  if lines[#lines] == "" and content:sub(-1) == "\n" then lines[#lines] = nil end
  local rejoined = table.concat(lines, "\n") .. (content:sub(-1) == "\n" and "\n" or "")
  if rejoined ~= content then
    fail("%s: lossless line split failed (unexpected line endings?)", filePath)
  end
  return lines
end

--------------------------------------------------------------------------------------------
-- Behavior parity: original versus stripped
--------------------------------------------------------------------------------------------

local runtime = dofile("generator/runtime.lua")
local client = dofile("emulator/client.lua")
local config = dofile("src/config.lua")

-- One fixed persona for both sides of every comparison. The absolute outputs do not matter,
-- only that original and stripped agree under identical inputs.
client.install({})

--- The flavor a correction file's own expansion window belongs to, so the compat shim serves
--- the constants the file was written against (Era masks differ from TBC+ masks).
local PREFIX_EXPANSION = {
  Era = "Classic", Sod = "Classic", Shared = "Classic",
  Tbc = "TBC", Wotlk = "Wotlk", Cata = "Cata", MoP = "MoP",
}

local function flavorFor(spec)
  local prefix = spec.file:match("^(%w+)/")
  local expansion = PREFIX_EXPANSION[prefix] or "Classic"
  for _, flavor in ipairs(config.flavors) do
    if flavor.expansion == expansion then return flavor end
  end
  fail("%s: no flavor found for expansion %s", spec.file, expansion)
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end

--- Load one correction file variant in a fresh compat sandbox and observe everything Baked
--- mode consumes from it.
---@return table { hints, functionNames, outputs }
local function observe(spec, content, label)
  local Lib = runtime.build()
  local compat = Lib.CorrectionCompat
  local remove = compat.Install(flavorFor(spec))

  local chunk, err = loadstring(content, "@" .. label)
  if not chunk then
    remove()
    fail("%s (%s) does not compile: %s", spec.file, label, tostring(err))
  end
  local ok, execErr = pcall(chunk, "QuestieTDB", Lib)
  if not ok then
    remove()
    fail("%s (%s) failed to execute: %s", spec.file, label, tostring(execErr))
  end

  local module = compat.modules[spec.module]
  if type(module) ~= "table" then
    remove()
    fail("%s (%s): module %s was not created", spec.file, label, spec.module)
  end

  local observed = {
    hints = deepCopy(compat.objectiveFirst),
    functionNames = {},
    outputs = {},
  }
  for name, value in pairs(module) do
    if type(value) == "function" then observed.functionNames[name] = true end
  end

  local callable = {}
  for _, name in ipairs(spec.dynamic or {}) do callable[#callable + 1] = name end
  for _, name in ipairs(spec.parameterized or {}) do callable[#callable + 1] = name end
  for _, name in ipairs(callable) do
    local fn = module[name]
    if type(fn) ~= "function" then
      remove()
      fail("%s (%s): %s is not a function after load", spec.file, label, name)
    end
    compat.BeginCapture()
    local callOk, returned = pcall(compat.Invoke, fn, module)
    if not callOk then
      remove()
      fail("%s (%s): %s raised: %s", spec.file, label, name, tostring(returned))
    end
    observed.outputs[name] = {
      returned = deepCopy(returned),
      captured = deepCopy(compat.EndCapture(spec.datatype)),
    }
  end

  remove()
  return observed
end

local function assertParity(spec, original, stripped)
  if not lib.deepEqual(original.hints, stripped.hints) then
    fail("%s: objectiveFirst hints differ after strip — a hint moved inside a static body",
      spec.file)
  end
  if not lib.deepEqual(original.functionNames, stripped.functionNames) then
    fail("%s: the module's function set changed after strip", spec.file)
  end
  if not lib.deepEqual(original.outputs, stripped.outputs) then
    fail("%s: a Dynamic or Parameterized function's output changed after strip", spec.file)
  end
end

--------------------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------------------

local totalBefore, totalAfter, strippedFiles = 0, 0, 0

for _, spec in ipairs(manifest) do
  if spec.static and #spec.static > 0 then
    local stagedPath = stagedDir .. "/src/corrections/" .. spec.file
    if lib.fileExists(stagedPath) then
      local sourcePath = "src/corrections/" .. spec.file
      local original = lib.readAll(sourcePath)
      local staged = lib.readAll(stagedPath)
      if staged ~= original then
        fail("%s differs from %s before stripping — already stripped, or a stale stage?",
          stagedPath, sourcePath)
      end

      local lines = toLines(original, spec.file)
      for _, functionName in ipairs(spec.static) do
        stripFunction(lines, functionName, spec.file)
      end
      local stripped = table.concat(lines, "\n") .. (original:sub(-1) == "\n" and "\n" or "")

      local chunk, err = loadstring(stripped, "@" .. spec.file)
      if not chunk then
        fail("%s does not compile after strip: %s", spec.file, tostring(err))
      end
      local function stillDefined(name)
        for _, line in ipairs(lines) do
          if isHeader(line, name) then return true end
        end
        return false
      end
      for _, name in ipairs(spec.dynamic or {}) do
        if not stillDefined(name) then
          fail("%s: dynamic function %s lost by the strip", spec.file, name)
        end
      end
      for _, name in ipairs(spec.parameterized or {}) do
        if not stillDefined(name) then
          fail("%s: parameterized function %s lost by the strip", spec.file, name)
        end
      end

      assertParity(spec, observe(spec, original, spec.file .. " original"),
        observe(spec, stripped, spec.file .. " stripped"))

      lib.writeAll(stagedPath, stripped)
      totalBefore = totalBefore + #original
      totalAfter = totalAfter + #stripped
      strippedFiles = strippedFiles + 1
      say(("  stripped %-32s %7.1f KB -> %5.1f KB")
        :format(spec.file, #original / 1024, #stripped / 1024))
    end
  end
end

if strippedFiles == 0 then
  say("strip-static: nothing to strip (no staged files carry static functions)")
else
  say(("strip-static: %d files, %.2f MB -> %.0f KB (parity checked)")
    :format(strippedFiles, totalBefore / 1048576, totalAfter / 1024))
end
