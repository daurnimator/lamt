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

local magicpattern = "\255[\239-\254]"

function bitread ( b , pos )
	return math.floor ( ( b % ( 2^pos ) ) / 2^(pos-1) )
end
function bitnum ( b , from , to )
	local sum = 0
	for i = 9-from , 9-to , -1 do
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
local layer = {
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
local function getbitrate ( c , v , l )
	local r = bitnum ( c , 1 , 4 )
	if v == 1 then
		return bitrate [ r ] [ l ]
	elseif v == 2 then
		if l == 1 then
			return bitrate [ r ] [ 4 ]
		elseif l == 2 or l == 3 then
			return bitrate [ r ] [ 5 ]
		end
	--else -- MPEG 2.5
	end
end
local samplerate = {
	[0] = { 44100 , 22050 , 11025 } ,
	[1] = { 48000 , 24000 , 12000 } ,
	[2] = { 32000 , 16000 , 8000 } ,
	[3] = { false , false , false }
}
local function getsamplerate ( c , v )
	return samplerate [ bitnum ( c , 5 , 6 ) ] [ math.ceil ( v ) ]
end
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

function info ( item )
	local fd = io.open ( item.path , "rb" )
	item = item or { }
	
	local tagatsof = 0 -- Bytes that tags use at start of file
	local tagateof = 0 -- Bytes that tags use at end of file
	-- APE
	if not item.tagtype then
		local offset , header = fileinfo.APE.find ( fd )
		if offset then
			if offset == 0 then 
				tagatsof = header.size
			else
				tagateof = header.size 
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
		if offset then
			if offset == 0 then
				tagatsof = header.size + 10
			else
				tagateof = header.size + 10
			end
			item.header = header
			item.tagtype = "id3v2"
			item.tags , item.extra = fileinfo.id3v2.info ( fd , offset , header )
		end
	end

	-- ID3v1 or ID3v1.1 tag
	if not item.tagtype then
		local offset = fileinfo.id3v1.find ( fd )
		if offset then tagateof = 128 end
		if offset then
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
	
	local filesize = fd:seek ( "end" )
	fd:seek ( "set" , tagatsof )
	
	local new = fd:read ( 2 )
	local old = ""
	local offset
	while new do
		local s , e = ( old .. new ):find ( magicpattern )
		if s then
			offset = fd:seek ( "cur" , s - #new + #old )
			break
		end
		local old = new:sub ( #magicpattern-1 )
		new = fd:read ( 2048 )
	end
	local b , c , d = string.byte ( fd:read ( 3 ) , 1 , 3 )
	
	local v = mpegversion [ bitnum ( b , 4 , 5 ) ]
	local l = layer [ bitnum ( b , 6 , 7 ) ] or 3 -- Guess mp3 if not known
	local crc = bitread ( b , 8 ) == 0
	local r = getbitrate ( c , v , l )
	local s = getsamplerate ( c , v )
	local padded = bitread ( c , 7 ) == 1
	local private = bitread ( c , 8 ) == 1
	local channelmode = bitnum ( d , 1 , 2 )
	local channels
	if channelmode == 3 then channels = 1 else channels = 2 end
	local copyright = bitread ( d , 5 ) == 1
	local o = bitread ( d , 6 ) == 1
	local emph = bitnum ( d , 7 , 8 )

	local length , frames , bytes , quality

	-- Look for XING header
	fd:seek ( "cur" , lensideinfo [ v ] [ channels ] 	)
	local h = fd:read ( 4 )
	if h == "Xing" or h == "Info" then
		local flags = fd:read ( 4 )
		local f = string.byte ( flags , 4 )
		if bitread ( f , 1 ) == 1 then -- Frames field
			local t = { string.byte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			frames = sum
		end
		if bitread ( f , 2 ) == 1 then -- Bytes field
			local t = { string.byte ( fd:read ( 4 ) , 1 , 4 ) }
			local sum = 0
			for i , v in ipairs ( t ) do
				sum = sum * 256 + v
			end
			bytes = sum
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
		bytes = filesize - offset - tagateof
	end
	if frames and s then
		length = frames * samplesperframe [ v ] [ l ] / s
		r = bytes*8/(length)
	elseif type ( r ) == "number" then
		length = bytes*8 / r
	elseif item.tags.length then
		length = item.tags.length [ 1 ]
	elseif s then
		-- Lets go frame finding!
		local frames = 1
		local old = ""
		while true do
			new = fd:read ( 2048 )
			if not new then break end
			frames = frames + select ( 2 , ( old .. new ):gsub ( magicpattern , { } ) )
			local old = new:sub ( #magicpattern-1 )
		end
		length = frames * samplesperframe [ v ] [ l ] / s
		--print(frames,length)
	else -- No idea
		--[[fd:seek ( "set" )
		local a = fd:read ( "*a" )
		local frames = select(2,a:gsub ( magicpattern , { }))
		print(frames)
		--print(a:find ( "Xing" ))
		--print(a:find ( "MLLT" ))--]]
		length = 0
	end
	--[[if not length or length == 0 then
		print( item.path )
		print( v , l , bytes , r , s , samplesperframe [ v ] [ l ] , unpack ( item.tags.length or { } ) )
	end
	print(item.path , length)--]]
	
	e = item.extra
	e.mpegversion = v
	e.layer = l
	e.crcprotected = crc
	e.bitrate = r
	e.samplerate = s
	e.padded = padded
	e.channels = channels
	e.channelmode = channelmode 
	e.channelmodestr = channelmodes [ channelmode ]
	e.copyright = copyright
	e.original = o
	e.emphasis = emph
	e.emphasisstr = emphasis [ emph ]
	e.length = length
	e.quality = quality
	e.bytes = bytes
	
	item.format = "mp" .. l
	
	if channelmode == 1 then
		e.modeextension = bitnum ( d , 3 , 4 )
	end
	
	item.length = length
	item.channels = channels+10
	item.samplerate = s
	item.bitrate = r
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

return { { "mp3" } , info , edit }
