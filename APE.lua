--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local ipairs , pairs , pcall , require , tostring , type = ipairs , pairs , pcall , require , tostring , type
local ioopen = io.open
local osremove , osrename = os.remove , os.rename
local tblappend , tblconcat , tblinherit = table.append , table.concat , table.inherit

module ( "lomp.fileinfo.APE" , package.see ( lomp ) )

pcall ( require , "luarocks.require" ) -- Activates luarocks if available.
local vstruct = require "vstruct"
local iconv = require "iconv"

_NAME = "APEv1 and APEv2 tag reader/writer"
-- Specifications:
 -- http://wiki.hydrogenaudio.org/index.php?title=APEv2
 -- http://wiki.hydrogenaudio.org/index.php?title=APEv2_specification
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Tags_Header
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Tag_Item
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_key
 -- http://wiki.hydrogenaudio.org/index.php?title=APE_Item_Value
 -- http://wiki.hydrogenaudio.org/index.php?title=Ape_Tags_Flags

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
	local offset = fd:seek ( "cur" )
	if fd:read ( 8 ) == "APETAGEX" then
		local h = vstruct.unpack ( "< version:u4 size:u4 items:u4 < flags:m4 x8" , fd )
		h.start = offset
		if h.version >= 2000 then
			tblinherit ( h , readflags ( h.flags ) , true ) 
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
				v = v:utf8 ( "ISO-8859-1" ) -- Convert from ascii: neccessary???
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
		local s , e = str:find ( "/" , 1 , true )
		local track = s and str:sub ( 1 , s - 1 ) or str
		local tot = e and str:sub ( e + 1 ) or ""
		
		local tracknum = decodeformats [ "number" ] ( track , version )
		if tracknum then
			return { tracknumber = tracknum , totaltracks = decodeformats [ "number" ] ( tot , version ) }
		else
			return { tracknumber = { track } }
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
		local s , e = str:find ( "/" , 1 , true )
		local disc = s and str:sub ( 1 , s - 1 ) or str
		local tot = e and str:sub ( e + 1 ) or ""
		
		local discnum = decodeformats [ "number" ] ( disc , version )
		if discnum then
			return { discnumber = discnum , totaldiscs = decodeformats [ "number" ] ( tot , version ) }
		else
			return { discnumber = { disc } }
		end
	end ,
}

local function interpretitem ( key , flags , val )
	local vals = val:explode ( "\0" , true )
	
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
		tblinherit ( result , func ( v , version ) , false )
	end
	
	return result
end

function readitem ( fd , header )
	local version = header.version
	local raw = vstruct.unpack ( "< valuesize:u4 flags:m4 key:z" , fd )
	local key = raw.key:lower ( )
	local val = fd:read ( raw.valuesize )
	local flags = readflags ( raw.flags )
	
	return key , flags , val
end

function info ( fd , location , header )
	fd:seek ( "set" , location )
	
	local tags , extra = { } , { apeversion = header.version }
	
	for i = 1 , header.items do
		if fd:seek ( "cur" ) >= ( location + header.size ) then break end
		tblinherit ( tags , interpretitem ( readitem ( fd , header ) ) , true )
	end
	
	return tags , extra
end

function find ( fd )
	-- Look at start of file
	fd:seek ( "set" )
	local h = readheader ( fd )
	if h then 
		fd:seek ( "set" , 32 )
		return 32 , h 
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

local function generateutf8item ( key , tbl )
	local flags = { false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false }
	
	-- Remove duplicates entries
	local newtable = { }
	for i , v in ipairs ( tbl ) do
		local dupe = false
		for ii , vv in pairs ( newtable ) do
			if v == vv then dupe = true break end
		end
		if not dupe then
			newtable [ #newtable + 1 ] = v
		end
	end
	
	local str = tblconcat ( newtable , "\0" )
	return { flags = flags , value = str }
end

function edit ( path , tags , inherit )
	local fd , err = ioopen ( path , "rb+" )
	if not fd then return ferror ( err , 3 ) end
	
	local offset , h = find ( fd )
	
	-- Make table of new items
	local newitems = { }
	for k , v in pairs ( tags ) do
		if not newitems [ k ] then
			newitems [ k ] = v
		else
			tblappend ( newitems [ k ] , v )
		end
	end
	
	if inherit then
		for i = 1 , h.items do
			if fd:seek ( "cur" ) >= ( offset + h.size ) then break end
			local key , flags , val = readitem ( fd , h )
			if newitems [ key ] then
				for k , v in pairs ( interpretitem ( key , flags , val ) ) do
					if not newitems [ k ] then
						newitems [ k ] = v
					else
						tblappend ( newitems [ k ] , v )
					end
				end
			else
				newitems [ key ] = { flags = flags , value = val }
			end
		end
	end
	
	local tag = ""
	local itemcount = 0
	for k , v in pairs ( newitems ) do
		local item = generateutf8item ( k , v )
		tag = tag .. vstruct.pack ( "< u4 m4 z s" , { #item.value , item.flags , k , item.value } )
		itemcount = itemcount + 1
	end
		
	local flags = { false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , false , true }
	-- Make footer
	local footer = vstruct.pack ( "< s8 u4 u4 u4 m4 x8" , { "APETAGEX" , 2000 , #tag + 32 , itemcount , flags } )
	-- Make header
	flags [ 30 ] = true
	local header = vstruct.pack ( "< s8 u4 u4 u4 m4 x8" , { "APETAGEX" , 2000 , #tag + 32 , itemcount , flags } )
	
	tag = header .. tag .. footer
	
	local cutoffstart , cutoffend = 0 , 0
	
	if offset == 0 then -- Tag at start of file
		cutoffstart = 32 + h.size
	end
	
	local offset , h = find ( fd )
	if h.hasheader then offset = offset - 32 end
	local filesize = fd:seek ( "end" )
	if offset then -- Footer at end of file
		if ( filesize - offset ) > #tag then -- Fits or goes over, ok to write
			cutoffend = filesize - offset
		end
	end
	
	if cutoffstart > 0 or cutoffend > 0 then
		local dir = path:match ( "(.*/)" ) or  "./"
		local filename = path:match ( "([^/]+)$" )
			
		-- Make a tmpfile
		local tmpfilename , wd , err
		for lim = 1 ,  20 do 
			tmpfilename = dir .. filename .. ".tmp" .. lim
			local td
			td , err = ioopen ( tmpfilename , "r" )
			if not td and err:find ( "No such file or directory" ) then -- Found an empty file
				wd , err = ioopen ( tmpfilename , "wb" )
				break
			end
		end
		if err then return ferror ( "Could not create temporary file: " .. err , 3 ) end
			
		fd:seek ( "set" , cutoffstart )
			
		local bytestogo = filesize - cutoffstart - cutoffend - 32
		while true do
			local bytestoread = ( bytestogo >= 1024 and 1024 ) or bytestogo
			local buff = fd:read ( bytestoread )
			if #buff == 0 then break end
			wd:write ( buff )
			bytestogo = bytestogo - #buff
		end
		fd:close ( )
		
		wd:write ( tag )
		
		wd:flush ( )
		wd:close ( )
		osremove ( path ) 
		osrename ( tmpfilename , path )
		osremove ( tmpfilename ) 
	else
		fd:seek ( "set" , offset )
		fd:write ( tag )
		fd:close ( )
	end
	
	return #tag
end
