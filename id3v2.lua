--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.id3v2" , package.see ( lomp ) )

require "vstruct"

_NAME = "ID3v2 tag reader/writer"
-- http://www.id3.org/id3v2.4.0-structure

local function desafesync ( tbl )
	local new = { }
	for i = 1 , #tbl do
		if i % 8 ~= 0 then
			table.insert ( new , tbl [ i ] )
		end
	end
	return vstruct.implode ( new )
end

local function readheader ( fd )
	local t = vstruct.unpack ( "> ident:s3 version:u1 revision:u1 flags:m1 safesyncsize:m4" , fd )
	if ( t.ident == "ID3" or t.ident == "3DI" ) then
		t.size = desafesync ( t.safesyncsize )
		t.safesyncsize = nil -- Don't need to keep this.
		return t
	else
		return false , "Not an ID3v2 header/footer"
	end
end

local function readframe ( fd )
	local t = vstruct.unpack ( "> id:s3 safesyncsize:m4 statusflags:m1 formatflags:m1" , fd )
	t.size = desafesync ( t.safesyncsize )
	t.safesyncsize = nil
	
end

local framedecode = {
	["UFID"] = function ( str )
			return vstruct.unpack ( "> owner_identifier:zW identifier:s64" , str )
		end ,
	["TIT1"] function ( str ) -- Content group description
			local t = vstruct.unpack ( "> encoding:u1" , str )
			--local encoding = 
			return 
		end ,
	["TIT2"] function ( str ) -- Title
			return
		end ,
	["TIT3"] function ( str ) -- Sub Title
			return
		end ,
	["TALB"] function ( str ) -- Source
			return
		end ,
	
}

function find ( fd )
	fd:seek ( "set" ) -- Look at start of file
	local h
	h = readheader ( fd )
	if h then return fd:seek ( "set" ) end
	fd:seek ( "end" , -10 )
	h = readheader ( fd )
	if h then 
		local offsetfooter = ( h.size + 20 ) -- Offset to start of footer from end of file
		fd:seek ( "end" , -offsetfooter) 
		h = readheader ( fd )
		if h and h.flags [ 5 ] then return fd:seek ( "end" , -offsetfooter ) end -- 4th flag (but its in reverse order) is if has footer
	end
end

function info ( fd , location , item )
	fd:seek ( "set" , location )
	local header = readheader ( fd )
	if header then
		item.tags = { }
		item.extra = { }
		
		return item
	else
		return false
	end
end

function generatetag ( tags )

end

function edit ( )

end
