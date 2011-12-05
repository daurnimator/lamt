-- FLAC reader

local assert , error = assert , error
local ipairs = ipairs
local strsub , strrep = string.sub , string.rep
local strchar = string.char
local tblinsert , tblremove = table.insert , table.remove

local misc = require "misc"
local get_from_string = misc.get_from_string
local get_from_fd = misc.get_from_fd
local file_insert = misc.file_insert

local vorbiscomments = require "vorbiscomments"

local ll = require "ll"
local num_to_be_uint = ll.num_to_be_uint
local be_uint_to_num = ll.be_uint_to_num
local extract_bits = ll.extract_bits
local be_bpeek = ll.be_bpeek

local BT_STREAMINFO     = 0
local BT_PADDING        = 1
local BT_APPLICATION    = 2
local BT_VORBIS_COMMENT = 4

local function find ( fd )
	fd:seek ( "set" )
	if fd:read ( 4 ) == "fLaC" then
		return 0
	end
	return false
end

local blockreaders = {
	[ BT_STREAMINFO ] = function ( s , tags , extra )
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
	[ BT_PADDING ] = function ( s , tags , extra )
		extra.padding = ( extra.padding or 0 ) + #s
	end ;
	[ BT_APPLICATION ] = function ( s , tags , extra )
		extra.applications = extra.applications or { }
		tblinsert ( extra.applications , { appID = be_uint_to_num ( s , 1 , 4 ) ; data = strsub ( s , 5 , -1 ) } )
	end ,
	--[[[ 3 ] = function ( fd , length , item ) -- SEEKTABLE (we can't do anything with this)
	end ,]]
	[ BT_VORBIS_COMMENT ] = function ( s , tags , extra ) -- VORBIS_COMMENT
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
		local lastmetadatablock = be_bpeek ( BLOCK_HEADER , 0 )
		local BLOCK_TYPE = be_uint_to_num ( BLOCK_HEADER , 1 , 1 ) % 2^7
		local BLOCK_LENGTH = be_uint_to_num ( BLOCK_HEADER , 2 , 4 )
		local BLOCK_DATA = get ( BLOCK_LENGTH )
		tblinsert ( extra.flac_metadata_blocks , { type = BLOCK_TYPE ; data = BLOCK_DATA } ) -- Keeping the block contents around could be memory consuming

		local f = blockreaders [ BLOCK_TYPE ]
		if f then f ( BLOCK_DATA , tags , extra ) end
	until lastmetadatablock

	return tags , extra
end

local function write_block ( fd , blocktype , data , last )
	local H1 = strchar ( ( last and 128 or 0 ) + blocktype )
	return assert ( fd:write (
		H1 , num_to_be_uint ( #data , 3 ) , -- BLOCK_HEADER
		data -- BLOCK_DATA
	) )
end

local function edit_vorbis_block ( tags , extra )
	-- Remove all old vorbis tags
	for i = #extra.flac_metadata_blocks , 1 , -1 do
		local v = extra.flac_metadata_blocks [ i ]
		if v.type == BT_VORBIS_COMMENT then
			tblremove ( extra.flac_metadata_blocks , i )
		end
	end
	local data = vorbiscomments.generate ( tags , extra )
	tblinsert ( extra.flac_metadata_blocks , { type = BT_VORBIS_COMMENT ; data = data } )
end

-- Edit a flac file.
local function edit ( fd , tags , extra )
	assert ( fd:seek ( "set" , 0 ) )
	local old_tags , old_extra = read ( get_from_fd ( fd ) )

	if tags then
		edit_vorbis_block ( tags , extra )
	end

	local havespace = 0
	for i , v in ipairs ( old_extra.flac_metadata_blocks ) do
		havespace = havespace + 4 + #v.data
	end

	local writethese = { }
	local needspace = 0
	for i , v in ipairs ( extra.flac_metadata_blocks ) do
		if v.type ~= BT_PADDING then
			needspace = needspace + 4 + #v.data
			tblinsert ( writethese , v )
		end
	end

	assert ( fd:seek ( "set" , 4 ) )

	if havespace < needspace then -- Haven't got enough space?
		-- Let's be nice and add some padding
		local PADDING_SIZE = 2^11
		file_insert ( fd , strrep ( "\0" , needspace - havespace + PADDING_SIZE ) )
		assert ( fd:seek ( "set" , 4 ) )
		havespace = needspace + PADDING_SIZE
	end

	local nblocks = #writethese
	for i = 1 , nblocks - 1 do
		local v = writethese [ i ]
		write_block ( fd , v.type , v.data )
	end

	local v = writethese [ nblocks ]
	local extraspace = havespace - needspace
	if extraspace < 4 then
		-- If you can't fit the header for the padding block then just pad out the last block with nul bytes
		write_block ( fd , v.type , v.data ..  strrep ( "\0" , extraspace ) , true )
	else
		-- Write out last tag
		write_block ( fd , v.type , v.data )
		-- Make a padding tag to take up remaning space before audio data
		write_block ( fd , BT_PADDING , strrep ( "\0" , extraspace - 4 ) , true )
	end
end

return {
	find = find ;
	read = read ;
	edit = edit ;
}
