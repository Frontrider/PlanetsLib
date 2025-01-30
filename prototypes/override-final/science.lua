local lib = require("lib.lib")
local tech = require("lib.technology")

local function science_sorted_by_order_or_name(table)
	table = util.table.deepcopy(table)

	lib.sort(table, function(left, right)
		if not (data.raw["tool"] and data.raw["tool"][left] and data.raw["tool"][right]) then
			return true
		end

		local left_order = data.raw["tool"][left].order
		local right_order = data.raw["tool"][right].order

		if left_order == nil then
			left_order = data.raw["tool"][left].name
		end
		if right_order == nil then
			right_order = data.raw["tool"][right].name
		end

		return left_order < right_order
	end)
	return table
end

-- fix ordering of science packs in the vanilla lab to match the pack's order string.
local lab = data.raw["lab"]["lab"]
local base_inputs = science_sorted_by_order_or_name(lab.inputs)
lab.inputs = base_inputs

-- the biolab should have all of these by default
data.raw["lab"]["biolab"].include_all_lab_science = true

for _, new_lab in pairs(data.raw["lab"]) do
	if new_lab["include_all_lab_science"] == true then
		for _, input in pairs(base_inputs) do
			if not lib.contains(new_lab.inputs, input) then
				table.insert(new_lab.inputs, input)
			end
		end
		new_lab.inputs = science_sorted_by_order_or_name(new_lab.inputs)
	elseif new_lab["sort_sciences"] == true then
		local local_inputs = new_lab.inputs
		new_lab.inputs = science_sorted_by_order_or_name(local_inputs)
	end
end

-- fix up selected sciences that are coming after promethium science.
-- We DO NOT check if the technology is actually coming after promethium science, because there may be some nesting!
local all_tech = data.raw["technology"]

--promethium is automatically set as an endgame technology, so it will always have all science packs.
data.raw["technology"]["promethium-science-pack"]["as_endgame_technology"] = true

for key, value in pairs(all_tech) do
	if value["as_endgame_technology"] == true then
		tech.set_science_packs_from_lab(value,lab)
	end
end