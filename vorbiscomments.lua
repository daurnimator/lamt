-- Vorbis_Comment http://www.xiph.org/vorbis/doc/v-comment.html

local error = error
local ipairs , pairs , rawset = ipairs , pairs , rawset
local setmetatable = setmetatable
local tblconcat , tblinsert = table.concat , table.insert
local strmatch , strgsub = string.match , string.gsub

local ll = require"ll"
local le_uint_to_num = ll.le_uint_to_num
local num_to_le_uint = ll.num_to_le_uint

local function read ( get , item )
	item.extra = item.extra or { }
	item.tags = item.tags or { }

	item.extra.vendor_string = get ( le_uint_to_num ( get(4) ) )

	for i = 1 , le_uint_to_num ( get(4) ) do -- 4 byte unsigned integer indicating how many comments.
		local line = get ( le_uint_to_num ( get(4) ) )
		local fieldname , value = strmatch ( line , "([^=]+)=(.*)" )
		fieldname = fieldname:lower ( )
		item.tags [ fieldname ] = item.tags [ fieldname ] or { }
		item.tags [ fieldname ] [ #item.tags [ fieldname ] + 1 ] = value
	end
end

local function generate ( edits , item , inherit , exact )
	local vendor_string = "lamt vorbiscomment" --"Xiph.Org libVorbis I 20020717"
	if item then
		vendor_string = item.extra.vendor_string
	end

	local comments = setmetatable ( { } , {
			__newindex = function ( t , k , v )
				-- k_clean is "A case-insensitive field name that may consist of ASCII 0x20 through 0x7D, 0x3D ('=') excluded."
				local k_clean = strgsub ( k , "[=%z\1-\31\127-\255]" , "" )
				k_clean = k_clean:lower ( )

				if k_clean ~= k and exact then
					error ( "Invalid field name" , 2 )
				end

				return rawset ( t , k_clean , v )
			end ;
		} )

	-- Merge edits:
	if inherit and item.tags then
		for k , v in pairs ( item.tags ) do
			for i , vv in ipairs ( v ) do -- Copy the table
				tblinsert ( comments [ k ] , vv )
			end
		end
	end

	for k , v in pairs ( edits ) do -- edits overwrite any old tags with the given key...
		comments [ k ] = v
	end

	local tbl = { }
	for k , v in pairs ( comments ) do
		for i , v in ipairs ( v ) do
			local vector = k .. "=" .. v
			tblinsert ( tbl , num_to_le_uint ( #vector ) .. vector )
		end
	end

	return num_to_le_uint ( #vendor_string ) .. vendor_string
			.. num_to_le_uint ( #tbl ) .. tblconcat ( tbl )
end

return {
	read = read ;
	generate = generate ;
}
