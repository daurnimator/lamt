-- "APEv1 and APEv2 tag reader/writer"
-- Specifications:
 -- http://wiki.hydrogenaudio.org/index.php?title=APEv2
 -- http://wiki.hydrogenaudio.org/index.php?title=APEv2_specification
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Tags_Header
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Tag_Item
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_key
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Item_Value
 -- http://wiki.hydrogenaudio.org/index.php?title=Ape_Tags_Flags

local assert , error = assert , error
local pairs = pairs
local strgmatch , strrep = string.gmatch , string.rep
local tblinsert , tblconcat = table.insert , table.concat

local misc = require "misc"
local get_from_fd = misc.get_from_fd
local read_terminated_string = misc.read_terminated_string

local ll = require "ll"
local le_uint_to_num = ll.le_uint_to_num
local num_to_le_uint = ll.num_to_le_uint
local extract_bits =   ll.extract_bits
local le_bpeek =       ll.le_bpeek


local function read_header_footer ( get )
	local h = { }
	if get ( 8 ) == "APETAGEX" then
		h.version = le_uint_to_num ( get ( 4 ) )
		h.size = le_uint_to_num ( get ( 4 ) )
		h.items = le_uint_to_num ( get ( 4 ) )

		local flags = get ( 4 )
		if h.version >= 2000 then
			h.hasheader = le_bpeek ( flags , 31 )
			h.hasfooter = not le_bpeek ( flags , 30 )
			h.isheader = le_bpeek ( flags , 29 )
		else -- Version 1
			h.hasheader = false
			h.hasfooter = true
			h.isheader = false
		end

		assert ( get ( 8 ) == "\0\0\0\0\0\0\0\0" )
		return h
	else
		return false
	end
end

local function find ( fd )
	local get = get_from_fd ( fd )

	-- Look at start of file
	assert ( fd:seek ( "set" ) )
	local h = read_header_footer ( get )
	if h then
		return 32 , h
	end

	-- Look at end of file
	local pos = assert ( fd:seek ( "end" , -32 ) )
	local h = read_header_footer ( get )
	if h then
		return pos + 32 - h.size , h
	end

	-- No tag
	return false , "Unable to find APE tag"
end

local contenttypes = {
	[ 0 ] = "text" ,
	[ 1 ] = "binary" ,
	[ 2 ] = "link" ,
}

local function read_item ( get , header )
	local length = le_uint_to_num ( get ( 4 ) )
	local flags = get ( 4 )
	local contenttype = contenttypes [ extract_bits ( flags , 1 , 2 ) ] -- Ends up as text in version 1 as flags are all 0s anyway
	local readonly = le_bpeek ( flags , 0 )

	local key = read_terminated_string ( get )

	local values = { }
	for v in strgmatch ( get ( length ) , "%Z+" ) do
		-- TODO: Switch on contenttype
		tblinsert ( values , v )
	end

	return key , values
end

-- Get should be at start of items (not a header/footer)
local function read ( get , header , tags , extra )
	tags = tags or { }
	extra = extra or { }

	extra.apeversion = header.version

	for i = 1 , header.items do
		local key , values = read_item ( get , header )
		-- TODO: interpret values
		tags [ key ] = values
	end

	return tags , extra
end


local function make_text_item ( key , values )
	local v = tblconcat ( values , "\0" ) -- Last value doesn't need to be followed by null byte
	return num_to_le_uint ( #v , 4 ) .. "\0\0\0\0" .. key .. "\0" .. v
end

local function make_tag ( items , doheader , dofooter , minlength )
	local n_items = #items
	items = tblconcat ( items )

	local taglength = ( doheader and 32 or 0 ) + #items + ( dofooter and 32 or 0 )

	if minlength and taglength < minlength then -- Need to truncate
		-- We don't have ftruncate; so (bad behaviour!) add some padding after last ape item
		items = items .. strrep ( "\0" , minlength - taglength )
	end

	local res = items

	-- Create header/footer
	local common = "APETAGEX" .. num_to_le_uint ( 2000 , 4 ) .. num_to_le_uint ( #items + ( doheader and 32 or 0 ) , 4 ) .. num_to_le_uint ( n_items , 4 )
	local flags = ( doheader and 2^31 or 0 ) + ( dofooter and 0 or 2^30 )
	local reserved = "\0\0\0\0\0\0\0\0"

	if doheader then
		res = common .. num_to_le_uint ( flags + 2^29 , 4 ) .. reserved .. res
	end
	if dofooter then
		res = res .. common .. num_to_le_uint ( flags , 4 ) .. reserved
	end

	return res
end

local function edit ( fd , tags , extra )
	local items = { }
	for key , values in pairs ( tags ) do
		tblinsert ( items , make_text_item ( key , values ) )
	end

	local tag
	local pos , oldheader = find ( fd )
	if not pos then -- Doesn't current have an ape tag
		-- Put tag at end of file
		tag = make_tag ( items , false , true )
		assert ( fd:seek ( "end" ) )
	elseif pos == 32 then -- Old tag was at start of file
		local hasroom = 32 + oldheader.size + ( oldheader.hasfooter and 32 or 0 )
		tag = make_tag ( items , true , oldheader.hasfooter , hasroom )
		if #tag > hasroom then -- Gotta shift file down
			local shiftby = #tag - hasroom
			file_insert ( fd , strrep ( "\0" , shiftby ) )
		end
		assert ( fd:seek ( "set" ) )
	elseif pos > 32 then -- Old tag was at end of file
		local fileend = assert ( fd:seek ( "end" ) )
		if oldheader.hasheader then pos = pos - 32 end

		tag = make_tag ( items , oldheader.hasheader , true , fileend - pos )
		assert ( fd:seek ( "set" , pos ) )
	elseif pos < 32 then
		error ( )
	end

	fd:write ( tag )
	fd:flush ( )
end

return {
	find = find ;
	read = read ;
	edit = edit ;
}
