--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local strbyte = string.byte
local strchar = string.char

module ( "lomp.fileinfo.wavpack" , package.see ( lomp ) )

_NAME = "Wavpack file format library"
-- Specifications:
 -- http://www.wavpack.com/file_format.txt

require "vstruct"

require "modules.fileinfo.APE"
require "modules.fileinfo.tagfrompath"

local sample_rates = {	6000 , 	8000 , 	9600 , 	11025 , 	12000 , 	16000 , 	22050 , 	24000 , 	32000 , 	44100 ,	48000 , 	64000 , 	88200 , 	96000 , 	192000 }

function intflags ( flags , i , j )
	j = j or i
	local result = 0
	while j >= i do
		result = result * 2
		if flags [ j ] then result = result + 1 end
		j = j - 1
	end
	return result
end
	
function info ( item )
	local fd = io.open ( item.path , "rb" )
	if not fd then return false end
	item = item or { }
	
	-- APE
	if not item.tagtype then
		local offset , header = fileinfo.APE.find ( fd )
		if offset then
			item.header = header
			item.tagtype = "APE"
			item.tags , item.extra = fileinfo.APE.info ( fd , offset , header )
		end
	end
	-- Figure out from path
	if not item.tagtype and config and config.tagpatterns and config.tagpatterns.default then -- If you get to here, there is probably no tag....
		item.tagtype = "pathderived"
		item.tags = fileinfo.tagfrompath.info ( item.path , config.tagpatterns.default )
		item.extra = { }
	else
		item.tags , item.extra = { } , { }
	end
	
	fd:seek ( "set" )
	
	local step = 2048
	local str = fd:read ( 4 )
	if not str then return false end -- EOF
	local t = { nil , nil , strbyte ( str , 1 , 4 ) } -- Check at current offset first
	
	local i = 3
	while true do
		if not t [ i + 3 ] then
			str = fd:read ( step )
			if not str then return false end -- EOF
			t = { t [ i + 1 ] , t [ i + 2 ] , strbyte ( str , 1 , #str ) }
			i = 1
		end
		if strchar ( unpack ( t , i , i + 3 ) ) == "wvpk" then 
			fd:seek ( "cur" , - #str + i + 1 ) 
			break
		end
		i = i + 1
	end
	
	local t = vstruct.unpack ( "< size:u4 version:u2 track_no:u1 index_no:u1 total_samples:u4 block_index:u4 block_samples:u4 flags:m4 crc:u4" , fd )

	item.extra = {
		version = version ;
		totalsamples = t.total_samples ;
		bitspersample = ( intflags ( t.flags , 1 , 2 ) + 1 ) * 8 ;
		stereo = not t.flags [ 3 ] ;
		hybrid = t.flags [ 4 ] ;
		jointstereo = t.flags [ 5 ] ;
		independantchanels = not t.flags [ 6 ] ;
		floatingpoint = t.flags [ 7 ] ;
	}
	
	local sampleratecode = intflags ( t.flags , 24 , 27 ) + 1
	if sampleratecode ~= 16 then
		item.extra.samplerate = sample_rates [ sampleratecode ] ;
	else
		-- TODO: read metadata sub blocks
	end
	
	if item.extra.hybrid then
		item.extra.hybridnoiseshaping = t.flags [ 7 ]
		item.extra.hybridparamscontrolbitrate = t.flags [ 10 ]
	end
	
	item.length = item.extra.totalsamples / item.extra.samplerate
	item.channels = item.extra.channels
	item.samplerate = item.extra.samplerate
	item.bitrate = 	item.extra.samplerate*item.extra.bitspersample
	item.filesize = fd:seek ( "end" )
	
	fd:close ( )
	
	return item
end

function edit ( item , inherit )
	return fileinfo.APE.edit ( item.path , item.tags , inherit )
end

return { { "wv" } , info , edit }
