--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local strbyte = string.byte

require "vstruct"

module ( "lomp.fileinfo.ogg" , package.see ( lomp ) )

local O , g , S = string.byte ( "OgS" , 1 , 3 )
local function validpage ( a , b , c , d )
	if a == O and b == g and c == g and d == S then return true else return false end
end

function findpage ( fd )
	local step = 2048
	local a , b , c , d
	local str = fd:read ( 4 )
	if not str then return false end -- EOF
	local t = { nil , nil , strbyte ( str , 1 , 4 ) } -- Check for frame at current offset first
	
	local i = 3
	while true do
		if not t [ i + 3 ] then
			str = fd:read ( step )
			if not str then return false end -- EOF
			t = { b , c , strbyte ( str , 1 , #str ) }
			i = 1
		end
		a , b , c , d =  unpack ( t , i , i + 3 )
		if validpage ( a , b , c , d ) then return fd:seek ( "cur" , - #str + i - 3 ) end
		i = i + 1
	end
	return false
end

function info ( item )
	local fd = io.open ( item.path , "rb" )
	if not fd then return false , "Could not open file" end
	item = item or { }
	item.extra = item.extra or { }
	
	local firstpageoffset = findpage ( fd )
	local header = vstruct.unpack ( "OggS:s4 version:u1 headertype:m1 granuleposition:u8 bitstreamserial:u4 sequencenumber:u4 checksum:u4 segments:u1" , fd )
	if header.version ~= 0 then return false , "Unsupported ogg version" end
	local segmenttable = { strbyte ( fd:read ( header.segments ) , 1 , header.segments ) }
	local segments , nexti = { } , 1
	for i , v in ipairs ( segmenttable ) do
		segments [ nexti ] = ( segments [ nexti ] or "" ) .. fd:read ( v )
		if v ~= 255 then
			nexti = nexti + 1
		end
	end

	-- Check vorbis
	if segments [ 1 ]:sub ( 2 , 7 ) ~= "vorbis" then
		return false , "Not Vorbis"
	end
	item.format = "vorbis"
	
	local packet_type = segments [ 1 ]:byte ( 1 , 1 )
	if packet_type == 1 then -- ID header
		local sd = vstruct.cursor ( segments [ 1 ] )
		sd:seek  ( "set" , 7 )
		local id = vstruct.unpack ( "version:u4 channels:u1 samplerate:u4 bitrate_maximum:i4 bitrate_nominal:i4 bitrate_minimum:i4 blocksize:x1 framingflag:m1" , sd )
		item.bitrate = id.bitrate_nominal
		item.channels = id.channels
		item.samplerate = id.samplerate
		item.extra.bitrate_maximum = id.bitrate_maximum
		item.extra.bitrate_nominal = id.bitrate_nominal
		item.extra.bitrate_minimum = id.bitrate_minimum
	elseif packet_type == 3 then -- Comment header
	elseif packet_type == 5 then -- Setup header
	else
	end
	
	return item
end

function edit ( item , edits , inherit )

end

return { { "ogg" } , info , edit }