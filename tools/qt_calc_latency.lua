-- Phase 2 Part 2.1 — threading / latency spike.
--
-- Measures the real cost of every calc-engine entry point the Qt host will drive,
-- through the SAME pob_host bridge the app uses, on the committed TestBuilds.
-- The numbers decide the threading model (sync-on-UI-thread vs engine thread vs
-- frame slicing), so this must measure the paths the UI actually calls:
--
--   * recalc      — the host's real edit path (buildFlag -> OnFrame) and its
--                   core (wipeGlobalCache + CalcsTab:BuildOutput), plus the
--                   MAIN / CALCS passes separately.
--   * calculators — getNodeCalculator / getMiscCalculator construction (paid on
--                   EVERY BuildOutput, CalcsTab.lua:449-450) and calcFullDPS.
--   * compares    — miscCalculator calcFunc() per hover: node add/remove
--                   (PassiveTreeView.lua:1620), item replace (ItemsTab.lua:2038),
--                   flask toggle (ItemsTab.lua:4571). This is the hover budget.
--   * power       — the full PowerBuilder coroutine sweep (tree heat map), which
--                   is one calcFunc per candidate node — the worst offender.
--   * marshalling — the host-side bridge getters QML calls after a recalc.
--   * memory      — Lua heap after repeated rebuilds (GlobalCache leak watch).
--
-- Run (cwd must be src/ so the engine finds TreeData/ etc.; ALL paths absolute):
--   pob-selftest.exe <repo>/src <repo>/runtime <repo>/tools/qt_calc_latency.lua
-- Report is written to $POB_LATENCY_OUT or $TEMP/pob_calc_latency.txt
-- (qDebug is invisible in these binaries — see STATUS.md env gotcha).
--
-- Exit code: 0 if every build measured, 1 if any build failed to load/calc.

_POB_LUA_DIR = _SRC_DIR .. "/../app/lua"
dofile(_POB_LUA_DIR .. "/pob_host.lua")

local OUT = os.getenv("POB_LATENCY_OUT") or ((os.getenv("TEMP") or ".") .. "/pob_calc_latency.txt")
local out = io.open(OUT, "w")
local function w(...) out:write(table.concat({ ... }, " ") .. "\n"); out:flush() end

-- Repetitions per measurement. Costly whole-build passes get few reps (the min
-- of a handful of runs is already a good estimate of the true cost); cheap
-- per-call paths are averaged over a batch instead.
local REPS = tonumber(os.getenv("POB_LATENCY_REPS") or "5")
local COMPARE_CALLS = tonumber(os.getenv("POB_LATENCY_COMPARES") or "10")
local POWER_CAP_MS = tonumber(os.getenv("POB_LATENCY_POWER_CAP") or "60000")

local function stats(samples)
	table.sort(samples)
	local sum = 0
	for _, v in ipairs(samples) do sum = sum + v end
	return {
		min = samples[1],
		med = samples[math.ceil(#samples / 2)],
		mean = sum / #samples,
		max = samples[#samples],
		n = #samples,
	}
end

-- Time `fn` `reps` times; `prep` (optional) runs UNTIMED before each rep — used to
-- wipe the GlobalCache so a pass is measured cold, the way a real edit pays for it.
-- Returns a stats table (ms) or nil + error message.
local function timeit(reps, fn, prep)
	local samples = { }
	for _ = 1, reps do
		if prep then local okP, errP = pcall(prep); if not okP then return nil, tostring(errP) end end
		local t0 = GetTime()
		local ok, err = pcall(fn)
		local dt = GetTime() - t0
		if not ok then return nil, tostring(err) end
		samples[#samples + 1] = dt
	end
	return stats(samples)
end

local rows = { }   -- { build, metric, stats, note }
local function record(build, metric, st, err, note)
	rows[#rows + 1] = { build = build, metric = metric, st = st, err = err, note = note }
	if st then
		w(string.format("  %-34s min=%7.1f med=%7.1f mean=%7.1f max=%7.1f ms  n=%d %s",
			metric, st.min, st.med, st.mean, st.max, st.n, note or ""))
	else
		w(string.format("  %-34s ERROR: %s", metric, tostring(err)))
	end
end

local testDir = _SRC_DIR .. "/../spec/TestBuilds/3.13"
-- Chosen for the two shapes Part 2.1 calls out plus coverage of the rest:
--   Mirage Archer Toxic Rain    — mirage/trigger + heaviest cluster-jewel tree
--   Dual Wield Cospris CoC      — trigger (cast-on-crit) build
--   Generals Perforate Zerker   — cluster jewels + minion (General's Cry mirages)
--   Dual Savior / OccVortex     — plain attack / DoT baselines
local builds = { "Mirage Archer Toxic Rain", "Dual Wield Cospris CoC",
                 "Generals Perforate Zerker", "Dual Savior", "OccVortex" }

-- The committed TestBuilds are 3.13-era. POB_LATENCY_EXTRA takes a ';'-separated
-- list of .xml build paths (e.g. from the user's own library) so the spike can be
-- sanity-checked against a current-league build without committing one.
local extraXml = { }
for path in string.gmatch(os.getenv("POB_LATENCY_EXTRA") or "", "[^;]+") do
	local f = io.open(path, "r")
	if f then
		local xml = f:read("*a"); f:close()
		local label = string.match(path, "([^/\\]+)%.xml$") or path
		builds[#builds + 1] = label
		extraXml[label] = xml
	else
		w("EXTRA-BUILD MISSING: " .. path)
	end
end

w("Phase 2 Part 2.1 — calc latency spike")
w("reps=" .. REPS .. " compareCalls=" .. COMPARE_CALLS .. " powerCapMs=" .. POWER_CAP_MS)
w("NOTE: GetTime() has 1 ms resolution; per-call figures are batch means.")
w("")

local anyFail = false
for _, name in ipairs(builds) do
	w("=== " .. name .. " ===")
	local tb
	if extraXml[name] then
		tb = { xml = extraXml[name] }
	else
		local ok
		ok, tb = pcall(dofile, testDir .. "/" .. name .. ".lua")
		if not ok or type(tb) ~= "table" then
			anyFail = true; w("  LOAD-FAIL " .. tostring(tb)); goto continue
		end
	end

	-- 1. Cold load: SetMode(BUILD, xml) + OnFrame, i.e. parse + full Init +
	--    first BuildOutput. This is "open a build" latency.
	local st, err = timeit(1, function() pob_loadBuildXML(tb.xml, name) end)
	record(name, "load (open build, incl. 1st calc)", st, err)

	local bm = main.modes.BUILD
	local ct = bm and bm.calcsTab
	if not ct then anyFail = true; w("  NO calcsTab"); goto continue end
	if not ct.mainOutput then pcall(function() ct:BuildOutput() end) end
	if not ct.mainOutput then anyFail = true; w("  CALC-FAIL (no mainOutput)"); goto continue end

	-- Build shape, for interpreting the numbers.
	local nodeCount, allocCount, candidateCount = 0, 0, 0
	for _, node in pairs(bm.spec.nodes) do
		nodeCount = nodeCount + 1
		if node.alloc then allocCount = allocCount + 1 end
		if node.modKey and node.modKey ~= "" and not node.alloc then
			candidateCount = candidateCount + 1
		end
	end
	local skillCount = 0
	for _, group in ipairs(bm.skillsTab.socketGroupList or { }) do
		skillCount = skillCount + #(group.displaySkillList or { })
	end
	w(string.format("  shape: treeNodes=%d allocated=%d powerCandidates=%d socketGroups=%d displaySkills=%d fullDPS=%s",
		nodeCount, allocCount, candidateCount, #(bm.skillsTab.socketGroupList or { }), skillCount,
		tostring(ct.mainOutput.FullDPS ~= nil)))

	-- 2. The host's real edit path: any mutation sets buildFlag, the frame
	--    consumes it (wipeGlobalCache -> outputRevision++ -> BuildOutput ->
	--    RefreshStatList). This is the per-keystroke / per-click latency.
	st, err = timeit(REPS, function()
		bm.buildFlag = true
		runCallback("OnFrame")
	end)
	record(name, "recalc: buildFlag -> OnFrame", st, err, "<- the per-edit cost")

	-- 3. Its core, without the surrounding frame work.
	st, err = timeit(REPS, function()
		wipeGlobalCache()
		ct:BuildOutput()
	end)
	record(name, "recalc: wipeCache + BuildOutput", st, err)

	-- 4. BuildOutput's four components, measured separately, each COLD (the
	--    GlobalCache wiped first — exactly what a real edit does). MAIN drives
	--    the sidebar + config usage sets; CALCS builds breakdowns; the two
	--    calculators are rebuilt on every BuildOutput whether used or not.
	--    Also measured warm (no wipe) to expose what the cache is worth.
	st, err = timeit(REPS, function() ct.calcs.buildOutput(bm, "MAIN") end, wipeGlobalCache)
	record(name, "  pass: buildOutput(MAIN) cold", st, err)
	st, err = timeit(REPS, function() ct.calcs.buildOutput(bm, "MAIN") end)
	record(name, "  pass: buildOutput(MAIN) warm", st, err)
	st, err = timeit(REPS, function() ct.calcs.buildOutput(bm, "CALCS") end, wipeGlobalCache)
	record(name, "  pass: buildOutput(CALCS) cold", st, err)
	st, err = timeit(REPS, function() ct.calcs.buildOutput(bm, "CALCS") end)
	record(name, "  pass: buildOutput(CALCS) warm", st, err)
	st, err = timeit(REPS, function() ct.calcs.getNodeCalculator(bm) end, wipeGlobalCache)
	record(name, "  pass: getNodeCalculator() cold", st, err)
	st, err = timeit(REPS, function() ct.calcs.getMiscCalculator(bm) end, wipeGlobalCache)
	record(name, "  pass: getMiscCalculator() cold", st, err)
	st, err = timeit(REPS, function() ct.calcs.calcFullDPS(bm, "CALCULATOR", { }, { }) end, wipeGlobalCache)
	record(name, "  pass: calcFullDPS(CALCULATOR) cold", st, err)
	st, err = timeit(REPS, function() bm:RefreshStatList() end)
	record(name, "  pass: RefreshStatList()", st, err)

	-- 5. Hover-compare budget. Every "hovering this gives you:" tooltip is one
	--    calcFunc() on the cached miscCalculator. Batch-timed: 1 ms clock.
	local calcFunc = ct:GetMiscCalculator()
	if calcFunc then
		-- baseline (no override) — the floor for any compare
		st, err = timeit(1, function()
			for _ = 1, COMPARE_CALLS do calcFunc({ }) end
		end)
		if st then st = { min = st.min / COMPARE_CALLS, med = st.med / COMPARE_CALLS,
		                  mean = st.mean / COMPARE_CALLS, max = st.max / COMPARE_CALLS, n = COMPARE_CALLS } end
		record(name, "compare: calcFunc({}) per call", st, err)

		-- node add (tree hover on an unallocated node)
		local candidates = { }
		for _, node in pairs(bm.spec.nodes) do
			if node.modKey and node.modKey ~= "" and not node.alloc and not node.ascendancyName then
				candidates[#candidates + 1] = node
				if #candidates >= COMPARE_CALLS then break end
			end
		end
		if #candidates > 0 then
			st, err = timeit(1, function()
				for _, node in ipairs(candidates) do calcFunc({ addNodes = { [node] = true } }) end
			end)
			if st then local n = #candidates
				st = { min = st.min / n, med = st.med / n, mean = st.mean / n, max = st.max / n, n = n } end
			record(name, "compare: node addNodes per call", st, err)
		end

		-- item replace (item tooltip / item list sort) — replacing an equipped
		-- item with itself costs the same as a real swap.
		local repSlot, repItem
		for _, slot in ipairs(bm.itemsTab.orderedSlots or { }) do
			local id = slot.selItemId
			if id and id ~= 0 and bm.itemsTab.items[id] then
				repSlot, repItem = slot.slotName, bm.itemsTab.items[id]
				break
			end
		end
		if repItem then
			st, err = timeit(1, function()
				for _ = 1, COMPARE_CALLS do
					calcFunc({ repSlotName = repSlot, repItem = repItem })
				end
			end)
			if st then st = { min = st.min / COMPARE_CALLS, med = st.med / COMPARE_CALLS,
			                  mean = st.mean / COMPARE_CALLS, max = st.max / COMPARE_CALLS, n = COMPARE_CALLS } end
			record(name, "compare: item replace per call", st, err, "slot=" .. tostring(repSlot))
		end

		-- FullDPS compare (useFullDPS=true adds a calcFullDPS per call)
		st, err = timeit(1, function()
			for _ = 1, COMPARE_CALLS do calcFunc({ }, true) end
		end)
		if st then st = { min = st.min / COMPARE_CALLS, med = st.med / COMPARE_CALLS,
		                  mean = st.mean / COMPARE_CALLS, max = st.max / COMPARE_CALLS, n = COMPARE_CALLS } end
		record(name, "compare: calcFunc({},fullDPS) /call", st, err)
	else
		record(name, "compare: (no miscCalculator)", nil, "GetMiscCalculator returned nil")
	end

	-- 5b. Real user actions through the host bridge, end to end. These are what
	--     a click/keystroke actually costs today: bridge call + engine mutation +
	--     buildFlag -> OnFrame recalc (the Qt models' refresh is on top).
	local pathNode
	for _, node in pairs(bm.spec.nodes) do
		if not node.alloc and node.modKey and node.modKey ~= "" and not node.ascendancyName
		   and (node.pathDist or 1000) <= 2 then
			pathNode = node; break
		end
	end
	if pathNode then
		st, err = timeit(math.min(REPS, 3), function()
			pob_allocNode(pathNode.id)
			pob_deallocNode(pathNode.id)
		end)
		if st then st = { min = st.min / 2, med = st.med / 2, mean = st.mean / 2, max = st.max / 2, n = st.n * 2 } end
		record(name, "action: tree node alloc/dealloc", st, err, "per click, id=" .. tostring(pathNode.id))
	end
	local checkOpt
	for _, opt in ipairs(pob_getConfigOptions() or { }) do
		if opt.type == "boolean" then checkOpt = opt; break end
	end
	if checkOpt then
		st, err = timeit(math.min(REPS, 3), function()
			pob_setConfigOption(checkOpt.name, not checkOpt.value)
			pob_setConfigOption(checkOpt.name, checkOpt.value)
		end)
		if st then st = { min = st.min / 2, med = st.med / 2, mean = st.mean / 2, max = st.max / 2, n = st.n * 2 } end
		record(name, "action: config check toggle", st, err, "per edit, var=" .. tostring(checkOpt.name))
	end

	-- 6. PowerBuilder: the tree heat map. One coroutine, resumed per frame,
	--    yielding on a 100 ms budget — the legacy frame-slicing precedent.
	--    Measured as total wall time + resume count for the whole sweep.
	local resumes, powerMs, capped = 0, 0, false
	local okPower, powerErr = pcall(function()
		ct.powerBuildFlag = true
		local t0 = GetTime()
		repeat
			ct:BuildPower()
			resumes = resumes + 1
			powerMs = GetTime() - t0
			if powerMs > POWER_CAP_MS then capped = true; ct.powerBuilder = nil end
		until not ct.powerBuilder
	end)
	if okPower then
		record(name, "power: full PowerBuilder sweep",
			{ min = powerMs, med = powerMs, mean = powerMs, max = powerMs, n = 1 }, nil,
			string.format("resumes=%d%s", resumes, capped and " (CAPPED)" or ""))
	else
		record(name, "power: full PowerBuilder sweep", nil, powerErr)
	end

	-- 7. Host-side marshalling: what the Qt bridge pays AFTER the engine is
	--    done, on the same thread. pob_getActiveSkills is included because it
	--    runs one BuildOutput per display skill (a known hot spot).
	st, err = timeit(REPS, function() pob_getCalcOutput() end)
	record(name, "marshal: pob_getCalcOutput()", st, err)
	st, err = timeit(REPS, function() pob_getConfigOptions() end)
	record(name, "marshal: pob_getConfigOptions()", st, err)
	st, err = timeit(REPS, function() pob_getItems() end)
	record(name, "marshal: pob_getItems()", st, err)
	st, err = timeit(1, function() pob_getTreeData() end)
	record(name, "marshal: pob_getTreeData()", st, err)
	st, err = timeit(1, function() pob_getActiveSkills() end)
	record(name, "marshal: pob_getActiveSkills()", st, err, "(1 BuildOutput per skill)")

	-- 8. Memory: the long-lived Qt process keeps calculator closures + the
	--    GlobalCache alive; legacy wipes every edit. Watch for growth.
	collectgarbage("collect")
	local kb0 = collectgarbage("count")
	for _ = 1, 5 do
		bm.buildFlag = true
		runCallback("OnFrame")
	end
	local kbHot = collectgarbage("count")
	collectgarbage("collect")
	local kb1 = collectgarbage("count")
	w(string.format("  %-34s baseline=%.1f MB peak=%.1f MB after-gc=%.1f MB (delta %+.1f MB over 5 recalcs)",
		"memory: Lua heap", kb0 / 1024, kbHot / 1024, kb1 / 1024, (kb1 - kb0) / 1024))

	w("")
	::continue::
end

-- Cross-build summary of the three numbers the decision hangs on.
w("=== SUMMARY (min of runs, ms) ===")
w(string.format("%-28s %13s %13s %13s %13s %13s", "build", "edit-recalc", "node click",
	"compare/call", "power sweep", "getCalcOutput"))
local byBuild = { }
for _, r in ipairs(rows) do
	byBuild[r.build] = byBuild[r.build] or { }
	byBuild[r.build][r.metric] = r.st and r.st.min or nil
end
for _, name in ipairs(builds) do
	local b = byBuild[name] or { }
	local function f(k) local v = b[k]; return v and string.format("%13.1f", v) or string.format("%13s", "-") end
	w(string.format("%-28s %s %s %s %s %s", name,
		f("recalc: buildFlag -> OnFrame"), f("action: tree node alloc/dealloc"),
		f("compare: node addNodes per call"),
		f("power: full PowerBuilder sweep"), f("marshal: pob_getCalcOutput()")))
end
w("")
w(anyFail and "RESULT: FAIL (a build failed to load/calc)" or "RESULT: OK")
out:close()
os.exit(anyFail and 1 or 0)
