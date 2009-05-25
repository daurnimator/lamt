--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.APE" , package.see ( lomp ) )

pcall ( require , "luarocks.require" ) -- Activates luarocks if available.
require "vstruct"
require "iconv"

local contenttypes = {
	[ 0 ] = "UTF-8" ,
	[ 1 ] = "binary" ,
	[ 2 ] = "link" ,
}

local function readflags ( flags )
	local f = { }
	f.hasheader = flags [ 32-31 ]
	f.hasfooter = not flags[ 32-30 ]
	f.isfooter = not flags [ 32-29 ]
	f.contenttype = contenttypes [ ( ( flags [ 32-2 ] and 2 ) or 0 )  + ( ( flags [ 32-1 ] and 1 ) or 0 ) ]
	f.readonly = flags [ 32-0 ]
	return f
end

function readheader ( fd )
	if fd:read ( 8 ) == "APETAGEX" then
		local h = vstruct.unpack ( "< version:u4 size:u4 items:u4 < flags:m4 x8" , fd )
		if h.version >= 2000 then table.inherit ( h , readflags ( h.flags ) , true ) 
		else -- Version 1
			h.isfooter = true
			h.hasfooter = true
			h.hasheader = false
			h.contenttype = "ISO-8859-1"
		end
		return h
	else
		return false
	end
end

local decodeformats = {
	[ "utf-8" ] =  function ( str , version )
		local tbl = str:explode ( "\0" , true )
		local result = { }
		for i , v in ipairs ( tbl ) do
			if version == 1000 then
				v = utf8 ( v , "ISO-8859-1" ) -- Convert from ascii: neccessary???
			end
			v = v:trim ( )
			result [ #result + 1 ] = v
		end
		return result
	end ,
	[ "number" ] = function ( str , version )
		local tbl = str:explode ( "\0" , true )
		local result = { }
		for i , v in ipairs ( tbl ) do
			v = v:trim ( )
			if tostring ( v ) then
				result [ #result + 1 ] = v
			end
		end
		return result
	end ,
	[ "binary" ] = function ( str , version )
		return { str }
	end ,
	[ "ignore" ] = function ( ) return { } end
}
local decode = {
	[ "title" ] = "utf-8" ,
	[ "subtitle" ] = "utf-8" ,
	[ "artist" ] = "utf-8" ,
	[ "album" ] = "utf-8" ,
	[ "debut album" ] = "utf-8" ,
	[ "publisher" ] = "utf-8" ,
	[ "conductor" ] = "utf-8" ,	
	[ "track" ] = function ( str , version )
		local s , e = string.find ( str , "/" , 1 , true )
		local track = str:sub ( 1 , s - 1 )
		local tot = str:sub ( e + 1 )
		
		local tracknum = decodeformats [ "number" ] ( track , version )
		if tracknum then
			return { tracknumber = tracknum , totaltracks = decodeformats [ "number" ] ( tot , version ) }
		else
			return { tracknumber = track }
		end
	end ,
	[ "composer" ] = "utf-8" ,	
	[ "comment" ] = "utf-8" ,	
	[ "copyright" ] = "utf-8" ,	
	[ "publicationright"] = { "publication right holder" , "utf-8" } ,
	[ "file" ] = "ignore" ,
	[ "EAN/UPC" ] = "binary" ,
	[ "isbn" ] = "utf-8" ,
	[ "catalog" ] = "binary" ,
	[ "lc" ] = { "label code" , "binary" } ,
	[ "year" ] = { "date" , "utf-8" } ,
	[ "record date" ] = { "date" , "utf-8" } ,
	[ "record location" ] = "utf-8" ,
	[ "genre" ] = "utf-8" ,
	[ "media" ] = "utf-8" ,
	[ "index" ] = "ignore" ,
	[ "related" ] = "utf-8" ,
	[ "isrc" ] = "utf-8" , -- Actually ascii, but utf-8 is good with ascii!
	[ "abstract" ] = "utf-8" ,
	[ "language" ] = "utf-8" ,
	[ "bibliography" ] = "utf-8" ,
	[ "introplay" ] = "ignore" ,
	[ "dummy" ] = "ignore" ,
	[ "disc" ] = function ( str , version )
		local s , e = string.find ( str , "/" , 1 , true )
		local disc = str:sub ( 1 , s - 1 )
		local tot = str:sub ( e + 1 )
		
		local discnum = decodeformats [ "number" ] ( disc , version )
		if discnum then
			return { discnumber = discnum , totaldiscs = decodeformats [ "number" ] ( tot , version ) }
		else
			return { discnumber = disc }
		end
	end ,
}

local function interpretitem ( key , flags , vals )
	local func
	if type ( decode [ key ]  ) == "function" then
		func = decode [ key ]
	elseif type ( decode [ key ] ) == "table" and decodeformats [ decode [ key ] [ 2 ] ] then 
		func = function ( str , version ) return { [ decode [ key ] [ 1 ] ] = decodeformats [ decode [ key ] [ 2 ] ] ( str , version ) } end
	elseif type ( decode [ key ] ) == "string" and decodeformats [ decode [ key ] ] then 
		func = function ( str , version ) return { [ key ] = decodeformats [ decode [ key ] ] ( str , version ) } end
	else -- tag not known
		func = function ( str , version ) return { [ key ] = decodeformats [ "binary" ] ( str , version ) } end -- Assume binary data
	end
	
	local result = { }
	for i , v in ipairs ( vals ) do
		v = v:trim ( )
		table.inherit ( result , func ( v , version ) , true )
	end
	
	return result
end

function readitem ( fd , header )
	local version = header.version
	local raw = vstruct.unpack ( "< valuesize:u4 flags:m4 key:z" , fd )
	local key = raw.key:lower ( )
	local val = fd:read ( raw.valuesize )
	local flags = readflags ( raw.flags )
	
	local vals = val:explode ( "\0" , true )
	
	return key , flags , vals
end

function info ( fd , location , header )
	fd:seek ( "set" , location )
	
	local tags , extra = { } , { apeversion = header.version }
	
	for i = 1 , header.items do
		if fd:seek ( "cur" ) >= location + header.size then break end
		table.inherit ( tags , interpretitem ( readitem ( fd , header ) ) , true )
	end
	
	return tags , extra
end

function find ( fd )
	-- Look at start of file
	fd:seek ( "set" )
	local h = readheader ( fd )
	if h then 
		fd:seek ( "set" )
		return 0 , h 
	end
	-- Look at end of file
	fd:seek ( "end" , -32 )
	local h = readheader ( fd )
	if h then
		local offsetfooter = ( h.size + ( ( h.hasheader and 32 ) or 0 ) ) -- Offset to start of footer from end of file
		local offsetfirstitem = fd:seek ( "end" , -offsetfooter) 
		if h and h.isfooter then return offsetfirstitem , h end
	end
	-- No tag
	return false
end
