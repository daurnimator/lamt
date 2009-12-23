--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local ipairs , require , type , unpack = ipairs , require , type , unpack
local ioopen = io.open

module ( "lomp.fileinfo.flac" , package.see ( lomp ) )

local vstruct = require "vstruct"

require "modules.fileinfo.vorbiscomments"

_NAME = "FLAC reader"

function find ( fd )
	fd:seek ( "set" ) -- Rewind file to start
	if fd:read ( 4 ) == "fLaC" then 
		return fd:seek ( "set" )
	end
end

local blockreaders = {
	[ 0 ] = function ( fd , length , item ) -- STREAMINFO
		local STREAMINFO = vstruct.unpack ( [=[>
			minblocksize:u2 maxblocksize:u2 minframesize:u3 maxframesize:u3
			[ 8 | samplerate:u20 channels:u3 bitspersample:u5 totalsamples:u36 ]
			md5:u16 
		]=] , item.extra )
		item.length = STREAMINFO.totalsamples / STREAMINFO.samplerate
		item.channels = STREAMINFO.channels
		item.samplerate = STREAMINFO.samplerate
		item.bitrate = 	STREAMINFO.samplerate*STREAMINFO.bitspersample
	end ,
	[ 1 ] = function ( fd , length , item ) -- PADDING
		local e = item.extra
		e.padding = e.padding or { }
		e.padding [ #e.padding + 1 ] = { start = fd:seek ( ) ; length = length ; }
	end ,
	[ 2 ] = function ( fd , length , item ) -- APPLICATION
		local e = item.extra
		e.applications = e.applications or { }
		e.applications [ #e.applications + 1 ] = vstruct.unpack ( "> appID:u4 appdata:s".. length , fd )
	end ,
	--[[[ 3 ] = function ( fd , length , item ) -- SEEKTABLE (we can't do anything with this)
	end ,--]]
	[ 4 ] = function ( fd , length , item ) -- VORBIS_COMMENT
		item.tagtype = "vorbiscomment"
		item.tags = { }
		item.extra.startvorbis = fd:seek ( "cur" )
		
		fileinfo.vorbiscomments.info ( fd , item )
	end ,
	[ 5 ] = function ( fd , length , item ) -- CUESHEET
		local e = item.extra
		e.cuesheet = e.cuesheet or { }
		e.cuesheet [ #e.cuesheet + 1 ] = vstruct.unpack ( [=[>
			catalognumber:s128 leadinsamples:u8 [ 1 | cd:b1 x7] x258 tracks:u1
		]=] , fd )
		-- TODO: read CUESHEET_TRACK block
	end ,
	[ 6 ] = function ( fd , length , item ) -- PICTURE
		local e = item.extra
		e.picture = e.picture or { }
		e.picture [ #e.picture + 1 ] = vstruct.unpack ( [=[>
			type:u4 mimetype:c4 desciption:c4 width:u4 height:u4 depth:u4 colours:u4 data:c4
		]=] , fd )
	end ,
}

function info ( item )
	local fd , err = ioopen ( item.path , "rb" )
	if not fd then return false , "Could not open file:" .. err end
	
	-- Format info found at http://flac.sourceforge.net/format.html
	if fd:read ( 4 ) == "fLaC" then 
		item.format = "flac"
		item.extra = { }
		
		repeat
			local METADATA_BLOCK_HEADER = vstruct.unpack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block_length:u3" , fd )
			local offset = fd:seek ( "cur" )
			local f = blockreaders [ METADATA_BLOCK_HEADER.block_type ] 
			if f then f ( fd , METADATA_BLOCK_HEADER.block_length , item ) end
			fd:seek ( "set" , offset + METADATA_BLOCK_HEADER.block_length )
		until METADATA_BLOCK_HEADER.lastmetadatablock
		
		if not item.tags then
			-- Figure out from path
			item.tagtype = "pathderived"
			item.tags = fileinfo.tagfrompath.info ( path , config.tagpatterns.default )
		end
		
		item.filesize = fd:seek ( "end" )
		
		fd:close ( )
		return item
	else
		-- not a flac file
		fd:close ( )
		return false , "Not a flac file"
	end
end

function write ( fd , tags )
	local item = info ( fd )
	
	
	local space_needed = #s
	
	local oldblocksize = 0
	if item.extra.startvorbis then
		fd:seek ( item.extra.startvorbis + 1 )
		oldblocksize = vstruct.unpack ( "u3" , fd ) [ 1 ]
	end
	
	if space_needed ~= oldblocksize then
		-- Look for padding blocks
		if type ( item.extra.padding ) == "table" then
			
		end
		
		if space_needed < oldblocksize then
			
		else --space_needed > oldblocksize then
			
		end
	end
	
	-- Write
end

function edit ( items , edits , inherit )
	local vorbistag = generatetag ( items , edits , inherit )
	-- Flac editing not ready yet
	return false
end

return { { "flac" , "fla" } , info , edit }
