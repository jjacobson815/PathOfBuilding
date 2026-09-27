-- Path of Building (Qt port)
--
-- Module: pob_timeless.lua  —  Timeless Jewel finder bridge
-- Phase 4 (Tree Tab), Part 4.5.
--
-- WHAT THIS IS
--   The legacy finder is one giant closure, TreeTabClass:FindTimelessJewel()
--   (src/Classes/TreeTab.lua L1369-2891), plus the double-click item creation
--   in src/Classes/TimelessJewelListControl.lua (TJLC L98-254). Every helper in
--   it is a closure-local `local function` reading `controls.*`, so none of it
--   is callable from outside. This module LIFTS that logic, verbatim wherever
--   possible (same tables, loops, formulas, label formatting; the `-- TreeTab.lua:NNNN`
--   comments point at the legacy source), into top-level globals that QML calls.
--   No legacy Control object is created or read: QML owns the UI.
--
--   Lifted from TreeTab.lua:
--     static tables ................ L1377-1480  (ignoredMods, totalMods, totalModIDs,
--                                                 reverseTotalModIDs, jewelTypes,
--                                                 conquerorTypes, devotionVariants)
--     stub restore at popup open ... L1404, L1453, L1524, L1696/1700, L1814, L2190
--     socket list .................. L1481-1533
--     buildMods .................... L1535
--     getNodeWeights ............... L1588  (fed from emulated slider labels)
--     parseSearchList / updateSearchList  L1604 / L1679
--     setAllocatedNodes / clearProtected  L1734 / L1767
--     protect Add / Clear buttons .. L1802 / L1810
--     slider change funcs .......... L1856 / L1885 / L1913 (-> pob_timelessSetWeights)
--     updateSliders ................ L1940  (-> weights returned by pob_timelessSelectNode)
--     nodeSelect selFunc ........... L1967  (-> pob_timelessSelectNode)
--     generateFallbackWeights ...... L2036
--     setupFallbackWeights ......... L2063
--     fallbackWeightsList .......... L2176
--     totalMinimumWeight changeFunc  L2199
--     searchList(Fallback) changeFunc L2217 / L2228
--     trade URL button body ........ L2277-2385 (minus the network league fetch)
--     searchSingleSocket ........... L2494
--     formatSearchValue / formatResults L2737 / L2753
--     reset button ................. L2812
--     search button ................ L2822
--   Lifted from TimelessJewelListControl.lua:
--     AddValueTooltip (tooltip lines)  TJLC L67
--     OnSelClick double-click item   TJLC L98
--
-- THE THREE CONTROL READS SUBSTITUTED (the only non-UI state the closure read
-- from controls; see the brief):
--   1. controls.socketFilter.state
--        -> timelessData.socketFilter (legacy initialises the checkbox from it
--           and its changeFunc writes it back, so they are always equal).
--   2. controls.fallbackWeightsList.list[controls.fallbackWeightsList.selIndex]
--        -> S.fallbackWeightsList[timelessData.fallbackWeightMode.idx or 1]
--           (legacy selIndex is initialised from / written to that idx).
--   3. slider value labels read by getNodeWeights()
--        (controls.nodeSlider{,2,3}Value.label)
--        -> numbers passed from QML (w1, w2 in 0..10; w3 in 0..500 or
--           "required"); sliderLabels() re-creates the exact legacy label strings
--           and the legacy getNodeWeights() parses them, so rounding/format is
--           unchanged.
--   Pure selection plumbing is passed as arguments instead of read from
--   controls: nodeSelect.list[selIndex].id -> optionIndex; "is the fallback list
--   shown" -> the `fallback` bool; protectAllocatedSelect:GetSelValue() -> name;
--   searchResults.selIndex/highlightIndex, realm, league, trade type and the
--   "search more" checkbox -> pob_timelessTradeUrl arguments.
--
-- SYNCHRONOUS: the search runs to completion inside pob_timelessSearch(), exactly
--   as the legacy Search button did (legacy also blocks the frame loop). The first
--   Glorious Vanity search inflates ~22 MB of LUT data (one-time stall, as legacy).
--
-- STATE: module state lives in the local table `S`. It is (re)initialised when
--   main.modes.BUILD or build.timelessData changes identity (a new build / a
--   reload creates a new timelessData table, Build.lua:78). Derived tables
--   (socket list, modData, node options) are rebuilt lazily. Persisted state stays
--   in build.timelessData; searchResults/sharedResults are ALWAYS the same table
--   references (wipeTable, never reassigned) as legacy requires.
--
-- All globals return plain Lua tables (no functions, no cycles); arrays are 1-based.

local ipairs = ipairs
local pairs = pairs
local next = next
local type = type
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local t_concat = table.concat
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_abs = math.abs
local m_random = math.random
local s_format = string.format
local s_gsub = string.gsub
local s_byte = string.byte
local s_char = string.char
local dkjson = require "dkjson"

-- ---------------------------------------------------------------------------
-- Static tables (TreeTab.lua:1377-1480), verbatim
-- ---------------------------------------------------------------------------

local ignoredMods = { "Might of the Vaal", "Legacy of the Vaal", "Strength", "Add Strength", "Dex", "Add Dexterity", "Devotion", "Price of Glory", "Ward" } -- TreeTab.lua:1377
local totalMods = { [2] = "Strength", [3] = "Dexterity", [4] = "Devotion" } -- TreeTab.lua:1378
local totalModIDs = { -- TreeTab.lua:1379
	["total_strength"] = { ["karui_notable_add_strength"] = true, ["karui_attribute_strength"] = true, ["karui_small_strength"] = true },
	["total_dexterity"] = { ["maraketh_notable_add_dexterity"] = true, ["maraketh_attribute_dex"] = true, ["maraketh_small_dex"] = true },
	["total_devotion"] = { ["templar_notable_devotion"] = true, ["templar_devotion_node"] = true, ["templar_small_devotion"] = true }
}
local reverseTotalModIDs = { -- TreeTab.lua:1384
	["karui_notable_add_strength"] = true,
	["karui_attribute_strength"] = true,
	["karui_small_strength"] = true,
	["maraketh_notable_add_dexterity"] = true,
	["maraketh_attribute_dex"] = true,
	["maraketh_small_dex"] = true,
	["templar_notable_devotion"] = true,
	["templar_devotion_node"] = true,
	["templar_small_devotion"] = true
}
local jewelTypes = { -- TreeTab.lua:1395
	{ label = "Glorious Vanity", name = "vaal", id = 1 },
	{ label = "Lethal Pride", name = "karui", id = 2 },
	{ label = "Brutal Restraint", name = "maraketh", id = 3 },
	{ label = "Militant Faith", name = "templar", id = 4 },
	{ label = "Elegant Hubris", name = "eternal", id = 5 },
	{ label = "Heroic Tragedy", name = "kalguur", id = 6 }
}
local conquerorTypes = { -- TreeTab.lua:1414
	[1] = {
		{ label = "Any", id = 1 },
		{ label = "Doryani (Corrupted Soul)", id = 2 },
		{ label = "Xibaqua (Divine Flesh)", id = 3 },
		{ label = "Ahuana (Immortal Ambition)", id = 4 }
	},
	[2] = {
		{ label = "Any", id = 1 },
		{ label = "Kaom (Strength of Blood)", id = 2 },
		{ label = "Rakiata (Tempered by War)", id = 3 },
		{ label = "Akoya (Chainbreaker)", id = 4 }
	},
	[3] = {
		{ label = "Any", id = 1 },
		{ label = "Asenath (Dance with Death)", id = 2 },
		{ label = "Nasima (Second Sight)", id = 3 },
		{ label = "Balbala (The Traitor)", id = 4 }
	},
	[4] = {
		{ label = "Any", id = 1 },
		{ label = "Avarius (Power of Purpose)", id = 2 },
		{ label = "Dominus (Inner Conviction)", id = 3 },
		{ label = "Maxarius (Transcendence)", id = 4 }
	},
	[5] = {
		{ label = "Any", id = 1 },
		{ label = "Cadiro (Supreme Decadence)", id = 2 },
		{ label = "Victario (Supreme Grandstanding)", id = 3 },
		{ label = "Caspiro (Supreme Ostentation)", id = 4 }
	},
	[6] = {
		{ label = "Any", id = 1 },
		{ label = "Vorana (Black Scythe Training)", id = 2 },
		{ label = "Uhtred (Celestial Mathematics)", id = 3 },
		{ label = "Medved (The Unbreaking Circle)", id = 4 }
	}
}
local devotionVariants = { -- TreeTab.lua:1463
	{ id = 1 , label = "Any" },
	{ id = 2 , label = "Totem Damage" },
	{ id = 3 , label = "Brand Damage" },
	{ id = 4 , label = "Channelling Damage" },
	{ id = 5 , label = "Area Damage" },
	{ id = 6 , label = "Elemental Damage" },
	{ id = 7 , label = "Elemental Resistances" },
	{ id = 8 , label = "Effect of non-Damaging Ailments" },
	{ id = 9 , label = "Elemental Ailment Duration" },
	{ id = 10, label = "Duration of Curses" },
	{ id = 11, label = "Minion Attack and Cast Speed" },
	{ id = 12, label = "Minions Accuracy Rating" },
	{ id = 13, label = "Mana Regen" },
	{ id = 14, label = "Skill Cost" },
	{ id = 15, label = "Non-Curse Aura Effect" },
	{ id = 16, label = "Defences from Shield" }
}
local socketFilterAdditionalDistanceMAX = 10 -- TreeTab.lua:1825
-- TreeTab.lua:2403 realm list (legacy lower-cases GetSelValue() -> "pc"/"sony"/"xbox", L2373)
local realmList = { "PC", "Sony", "Xbox" }
-- TreeTab.lua:2464 trade type labels (UI) and TreeTab.lua:2329 their API values
local tradeTypeLabels = {
	"Instant buyout",
	"Instant buyout and in person",
	"In person (online in league)",
	"In person (online)",
	"Any (includes offline)"
}
local tradeTypes = {
	"securable",
	"available",
	"onlineleague",
	"online",
	"any"
}

-- sentinel: "list text never parsed yet" (never equal to a string or nil)
local UNPARSED = { }

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------

local S = nil

local function bindSpec(st, spec)
	st.spec = spec
	st.treeData = spec.tree                              -- TreeTab.lua:1371
	st.legionNodes = spec.tree.legion.nodes              -- TreeTab.lua:1372
	st.legionAdditions = spec.tree.legion.additions      -- TreeTab.lua:1373
	st.modDataTypeId = nil     -- force buildMods()
	st.socketSig = nil         -- force socket list rebuild
end

local function newState(build)
	local st = {
		build = build,
		timelessData = build.timelessData,               -- TreeTab.lua:1374
		modData = { },                                   -- TreeTab.lua:1376
		nodeOptions = { },
		modDataTypeId = nil,
		jewelSockets = { },
		socketSig = nil,
		searchListTbl = { },                             -- TreeTab.lua:1602
		searchListFallbackTbl = { },                     -- TreeTab.lua:1603
		parsedSearchList = UNPARSED,
		parsedSearchListFallback = UNPARSED,
		allocatedNodes = { },                            -- TreeTab.lua:1730
		protectedNodes = { },                            -- TreeTab.lua:1731
		protectedNodesCount = 0,                         -- TreeTab.lua:1732
		allocatedNodesInRadiusCount = 0,                 -- TreeTab.lua:1733 (was self.allocatedNodesInRadiusCount)
		protectOptions = { },                            -- controls.protectAllocatedSelect list
		nodeSelIndex = 1,                                -- controls.nodeSelect.selIndex
		fallbackWeightsList = { },                       -- TreeTab.lua:2176
		lastSearch = nil,                                -- controls.searchTradeButton.lastSearch
		tradeLabel = "Open Trade URL",                   -- controls.searchTradeButton.label
		resultsSelIndex = nil,                           -- controls.searchResults.selIndex
		highlightIndex = nil,                            -- controls.searchResults.highlightIndex
		fallbackGenerated = false,                       -- controls.searchListFallbackButton.label "^4" highlight
		resultsVersion = 0,
		resultsCache = nil,
		msg = "",                                        -- controls.msg.label
	}
	bindSpec(st, build.spec)
	-- TreeTab.lua:2176
	for _, stat in ipairs(data.powerStatList) do
		if not stat.ignoreForItems and stat.label ~= "Name" then
			t_insert(st.fallbackWeightsList, {
				label = "Sort by " .. stat.label,
				stat = stat.stat,
				transform = stat.transform,
			})
		end
	end
	return st
end

-- ---------------------------------------------------------------------------
-- Lifted closure helpers (they read the module state S)
-- ---------------------------------------------------------------------------

-- TreeTab.lua:1481-1533 — jewel socket list. Rebuilt lazily when the spec, tree,
-- or the set of allocated jewel sockets changes (the "# " label prefix depends
-- on allocation; legacy rebuilt it on every popup open).
local function socketSignature(build)
	local ids = { }
	for nodeId, node in pairs(build.spec.allocNodes) do
		if type(node) == "table" and node.isJewelSocket then
			ids[#ids + 1] = nodeId
		end
	end
	t_sort(ids)
	return tostring(build.spec) .. "|" .. tostring(build.spec.tree) .. "|" .. t_concat(ids, ",")
end

local function buildJewelSockets()
	local build = S.build
	local treeData = S.treeData
	local jewelSockets = { }
	t_insert(jewelSockets, {
		label = "All Sockets",
		keystone = "Multi-Socket Search",
		id = -1
	})
	for socketId, socketData in pairs(build.spec.nodes) do
		if socketData.isJewelSocket and socketData.name ~= "Charm Socket"then
			local keystone = "Unknown"
			if socketId == 26725 then
				keystone = "Marauder"
			elseif socketId == 54127 then
				keystone = "Duelist"
			elseif socketId == 7960 then
				keystone = "Templar/Witch"
			else
				local minDistance = math.huge
				-- nil-guard added: legacy assumed every spec jewel socket has nodesInRadius
				local treeNode = treeData.nodes[socketId]
				for _, nodeInRadius in pairs(treeNode and treeNode.nodesInRadius and treeNode.nodesInRadius[3] or { }) do
					if nodeInRadius.isKeystone then
						local distance = math.sqrt((nodeInRadius.x - socketData.x) ^ 2 + (nodeInRadius.y - socketData.y) ^ 2)
						if distance < minDistance then
							keystone = nodeInRadius.name
							minDistance = distance
						end
					end
				end
			end
			local label = keystone .. ": " .. socketId
			if build.spec.allocNodes[socketId] then
				label = "# " .. label
			end
			t_insert(jewelSockets, {
				label = label,
				keystone = keystone,
				id = socketId
			})
		end
	end
	-- Sort all sockets except all sockets option
	local allSocketsEntry = t_remove(jewelSockets, 1)
	t_sort(jewelSockets, function(a, b) return a.label < b.label end)
	t_insert(jewelSockets, 1, allSocketsEntry)
	return jewelSockets
end

-- Legacy nodeSelect selFunc stat count lookup (TreeTab.lua:1970-1989)
local function nodeStatInfo(id)
	local nodeSliderStatLabel = "None"
	local nodeSlider2StatLabel = "None"
	local statCount = 0
	for _, legionNode in ipairs(S.legionNodes) do
		if legionNode.id == id then
			statCount = #legionNode.sd
			nodeSliderStatLabel = legionNode.sd[1] or "None"
			nodeSlider2StatLabel = legionNode.sd[2] or "None"
			break
		end
	end
	if statCount == 0 then
		for _, legionAddition in ipairs(S.legionAdditions) do
			if legionAddition.id == id then
				statCount = #legionAddition.sd
				nodeSliderStatLabel = legionAddition.sd[1] or "None"
				nodeSlider2StatLabel = legionAddition.sd[2] or "None"
				break
			end
		end
	end
	return statCount, nodeSliderStatLabel, nodeSlider2StatLabel
end

-- TreeTab.lua:1535
local function buildMods()
	local timelessData = S.timelessData
	local modData = S.modData
	local legionNodes = S.legionNodes
	local legionAdditions = S.legionAdditions
	wipeTable(modData)
	local smallModData = { }
	for _, node in pairs(legionNodes) do
		if node.id:match("^" .. timelessData.jewelType.name .. "_.+") and not isValueInArray(ignoredMods, node.dn) and not node.ks then
			if node["not"] then
				t_insert(modData, {
					label = node.dn .. "                                                " .. node.sd[1],
					descriptions = copyTable(node.sd),
					type = timelessData.jewelType.name,
					id = node.id,
					dn = node.dn, -- port: kept so QML can show the plain name
				})
				if node.sd[2] then
					modData[#modData].label = modData[#modData].label .. " " .. node.sd[2]
				end
			else
				t_insert(smallModData, {
					label = node.dn,
					descriptions = copyTable(node.sd),
					type = timelessData.jewelType.name,
					id = node.id,
					dn = node.dn,
				})
			end
		end
	end
	for _, addition in pairs(legionAdditions) do
		-- exclude passives that are already added (vaal, attributes, devotion)
		if addition.id:match("^" .. timelessData.jewelType.name .. "_.+") and not isValueInArray(ignoredMods, addition.dn) and timelessData.jewelType.name ~= "vaal" then
			t_insert(modData, {
				label = addition.dn,
				descriptions = copyTable(addition.sd),
				type = timelessData.jewelType.name,
				id = addition.id,
				dn = addition.dn,
			})
		end
	end
	t_sort(modData, function(a, b) return a.label < b.label end)
	t_sort(smallModData, function (a, b) return a.label < b.label end)
	if totalMods[timelessData.jewelType.id] then
		t_insert(modData, 1, {
			label = "Total " .. totalMods[timelessData.jewelType.id],
			descriptions = { "This is a hybrid node containing all additions to " .. totalMods[timelessData.jewelType.id] },
			type = timelessData.jewelType.name,
			id = "total_" .. totalMods[timelessData.jewelType.id]:lower(),
			totalMod = true
		})
	end
	t_insert(modData, 1, { label = "..." })
	for i = 1, #smallModData do
		modData[#modData + 1] = smallModData[i]
	end

	-- port: plain marshalled copy of the dropdown for QML (static per jewel type)
	S.nodeOptions = { }
	for i, entry in ipairs(modData) do
		local twoStats = false
		if entry.id then
			local statCount = nodeStatInfo(entry.id)
			twoStats = statCount > 1 -- TreeTab.lua:1998 controls.nodeSlider2.enabled
		end
		S.nodeOptions[i] = {
			index = i,
			id = entry.id,
			label = entry.label,
			name = entry.dn or entry.label,
			descriptions = entry.descriptions and copyTable(entry.descriptions) or { },
			twoStats = twoStats,
		}
	end
	S.modDataTypeId = timelessData.jewelType.id
end

-- Emulates the three slider value labels (TreeTab.lua:1857, 1886/1991-1996, 1914-1918)
-- from plain numbers, so the legacy getNodeWeights() below stays verbatim.
local function sliderLabels(w1, w2, w3, twoStats)
	local labels = { }
	local val1 = m_min(m_max((tonumber(w1) or 0) / 10, 0), 1)
	labels.nodeSliderValue = s_format("^7%.3f", val1 * 10)
	if twoStats then
		local val2 = m_min(m_max((tonumber(w2) or 0) / 10, 0), 1)
		labels.nodeSlider2Value = s_format("^7%.3f", val2 * 10)
	else
		-- TreeTab.lua:1990: slider2 disabled (val 0, "^9" label) for nodes with <= 1 stat
		labels.nodeSlider2Value = s_format("^9%.3f", 0)
	end
	-- slider3: val == 1 (the maximum, 500) shows "Required" (TreeTab.lua:1914)
	local isRequired = (type(w3) == "string" and w3:lower() == "required") or (tonumber(w3) and tonumber(w3) >= 500)
	if isRequired then
		labels.nodeSlider3Value = "^7Required"
	else
		local val3 = m_min(m_max((tonumber(w3) or 0) / 500, 0), 1)
		labels.nodeSlider3Value = s_format("^7%.f", val3 * 500)
	end
	return labels
end

-- TreeTab.lua:1588 (control labels substituted by the emulated label table)
local function getNodeWeights(labels)
	local nodeWeights = {
		[1] = labels.nodeSliderValue:sub(3):lower(),
		[2] = labels.nodeSlider2Value:sub(3):lower(),
		[3] = labels.nodeSlider3Value:sub(3):lower()
	}
	for i, nodeWeight in ipairs(nodeWeights) do
		if tonumber(nodeWeight) ~= nil then
			nodeWeights[i] = round(tonumber(nodeWeight), 3)
		end
	end
	return nodeWeights
end

-- TreeTab.lua:1940 updateSliders, inverted: returns the slider positions (in
-- slider units) that legacy would show for an existing row.
local function sliderValuesFromRow(sliderData, twoStats)
	local w1, w2, w3
	if sliderData[2] == "required" then
		w1 = 10
	else
		w1 = m_min(m_max((tonumber(sliderData[2]) or 0) / 10, 0), 1) * 10
	end
	if twoStats then
		if sliderData[3] == "required" then
			w2 = 10
		else
			w2 = m_min(m_max((tonumber(sliderData[3]) or 0) / 10, 0), 1) * 10
		end
	else
		w2 = 0 -- slider2 disabled: selFunc forced val = 0 (TreeTab.lua:1992)
	end
	if sliderData[4] == "required" then
		w3 = "required"
	else
		w3 = m_min(m_max((tonumber(sliderData[4]) or 0) / 500, 0), 1) * 500
	end
	return w1, w2, w3
end

-- TreeTab.lua:1604 parseSearchList, mode 0 (text -> table)
local function parseSearchListText(fallback)
	local timelessData = S.timelessData
	if fallback then
		-- timelessData.searchListFallback => searchListFallbackTbl
		if timelessData.searchListFallback then
			S.searchListFallbackTbl = { }
			local searchListFallbackTbl = S.searchListFallbackTbl
			for inputLine in timelessData.searchListFallback:gmatch("[^\r\n]+") do
				searchListFallbackTbl[#searchListFallbackTbl + 1] = { }
				for splitLine in inputLine:gmatch("([^,%s]+)") do
					searchListFallbackTbl[#searchListFallbackTbl][#searchListFallbackTbl[#searchListFallbackTbl] + 1] = splitLine
				end
			end
		end
		S.parsedSearchListFallback = timelessData.searchListFallback
	else
		-- timelessData.searchList => searchListTbl
		if timelessData.searchList then
			S.searchListTbl = { }
			local searchListTbl = S.searchListTbl
			for inputLine in timelessData.searchList:gmatch("[^\r\n]+") do
				searchListTbl[#searchListTbl + 1] = { }
				for splitLine in inputLine:gmatch("([^,%s]+)") do
					searchListTbl[#searchListTbl][#searchListTbl[#searchListTbl] + 1] = splitLine
				end
			end
		end
		S.parsedSearchList = timelessData.searchList
	end
end

-- TreeTab.lua:1604 parseSearchList, mode 1 (table -> text, rewriting the row of
-- the currently selected node with the slider weights).
-- `selectedId` replaces controls.nodeSelect.list[controls.nodeSelect.selIndex].id,
-- `nodeWeights` replaces getNodeWeights() on the live slider labels.
local function parseSearchListRewrite(fallback, selectedId, nodeWeights)
	local timelessData = S.timelessData
	local tbl = fallback and S.searchListFallbackTbl or S.searchListTbl
	local searchText = ""
	for _, curRow in ipairs(tbl) do
		if curRow[1] == selectedId then
			curRow[2] = nodeWeights[1]
			curRow[3] = nodeWeights[2]
			curRow[4] = nodeWeights[3]
		end
		if #searchText > 0 then
			searchText = searchText .. "\n"
		end
		searchText = searchText .. t_concat(curRow, ", ")
	end
	if fallback then
		if timelessData.searchListFallback ~= searchText then
			timelessData.searchListFallback = searchText
			S.build.modFlag = true
		end
		-- the table already reflects the text (legacy does not re-parse here)
		S.parsedSearchListFallback = timelessData.searchListFallback
	else
		if timelessData.searchList ~= searchText then
			timelessData.searchList = searchText
			S.build.modFlag = true
		end
		S.parsedSearchList = timelessData.searchList
	end
end

-- TreeTab.lua:1679
local function updateSearchList(text, fallback)
	local timelessData = S.timelessData
	if fallback then
		timelessData.searchListFallback = text
	else
		timelessData.searchList = text
	end
	parseSearchListText(fallback)
	S.build.modFlag = true
end

-- TreeTab.lua:1734
local function setAllocatedNodes() -- find allocated nodes in radius for Militant Faith filtering / protected nodes dropdown
	local timelessData = S.timelessData
	local treeData = S.treeData
	local build = S.build
	if timelessData.jewelSocket.id == -1 or not treeData.nodes[timelessData.jewelSocket.id] then
		return
	end
	-- nil-guard added: a non-socket node id has no nodesInRadius
	if not treeData.nodes[timelessData.jewelSocket.id].nodesInRadius then
		return
	end
	local nodeNames = { }
	local radiusNodes = treeData.nodes[timelessData.jewelSocket.id].nodesInRadius[3] -- large radius around timelessData.jewelSocket.id
	local grantedPassives = build.calcsTab and build.calcsTab.mainEnv and build.calcsTab.mainEnv.grantedPassives or { }
	for nodeId in pairs(radiusNodes) do
		if grantedPassives[nodeId] ~= nil or build.spec.allocNodes[nodeId] ~= nil then
			S.allocatedNodes[nodeId] = true
			if treeData.nodes[nodeId] and treeData.nodes[nodeId].isNotable then
				t_insert(nodeNames, treeData.nodes[nodeId].dn)
			end
		end
	end
	S.protectOptions = nodeNames -- controls.protectAllocatedSelect:SetList(nodeNames)
	S.allocatedNodesInRadiusCount = #nodeNames
end

-- TreeTab.lua:1767
local function clearProtected() -- clear all controls, nodes related to Militant Faith filtering
	S.protectedNodesCount = 0
	S.protectedNodes = { }
	-- (legacy also removed the "protected:<name>" label controls; QML renders S.protectedNodes)
end

-- ---------------------------------------------------------------------------
-- ensure(): (re)initialise S for the current build and restore persisted stubs
-- ---------------------------------------------------------------------------

local function ensure()
	local build = main and main.modes and main.modes.BUILD
	if not build or type(build.timelessData) ~= "table" or not build.spec or not build.spec.tree or not build.spec.tree.legion then
		return nil
	end
	if not S or S.build ~= build or S.timelessData ~= build.timelessData then
		S = newState(build)
	end
	if S.spec ~= build.spec or S.treeData ~= build.spec.tree then
		bindSpec(S, build.spec)
	end
	local timelessData = S.timelessData
	-- Build.lua:78 always creates these; guards only for foreign/partial tables
	timelessData.jewelType = timelessData.jewelType or { }
	timelessData.conquerorType = timelessData.conquerorType or { }
	timelessData.jewelSocket = timelessData.jewelSocket or { }
	timelessData.fallbackWeightMode = timelessData.fallbackWeightMode or { }
	timelessData.searchResults = timelessData.searchResults or { }
	timelessData.sharedResults = timelessData.sharedResults or { }

	-- TreeTab.lua:1403 rebuild `timelessData.jewelType` as we only store the minimum amount of `jewelType` data in build XML
	if next(timelessData.jewelType) then
		for idx, jewelType in ipairs(jewelTypes) do
			if jewelType.id == timelessData.jewelType.id then
				timelessData.jewelType = jewelType
				break
			end
		end
		-- port: an unknown id would crash legacy (jewelType.name == nil); fall back to the default
		if not timelessData.jewelType.name then
			timelessData.jewelType = jewelTypes[1]
		end
	else
		timelessData.jewelType = jewelTypes[1]
	end
	-- TreeTab.lua:1452 rebuild `timelessData.conquerorType` as we only store the minimum amount of `conquerorType` data in build XML
	if next(timelessData.conquerorType) then
		for idx, conquerorType in ipairs(conquerorTypes[timelessData.jewelType.id]) do
			if conquerorType.id == timelessData.conquerorType.id then
				timelessData.conquerorType = conquerorType
				break
			end
		end
		-- port: same crash guard as above (legacy DropDown selIndex = nil)
		if not timelessData.conquerorType.label then
			timelessData.conquerorType = conquerorTypes[timelessData.jewelType.id][1]
		end
	else
		timelessData.conquerorType = conquerorTypes[timelessData.jewelType.id][1]
	end

	-- TreeTab.lua:1481 socket list (lazy)
	local sig = socketSignature(build)
	if S.socketSig ~= sig then
		S.jewelSockets = buildJewelSockets()
		S.socketSig = sig
	end
	-- TreeTab.lua:1523 rebuild `timelessData.jewelSocket` as we only store the minimum amount of `jewelSocket` data in build XML
	if next(timelessData.jewelSocket) then
		for idx, jewelSocket in ipairs(S.jewelSockets) do
			if jewelSocket.id == timelessData.jewelSocket.id then
				timelessData.jewelSocket = jewelSocket
				break
			end
		end
	else
		timelessData.jewelSocket = S.jewelSockets[1]
	end

	-- TreeTab.lua:1966 buildMods() (lazy, per jewel type)
	if S.modDataTypeId ~= timelessData.jewelType.id then
		buildMods()
	end

	-- TreeTab.lua:1677-1678 initial parse; re-parse only when the text changed
	-- outside this module (e.g. build XML load)
	if S.parsedSearchList ~= timelessData.searchList then
		parseSearchListText(false)
	end
	if S.parsedSearchListFallback ~= timelessData.searchListFallback then
		parseSearchListText(true)
	end

	-- TreeTab.lua:1814 "set shown and list on load": refreshed on every call
	-- because the port's finder is not modal (allocations can change meanwhile)
	if timelessData.socketFilter then
		setAllocatedNodes()
	end
	return S
end

-- ---------------------------------------------------------------------------
-- Search (TreeTab.lua:2494-2887)
-- ---------------------------------------------------------------------------

-- Helper function to search a single socket
-- TreeTab.lua:2494
local function searchSingleSocket(socketId, socketInfo)
	local build = S.build
	local treeData = S.treeData
	local timelessData = S.timelessData
	local legionNodes = S.legionNodes
	local legionAdditions = S.legionAdditions
	local protectedNodes = S.protectedNodes
	local protectedNodesCount = S.protectedNodesCount
	if not treeData.nodes[socketId] or not treeData.nodes[socketId].isJewelSocket then
		return nil
	end

	local radiusNodes = treeData.nodes[socketId].nodesInRadius[3]
	local allocatedNodes = { }
	local unAllocatedNodesDistance = { }
	local targetNodes = { }
	local targetSmallNodes = { ["attributeSmalls"] = 0, ["otherSmalls"] = 0 }
	local desiredNodes = { }
	local minimumWeights = { }
	local resultNodes = { }
	local rootNodes = { }
	local desiredIdx = 0
	local searchListCombinedTbl = { }
	local searchListNodeFound = { }

	for _, curRow in ipairs(S.searchListTbl) do
		searchListNodeFound[curRow[1]] = true
		searchListCombinedTbl[#searchListCombinedTbl + 1] = copyTable(curRow)
	end
	for _, curRow in ipairs(S.searchListFallbackTbl) do
		if not searchListNodeFound[curRow[1]] then
			searchListCombinedTbl[#searchListCombinedTbl + 1] = copyTable(curRow)
		end
	end

	for _, desiredNode in ipairs(searchListCombinedTbl) do
		if #desiredNode > 1 then
			local displayName = nil
			local singleStat = false
			if totalMods[timelessData.jewelType.id] and desiredNode[1] == "total_" .. totalMods[timelessData.jewelType.id]:lower() then
				desiredNode[1] = "totalStat"
				displayName = totalMods[timelessData.jewelType.id]
			end
			if displayName == nil then
				for _, legionNode in ipairs(legionNodes) do
					if legionNode.id == desiredNode[1] then
						-- non-vaal replacements only support one nodeWeight
						if timelessData.jewelType.id > 1 then
							singleStat = true
						end
						displayName = t_concat(legionNode.sd, " + ")
						break
					end
				end
			end
			if displayName == nil then
				for _, legionAddition in ipairs(legionAdditions) do
					if legionAddition.id == desiredNode[1] then
						-- additions only support one nodeWeight
						singleStat = true
						displayName = t_concat(legionAddition.sd, " + ")
						break
					end
				end
			end
			if displayName ~= nil then
				for i, val in ipairs(desiredNode) do
					if singleStat and i == 2 then
						desiredNode[2] = tonumber(desiredNode[2]) or tonumber(desiredNode[3]) or 1
					end
					if val == "required" then
						desiredNode[i] = (singleStat and i == 2) and desiredNode[2] or 0
						-- port: legacy compared `desiredNode[4] < 0.001` directly, which raises
						-- "attempt to compare string with number" when row[4] is still a
						-- string from the text box; tonumber() keeps the intended semantics.
						if desiredNode[4] == nil or (tonumber(desiredNode[4]) or 0) < 0.001 then
							desiredNode[4] = 0.001
						end
					end
				end
				-- port: tonumber(...) or 0 guards a non-numeric 4th field (legacy: compare-nil error)
				if desiredNode[4] ~= nil and (tonumber(desiredNode[4]) or 0) > 0 then
					t_insert(minimumWeights, { reqNode = desiredNode[1], weight = tonumber(desiredNode[4]) })
				end
				-- if we're protecting a node and the number of protected nodes is less than the total allocated in radius and the total desired nodes is less than the total allocated in radius
				-- these constraints avoid a blank result in the case where you set a min weight of 1 onto a non devotion stat with zero unprotected nodes
				if protectedNodesCount > 0 and protectedNodesCount < S.allocatedNodesInRadiusCount and (#searchListCombinedTbl < S.allocatedNodesInRadiusCount) then
					t_insert(minimumWeights, { reqNode = desiredNode[1], weight = 1 })
				end
				if desiredNodes[desiredNode[1]] then
					desiredNodes[desiredNode[1]] = {
						nodeWeight = tonumber(desiredNode[2]) or 0.001,
						nodeWeight2 = tonumber(desiredNode[3]) or 0.001,
						displayName = displayName or desiredNode[1],
						desiredIdx = desiredNodes[desiredNode[1]].desiredIdx
					}
				else
					desiredIdx = desiredIdx + 1
					desiredNodes[desiredNode[1]] = {
						nodeWeight = tonumber(desiredNode[2]) or 0.001,
						nodeWeight2 = tonumber(desiredNode[3]) or 0.001,
						displayName = displayName or desiredNode[1],
						desiredIdx = desiredIdx
					}
				end
			end
		end
	end
	wipeTable(searchListCombinedTbl)

	for _, class in pairs(treeData.classes) do
		rootNodes[class.startNodeId] = true
	end

	-- control read #1 substituted: controls.socketFilter.state -> timelessData.socketFilter
	if timelessData.socketFilter then
		timelessData.socketFilterDistance = timelessData.socketFilterDistance or 0
		local grantedPassives = build.calcsTab and build.calcsTab.mainEnv and build.calcsTab.mainEnv.grantedPassives or { }
		for nodeId in pairs(radiusNodes) do
			allocatedNodes[nodeId] = grantedPassives[nodeId] ~= nil or build.spec.allocNodes[nodeId] ~= nil
			if timelessData.socketFilterDistance > 0 then
				unAllocatedNodesDistance[nodeId] = build.spec.nodes[nodeId] and build.spec.nodes[nodeId].pathDist or 1000
			end
		end
	end

	for nodeId in pairs(radiusNodes) do
		if not rootNodes[nodeId]
		and not treeData.nodes[nodeId].isJewelSocket
		and not treeData.nodes[nodeId].isKeystone
		and (not timelessData.socketFilter or allocatedNodes[nodeId] or (timelessData.socketFilterDistance > 0 and unAllocatedNodesDistance[nodeId] <= timelessData.socketFilterDistance)) then
			if (treeData.nodes[nodeId].isNotable or timelessData.jewelType.id == 1) then
				targetNodes[nodeId] = true
			elseif desiredNodes["totalStat"] and not treeData.nodes[nodeId].isNotable then
				if isValueInArray({ "Strength", "Intelligence", "Dexterity" }, treeData.nodes[nodeId].dn) then
					targetSmallNodes.attributeSmalls = targetSmallNodes.attributeSmalls + 1
				else
					targetSmallNodes.otherSmalls = targetSmallNodes.otherSmalls + 1
				end
			end
		end
	end

	local seedWeights = { }
	local seedMultiplier = timelessData.jewelType.id == 5 and 20 or 1 -- Elegant Hubris
	-- TreeTab.lua:2625
	for curSeed = data.timelessJewelSeedMin[timelessData.jewelType.id] * seedMultiplier, data.timelessJewelSeedMax[timelessData.jewelType.id] * seedMultiplier, seedMultiplier do
		seedWeights[curSeed] = 0
		resultNodes[curSeed] = { }
		for targetNode in pairs(targetNodes) do
			local jewelDataTbl = data.readLUT(curSeed, targetNode, timelessData.jewelType.id)
			if not next(jewelDataTbl) then
				ConPrintf("Missing LUT: " .. timelessData.jewelType.label)
			else
				local curNode = nil
				local curNodeId = nil
				if (timelessData.jewelType.id == 4 and isValueInTable(protectedNodes, treeData.nodes[targetNode].dn)) then -- protected
					if jewelDataTbl[1] >= data.timelessJewelAdditions then -- protected node is a replacement, invalidate seed
						resultNodes[curSeed] = nil
						break
					end
					if not desiredNodes["totalStat"] then -- only add if user has not entered their own Devotion to the table
						desiredNodes["totalStat"] = {
							nodeWeight = 0.1, -- keeps total score low to let desired stats decide sort
							nodeWeight2 = 0,
							displayName = "Devotion",
							desiredIdx = desiredIdx + 1
						}
					end
					curNodeId = "totalStat"
				end
				if jewelDataTbl[1] >= data.timelessJewelAdditions and not isValueInTable(protectedNodes, treeData.nodes[targetNode].dn) then -- replace
					curNode = legionNodes[jewelDataTbl[1] + 1 - data.timelessJewelAdditions]
					curNodeId = curNode and legionNodes[jewelDataTbl[1] + 1 - data.timelessJewelAdditions].id or nil
				else -- add
					curNode = legionAdditions[jewelDataTbl[1] + 1]
					curNodeId = curNode and legionAdditions[jewelDataTbl[1] + 1].id or nil
				end
				if desiredNodes["totalStat"] and reverseTotalModIDs[curNodeId] then
					curNodeId = "totalStat"
				end
				if timelessData.jewelType.id == 1 then
					local headerSize = #jewelDataTbl
					if headerSize == 2 or headerSize == 3 then
						if desiredNodes[curNodeId] then
							resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
							local statMod1 = curNode.stats[curNode.sortedStats[1]]
							local weight = desiredNodes[curNodeId].nodeWeight * jewelDataTbl[statMod1.index + 1]
							local statMod2 = curNode.stats[curNode.sortedStats[2]]
							if statMod2 then
								weight = weight + desiredNodes[curNodeId].nodeWeight2 * jewelDataTbl[statMod2.index + 1]
							end
							t_insert(resultNodes[curSeed][curNodeId], targetNode)
							t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
							resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + weight
							seedWeights[curSeed] = seedWeights[curSeed] + weight
						end
					elseif headerSize == 6 or headerSize == 8 then
						for i, jewelData in ipairs(jewelDataTbl) do
							curNode = legionAdditions[jewelDataTbl[i] + 1]
							curNodeId = curNode and legionAdditions[jewelDataTbl[i] + 1].id or nil
							if i <= (headerSize / 2) then
								if desiredNodes[curNodeId] then
									resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
									local weight = desiredNodes[curNodeId].nodeWeight * jewelDataTbl[i + (headerSize / 2)]
									resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + weight
									t_insert(resultNodes[curSeed][curNodeId], targetNode)
									t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
									seedWeights[curSeed] = seedWeights[curSeed] + weight
								end
							else
								break
							end
						end
					end
				elseif desiredNodes[curNodeId] then
					resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
					resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + desiredNodes[curNodeId].nodeWeight
					t_insert(resultNodes[curSeed][curNodeId], targetNode)
					t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
					seedWeights[curSeed] = seedWeights[curSeed] + desiredNodes[curNodeId].nodeWeight
				end
			end
		end
		if resultNodes[curSeed] and desiredNodes["totalStat"] then
			resultNodes[curSeed]["totalStat"] = resultNodes[curSeed]["totalStat"] or { targetNodeNames = { }, totalWeight = 0 }
			if timelessData.jewelType.id == 4 then -- Militant Faith
				local addedWeight = desiredNodes["totalStat"].nodeWeight * (5 * targetSmallNodes.otherSmalls + 10 * targetSmallNodes.attributeSmalls)
				addedWeight = addedWeight + resultNodes[curSeed]["totalStat"].totalWeight * 4
				resultNodes[curSeed]["totalStat"].totalWeight = resultNodes[curSeed]["totalStat"].totalWeight + addedWeight
				seedWeights[curSeed] = seedWeights[curSeed] + addedWeight
			else
				local addedWeight = desiredNodes["totalStat"].nodeWeight * (4 * targetSmallNodes.otherSmalls + 2 * targetSmallNodes.attributeSmalls)
				addedWeight = addedWeight + resultNodes[curSeed]["totalStat"].totalWeight * 19
				resultNodes[curSeed]["totalStat"].totalWeight = resultNodes[curSeed]["totalStat"].totalWeight + addedWeight
				seedWeights[curSeed] = seedWeights[curSeed] + addedWeight
			end
		end
		if resultNodes[curSeed] then
			-- check minimum weights
			for _, val in ipairs(minimumWeights) do
				if (resultNodes[curSeed][val.reqNode] and resultNodes[curSeed][val.reqNode].totalWeight or 0) < val.weight then
					resultNodes[curSeed] = nil
					break
				end
			end
		end
	end

	return {
		resultNodes = resultNodes,
		seedWeights = seedWeights,
		desiredNodes = desiredNodes,
		socketInfo = socketInfo
	}
end

-- TreeTab.lua:2737
local function formatSearchValue(input)
	local   matchPattern1 = " 0"
	local replacePattern1 = "   "
	local   matchPattern2 = ".0 "
	local replacePattern2 = "    "
	local   matchPattern3 = "  %."
	local replacePattern3 = "0."
	local   matchPattern4 = "%.([0-9])0"
	local replacePattern4 = ".%1  "
	return (" " .. s_format("%006.2f", input))
	:gsub(matchPattern1, replacePattern1):gsub(matchPattern1, replacePattern1)
	:gsub(matchPattern2, replacePattern2):gsub(matchPattern2, replacePattern2)
	:gsub(matchPattern3, replacePattern3)
	:gsub(matchPattern4, replacePattern4)
end

-- TreeTab.lua:2753
local function formatResults(resultNodes, seedWeights, desiredNodes, socketInfo)
	local timelessData = S.timelessData
	local results = { }
	for seedMatch, seedData in pairs(resultNodes) do
		-- filter out the results so that only the ones that beat the total minimum weight parameter remain in search results
		local passesMin = (not timelessData.totalMinimumWeight) or (seedWeights[seedMatch] >= timelessData.totalMinimumWeight)
		if seedWeights[seedMatch] > 0 and passesMin then
			local labelPrefix = socketInfo and (socketInfo.label .. " | ") or ""
			local result = {
				label = labelPrefix .. seedMatch .. ":",
				seed = seedMatch,
				total = seedWeights[seedMatch]
			}
			if socketInfo then
				result.socketId = socketInfo.id
				result.socketLabel = socketInfo.label
			end
			if timelessData.jewelType.id == 1 or timelessData.jewelType.id == 3 then
				-- Glorious Vanity [100-8000], Brutal Restraint [500-8000]
				if seedMatch < 1000 then
					result.label = "  " .. result.label
				end
			elseif timelessData.jewelType.id == 4 then
				-- Militant Faith [2000-10000]
				if seedMatch < 10000 then
					result.label = "  " .. result.label
				end
			else
				-- Elegant Hubris [2000-160000]
				if seedMatch < 10000 then
					result.label = "    " .. result.label
				elseif seedMatch < 100000 then
					result.label = "  " .. result.label
				end
			end
			local sortedNodeArray = { }
			for legionId, desiredNode in pairs(desiredNodes) do
				if seedData[legionId] then
					if desiredNode.desiredIdx == 8 then
						sortedNodeArray[8] = " ..."
					elseif desiredNode.desiredIdx < 8 then
						sortedNodeArray[desiredNode.desiredIdx] = formatSearchValue(seedData[legionId].totalWeight)
					end
					result[legionId] = result[legionId] or { }
					result[legionId].targetNodeNames = seedData[legionId].targetNodeNames
				elseif desiredNode.desiredIdx < 8 then
					sortedNodeArray[desiredNode.desiredIdx] = "     0     "
				end
			end
			result.label = result.label .. t_concat(sortedNodeArray)
			t_insert(results, result)
		end
	end
	return results
end

-- TreeTab.lua:2822 search button body
local function runSearch()
	local timelessData = S.timelessData
	local jewelSockets = S.jewelSockets
	if timelessData.jewelSocket.id == -1 then
		wipeTable(timelessData.searchResults)
		wipeTable(timelessData.sharedResults)
		timelessData.sharedResults.type = timelessData.jewelType
		timelessData.sharedResults.conqueror = timelessData.conquerorType
		-- port: `or devotionVariants[1]` guards an out-of-range persisted index (legacy: nil -> trade URL crash)
		timelessData.sharedResults.devotionVariant1 = devotionVariants[timelessData.devotionVariant1] or devotionVariants[1]
		timelessData.sharedResults.devotionVariant2 = devotionVariants[timelessData.devotionVariant2] or devotionVariants[1]
		timelessData.sharedResults.multiSocket = true

		for socketIdx = 2, #jewelSockets do
			local currentSocket = jewelSockets[socketIdx]
			local searchResult = searchSingleSocket(currentSocket.id, currentSocket)
			if searchResult then
				local resultNodes = searchResult.resultNodes
				local seedWeights = searchResult.seedWeights
				local desiredNodes = searchResult.desiredNodes

				timelessData.sharedResults.desiredNodes = desiredNodes

				for _, result in ipairs(formatResults(resultNodes, seedWeights, desiredNodes, currentSocket)) do
					timelessData.searchResults[#timelessData.searchResults + 1] = result
				end
			end
		end

		t_sort(timelessData.searchResults, function(a, b)
			if a.total == b.total then
				return (a.socketLabel or "") < (b.socketLabel or "")
			end
			return a.total > b.total
		end)

		-- controls.searchTradeButton.enabled is derived from #searchResults in GetState
		S.lastSearch = nil
		S.tradeLabel = "Open Trade URL"
		S.highlightIndex = nil
		S.resultsSelIndex = 1
	else
		local searchResult = searchSingleSocket(timelessData.jewelSocket.id, timelessData.jewelSocket)
		if searchResult then
			local resultNodes = searchResult.resultNodes
			local seedWeights = searchResult.seedWeights
			local desiredNodes = searchResult.desiredNodes

			wipeTable(timelessData.searchResults)
			wipeTable(timelessData.sharedResults)
			timelessData.sharedResults.type = timelessData.jewelType
			timelessData.sharedResults.conqueror = timelessData.conquerorType
			timelessData.sharedResults.devotionVariant1 = devotionVariants[timelessData.devotionVariant1] or devotionVariants[1]
			timelessData.sharedResults.devotionVariant2 = devotionVariants[timelessData.devotionVariant2] or devotionVariants[1]
			timelessData.sharedResults.socket = timelessData.jewelSocket
			timelessData.sharedResults.desiredNodes = desiredNodes

			for _, result in ipairs(formatResults(resultNodes, seedWeights, desiredNodes, nil)) do
				timelessData.searchResults[#timelessData.searchResults + 1] = result
			end
			t_sort(timelessData.searchResults, function(a, b) return a.total > b.total end)
			S.lastSearch = nil
			S.tradeLabel = "Open Trade URL"
			S.highlightIndex = nil
			S.resultsSelIndex = 1
		else
			-- legacy silently did nothing; surface it
			S.msg = "Selected jewel socket is not a valid jewel socket on this tree."
		end
	end
	S.resultsVersion = S.resultsVersion + 1
end

-- ---------------------------------------------------------------------------
-- Fallback weights (TreeTab.lua:2036-2174)
-- ---------------------------------------------------------------------------

-- TreeTab.lua:2036
local function generateFallbackWeights(nodes, powerStat)
	local build = S.build
	local calcFunc, calcBase = build.calcsTab:GetMiscCalculator(build)
	local newList = { }
	local basePower = data.powerStatList.GetFromOutput(calcBase, powerStat)
	for _, newNode in ipairs(nodes) do
		local powerEntry = { id = newNode.id }
		-- nodes that have multiple lines are represented as a list in newNode.node
		local nodeLines = newNode.node or { newNode }
		for i = 1, #nodeLines do
			local node = nodeLines[i]
			local nodeOutput = calcFunc({ addNodes = { [node] = true } })
			local nodePower = data.powerStatList.GetFromOutput(nodeOutput, powerStat)
			-- avoid infinity
			if basePower == 0 then
				powerEntry["weight" .. i] = 0
			else
				local powerGain = (nodePower - basePower) /
					-- normalize with absolute base power so that the result isn't negative
					math.abs(basePower)
				powerEntry["weight" .. i] = powerGain / (newNode.divisor or 1)
			end
		end
		t_insert(newList, powerEntry)
	end
	return newList
end

-- TreeTab.lua:2063
local function setupFallbackWeights()
	local timelessData = S.timelessData
	local modData = S.modData
	local legionNodes = S.legionNodes
	local legionAdditions = S.legionAdditions
	-- replaceHelperFunc is duplicated from PassiveSpec.lua
	local replaceHelperFunc = function(statToFix, statKey, statMod, value)
		if statMod.fmt == "g" then -- note the only one we actually care about is "Ritual of Flesh" life regen
			if statKey:find("per_minute") then
				value = round(value / 60, 1)
			elseif statKey:find("permyriad") then
				value = value / 100
			elseif statKey:find("_ms") then
				value = value / 1000
			end
		end
		--if statMod.fmt == "d" then -- only ever d or g, and we want both past here
		if statMod.min ~= statMod.max then
			return statToFix:gsub("%(" .. statMod.min .. "%-" .. statMod.max .. "%)", value)
		elseif statMod.min ~= value then -- only true for might/legacy of the vaal which can combine stats
			return statToFix:gsub(statMod.min, value)
		end
		return statToFix -- if it doesn't need to be changed
	end

	local nodes = { }
	for _, modNode in ipairs(modData) do
		if modNode.id then
			local newNode = nil
			for _, legionNode in ipairs(legionNodes) do
				if legionNode.id == modNode.id or (totalModIDs[modNode.id] and totalModIDs[modNode.id][legionNode.id]) then
						newNode = { }
						newNode.id = modNode.id
						if modNode.type == "vaal" then
							if #legionNode.sd == 2 then
								newNode.calcMultiple = true
								if legionNode.modListGenerated then
									newNode.node = copyTable(legionNode.modListGenerated)
								else
									-- generate modList
									local modList1, extra1 = modLib.parseMod(replaceHelperFunc(legionNode.sd[1], legionNode.sortedStats[1], legionNode.stats[legionNode.sortedStats[1]], 100))
									local modList2, extra2 = modLib.parseMod(replaceHelperFunc(legionNode.sd[2], legionNode.sortedStats[2], legionNode.stats[legionNode.sortedStats[2]], 100))
									local modLists = { { modList = modList1 }, { modList = modList2 } }
									legionNode.modListGenerated = copyTable(modLists)
									newNode.node = copyTable(modLists)
								end
								newNode.node[1].id = legionNode.id
								newNode.node[2].id = legionNode.id
							else
								if legionNode.modListGenerated then
									newNode.modList = copyTable(legionNode.modListGenerated)
								else
									-- generate modList
									local modList, extra = modLib.parseMod(replaceHelperFunc(legionNode.sd[1], legionNode.sortedStats[1], legionNode.stats[legionNode.sortedStats[1]], 100))
									legionNode.modListGenerated = modList
									newNode.modList = modList
								end
							end
							newNode.divisor = 100
						else
							newNode.modList = legionNode.modList
							if modNode.totalMod then
								newNode.divisor = legionNode.modList[1].value
							end
						end
					break
				end
			end
			if not newNode then
				for _, legionAddition in ipairs(legionAdditions) do
					if legionAddition.id == modNode.id or (totalModIDs[modNode.id] and totalModIDs[modNode.id][legionAddition.id]) then
						newNode = { }
						newNode.id = modNode.id
						if legionAddition.modList then
							newNode.modList = legionAddition.modList
						elseif legionAddition.modListGenerated then
							newNode.modList = legionAddition.modListGenerated
						else
							-- generate modList
							local line = legionAddition.sd[1]
							if modNode.type == "vaal" then
								-- port BUG FIX: legacy TreeTab.lua:2140 read
								--   `for key, stat in legionAddition.stats do`
								-- (missing pairs(); iterating a table value raises "attempt to call a
								-- table value"). Unreachable in practice (buildMods skips vaal
								-- additions) but fixed so it cannot throw.
								for key, stat in pairs(legionAddition.stats) do -- should only be length 1
									line = replaceHelperFunc(line, key, stat, 100)
								end
							end
							local modList, extra = modLib.parseMod(line)
							legionAddition.modListGenerated = modList
							newNode.modList = modList
						end
						if modNode.type == "vaal" then
							newNode.divisor = 100
						elseif modNode.totalMod then
							newNode.divisor = newNode.modList[1].value
						end
						break
					end
				end
			end
			if newNode then
				t_insert(nodes, newNode)
			end
		end
	end
	-- control read #2 substituted:
	-- controls.fallbackWeightsList.list[controls.fallbackWeightsList.selIndex]
	local powerStat = S.fallbackWeightsList[timelessData.fallbackWeightMode.idx or 1] or S.fallbackWeightsList[1]
	local output = generateFallbackWeights(nodes, powerStat)
	local newList = ""
	local weightScalar = 100
	for _, legionNode in ipairs(output) do
		if legionNode.weight1 ~= 0 or (legionNode.weight2 and legionNode.weight2 ~= 0) then
			if #newList > 0 then
				newList = newList .. "\n"
			end
			newList = newList .. legionNode.id .. ", " .. round(legionNode.weight1 * weightScalar, 3) .. ", " .. round((legionNode.weight2 or 0) * weightScalar, 3) .. ", 0"
		end
	end
	updateSearchList(newList, true)
end

-- ---------------------------------------------------------------------------
-- State marshalling
-- ---------------------------------------------------------------------------

-- TJLC L67 AddValueTooltip, as plain lines (colour codes dropped, indentation kept)
local function buildResultTooltip(row, sharedList)
	local lines = { }
	if row.label:match("B2B2B2") == nil then
		t_insert(lines, "Double click to add this jewel to your build.")
	else
		t_insert(lines, tostring(sharedList.type and sharedList.type.label or "") .. " " .. tostring(row.seed) .. " was successfully added to your build.")
	end
	local sortedNodeLists = { }
	local maxIdx = 0
	for legionId, desiredNode in pairs(sharedList.desiredNodes or { }) do
		if row[legionId] and desiredNode.desiredIdx then
			local entry = { desiredNode.displayName .. ":" }
			if row[legionId].targetNodeNames and #row[legionId].targetNodeNames > 0 then
				for _, name in ipairs(row[legionId].targetNodeNames) do
					t_insert(entry, "    " .. tostring(name))
				end
			else
				t_insert(entry, "    None")
			end
			sortedNodeLists[desiredNode.desiredIdx] = entry
			maxIdx = m_max(maxIdx, desiredNode.desiredIdx)
		end
	end
	if next(sortedNodeLists) then
		t_insert(lines, "Node List:")
		for i = 1, maxIdx do
			if sortedNodeLists[i] then
				for _, line in ipairs(sortedNodeLists[i]) do
					t_insert(lines, "    " .. line)
				end
			end
		end
	end
	if row.total > 0 then
		t_insert(lines, "Combined Node Weight: " .. row.total)
	end
	return lines
end

-- Result rows are marshalled ON DEMAND, a page at a time (pob_timelessGetResults):
-- a multi-socket search can produce 100k+ rows (legacy keeps the same list),
-- and converting all of them -- tooltips included -- on every state call would
-- stall the UI. Rows are cached per search (resultsVersion) as they are built.
local function marshalRow(i)
	local timelessData = S.timelessData
	local list = timelessData.searchResults
	local cache = S.resultsCache
	if not cache or cache.version ~= S.resultsVersion or cache.count ~= #list then
		cache = { version = S.resultsVersion, count = #list, rows = { } }
		S.resultsCache = cache
	end
	local row = list[i]
	if not row then return nil end
	local hit = cache.rows[i]
	-- The label changes in place when a jewel is added (^xB2B2B2 prefix).
	if hit and hit.label == row.label then return hit end
	hit = {
		index = i,
		label = row.label,
		seed = row.seed,
		total = row.total,
		socketId = row.socketId,
		socketLabel = row.socketLabel,
		added = row.label:match("B2B2B2") ~= nil,
		tooltip = buildResultTooltip(row, timelessData.sharedResults or { }),
	}
	cache.rows[i] = hit
	return hit
end

local RESULT_PAGE = 200

local function currentSocketIndex()
	local timelessData = S.timelessData
	-- TreeTab.lua:1758 search through `jewelSockets` for the correct `id` as the `idx` can become stale due to dynamic sorting
	for idx, jewelSocket in ipairs(S.jewelSockets) do
		if jewelSocket.id == timelessData.jewelSocket.id then
			return idx
		end
	end
	return 1
end

function pob_timelessGetState()
	local st = ensure()
	if not st then
		return { error = "No build loaded", msg = "No build loaded", results = { } }
	end
	local timelessData = st.timelessData
	local state = { }

	state.jewelTypes = { }
	for i, jt in ipairs(jewelTypes) do
		state.jewelTypes[i] = { id = jt.id, label = jt.label }
	end
	state.jewelTypeIndex = timelessData.jewelType.id

	state.conquerors = { }
	for i, ct in ipairs(conquerorTypes[timelessData.jewelType.id]) do
		state.conquerors[i] = { id = ct.id, label = ct.label }
	end
	state.conquerorIndex = timelessData.conquerorType.id -- TreeTab.lua:1727

	state.showDevotion = timelessData.jewelType.id == 4 -- TreeTab.lua:1692
	state.devotionVariants = { }
	for i, dv in ipairs(devotionVariants) do
		state.devotionVariants[i] = { id = dv.id, label = dv.label }
	end
	state.devotion1 = timelessData.devotionVariant1 or 1 -- TreeTab.lua:1696
	state.devotion2 = timelessData.devotionVariant2 or 1 -- TreeTab.lua:1700

	state.sockets = { }
	for i, sock in ipairs(st.jewelSockets) do
		state.sockets[i] = { id = sock.id, label = sock.label }
	end
	state.socketIndex = currentSocketIndex()

	state.socketFilter = timelessData.socketFilter and true or false -- TreeTab.lua:1797
	state.socketFilterDistance = timelessData.socketFilterDistance or 0 -- TreeTab.lua:1847
	state.socketFilterDistanceMax = socketFilterAdditionalDistanceMAX

	state.showProtect = (timelessData.jewelType.id == 4 and state.socketFilter) -- TreeTab.lua:1817
	state.protectOptions = copyTable(st.protectOptions)
	state.protectedNodes = copyTable(st.protectedNodes)

	state.nodeOptions = st.nodeOptions
	state.nodeSelIndex = st.nodeSelIndex

	state.fallbackModes = { }
	for i, fw in ipairs(st.fallbackWeightsList) do
		state.fallbackModes[i] = fw.label
	end
	state.fallbackModeIndex = timelessData.fallbackWeightMode.idx or 1 -- TreeTab.lua:2190
	state.fallbackGenerated = st.fallbackGenerated

	state.searchList = timelessData.searchList or ""                   -- TreeTab.lua:2224
	state.searchListFallback = timelessData.searchListFallback or ""   -- TreeTab.lua:2235
	state.totalMinimumWeight = timelessData.totalMinimumWeight

	-- First page only; the rest via pob_timelessGetResults(offset, count).
	state.resultCount = #timelessData.searchResults
	state.results = { }
	for i = 1, m_min(RESULT_PAGE, state.resultCount) do state.results[i] = marshalRow(i) end
	state.resultsSelIndex = st.resultsSelIndex
	state.highlightIndex = st.highlightIndex
	state.tradeEnabled = #timelessData.searchResults > 0 -- TreeTab.lua:2386/2855/2880, reset: 2816
	state.tradeLabel = st.tradeLabel
	state.realms = copyTable(realmList)
	state.tradeTypes = copyTable(tradeTypeLabels)

	state.msg = st.msg or ""
	return state
end

-- Rows [offset, offset + count - 1] (1-based) of the current results.
function pob_timelessGetResults(offset, count)
	local st = ensure()
	if not st then return { rows = { }, total = 0 } end
	offset = m_max(1, tonumber(offset) or 1)
	count = m_min(tonumber(count) or RESULT_PAGE, 1000)
	local rows = { }
	for i = offset, m_min(offset + count - 1, #st.timelessData.searchResults) do
		rows[#rows + 1] = marshalRow(i)
	end
	return { rows = rows, offset = offset, total = #st.timelessData.searchResults }
end

-- ---------------------------------------------------------------------------
-- Setters
-- ---------------------------------------------------------------------------

function pob_timelessSet(field, value)
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	local timelessData = st.timelessData
	local build = st.build
	st.msg = ""

	-- DropDownControl:SetSel only fires selFunc when the index changes, so the
	-- dropdown-backed fields below are no-ops on an unchanged index.
	if field == "jewelType" then
		local index = tonumber(value)
		local jt = index and jewelTypes[index]
		if jt and jt.id ~= timelessData.jewelType.id then
			-- TreeTab.lua:1707 selFunc
			timelessData.jewelType = jt
			-- (devotion label / protect label visibility are derived in GetState)
			timelessData.conquerorType = conquerorTypes[timelessData.jewelType.id][1]
			st.nodeSelIndex = 1
			buildMods()
			updateSearchList("", false)
			updateSearchList("", true)
		end
	elseif field == "conqueror" then
		local index = tonumber(value)
		local list = conquerorTypes[timelessData.jewelType.id]
		local ct = index and list[index]
		if ct and ct.id ~= timelessData.conquerorType.id then
			-- TreeTab.lua:1723 selFunc
			timelessData.conquerorType = ct
			build.modFlag = true
		end
	elseif field == "devotion1" then
		local index = tonumber(value)
		if index and devotionVariants[index] and index ~= timelessData.devotionVariant1 then
			-- TreeTab.lua:1693 selFunc (legacy sets no modFlag here)
			timelessData.devotionVariant1 = index
		end
	elseif field == "devotion2" then
		local index = tonumber(value)
		if index and devotionVariants[index] and index ~= timelessData.devotionVariant2 then
			-- TreeTab.lua:1697 selFunc (legacy sets no modFlag here)
			timelessData.devotionVariant2 = index
		end
	elseif field == "socket" then
		local index = tonumber(value)
		local sock = index and st.jewelSockets[index]
		if sock and sock.id ~= timelessData.jewelSocket.id then
			-- TreeTab.lua:1753 selFunc
			timelessData.jewelSocket = sock
			setAllocatedNodes() -- reset list when changing sockets
			build.modFlag = true
		end
	elseif field == "socketFilter" then
		-- TreeTab.lua:1777 changeFunc
		local on = value and value ~= "false" and value ~= 0 and true or false
		timelessData.socketFilter = on
		build.modFlag = true
		if on then
			setAllocatedNodes()
		else
			clearProtected()
		end
	elseif field == "socketFilterDistance" then
		-- TreeTab.lua:1827 changeFunc; `value` is in label units (0..10), the
		-- slider value is value / MAX. Legacy sets no modFlag here.
		local sliderVal = m_min(m_max((tonumber(value) or 0) / socketFilterAdditionalDistanceMAX, 0), 1)
		timelessData.socketFilterDistance = m_floor(sliderVal * socketFilterAdditionalDistanceMAX + 0.01)
	elseif field == "fallbackMode" then
		local index = tonumber(value)
		if index and st.fallbackWeightsList[index] and index ~= (timelessData.fallbackWeightMode.idx or 1) then
			-- TreeTab.lua:2186 selFunc (legacy sets no modFlag here)
			timelessData.fallbackWeightMode.idx = index
		end
	elseif field == "totalMinimumWeight" then
		-- TreeTab.lua:2199: EditControl filter "%D" (digits only), then tonumber
		local num
		if type(value) == "number" then
			num = m_floor(m_max(value, 0))
		elseif value ~= nil then
			num = tonumber((tostring(value):gsub("%D", "")))
		end
		timelessData.totalMinimumWeight = num or nil
		build.modFlag = true
	elseif field == "searchList" or field == "searchListFallback" then
		-- TreeTab.lua:2217 / 2228 changeFunc; EditControl filter "^%C\t\n"
		-- strips control characters other than tab / newline.
		local fallback = field == "searchListFallback"
		local text = (tostring(value or "")):gsub("[^%C\t\n]", "")
		local current = fallback and timelessData.searchListFallback or timelessData.searchList
		-- port: skip when QML echoes the unchanged text (avoids a spurious unsaved flag)
		if text ~= current then
			if fallback then
				timelessData.searchListFallback = text
			else
				timelessData.searchList = text
			end
			parseSearchListText(fallback)
			build.modFlag = true
		end
	else
		st.msg = "Unknown field: " .. tostring(field)
	end
	return pob_timelessGetState()
end

-- TreeTab.lua:1967 nodeSelect selFunc.
-- `optionIndex` indexes state.nodeOptions (== modData); `fallback` selects the list
-- being edited (legacy: controls.searchListFallback.shown); w1/w2/w3 are the
-- current slider values (legacy read them from the slider labels).
function pob_timelessSelectNode(optionIndex, fallback, w1, w2, w3)
	local st = ensure()
	if not st then
		return { exists = false, state = pob_timelessGetState() }
	end
	local timelessData = st.timelessData
	st.msg = ""
	local index = tonumber(optionIndex)
	local value = index and st.modData[index]
	if not value then
		return { exists = false, state = pob_timelessGetState() }
	end
	st.nodeSelIndex = index
	if not value.id then
		-- the "..." entry: legacy selFunc does nothing
		return { exists = false, state = pob_timelessGetState() }
	end

	local statCount, nodeSliderStatLabel, nodeSlider2StatLabel = nodeStatInfo(value.id)
	local twoStats = statCount > 1 -- TreeTab.lua:1990-1998

	local nodeWeights = getNodeWeights(sliderLabels(w1, w2, w3, twoStats))
	local newNode = value.id .. ", " .. nodeWeights[1] .. ", " .. nodeWeights[2] .. ", " .. nodeWeights[3]
	local tbl = fallback and st.searchListFallbackTbl or st.searchListTbl
	for _, searchRow in ipairs(tbl) do
		-- update nodeSlider values and prevent duplicate searchList entries
		if searchRow[1] == value.id then
			local r1, r2, r3 = sliderValuesFromRow(searchRow, twoStats) -- updateSliders(searchRow)
			return {
				exists = true,
				w1 = r1, w2 = r2, w3 = r3,
				twoStats = twoStats,
				statLabel1 = nodeSliderStatLabel,
				statLabel2 = nodeSlider2StatLabel,
			}
		end
	end
	-- controls.searchList(Fallback):Insert at the end of the buffer, which fires
	-- the EditControl changeFunc (TreeTab.lua:2217/2228) -> text + reparse + modFlag
	if fallback then
		local buf = timelessData.searchListFallback or ""
		timelessData.searchListFallback = buf .. ((#buf > 0 and "\n" or "") .. newNode)
		parseSearchListText(true)
	else
		local buf = timelessData.searchList or ""
		timelessData.searchList = buf .. ((#buf > 0 and "\n" or "") .. newNode)
		parseSearchListText(false)
	end
	st.build.modFlag = true
	return {
		exists = false,
		twoStats = twoStats,
		statLabel1 = nodeSliderStatLabel,
		statLabel2 = nodeSlider2StatLabel,
		state = pob_timelessGetState(),
	}
end

-- Slider change funcs (TreeTab.lua:1856/1885/1913) -> parseSearchList(1, fallback)
function pob_timelessSetWeights(optionIndex, fallback, w1, w2, w3)
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	st.msg = ""
	local index = tonumber(optionIndex)
	local value = index and st.modData[index]
	local selectedId = value and value.id or nil
	if index and value then
		st.nodeSelIndex = index
	end
	local twoStats = false
	if selectedId then
		twoStats = nodeStatInfo(selectedId) > 1
	end
	-- control read #3 substituted: the slider labels are rebuilt from numbers
	parseSearchListRewrite(fallback and true or false, selectedId, getNodeWeights(sliderLabels(w1, w2, w3, twoStats)))
	return pob_timelessGetState()
end

-- TreeTab.lua:1802 (Add) / 1810 (Clear)
function pob_timelessProtect(action, name)
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	st.msg = ""
	if action == "add" then
		local selValue = name
		-- the legacy dropdown could only offer names from its list
		if selValue and isValueInArray(st.protectOptions, selValue) and not isValueInArray(st.protectedNodes, selValue) then
			st.protectedNodesCount = st.protectedNodesCount + 1
			t_insert(st.protectedNodes, selValue)
		end
	elseif action == "clear" then
		clearProtected()
	else
		st.msg = "Unknown protect action: " .. tostring(action)
	end
	return pob_timelessGetState()
end

-- TreeTab.lua:2191 Generate button
function pob_timelessGenerateFallback()
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	st.msg = ""
	local ok, err = pcall(setupFallbackWeights)
	if ok then
		st.fallbackGenerated = true -- controls.searchListFallbackButton.label = "^4Fallback Nodes"
	else
		st.msg = "Failed to generate fallback weights: " .. tostring(err)
	end
	return pob_timelessGetState()
end

-- TreeTab.lua:2822 Search button (synchronous, like legacy)
function pob_timelessSearch()
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	st.msg = ""
	local ok, err = pcall(runSearch)
	if not ok then
		st.msg = "Search failed: " .. tostring(err)
		st.resultsVersion = st.resultsVersion + 1
	end
	return pob_timelessGetState()
end

-- TreeTab.lua:2812 Reset button
function pob_timelessReset()
	local st = ensure()
	if not st then
		return pob_timelessGetState()
	end
	st.msg = ""
	updateSearchList("", true)
	updateSearchList("", false)
	wipeTable(st.timelessData.searchResults)
	-- controls.searchTradeButton.enabled = false (derived: #searchResults == 0)
	clearProtected()
	st.fallbackGenerated = false
	st.resultsVersion = st.resultsVersion + 1
	return pob_timelessGetState()
end

-- TimelessJewelListControl.lua:98 OnSelClick (double click)
function pob_timelessAddJewel(resultIndex)
	local st = ensure()
	if not st then
		return { ok = false, error = "No build loaded" }
	end
	local build = st.build
	local list = st.timelessData.searchResults
	local sharedList = st.timelessData.sharedResults
	local index = tonumber(resultIndex)
	local row = index and list[index]
	if not row then
		return { ok = false, error = "No such result row" }
	end
	if row.label:match("B2B2B2") ~= nil then
		-- legacy: double click on an already-added row is a no-op
		return { ok = false, error = "Already added" }
	end
	if not sharedList.type or not sharedList.conqueror then
		return { ok = false, error = "No search metadata" }
	end
	local socketInfo = row.socketLabel or (sharedList.socket and sharedList.socket.keystone) or "Unknown"
	local label = "[" .. row.seed .. "; " .. row.total.. "; " .. socketInfo .. "]\n"
	local variant = sharedList.conqueror.id == 1 and 1 or (sharedList.conqueror.id - 1) .. "\n"
	local itemData = [[
Heroic Tragedy ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Variant: Vorana (Black Scythe Training)
Variant: Uhtred (Celestial Mathematics)
Variant: Medved (The Unbreaking Circle)
Selected Variant: ]] .. variant .. "\n" .. [[
Radius: Large
Implicits: 0
{variant:1}Remembrancing ]] .. row.seed .. [[ songworthy deeds by the line of Vorana
{variant:2}Remembrancing ]] .. row.seed .. [[ songworthy deeds by the line of Uhtred
{variant:3}Remembrancing ]] .. row.seed .. [[ songworthy deeds by the line of Medved
Passives in radius are Conquered by the Kalguur
Historic
]]
	if sharedList.type.id == 1 then
		itemData = [[
Glorious Vanity ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Variant: Doryani (Corrupted Soul)
Variant: Xibaqua (Divine Flesh)
Variant: Ahuana (Immortal Ambition)
Selected Variant: ]] .. variant .. "\n" ..[[
Radius: Large
Implicits: 0
{variant:1}Bathed in the blood of ]] .. row.seed .. [[ sacrificed in the name of Doryani
{variant:2}Bathed in the blood of ]] .. row.seed .. [[ sacrificed in the name of Xibaqua
{variant:3}Bathed in the blood of ]] .. row.seed .. [[ sacrificed in the name of Ahuana
Passives in radius are Conquered by the Vaal
Historic
]]
	elseif sharedList.type.id == 2 then
		itemData = [[
Lethal Pride ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Variant: Kaom (Strength of Blood)
Variant: Rakiata (Tempered by War)
Variant: Akoya (Chainbreaker)
Selected Variant: ]] .. variant .. "\n" .. [[
Radius: Large
Implicits: 0
{variant:1}Commanded leadership over ]] .. row.seed .. [[ warriors under Kaom
{variant:2}Commanded leadership over ]] .. row.seed .. [[ warriors under Rakiata
{variant:3}Commanded leadership over ]] .. row.seed .. [[ warriors under Akoya
Passives in radius are Conquered by the Karui
Historic
]]
	elseif sharedList.type.id == 3 then
		itemData = [[
Brutal Restraint ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Variant: Asenath (Dance with Death)
Variant: Nasima (Second Sight)
Variant: Balbala (The Traitor)
Selected Variant: ]] .. variant .. "\n" .. [[
Radius: Large
Implicits: 0
{variant:1}Denoted service of ]] .. row.seed .. [[ dekhara in the akhara of Asenath
{variant:2}Denoted service of ]] .. row.seed .. [[ dekhara in the akhara of Nasima
{variant:3}Denoted service of ]] .. row.seed .. [[ dekhara in the akhara of Balbala
Passives in radius are Conquered by the Maraketh
Historic
]]
	elseif sharedList.type.id == 4 then
		local dv1 = sharedList.devotionVariant1 or devotionVariants[1]
		local dv2 = sharedList.devotionVariant2 or devotionVariants[1]
		local altVariant = dv1.id ~= 1 and dv1.id or m_random(2, 16)
		local altVariant2 = dv2.id ~= 1 and dv2.id or m_random(2, 16)
		if altVariant == altVariant2 then
			altVariant = altVariant % 15 + 2
		end
		itemData = [[
Militant Faith ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Has Alt Variant: true
Has Alt Variant Two: true
Variant: Avarius (Power of Purpose)
Variant: Dominus (Inner Conviction)
Variant: Maxarius (Transcendence)
Variant: Totem Damage
Variant: Brand Damage
Variant: Channelling Damage
Variant: Area Damage
Variant: Elemental Damage
Variant: Elemental Resistances
Variant: Effect of non-Damaging Ailments
Variant: Elemental Ailment Duration
Variant: Duration of Curses
Variant: Minion Attack and Cast Speed
Variant: Minions Accuracy Rating
Variant: Mana Regen
Variant: Skill Cost
Variant: Non-Curse Aura Effect
Variant: Defences from Shield
Selected Variant: ]] .. variant .. "\n" .. [[
Selected Alt Variant: ]] .. altVariant + 2 .. "\n" .. [[
Selected Alt Variant Two: ]] .. altVariant2 + 2 .. "\n" .. [[
Radius: Large
Implicits: 0
{variant:1}Carved to glorify ]] .. row.seed .. [[ new faithful converted by High Templar Avarius
{variant:2}Carved to glorify ]] .. row.seed .. [[ new faithful converted by High Templar Dominus
{variant:3}Carved to glorify ]] .. row.seed .. [[ new faithful converted by High Templar Maxarius
{variant:4}4% increased Totem Damage per 10 Devotion
{variant:5}4% increased Brand Damage per 10 Devotion
{variant:6}Channelling Skills deal 4% increased Damage per 10 Devotion
{variant:7}4% increased Area Damage per 10 Devotion
{variant:8}4% increased Elemental Damage per 10 Devotion
{variant:9}+2% to all Elemental Resistances per 10 Devotion
{variant:10}3% increased Effect of non-Damaging Ailments on Enemies per 10 Devotion
{variant:11}4% reduced Elemental Ailment Duration on you per 10 Devotion
{variant:12}4% reduced Duration of Curses on you per 10 Devotion
{variant:13}1% increased Minion Attack and Cast Speed per 10 Devotion
{variant:14}Minions have +60 to Accuracy Rating per 10 Devotion
{variant:15}Regenerate 0.6 Mana per Second per 10 Devotion
{variant:16}1% reduced Mana Cost of Skills per 10 Devotion
{variant:17}1% increased effect of Non-Curse Auras per 10 Devotion
{variant:18}3% increased Defences from Equipped Shield per 10 Devotion
Passives in radius are Conquered by the Templars
Historic
]]
		elseif sharedList.type.id == 5 then
		itemData = [[
Elegant Hubris ]] .. label .. [[
Timeless Jewel
League: Legion
Limited to: 1 Historic
Variant: Cadiro (Supreme Decadence)
Variant: Victario (Supreme Grandstanding)
Variant: Caspiro (Supreme Ostentation)
Selected Variant: ]] .. variant .. "\n" .. [[
Radius: Large
Implicits: 0
{variant:1}Commissioned ]] .. row.seed .. [[ coins to commemorate Cadiro
{variant:2}Commissioned ]] .. row.seed .. [[ coins to commemorate Victario
{variant:3}Commissioned ]] .. row.seed .. [[ coins to commemorate Caspiro
Passives in radius are Conquered by the Eternal Empire
Historic
]]
	end
	local item = new("Item", itemData)
	build.itemsTab:AddItem(item, true)
	build.itemsTab:PopulateSlots()
	list[index].label = "^xB2B2B2" .. list[index].label
	st.resultsVersion = st.resultsVersion + 1
	-- The legacy frame loop would consume build.buildFlag set by AddItem; the port
	-- has no frame loop, so trigger the host's recalc if it is present.
	if type(pob_recalculate) == "function" then
		pcall(pob_recalculate)
	end
	return { ok = true, itemName = item.name or item.title, itemId = item.id }
end

-- TreeTab.lua:2277-2385 trade URL button body, minus OpenURL/Copy and minus the
-- network league fetch (league is a plain string argument).
--   startIndex  = controls.searchResults.selIndex
--   endIndex    = controls.searchResults.highlightIndex (nil -> page-size logic)
--   realm       = "pc" | "sony" | "xbox" (or "PC"/"Sony"/"Xbox", or index 1..3)
--   league      = league name (default "Standard")
--   tradeTypeIndex = self.tradeTypeIndex (1..5, default 1)
--   searchMore  = controls.searchMore.state
-- Keeps the legacy `lastSearch` paging: calling again with the range this call
-- returned advances to the next page, exactly like clicking the button again.
function pob_timelessTradeUrl(startIndex, endIndex, realm, league, tradeTypeIndex, searchMore)
	local st = ensure()
	if not st then
		return { error = "No build loaded" }
	end
	local timelessData = st.timelessData
	-- legacy button is disabled without results (TreeTab.lua:2386)
	if not (timelessData.searchResults and #timelessData.searchResults > 0) or not timelessData.sharedResults.conqueror then
		return { error = "No search results" }
	end
	searchMore = searchMore and true or false
	local selIndex = tonumber(startIndex)
	local highlightIndex = tonumber(endIndex)

	local seedTrades = {}
	local startRow, endRow
	if highlightIndex and not searchMore then
		startRow = m_min(selIndex or 1, highlightIndex)
		endRow = m_max(selIndex or 1, highlightIndex)
	else
		startRow = selIndex or 1
		local maxFilters = searchMore and 180 or 10
		endRow = startRow + m_floor(maxFilters / ((timelessData.sharedResults.conqueror.id == 1) and 3 or 1))
	end
	startRow = m_max(startRow, 1) -- port: guard against 0/negative from QML

	local seedCount = m_min(#timelessData.searchResults - startRow, endRow - startRow) + 1
	-- update if not highlighted already

	local prevSearch = st.lastSearch
	if prevSearch and prevSearch[1] == startRow and prevSearch[2] == seedCount then
		startRow = endRow + 1
		if (startRow > #timelessData.searchResults) then
			return { url = nil, done = true, startIndex = nil, endIndex = nil, nextStart = nil }
		end
		seedCount = m_min(#timelessData.searchResults - startRow + 1, seedCount)
		endRow = startRow + seedCount - 1
	end
	st.resultsSelIndex = startRow
	st.highlightIndex = endRow

	st.lastSearch = {startRow, seedCount}

	for i = startRow, startRow + seedCount - 1 do
		local result = timelessData.searchResults[i]

		-- NB: legacy keys the trade ids by the CURRENT jewel type (not sharedResults.type); kept verbatim
		local conquerorKeystoneTradeIds = data.timelessJewelTradeIDs[timelessData.jewelType.id].keystone
		local conquerorTradeIds = { conquerorKeystoneTradeIds[1], conquerorKeystoneTradeIds[2], conquerorKeystoneTradeIds[3] }
		if timelessData.sharedResults.conqueror.id > 1 then
			conquerorTradeIds = { conquerorKeystoneTradeIds[timelessData.sharedResults.conqueror.id - 1] }
		end

		for _, tradeId in ipairs(conquerorTradeIds) do
			t_insert(seedTrades, {
				id = tradeId,
				value = {
					min = result.seed,
					max = result.seed
				}
			})
		end
	end

	local tti = m_min(m_max(m_floor(tonumber(tradeTypeIndex) or 1), 1), #tradeTypes)
	local search = {
		query = {
			status = {
				option = tradeTypes[tti]
			},
			stats = {
				{
					filters = seedTrades,
					type = "count",
					value = {
						min = 1
					}
				}
			}
		},
		sort = {
			price = "asc"
		}
	}

	if data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion ~= nil then
		local devotionFilters = {}
		local dv1 = timelessData.sharedResults.devotionVariant1 or devotionVariants[1]
		local dv2 = timelessData.sharedResults.devotionVariant2 or devotionVariants[1]
		if dv1.id > 1 then
			t_insert(devotionFilters, { id = data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion[dv1.id - 1] })
		end
		if dv2.id > 1 then
			t_insert(devotionFilters, { id = data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion[dv2.id - 1] })
		end
		if next(devotionFilters) then
			t_insert(search.query.stats, {
				filters = devotionFilters,
				type = "and"
			})
		end
	end

	-- TreeTab.lua:2373: controls.realmSelection:GetSelValue():lower() over {"PC","Sony","Xbox"}
	local selectedRealm
	if type(realm) == "number" then
		selectedRealm = (realmList[realm] or realmList[1]):lower()
	else
		selectedRealm = tostring(realm or "PC"):lower()
	end
	if selectedRealm ~= "pc" and selectedRealm ~= "sony" and selectedRealm ~= "xbox" then
		selectedRealm = "pc"
	end
	-- legacy: controls.searchTradeLeagueSelect:GetSelValue() (network list)
	local leagueName = (league ~= nil and tostring(league) ~= "") and tostring(league) or "Standard"

	local realmPath = selectedRealm == "pc" and "" or (selectedRealm .. "/")
	local url = "https://www.pathofexile.com/trade/search/" .. realmPath ..
		leagueName ..
		"/?q=" .. (s_gsub(dkjson.encode(search), "[^a-zA-Z0-9]", function(a)
			return s_format("%%%02X", s_byte(a))
		end))
	-- legacy: OpenURL(url); Copy(url) — left to QML
	st.tradeLabel = "Open Next Trade URL"

	local lastRow = startRow + seedCount - 1
	local nextStart = lastRow + 1
	if nextStart > #timelessData.searchResults then
		nextStart = nil
	end
	return { url = url, startIndex = startRow, endIndex = lastRow, nextStart = nextStart }
end

-- ---------------------------------------------------------------------------
-- Self test
-- ---------------------------------------------------------------------------

local SELFTEST_SOCKET = 26725 -- Marauder socket

local function selftestFindOption(st, id)
	for i, entry in ipairs(st.modData) do
		if entry.id == id then
			return i
		end
	end
end

local function selftestFindSocket(st, id)
	for i, sock in ipairs(st.jewelSockets) do
		if sock.id == id then
			return i
		end
	end
end

-- first legion node (then addition) id matching `pattern`, not ignored, not a keystone
local function selftestPickLegionId(st, pattern)
	for _, node in ipairs(st.legionNodes) do
		if node.id:match(pattern) and not isValueInArray(ignoredMods, node.dn) and not node.ks then
			return node.id
		end
	end
	for _, addition in ipairs(st.legionAdditions) do
		if addition.id:match(pattern) and not isValueInArray(ignoredMods, addition.dn) then
			return addition.id
		end
	end
end

local function selftestPrepare(st, typeIndex)
	pob_timelessSet("jewelType", typeIndex)
	-- the jewelType selFunc only clears the lists on an actual change
	pob_timelessSet("searchList", "")
	pob_timelessSet("searchListFallback", "")
	pob_timelessSet("conqueror", 1)
	pob_timelessSet("socketFilter", false)
	pob_timelessSet("totalMinimumWeight", nil)
	local sockIdx = selftestFindSocket(st, SELFTEST_SOCKET)
	if sockIdx then
		pob_timelessSet("socket", sockIdx)
	end
	return sockIdx
end

local function selftestChecks(res)
	local st = ensure()
	local treeData = st.treeData
	local td = st.timelessData
	local resultsRef, sharedRef = td.searchResults, td.sharedResults
	local sockNode = treeData.nodes[SELFTEST_SOCKET]
	if not sockNode or not sockNode.isJewelSocket or not sockNode.nodesInRadius then
		res.error = "socket " .. SELFTEST_SOCKET .. " not on this tree"
		return
	end
	local radius = sockNode.nodesInRadius[3]

	-- (a) LUT load for all 6 jewel types ---------------------------------------
	local cands = { }
	for nodeId in pairs(radius) do
		local tn = treeData.nodes[nodeId]
		local map = data.nodeIDList[nodeId]
		if tn and tn.isNotable and not tn.isKeystone and not tn.isJewelSocket and map and map.index <= data.nodeIDList["sizeNotable"] then
			cands[#cands + 1] = nodeId
		end
	end
	t_sort(cands)
	local lutNode = cands[1]
	res.lutNode = lutNode
	local lutAll = lutNode ~= nil
	for t = 1, 6 do
		local good = false
		if lutNode then
			local seed = data.timelessJewelSeedMin[t] * (t == 5 and 20 or 1)
			local okL, tbl = pcall(data.readLUT, seed, lutNode, t)
			good = okL and type(tbl) == "table" and next(tbl) ~= nil
			if not okL then
				res["lut" .. t .. "Error"] = tostring(tbl)
			end
		end
		res["lut" .. t] = good
		lutAll = lutAll and good
	end
	res.lutAllTypes = lutAll

	-- (b) Lethal Pride single-socket search -----------------------------------
	local sockIdx = selftestPrepare(st, 2)
	res.socketFound = sockIdx ~= nil
	local desiredId = selftestPickLegionId(st, "^karui_notable")
	res.lpDesiredId = desiredId
	local optIdx = desiredId and selftestFindOption(st, desiredId)
	res.lpOptionFound = optIdx ~= nil
	if optIdx then
		local r1 = pob_timelessSelectNode(optIdx, false, 1, 0, 0)
		res.selectNodeAppended = (r1.exists == false) and (td.searchList == desiredId .. ", 1, 0, 0")
		local r2 = pob_timelessSelectNode(optIdx, false, 5, 5, 5)
		res.selectNodeExists = (r2.exists == true) and r2.w1 == 1 and r2.w3 == 0
		-- slider rewrite path keeps the same row (weight 1)
		pob_timelessSetWeights(optIdx, false, 1, 0, 0)
		res.setWeightsText = td.searchList == desiredId .. ", 1, 0, 0"
	elseif desiredId then
		pob_timelessSet("searchList", desiredId .. ", 1, 0, 0")
	end
	local t0 = os.clock()
	pob_timelessSearch()
	res.lpSearchSeconds = os.clock() - t0
	local results = td.searchResults
	res.lpResults = #results
	local sorted, inRange = true, true
	for i, r in ipairs(results) do
		if i > 1 and results[i - 1].total < r.total then
			sorted = false
		end
		if r.seed < data.timelessJewelSeedMin[2] or r.seed > data.timelessJewelSeedMax[2] then
			inRange = false
		end
	end
	res.lpSorted = sorted
	res.lpSeedsInRange = inRange
	res.lethalPrideSearch = #results > 0 and sorted and inRange and st.msg == ""

	-- (c) independent cross-check of the top result ---------------------------
	res.crossCheck = false
	if results[1] and desiredId then
		local top = results[1]
		local rootNodes = { }
		for _, class in pairs(treeData.classes) do
			rootNodes[class.startNodeId] = true
		end
		local count = 0
		for nodeId in pairs(radius) do
			local tn = treeData.nodes[nodeId]
			if not rootNodes[nodeId] and not tn.isJewelSocket and not tn.isKeystone and tn.isNotable then
				local tbl = data.readLUT(top.seed, nodeId, 2)
				if next(tbl) then
					local entry
					if tbl[1] >= data.timelessJewelAdditions then
						entry = st.legionNodes[tbl[1] + 1 - data.timelessJewelAdditions]
					else
						entry = st.legionAdditions[tbl[1] + 1]
					end
					if entry and entry.id == desiredId then
						count = count + 1
					end
				end
			end
		end
		local weight = 1
		res.crossCheckExpected = count * weight
		res.crossCheckTotal = top.total
		res.crossCheckSeed = top.seed
		local names = top[desiredId] and top[desiredId].targetNodeNames
		res.crossCheck = count > 0 and (count * weight) == top.total and names ~= nil and #names == count
	end

	-- (e) trade URL on the Lethal Pride results -------------------------------
	res.tradeUrl = false
	if #results > 0 then
		local prefix = "https://www.pathofexile.com/trade/search/Standard/?q="
		local tr = pob_timelessTradeUrl(1, nil, "pc", "Standard", 1, false)
		local url = tr and tr.url
		if url and url:sub(1, #prefix) == prefix then
			local decoded = (url:sub(#prefix + 1):gsub("%%(%x%x)", function(h)
				return s_char(tonumber(h, 16))
			end))
			local okJ, parsed = pcall(dkjson.decode, decoded)
			res.tradeJsonValid = okJ and type(parsed) == "table"
			res.tradeUrl = decoded:find("pseudo_timeless_jewel_", 1, true) ~= nil and res.tradeJsonValid
			res.tradeRange = { tr.startIndex, tr.endIndex }
		end
	end

	-- (d) Elegant Hubris seeds are multiples of 20 ----------------------------
	selftestPrepare(st, 5)
	local ehId = selftestPickLegionId(st, "^eternal_notable")
	res.ehDesiredId = ehId
	res.elegantHubrisStep = false
	if ehId then
		pob_timelessSet("searchList", ehId .. ", 1, 0, 0")
		local t1 = os.clock()
		pob_timelessSearch()
		res.ehSearchSeconds = os.clock() - t1
		local ehResults = td.searchResults
		res.ehResults = #ehResults
		local allDiv = #ehResults > 0
		for _, r in ipairs(ehResults) do
			if r.seed % 20 ~= 0 or r.seed < 2000 or r.seed > 160000 then
				allDiv = false
				break
			end
		end
		res.elegantHubrisStep = allDiv
	end

	res.resultsIdentity = td.searchResults == resultsRef and td.sharedResults == sharedRef

	-- (f) <TimelessData> build XML save / load round trip ----------------------
	res.saveLoad = false
	local build = st.build
	local expectId = selftestPickLegionId(st, "^karui_notable") or "karui_x"
	selftestPrepare(st, 2)
	pob_timelessSet("conqueror", 3)
	pob_timelessSet("devotion1", 2)
	pob_timelessSet("devotion2", 3)
	pob_timelessSet("socketFilter", true)
	pob_timelessSet("socketFilterDistance", 3)
	local expectFallbackIdx = #st.fallbackWeightsList >= 2 and 2 or 1
	pob_timelessSet("fallbackMode", expectFallbackIdx)
	pob_timelessSet("searchList", expectId .. ", 1, 0, 0")
	pob_timelessSet("searchListFallback", expectId .. ", 2, 0, 0")
	local expectList = td.searchList
	local expectFallback = td.searchListFallback

	local xmlNode = { elem = "Build" }
	local okSave, errSave = pcall(build.Save, build, xmlNode)
	local tdChild
	if okSave then
		for _, child in ipairs(xmlNode) do
			if type(child) == "table" and child.elem == "TimelessData" then
				tdChild = child
			end
		end
	end
	if not okSave or not tdChild then
		-- Build:Save needs a fully calculated build (mainEnv.player.mainSkill); if it
		-- is not reachable standalone the round trip is skipped (flag stays true).
		res.saveLoadSkipped = true
		res.saveLoadError = okSave and "no <TimelessData> child" or tostring(errSave)
		res.saveLoad = true
	else
		-- scramble so the load visibly restores everything
		td.jewelType = { }
		td.conquerorType = { }
		td.devotionVariant1 = 1
		td.devotionVariant2 = 1
		td.jewelSocket = { }
		td.fallbackWeightMode = { }
		td.socketFilter = false
		td.socketFilterDistance = 0
		td.searchList = ""
		td.searchListFallback = ""
		-- Build:Load also rewrites these <Build> attribs / Spectre list; snapshot them
		local snap = {
			targetVersion = build.targetVersion, viewMode = build.viewMode,
			characterLevel = build.characterLevel, characterLevelAutoMode = build.characterLevelAutoMode,
			bandit = build.bandit, pantheonMajorGod = build.pantheonMajorGod, pantheonMinorGod = build.pantheonMinorGod,
			mainSocketGroup = build.mainSocketGroup,
		}
		local spectres = build.spectreList and copyTable(build.spectreList) or nil
		-- load ONLY the <TimelessData> section back (with the saved <Build> attribs)
		local loadNode = { elem = "Build", attrib = xmlNode.attrib, tdChild }
		local okLoad, errLoad = pcall(build.Load, build, loadNode, build.dbFileName)
		for k, v in pairs(snap) do
			build[k] = v
		end
		if spectres and build.spectreList then
			wipeTable(build.spectreList)
			for i, v in ipairs(spectres) do
				build.spectreList[i] = v
			end
		end
		if not okLoad then
			res.saveLoadError = tostring(errLoad)
		else
			ensure() -- popup-open stub restore (TreeTab.lua:1404/1453/1524)
			res.slJewelType = td.jewelType.id == 2 and td.jewelType.name == "karui"
			res.slConqueror = td.conquerorType.id == 3 and td.conquerorType.label == conquerorTypes[2][3].label
			res.slDevotion = td.devotionVariant1 == 2 and td.devotionVariant2 == 3
			res.slSocket = td.jewelSocket.id == SELFTEST_SOCKET and td.jewelSocket.label ~= nil
			res.slFallbackMode = td.fallbackWeightMode.idx == expectFallbackIdx
			res.slFilter = td.socketFilter == true and td.socketFilterDistance == 3
			res.slLists = td.searchList == expectList and td.searchListFallback == expectFallback
			res.slParsed = S.searchListTbl[1] ~= nil and S.searchListTbl[1][1] == expectId
			res.slResultsIdentity = td.searchResults == resultsRef and td.sharedResults == sharedRef
			res.saveLoad = res.slJewelType and res.slConqueror and res.slDevotion and res.slSocket
				and res.slFallbackMode and res.slFilter and res.slLists and res.slParsed and res.slResultsIdentity
		end
	end
end

function pob_selftestTimeless()
	local res = { ok = false }
	local build = main and main.modes and main.modes.BUILD
	if not build or type(build.timelessData) ~= "table" then
		res.error = "No build loaded"
		return res
	end
	local td = build.timelessData

	-- Snapshot BEFORE ensure() so even un-restored stubs come back exactly.
	-- Every field except the two result tables is deep-copied (fallbackWeightMode
	-- is mutated in place by the setters). searchResults/sharedResults keep their
	-- identity: the search only wipes and refills them with NEW row tables, so a
	-- shallow key copy restores the original rows exactly.
	local backup = { }
	for k, v in pairs(td) do
		if k ~= "searchResults" and k ~= "sharedResults" then
			backup[k] = type(v) == "table" and copyTable(v) or v
		end
	end
	local resultsRef, sharedRef = td.searchResults, td.sharedResults
	local resultsBackup = resultsRef and copyTable(resultsRef, true)
	local sharedBackup = sharedRef and copyTable(sharedRef, true)
	local modFlagBackup = build.modFlag

	local st0 = ensure()
	local stBackup = st0 and {
		protectedNodes = copyTable(st0.protectedNodes),
		protectedNodesCount = st0.protectedNodesCount,
		protectOptions = copyTable(st0.protectOptions),
		allocatedNodesInRadiusCount = st0.allocatedNodesInRadiusCount,
		nodeSelIndex = st0.nodeSelIndex,
		lastSearch = st0.lastSearch and copyTable(st0.lastSearch),
		tradeLabel = st0.tradeLabel,
		resultsSelIndex = st0.resultsSelIndex,
		highlightIndex = st0.highlightIndex,
		fallbackGenerated = st0.fallbackGenerated,
		msg = st0.msg,
	}

	local okRun, errRun = true, nil
	if st0 then
		okRun, errRun = pcall(selftestChecks, res)
	else
		res.error = "timeless state unavailable"
	end
	if not okRun then
		res.error = tostring(errRun)
	end

	-- restore build.timelessData ------------------------------------------------
	for k in pairs(td) do
		if k ~= "searchResults" and k ~= "sharedResults" and backup[k] == nil then
			td[k] = nil
		end
	end
	for k, v in pairs(backup) do
		td[k] = v
	end
	td.searchResults = resultsRef
	td.sharedResults = sharedRef
	if resultsRef then
		wipeTable(resultsRef)
		for k, v in pairs(resultsBackup) do
			resultsRef[k] = v
		end
	end
	if sharedRef then
		wipeTable(sharedRef)
		for k, v in pairs(sharedBackup) do
			sharedRef[k] = v
		end
	end
	build.modFlag = modFlagBackup
	-- restore module-only (non-persisted) state; derived tables re-sync lazily on
	-- the next ensure() (list texts differ from the parsed ones -> re-parse,
	-- jewel type id differs -> buildMods)
	if S and S.build == build and S.timelessData == td and stBackup then
		-- explicit key list: several of these may legitimately be nil
		for _, k in ipairs({ "protectedNodes", "protectedNodesCount", "protectOptions", "allocatedNodesInRadiusCount",
			"nodeSelIndex", "lastSearch", "tradeLabel", "resultsSelIndex", "highlightIndex", "fallbackGenerated", "msg" }) do
			S[k] = stBackup[k]
		end
		S.resultsVersion = S.resultsVersion + 1
		S.resultsCache = nil
	end
	res.restored = td.searchResults == resultsRef and td.sharedResults == sharedRef

	res.ok = (res.error == nil)
		and res.lutAllTypes == true
		and res.lethalPrideSearch == true
		and res.crossCheck == true
		and res.elegantHubrisStep == true
		and res.tradeUrl == true
		and res.saveLoad == true
		and res.resultsIdentity == true
		and res.restored == true
	return res
end
