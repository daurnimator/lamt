--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local prefix = (...):match("^(.-)[^%.]*$")

local error , ipairs , require , unpack = error , ipairs , require , unpack
local strbyte = string.byte
local floor = math.floor
local ioopen = io.open

module ( "lomp.fileinfo.mpeg" , package.see ( lomp ) )

require ( prefix .. "APE" )
require ( prefix .. "id3v2" )
require ( prefix .. "id3v1" )
require ( prefix .. "tagfrompath" )

-- If quick it set, lengths and bitrates of many VBR files will probably be incorrect
local quick = false

_NAME = "MPEG file format library"
-- Specifications:
 -- http://www.datavoyage.com/mpgscript/mpeghdr.htm

local function bitread ( b , from , to )
	to = to or from
	return floor ( ( b % ( 2^to ) ) / 2^( from -1) )
end

local mpegversion = {
	[0] = 2.5 ,
	[1] = false ,
	[2] = 2 ,
	[3] = 1 ,
}
local tolayer = {
	[0] = false ,
	[1] = 3 ,
	[2] = 2 ,
	[3] = 1 ,
}
local bitrate = {
	[0] = { } ,
	[1] = { 32000 , 	32000 , 	32000 , 	32000 , 	8000 } ,
	[2] = { 64000 , 	48000 , 	40000 , 	48000 , 	16000 } ,
	[3] = { 96000 , 	56000 , 	48000 , 	56000 , 	24000 } ,
	[4] = { 128000 , 	64000 , 	56000 , 	64000 , 	32000 } ,
	[5] = { 160000 , 	80000 , 	64000 , 	80000 , 	40000 } ,
	[6] = { 192000 , 	96000 , 	80000 , 	96000 , 	48000 } ,
	[7] = { 224000 , 	112000 , 	96000 , 	112000 , 	56000 } ,
	[8] = { 256000 , 	128000 , 	112000 , 	128000 , 	64000 } ,
	[9] = { 288000 , 	160000 , 	128000 , 	144000 , 	80000 } ,
	[10] = { 320000 , 	192000 , 	160000 , 	160000 , 	96000 } ,
	[11] = { 352000 , 	224000 , 	192000 , 	176000 , 	112000 } ,
	[12] = { 384000 , 	256000 , 	224000 , 	192000 , 	128000 } ,
	[13] = { 416000 , 	320000 , 	256000 , 	224000 , 	144000 } ,
	[14] = { 448000 , 	384000 , 	320000 , 	256000 , 	160000 } ,
	[15] = { false , 	false , 	false , 	false , 	false }
}
local function getbitrate ( c , version ,layer )
	local bps = bitread ( c , 5 , 8 )
	if version == 1 then
		return bitrate [ bps ] [ layer ]
	elseif version == 2 or version == 2.5 then
		if layer == 1 then
			return bitrate [ bps ] [ 4 ]
		elseif layer == 2 or layer == 3 then
			return bitrate [ bps ] [ 5 ]
		end
	end
end
local samplerates = {
	[1] = { [0]=44100 , 4800 , 32000 , false } ,
	[2] = { [0]=22050 , 24000 , 16000 , false } ,
	[2.5] = { [0]=11025 , 12000 , 8000 , false }
}
local channelmodes = {
	[0] = "Stereo" ,
	[1] = "Joint Stereo" ,
	[2] = "Dual Channel" ,
	[3] = "Mono"
}
local emphasis = {
	[0] = "None" ,
	[1] = "50/15ms" ,
	[2] = false ,
	[3] = "CCIT J.17"
}
local samplesperframe = { -- [mpgversion][layer]
	[1] = { 384 , 1152 , 1152 } ,
	[2] = { 384 , 1152 , 576 } ,
	[2.5] = { 384 , 1152 , 576 }
}
local lensideinfo = { -- [mpegversion][channels] (bytes)
	[1] = { 17 , 32 } ,
	[2] = { 9 , 17 } ,
	[2.5] = { 9 , 17 }
}

local function validframe ( a , b , c , d )
	if a ~= 255 or b < 224 
		or bitread ( b , 4 , 5 ) == 1 -- Invalid Mpeg Version
		or b % 8 < 2 -- bitread ( b , 2 , 3 ) == 0 -- Invalid Layer
		or c >= 240 --bitread ( c , 5 , 8 ) == 15 -- Invalid bitrate
		or c < 16 -- bitread ( c , 5 , 8 ) == 0 -- Not an invalid bitrate, but still impossible to use
		or ( c % 16 >= 12 ) --bitread ( c , 3 , 4 ) == 3 -- Invalid Sampling rate
		then return false 
	else return true end
end

local function getframelength ( layer , samplerate , spf , bitrate , padded )
	if layer == 1 then
		return ( floor ( 12 * bitrate / samplerate ) + padded ) * 4
	else
		return floor ( spf / 8 * bitrate / samplerate ) + padded
	end
end

local function findframesync ( fd )
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
		if validframe ( a , b , c , d ) then return fd:seek ( "cur" , - #str + i - 3 ) , a , b , c , d end
		i = i + 1
	end
	return false
end

function info ( item )
	local fd = ioopen ( item.path , "rb" )
	if not fd then return false , "Could not open file" end
	item = item or { }
	
	local tagatsof = 0 -- Bytes that tags use at start of file
	local tagateof = 0 -- Bytes that tags use at end of file
	
	-- APE
	if not item.tagtype then
		local offset , header = fileinfo.APE.find ( fd )
		if offset and not item.tagtype then
			if offset == 0 then 
				tagatsof = tagatsof + header.size
			else
				tagateof = tagateof + header.size 
				if header.hasheader then
					tagateof = tagateof + 32
				end
			end
			item.header = header
			item.tagtype = "APE"
			item.tags , item.extra = fileinfo.APE.info ( fd , offset , header )
		end
	end

	-- ID3v2
	if not item.tagtype then
		local offset , header = fileinfo.id3v2.find ( fd )
		if offset and not item.tagtype then
			if offset == 0 then
				tagatsof = tagatsof + header.size + 10
			else
				tagateof = tagateof + header.size + 10
			end
			item.header = header
			item.tagtype = "id3v2"
			item.tags , item.extra = fileinfo.id3v2.info ( fd , offset , header )
		end
	end
	
	-- ID3v1 or ID3v1.1 tag
	if not item.tagtype then
		local offset = fileinfo.id3v1.find ( fd )
		if offset then tagateof = tagateof + 128 end
		if offset and not item.tagtype then
			item.tagtype = "id3v1"
			item.tags , item.extra = fileinfo.id3v1.info ( fd , offset )
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
	
	local extra = item.extra
	
	local filesize = fd:seek ( "end" )
	fd:seek ( "set" , tagatsof )

	-- Find first frame header
	local framecounter = 0
	local firstframeoffset , framelength
	local version , layer , bps , samplerate , padded , spf
	local crc , private , channelmode , channels , copyright , original , emph
	
	while true do
		local a , b , c , d
		local strangebps = 0
		local found = false
		while not found do while not found do
			firstframeoffset , a , b , c , d = findframesync ( fd )
			if not firstframeoffset then -- No frames found in file
				return false
			end
			fd:seek ( "cur" , 1 ) -- Seek one byte forward for next iteration
			
			version = mpegversion [ bitread ( b , 4 , 5 ) ]
			layer = tolayer [ bitread ( b , 2 , 3 ) ]
			spf = samplesperframe [ version ] [ layer ]
			bps = getbitrate ( c , version , layer )
			samplerate = samplerates [ version ] [ bitread ( c , 3 , 4 ) ]
			if bps == nil then
				if strangebps < 10 then -- Probably a bad frame, try again
					strangebps = strangebps + 1
					break
				else -- Well, hows that: a frame with no known bitrate.... WTF DO WE DO NOW
					extra.CBR = true -- Least we know its going to be CBR
					framecounter = framecounter + strangebps
				end
			end
			padded = bitread ( c , 2 )
			framelength = getframelength ( layer , samplerate , spf , bps , padded )
			padded = ( padded == 1 )
			found = true
		end end
		
		-- Check we haven't found a false sync by looking if theres a frame where there should be...
		fd:seek ( "set" , firstframeoffset + framelength )
		if validframe ( strbyte ( fd:read ( 4 ) , 1 ,4 ) ) then
			framecounter = framecounter + 1
			crc = bitread ( b , 1 ) == 0
			private = bitread ( c , 1 ) == 1
			channelmode = bitread ( d , 7 , 8 )
			if channelmode == 3 then
				channels = 1 
			elseif channelmode == 1 then
				channels = 2
				extra.modeextension = bitread ( d , 5 , 6 )
			else
				channels = 2
			end
			copyright = bitread ( d , 5 ) == 1
			original = bitread ( d , 6 ) == 1
			emph = bitread ( d , 1 , 2 )
			break
		else
			fd:seek ( "set" , firstframeoffset + 1 )
		end
	end
	
	local length , frames , bytes , quality
	
	-- Look for XING header
	fd:seek ( "cur" , lensideinfo [ version ] [ channels ] )
	local h = fd:read ( 4 )
	if h == "Xing" or h == "Info" then
		local flags = fd:read ( 4 )
		local f = strbyte ( flags , 4 )
		if bitread ( f , 2 ) == 1 then -- Bytes field
			local t = { strbyte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			bytes = sum
		end
		if bitread ( f , 1 ) == 1 then -- Frames field
			local t = { strbyte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			frames = sum
		end
		if bitread ( f , 3 ) == 1 then -- TOC field
			fd:read ( 100 )
		end
		if bitread ( f , 4 ) == 1 then -- Quality field
			local t = { strbyte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			quality = sum
		end
	end
	if not bytes then
		bytes = filesize - firstframeoffset - tagateof
	end
	local guesslength = bytes * 8 / bps
	if frames and samplerate then
		length = frames * spf / samplerate
		bps = bytes*8/(length)
		error("XING" , guesslength , length )
	elseif item.tags and item.tags.length then
		length = item.tags.length [ 1 ]
	end
	if length and ( guesslength*1.01 < length or guesslength*.99 > length ) then -- If guessed length isn't within 1% of actual length, isn't CBR
		extra.CBR = false
	end
	-- Try and figure out if file is CBR:
	if extra.CBR == nil and not quick then
		local testpositions = { 0.2 , 0.7 }
		-- Look at certain percentages of the way through the file:
		-- If they have a different bitrates, file must be VBR
		for i , percentoffset in ipairs ( testpositions ) do
			fd:seek ( "set" , firstframeoffset + floor ( bytes * percentoffset ) )
			
			local newbitrate , newerbitrate
			while true do
				local offset , a , b , c , d = findframesync ( fd )
				if not offset then break end
				
				newbitrate = getbitrate ( c , version , layer )
				local padded= bitread ( c , 2 )
				
				-- Check we haven't found a false sync by looking if theres a frame where the next one should be...
				fd:seek ( "set" , offset + getframelength ( layer , samplerate , spf , newbitrate , padded ) )
				
				local w , x , y , z = strbyte ( fd:read ( 4 ) , 1 ,4 )
				if validframe ( w , x , y , z ) then
					newerbitrate  = getbitrate ( y , version , layer )
					break
				else
					fd:seek ( "set" , offset + 1 )
				end
			end
			
			if newbitrate ~= bps and newerbitrate ~= bps then -- Is VBR
				extra.CBR = false
				break
			end
			
			-- Assume CBR
			extra.CBR = true
		end
	end
	if not length then
		if extra.CBR or quick then
			length = guesslength
		elseif samplerate and spf and bps then
			-- Lets go frame finding!
			local runningbitrate = bps
			fd:seek ( "set" , firstframeoffset + framelength )
			
			while true do
				local frameoffset , a , b , c , d = findframesync ( fd )
				if not frameoffset then break end
				
				local newbitrate = getbitrate ( c , version , layer )
				if newbitrate ~= bps then extra.CBR = false end
				
				framecounter = framecounter + 1
				runningbitrate = runningbitrate + newbitrate
				
				local padded = bitread ( c , 2 )
				fd:seek ( "set" , frameoffset + getframelength ( layer , samplerate , spf , newbitrate , padded ) )
			end
			
			extra.frames = framecounter
			length = framecounter * spf / samplerate
			bps = runningbitrate / framecounter
		else -- No idea, can't figure out length?
			length = 0
		end
	end
	extra.mpegversion = version
	extra.layer = layer
	extra.crcprotected = crc
	extra.bitrate = bps
	extra.samplerate = samplerate
	extra.padded = padded
	extra.channels = channels
	extra.channelmode = channelmode 
	extra.channelmodestr = channelmodes [ channelmode ]
	extra.copyright = copyright
	extra.original = original
	extra.emphasis = emph
	extra.emphasisstr = emphasis [ emph ]
	extra.length = length
	extra.quality = quality
	extra.bytes = bytes
	
	item.format = "mp" .. layer
	
	item.length = length
	item.channels = channels
	item.samplerate = samplerate
	item.bitrate = bps
	item.filesize = filesize
	
	fd:close ( )
	
	return item
end

function edit ( item , edits , inherit )
	if item.tagtype == "id3v1" then -- ID3v1 or ID3v1.1 tag
		return fileinfo.id3v1.edit ( item.path , edits , true )
	elseif item.tagtype == "APE" then -- APE
		return fileinfo.APE.edit ( item.path , edits , inherit )
	--elseif item.tagtype == "id3v2" then -- ID3v2
	else -- id3v2 by default
		local overwrite
		if inherit then 
			overwrite = true
		else
			overwrite = "new"
		end
		local id3version = item.extra.id3v2version or 3
		--edit ( tags , path , overwrite , id3version , footer , dontwrite )
		return fileinfo.id3v2.edit ( edits , item.path , overwrite , id3version , false , false )
	end
end

return { { "mpeg" ; "mpg" ; "mp1" ; "mp2" ; "mp3" ; "mpa" ; } , info , edit }
