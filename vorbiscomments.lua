-- Vorbis_Comment
-- http://www.xiph.org/vorbis/doc/v-comment.html
-- https://wiki.xiph.org/VorbisComment

local error = error
local ipairs , pairs , rawset = ipairs , pairs , rawset
local setmetatable = setmetatable
local tblconcat , tblinsert = table.concat , table.insert
local strmatch , strgsub = string.match , string.gsub

local ll = require"ll"
local le_uint_to_num = ll.le_uint_to_num
local num_to_le_uint = ll.num_to_le_uint

local function read ( get , tags , extra )
	tags = tags or { }
	extra = extra or { }

	extra.vendor_string = get ( le_uint_to_num ( get(4) ) )

	for i = 1 , le_uint_to_num ( get(4) ) do -- 4 byte unsigned integer indicating how many comments.
		local line = get ( le_uint_to_num ( get(4) ) )
		local fieldname , value = strmatch ( line , "([^=]+)=(.*)" )
		fieldname = fieldname:lower ( )

		tags [ fieldname ] = tags [ fieldname ] or { }
		tblinsert ( tags [ fieldname ] , value )
	end

	return tags , extra
end

local function generate ( edits , extra , exact )
	vendor_string = ( extra and extra.vendor_string ) or "lamt vorbiscomment" --"Xiph.Org libVorbis I 20020717"

	local tbl = { }
	for k , v in pairs ( edits ) do
		local k_clean = strgsub ( k , "[=%z\1-\31\127-\255]" , "" )
		k_clean = k_clean:lower ( )

		if k_clean ~= k and exact then
			error ( "Invalid field name" , 2 )
		end

		for i , v in ipairs ( v ) do
			local vector = k_clean .. "=" .. tostring ( v )
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
