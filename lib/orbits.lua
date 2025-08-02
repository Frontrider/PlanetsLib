local Public = {}

function Public.get_rectangular_position_from_polar(distance, orientation)
	if distance == 0 then
		return 0, 0
	else
		return distance * math.sin(orientation * 2 * math.pi), -distance * math.cos(orientation * 2 * math.pi)
	end
end

function Public.get_polar_position_from_rectangular(x, y)
	local distance = math.sqrt(x * x + y * y)
	local orientation = (0.25 + math.atan2(y, x) / (2 * math.pi)) % 1

	return distance, orientation
end

function Public.get_absolute_polar_position_from_orbit(orbit)
	local parent = orbit.parent

	assert(
		parent.type == "planet" or parent.type == "space-location",
		"Parent types other than planet or space-location are not yet supported"
	)

	if parent.name == "star" then
		return orbit.distance, orbit.orientation
	end

	local parent_data = data.raw[parent.type][parent.name]

	assert(parent_data, string.format("%s with name '%s' not found", parent.type, parent.name))

	local parent_distance = parent_data.distance
	local parent_orientation = parent_data.orientation

	if parent_data.orbit then -- Overwrite distance and orientation
		parent_distance, parent_orientation = Public.get_absolute_polar_position_from_orbit(parent_data.orbit)
	end

	local parent_angle = parent_orientation * 2 * math.pi
	local orbit_angle = orbit.orientation * 2 * math.pi -- Note that this isn't rotated by the parent's orientation.

	local px = parent_distance * math.cos(parent_angle)
	local py = parent_distance * math.sin(parent_angle)

	local ox = orbit.distance * math.cos(orbit_angle)
	local oy = orbit.distance * math.sin(orbit_angle)

	local x = px + ox
	local y = py + oy

	local distance = math.sqrt(x * x + y * y)
	local orientation = math.atan2(y, x) / (2 * math.pi)

	if orientation < 0 then
		orientation = orientation + 1
	end
	if orientation > 1 then
		orientation = orientation - 1
	end

	return distance, orientation
end

function Public.locations_ordered_by_orbits(locations)
	local ordered_locations = {}

	local visited = {}
	local temporary_marks = {}

	local function visit(location, ordered)
		if temporary_marks[location.name] then
			if not (location.orbit and location.orbit.parent and location.orbit.parent.name == location.name) then -- Self-parents are acceptable. Presumably this is only the case for data.raw["space-location"]["star"].
				error("Circular orbit dependency detected at " .. location.name)
			end
		end
		if not visited[location.name] then
			temporary_marks[location.name] = true

			if location.orbit and location.orbit.parent then
				local parent_type = location.orbit.parent.type
				local parent_name = location.orbit.parent.name

				if parent_name ~= location.name then
					local parent = data.raw[parent_type][parent_name]
					if parent then
						visit(parent, ordered)
					end
				end
			end

			temporary_marks[location.name] = false
			visited[location.name] = true
			table.insert(ordered, location)
		end
	end

	for _, location in pairs(locations) do
		if not visited[location.name] then
			visit(location, ordered_locations)
		end
	end

	return ordered_locations
end

function Public.is_parent(parent_prototype, child_prototype)
	Public.ensure_all_locations_have_orbits()

	if not (parent_prototype and parent_prototype.type and parent_prototype.name) then
		error("PlanetsLib.orbits.is_parent: invalid parent_prototype supplied")
	end
	if not (child_prototype and child_prototype.type and child_prototype.name) then
		error("PlanetsLib.orbits.is_parent: invalid child_prototype supplied")
	end

	if parent_prototype.type == child_prototype.type and parent_prototype.name == child_prototype.name then
		return false
	end

	local visited = {}
	local current = child_prototype

	while current do
		local orbit = current.orbit
		if not (orbit and orbit.parent) then
			return parent_prototype.type == "space-location" and parent_prototype.name == "star"
		end

		local parent = orbit.parent

		if parent.type == parent_prototype.type and parent.name == parent_prototype.name then
			return true
		end

		-- Prevent infinite loops
		local key = (parent.type or "") .. "|||||" .. (parent.name or "")
		if visited[key] then
			return false -- Circular dependency detected; bail out.
		end
		visited[key] = true

		local parent_data = data.raw[parent.type] and data.raw[parent.type][parent.name]
		if not parent_data then
			return false -- Broken reference – treat as no parent.
		end

		current = parent_data
	end

	return false
end

function Public.update_positions_of_all_children_via_orbits(parent_prototype)
	Public.ensure_all_locations_have_orbits()

	assert(
		parent_prototype.type == "planet" or parent_prototype.type == "space-location",
		"[PlanetsLib.orbits.update_positions_of_all_children_via_orbits] Parent types other than planet or space-location are not yet supported"
	)

	local parent_x, parent_y =
		Public.get_rectangular_position_from_polar(parent_prototype.distance, parent_prototype.orientation)

	local parent_orbital_x, parent_orbital_y = Public.get_rectangular_position_from_polar(
		Public.get_absolute_polar_position_from_orbit(parent_prototype.orbit)
	)

	local locations = {}

	for _, type in pairs({ "space-location", "planet" }) do
		for _, location in pairs(data.raw[type]) do
			locations[#locations + 1] = location
		end
	end

	local ordered_locations = Public.locations_ordered_by_orbits(locations)

	for _, location in pairs(ordered_locations) do
		if Public.is_parent(parent_prototype, location) then
			local child_x, child_y = Public.get_rectangular_position_from_polar(location.distance, location.orientation)

			local child_orbital_x, child_orbital_y = Public.get_rectangular_position_from_polar(
				Public.get_absolute_polar_position_from_orbit(location.orbit)
			)

			local orbital_delta_x, orbital_delta_y =
				child_orbital_x - parent_orbital_x, child_orbital_y - parent_orbital_y

			local child_new_x, child_new_y = parent_x + orbital_delta_x, parent_y + orbital_delta_y

			local child_new_distance, child_new_orientation =
				Public.get_polar_position_from_rectangular(child_new_x, child_new_y)

			if child_x ~= child_new_x or child_y ~= child_new_y then
				log(
					"PlanetsLib: updating "
						.. location.name
						.. " from x="
						.. child_x
						.. ", y="
						.. child_y
						.. " to x="
						.. child_new_x
						.. ", y="
						.. child_new_y
				)

				location.distance = child_new_distance
				location.orientation = child_new_orientation
			end
		end
	end
end

function Public.ensure_all_locations_have_orbits()
	for _, type in pairs({ "space-location", "planet" }) do
		for _, location in pairs(data.raw[type]) do
			if
				not (
					location.orbit
					and location.orbit.parent
					and location.orbit.distance
					and (location.orbit.orientation or location.orbit.distance == 0)
				)
			then
				location.orbit = {
					parent = {
						type = "space-location",
						name = "star",
					},
					distance = location.distance,
					orientation = location.orientation,
				}
			end
		end
	end
end

return Public
