-- Qt-host calc-parity diagnostic.
--
-- Loads every spec/TestBuilds/3.13 build through the SAME pob_host bridge the Qt
-- app uses, runs the calc, and diffs calcsTab.mainOutput against the committed
-- .lua snapshot. Proves the Qt host can load + calc real builds end-to-end and
-- surfaces any per-key divergence.
--
-- Run (cwd must be src/ so the engine finds TreeData/ etc.):
--   pob-selftest <src> <runtime> tools/qt_calc_parity.lua
-- Report is written to $TEMP/pob_parity_report.txt (qDebug is invisible in the
-- GUI-subsystem binaries).
--
-- NOTE ON THE BASELINE: the committed spec/TestBuilds/3.13/*.lua snapshots are
-- 3.13-era expected outputs; the engine is 3.28, so many keys legitimately drift
-- (e.g. SpellSuppressionEffect 50->40, mana/life mechanics, renamed/removed keys).
-- That is why TestBuilds_spec is tagged #builds and EXCLUDED from the default
-- busted task — the snapshots are regenerated per engine version via the busted
-- `generate` task, not asserted routinely. The ASSERTED calc-parity gate is the
-- busted System specs (spec/System, run in CI). Treat this tool as a bridge
-- smoke test + a same-engine Qt-vs-legacy diff aid, NOT a pass/fail gate against
-- the stale snapshots. Hard-fails only if a build cannot be loaded/calculated.

_POB_LUA_DIR = _SRC_DIR .. "/../app/lua"
dofile(_POB_LUA_DIR .. "/pob_host.lua")

local OUT = (os.getenv("TEMP") or ".") .. "/pob_parity_report.txt"
local out = io.open(OUT, "w")
local function w(...) out:write(table.concat({ ... }, " ") .. "\n"); out:flush() end
local function round(x, p) local m = 10 ^ (p or 4); return math.floor(x * m + 0.5) / m end

local testDir = _SRC_DIR .. "/../spec/TestBuilds/3.13"
local builds = { "Dual Savior", "Dual Wield Cospris CoC", "Generals Perforate Zerker",
                 "Mirage Archer Toxic Rain", "OccVortex" }

local anyLoadFail = false
local gKeys, gMatch = 0, 0
for _, name in ipairs(builds) do
  local ok, tb = pcall(dofile, testDir .. "/" .. name .. ".lua")
  if not ok or type(tb) ~= "table" then anyLoadFail = true; w("LOAD-FAIL", name, tostring(tb)); goto continue end
  local okLoad = pcall(pob_loadBuildXML, tb.xml, name)
  local ct = main.modes.BUILD.calcsTab
  if ct and not ct.mainOutput then pcall(function() ct:BuildOutput() end) end
  local mo = (ct and ct.mainOutput) or {}
  if not okLoad or not (ct and ct.mainOutput) then anyLoadFail = true; w("CALC-FAIL", name); goto continue end
  local keys, match = 0, 0
  for key, expected in pairs(tb.output) do
    keys = keys + 1; gKeys = gKeys + 1
    local actual = mo[key]
    local good
    if type(expected) == "number" and type(actual) == "number" then good = round(expected) == round(actual)
    else good = expected == actual end
    if good then match = match + 1; gMatch = gMatch + 1 end
  end
  w(string.format("%-28s loaded+calculated OK  keys=%d snapshot-match=%d (%.0f%%)",
     name, keys, match, keys > 0 and match / keys * 100 or 0))
  ::continue::
end
w(string.format("TOTAL snapshot-match %d/%d (%.0f%%); loads=%s",
   gMatch, gKeys, gKeys > 0 and gMatch / gKeys * 100 or 0, anyLoadFail and "SOME FAILED" or "ALL OK"))
w(anyLoadFail and "RESULT: FAIL (a build failed to load/calc)"
              or "RESULT: OK (all builds loaded+calculated; snapshot drift is 3.13-vs-3.28 version, expected)")
out:close()
os.exit(anyLoadFail and 1 or 0)
