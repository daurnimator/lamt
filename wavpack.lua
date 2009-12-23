--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local require , unpack = require , unpack
local strbyte , strchar = string.byte , string.char
local ioopen = io.open

module ( "lomp.fileinfo.wavpack" , package.see ( lomp ) )

_NAME = "Wavpack file format library"
-- Specifications:
 -- http://www.wavpack.com/file_format.txt

local vstruct = require "vstruct"

require "modules.fileinfo.APE"
require "modules.fileinfo.tagfrompath"

local sample_rates = { [0]=6000 , 	8000 , 	9600 , 	11025 , 	12000 , 	16000 , 	22050 , 	24000 , 	32000 , 	44100 ,	48000 , 	64000 , 	88200 , 	96000 , 	192000 }
	
function info ( item )
	local fd = ioopen ( item.path , "rb" )
	if not fd then return false , "Could not open file" end
	
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
	if not item.tagtype then
		if config and config.tagpatterns and config.tagpatterns.default then -- If you get to here, there is probably no tag....
			item.tagtype = "pathderived"
			item.tags = fileinfo.tagfrompath.info ( item.path , config.tagpatterns.default )
			item.extra = { }
		else
			item.tags , item.extra = { } , { }
		end
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
	
	local t = vstruct.unpack ( [=[ <
		cksize:u4 version:u2 track_no:u1 index_no:u1 totalsamples:u4 block_index:u4 block_samples:u4
		[ 4 | bytespersample:u2 mono:b1 hybrid:b1 jointstereo:b1 cross_channel_decorrelation:b1 hybrid_noise_shaping:b1 floating_point_data:b1 
			extended_size_integers:b1 hybrid_mode_parameters_control_bitrate:b1 hybrid_noise_balanced:b1 initial_block:b1 final_block:b1
			leftshift:u5 maximum_magnitude:u5 sampleratecode:u4 x2 useIIR:b1 falsestereo:b1 x1]
		crc:u4]=] , fd )
	t.bytespersample = t.bytespersample + 1
	
	t.bitspersample = t.bytespersample * 8
	t.stereo = not t.mono
	t.lossless = not t.hybrid
	t.independantchanels = not t.cross_channel_decorrelation
	t.integer_data = not t.floating_point_data
	t.hybrid_mode_parameters_control_noise_level = not t.hybrid_mode_parameters_control_bitrate
	if t.sampleratecode ~= 15 then -- (1111 = unknown/custom)
		t.samplerate = sample_rates [ t.sampleratecode ]
	end
	
	--[[ TODO: read metadata sub blocks
	local b = vstruct.unpack ( [=[ <
		[ 1 |  ]
		
	]=] , fd ) --]]
	
	if t.block_index ~= 0 or t.totalsamples == 2^32-1 or not t.samplerate then -- Need to find length the hard way
		-- TODO: traverse file
		return false
	else
		item.length = t.totalsamples / t.samplerate
		item.samplerate = t.samplerate
		item.bitrate = 	t.samplerate*t.bitspersample
	end
	item.channels = t.channels
	item.filesize = fd:seek ( "end" )
	
	fd:close ( )
	item.extra = t
	return item
end

function edit ( item , inherit )
	return fileinfo.APE.edit ( item.path , item.tags , inherit )
end

return { { "wv" } , info , edit }
