-- FLAC reader

local strsub , strrep = string.sub , string.rep
local tblinsert = table.insert

local misc = require "misc"
local get_from_string = misc.get_from_string

local vorbiscomments = require "vorbiscomments"

local ll = require "ll"
local num_to_be_uint = ll.num_to_be_uint
local be_uint_to_num = ll.be_uint_to_num
local extract_bits = ll.extract_bits
local bpeek = ll.bpeek

local function find ( fd )
	fd:seek ( "set" )
	if fd:read ( 4 ) == "fLaC" then
		return 0
	end
	return false
end

local blockreaders = {
	[ 0 ] = function ( s , tags , extra ) -- STREAMINFO
		extra.minblocksize = be_uint_to_num ( s , 1 , 2 )
		extra.maxblocksize = be_uint_to_num ( s , 3 , 4 )
		extra.minframesize = be_uint_to_num ( s , 5 , 7 )
		extra.maxframesize = be_uint_to_num ( s , 8 , 10 )

		extra.sample_rate = extract_bits ( s , 80 , 99 )
		extra.channels = extract_bits ( s , 100 , 102 ) + 1
		extra.bits_per_sample = extract_bits ( s , 103 , 107 ) + 1
		extra.totalframes = extract_bits ( s , 108 , 143 )

		extra.md5 = strsub ( s , 19 , 34 )
	end ;
	[ 1 ] = function ( s , tags , extra ) -- PADDING
		extra.padding = ( extra.padding or 0 ) + #s
	end ;
	[ 2 ] = function ( s , tags , extra ) -- APPLICATION
		extra.applications = extra.applications or { }
		tblinsert ( extra.applications , { appID = be_uint_to_num ( s , 1 , 4 ) ; data = strsub ( s , 5 , -1 ) } )
	end ,
	--[[[ 3 ] = function ( fd , length , item ) -- SEEKTABLE (we can't do anything with this)
	end ,]]
	[ 4 ] = function ( s , tags , extra ) -- VORBIS_COMMENT
		vorbiscomments.read ( get_from_string ( s ) , tags , extra )
	end ,
	--[[ NYI: CUESHEET
	[ 5 ] = function ( s , tags , extra  ) -- CUESHEET
	end , ]]
	--[[ NYI: PICTURE
	[ 6 ] = function ( s , tags , extra  ) -- PICTURE
	end ,
	]]
}

local function read ( get , tags , extra )
	assert ( get ( 4 )  == "fLaC" , "Not a flac file" )

	tags = tags or { }
	extra = extra or { }

	extra.flac_metadata_blocks = { }
	repeat
		local BLOCK_HEADER = get ( 4 )
		local lastmetadatablock = bpeek ( BLOCK_HEADER , 0 )
		local BLOCK_TYPE = be_uint_to_num ( BLOCK_HEADER , 1 , 1 ) % 2^7
		local BLOCK_LENGTH = be_uint_to_num ( BLOCK_HEADER , 2 , 4 )
		local BLOCK_DATA = get ( BLOCK_LENGTH )
		tblinsert ( extra.flac_metadata_blocks , { type = BLOCK_TYPE ; data = BLOCK_DATA } ) -- Keeping the block contents around could be memory consuming

		local f = blockreaders [ BLOCK_TYPE ]
		if f then f ( BLOCK_DATA , tags , extra ) end
	until lastmetadatablock

	return tags , extra
end

--[[
-- Edit a flac file.
 -- Note: This will move all vorbis and padding to the end of the metadata section of the file. (even if it fails)
function edit ( fd , tags , extra )
	assert ( extra.flac_metadata_blocks , "Need to call flac.read first" )

	local vorbistag = vorbiscomments.generate ( tags , extra )
	local needspace = #vorbistag + 4

	local havespace = 0
	local keep_as_is = { }
	for i , v in ipairs ( extra.flac_metadata_blocks ) do
		if v.type == 1 or v.type == 4 then -- Padding or Vorbis Comment
			havespace = havespace + 4 + #v.data
		else
			tblinsert ( keep_as_is , v )
		end
	end

	if havespace >= needspace then -- Got enough space
		fd:seek ( "set" , 4 )
		for i , v in ipairs ( keep_as_is ) do
			-- Write block out to file: we aren't modifying it
			assert ( fd:write (
				num_to_be_uint ( v.type , 1 ) , num_to_be_uint ( #v.data , 3 ) , -- BLOCK_HEADER (not last)
				v.data -- BLOCK_DATA
			) )
		end
		local extraspace = havespace - needspace
		if extraspace < 4 then
			-- If you can't fit the header for the padding block then just pad out the vorbis comment with nul bytes
			assert ( fd:write (
				"\132" , num_to_be_uint ( #vorbistag + extraspace , 3 ) , -- BLOCK_HEADER (this is last block)
				vorbistag ..  strrep ( "\0" , extraspace ) -- BLOCK_DATA
			) )
		else
			-- Write out vorbis tag
			assert ( fd:write (
				"\4" , num_to_be_uint ( #vorbistag , 3 ) , -- BLOCK_HEADER (not last)
				vorbistag -- BLOCK_DATA
			) )
			-- Make a padding tag to take up remaning space before audio data
			assert ( fd:write (
				"\129" , num_to_be_uint ( extraspace - 4 , 3 ) , -- BLOCK_HEADER (this is last block)
				strrep ( "\0" , extraspace - 4 ) -- BLOCK_DATA
			) )
		end
	else -- Damn, gotta shift the whole file down

	end
end
--]]

return {
	read = read ;
}
