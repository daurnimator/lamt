--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.wavpack" , package.see ( lomp ) )

require "vstruct"

require "modules.fileinfo.APE"
require "modules.fileinfo.tagfrompath"

local sample_rates = { 6000 , 8000 , 9600 , 11025 , 12000 , 16000 , 22050 , 24000 , 32000 , 44100 , 48000 , 64000 , 88200 , 9600 }

function info ( item )
	local fd = io.open ( item.path , "rb" )
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
	end
	
	fd:seek ( "set" )
	local new = fd:read ( 4 )
	local old = ""
	while new do
		local s , e = ( old .. new ):find ( "wvpk" )
		if s then
			fd:seek ( "cur" , e - #new + #old )
			break
		end
		local old = new:sub ( -3 , -1 )
		new = fd:read ( 2048 )
	end
	
	local t = vstruct.unpack ( "< size:u4 version:u2 track_no:u1 index_no:u1 total_samples:u4 block_index:u4 block_samples:u4 flags:m4 crc:u4" , fd )
	
	item.extra = {
		version = version ;
		totalsamples = t.total_samples ;
		bitspersample = ( vstruct.implode ( { unpack ( t.flags , 1 , 2 ) } ) + 1 ) * 8 ;
		stereo = not t.flags [ 3 ] ;
		hybrid = t.flags [ 4 ] ;
		jointstereo = t.flags [ 5 ] ;
		independantchanels = not t.flags [ 6 ] ;
		floatingpoint = t.flags [ 8 ] ;
		sampleratecode = vstruct.implode ( { unpack ( t.flags , 23 , 26 ) } ) + 1 ; -- Incorrect...
	}
	if sampleratecode ~= 16 then
		item.exta.samplerate = sample_rates [ item.extra.sampleratecode ] ;
	else
		-- TODO: metadata sub blocks
	end
	print(item.extra.sampleratecode , sample_rates [ item.extra.sampleratecode ] , unpack ( t.flags , 23 , 26 ) )
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
