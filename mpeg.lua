--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.mpeg" , package.see ( lomp ) )

require "modules.fileinfo.APE"
require "modules.fileinfo.id3v2"
require "modules.fileinfo.id3v1"
require "modules.fileinfo.tagfrompath"

local magicpattern = "\255[\224-\254]"

local function bitread ( b , pos )
	return math.floor ( ( b % ( 2^pos ) ) / 2^(pos-1) )
end
local function bitnum ( b , from , to )
	local sum = 0
	for i = to , from , -1 do
		sum = sum*2 + bitread ( b , i )
	end
	return sum
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
	[2] = { 64000 ,	48000 , 	40000 , 	48000 , 	16000 } ,
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
	[15] = { false , false , false , false }
}
local function getbitrate ( c , version ,layer )
	local bps = bitnum ( c , 5 , 8 )
	if version == 1 then
		return bitrate [ bps ] [ layer ]
	elseif version == 2 then
		if layer == 1 then
			return bitrate [ bps ] [ 4 ]
		elseif layer == 2 or layer == 3 then
			return bitrate [ bps ] [ 5 ]
		end
	--else -- MPEG 2.5
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

local function findinfile ( fd , pattern , callback )
	local step = 2048
	local new = fd:read ( #pattern )
	local old = ""
	while new do
		local s , e = ( old .. new ):find ( pattern )
		if s then
			local offset = fd:seek ( "cur" , s - #new + #old - 1 )
			if callback ( fd , offset ) then return true end
		end
		local old = new:sub ( - #pattern + 1 )
		new = fd:read ( step )
	end
	return false
end

function info ( item )
	local fd = io.open ( item.path , "rb" )
	item = item or { }
	
	local tagatsof = 0 -- Bytes that tags use at start of file
	local tagateof = 0 -- Bytes that tags use at end of file
	-- APE
	do
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
	do
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
	do
		local offset = fileinfo.id3v1.find ( fd )
		if offset then tagateof = tagateof + 128 end
		if offset and not item.tagtype then
			item.tagtype = "id3v1"
			item.tags , item.extra = fileinfo.id3v1.info ( fd , offset )
		end
	end
	
	-- Figure out from path
	if not item.tagtype then -- If you get to here, there is probably no tag....
		item.tagtype = "pathderived"
		item.tags = fileinfo.tagfrompath.info ( item.path , config.tagpatterns.default )
		item.extra = { }
	end
	
	extra = item.extra
	local filesize = fd:seek ( "end" )
	fd:seek ( "set" , tagatsof )
	
	-- Find first frame header
	local firstframeoffset , framelength
	local framecounter = 0
	
	local version , layer , bps , samplerate , padded , spf
	local crc , private , channelmode , channels , copyright , original , emph
	
	local strangebps = 0
	
	findinfile ( fd , magicpattern , function ( fd , offset )
		firstframeoffset = offset
		
		local str = fd:read ( 4 )
		if not str then return false end
		local a , b , c , d = string.byte ( str , 1 , 4 )

		version = mpegversion [ bitnum ( b , 4 , 5 ) ]
		layer = tolayer [ bitnum ( b , 2 , 3 ) ]
		if version == false or layer == false then return false end
		spf = samplesperframe [ version ] [ layer ]
		bps = getbitrate ( c , version , layer )
		samplerate = samplerates [ version ] [ bitnum ( c , 3 , 4 ) ]
		if bps == false or samplerate == false then return false end
		if bps == nil then
			if strangebps < 5 then -- Probably a bad frame, try again
				strangebps = strangebps + 1
				return false
			else -- Well, hows that: a frame with no bitrate.... WTF DO WE DO NOW
				framecounter = framecounter + strangebps
			end
		end
		padded = bitread ( c , 2 )
		
		if layer == 1 then
			framelength = ( math.floor ( 12 * bps / samplerate ) + padded ) * 4
		else
			framelength = math.floor ( spf / 8 * bps / samplerate ) + padded
		end
		padded = ( padded == 1 )
		
		fd:seek ( "cur" , framelength - 4 )
		local x , y = string.byte ( fd:read ( 4 ) , 1 ,4 )
		if x == 255 and y >= 224 then
			framecounter = framecounter + 1
			crc = bitread ( b , 1 ) == 0
			private = bitread ( c , 1 ) == 1
			channelmode = bitnum ( d , 7 , 8 )
			if channelmode == 3 then
				channels = 1 
			elseif channelmode == 1 then
				channels = 2
				extra.modeextension = bitnum ( d , 5 , 6 )
			else
				channels = 2
			end
			copyright = bitread ( d , 5 ) == 1
			original = bitread ( d , 6 ) == 1
			emph = bitnum ( d , 1 , 2 )
			return true
		else
			fd:seek ( "set" , firstframeoffset + 1 )
		end
	end )
	
	local length , frames , bytes , quality
	
	-- Look for XING header
	fd:seek ( "cur" , lensideinfo [ version ] [ channels ] 	)
	local h = fd:read ( 4 )
	if h == "Xing" or h == "Info" then
		local flags = fd:read ( 4 )
		local f = string.byte ( flags , 4 )
		if bitread ( f , 2 ) == 1 then -- Bytes field
			local t = { string.byte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			bytes = sum
		end
		if bitread ( f , 1 ) == 1 then -- Frames field
			local t = { string.byte ( fd:read ( 4 ) , 1 , 4 ) }
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
			local t = { string.byte ( fd:read ( 4 ) , 1 , 4 ) }
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
		print("XING" , guesslength , length )
		if guesslength*1.01 > length or guesslength*.99 < length then -- If guessed length isn't within 1% of actual length, isn't CBR
			extra.CBR = false
		end
	elseif item.tags.length then
		length = item.tags.length [ 1 ]
	elseif extra.CBR ~= false and type ( bps ) == "number" then
		length = guesslength
	elseif samplerate and spf and bps then
		-- Lets go frame finding!
		local framecounter , runningbitrate = 1 , bps
		fd:seek ( "set" , firstframeoffset + framelength )

		local a , b , c , d 
		findinfile ( fd , magicpattern , function ( fd , offset )
			local str = fd:read ( 4 )
			if not str then return false end
			a , b , c , d = string.byte ( str , 1 , 4 )
			
			local newbitrate = getbitrate ( c , version , layer )
			if newbitrate ~= bps then extra.CBR = false end
			if not newbitrate then return false end
			
			local padded = bitread ( c , 2 )
			if layer == 1 then
				framelength = ( math.floor ( 12 * newbitrate / samplerate ) + padded ) * 4
			else
				framelength = math.floor ( spf / 8 * newbitrate / samplerate ) + padded
			end
			framecounter = framecounter + 1
			runningbitrate = runningbitrate + newbitrate
			fd:seek ( "cur" , framelength - 4 )	
		end )

		length = framecounter * spf / samplerate
		bps = runningbitrate / framecounter
		local ratio = length/guesslength - 1
		if math.abs ( ratio ) > 0.001 then print ( length , guesslength ) end
		--print(framecounter , length, guesslength , length/guesslength - 1 ,bps,version,layer)

	else -- No idea, can't figure out length?
		length = 0
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
	extra.original = o
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

return { { "mp3" , "mp2" , "mpg" , "mpeg" } , info , edit }
