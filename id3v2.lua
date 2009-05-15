--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.id3v2" , package.see ( lomp ) )

pcall ( require , "luarocks.require" ) -- Activates luarocks if available.
require "vstruct"
require "iconv"

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

local frameencode = {
	["uniquefileid"] = "UFID" ,
	["content group"] = "TIT1" ,
	["title"] = "TIT2" ,
	["subtitle"] = "TIT3" ,
	["album"] = "TALB" ,
	["original album"] = "TOAL" ,
	["tracknumber"] = function ( item )
						local t = { }
						for i , v in ipairs ( item ["tracknumber"] ) do
							if item ["totaltracks"] [i] then
								table.insert ( t , tostring ( v ) .. "/" .. item ["totaltracks"] [i] )
							else
								table.insert ( t , tostring ( v ) ) 
							end	
						end
						return "TRCK" , t
					end ,
	["totaltracks"] = function ( item )
						if not item ["tracknumber"] [i] then -- If not going to put in with tracknumber in TRCK, put in TXXX
							return "TXXX"
						end
					end ,
	["discnumber"] = function ( item )
						local t = { }
						for i , v in ipairs ( item ["tracknumber"] ) do
							if item ["totaltracks"] [i] then
								table.insert ( t , tostring ( v ) .. "/" .. item ["totaltracks"] [i] )
							else
								table.insert ( t , tostring ( v ) ) 
							end	
						end
						return "TPOS" , t
					end ,	
	["totaldiscs"] = function ( item )
						if not item ["discnumber"] [i] then -- If not going to put in with discnumber in TPOS, put in TXXX
							return "TXXX"
						end
					end ,
	["set subtitle"] = "TSST" ,
	["isrc"] = "TSRC" ,
}

local encodings = {
	[ 0 ] = { name = "ISO-8859-1" , nulls = "1" } , 
	[ 1 ] = { name = "UTF-16" , nulls = "2" } , 
	[ 2 ] = { name = "UTF-16BE" , nulls = "2" } , 
	[ 3 ] = { name = "UTF-8" , nulls = "1" } , 
}

local function readtextframe ( str )
	local t = vstruct.unpack ( "> encoding:u1 text:s" , str )
	return iconv.new ( "UTF-8" , encodings [ t.encoding ].name ):iconv ( t.text ) )
end

local framedecode = {
	["UFID"] = function ( str )
			return vstruct.unpack ( "> ownerid:z uniquefileid:s64" , str )
		end ,
		
	-- TEXT fields
	["TIT1"] = function ( str ) -- Content group description
			return { [ "content group" ] = readtextframe ( str ) }
		end ,
	["TIT2"] = function ( str ) -- Title/Songname/Content description
			return { [ "title" ] = readtextframe ( str ) }
		end ,
	["TIT3"] = function ( str ) -- Subtitle/Description refinement
			return { [ "subtitle" ] = readtextframe ( str ) }
		end ,
	["TALB"] = function ( str ) -- Album/Movie/Show title
			return { [ "album" ] = readtextframe ( str ) }
		end ,
	["TOAL"] = function ( str ) -- Original album/movie/show title
			return { [ "original album" ] = readtextframe ( str ) }
		end ,
	["TRCK"] = function ( str ) -- Track number/Position in set
			local track , total = string.match ( readtextframe ( str ) , "([^/*])/?(.-*)" )
			return { [ "tracknumber" ] = track , ["totaltracks"] = total }
		end ,
	["TPOS"] = function ( str ) -- Part of a set
			local disc , total = string.match ( readtextframe ( str ) , "([^/*])/?(.-*)" )
			return { [ "discnumber" ] = disc , ["totaldiscs"] = total }
		end ,
	["TSST"] = function ( str ) -- Set subtitle
			return { [ "set subtitle" ] = readtextframe ( str ) }
		end ,
	["TSRC"] = function ( str ) -- ISRC
			return { [ "ISRC" ] = readtextframe ( str ) }
		end ,
	
	-- URL fields,
	["WCOM"] = function ( str ) -- Commerical information
		return { buyurl = str }
	end ,
	["WCOP"] = function ( str ) -- Copyright/Legal information
		return { buyurl = str }
	end ,
	["WOAF"] = function ( str ) -- Official audio file webpage
		return { buyurl = str }
	end ,
	["WOAR"] = function ( str ) -- Official artist/performer webpage
		return { buyurl = str }
	end ,
	["WOAS"] = function ( str ) -- Official audio source webpage
		return { buyurl = str }
	end ,
	["WORS"] = function ( str ) -- Official Internet radio station homepage
		return { buyurl = str }
	end ,
	["WPAY"] = function ( str ) -- Payment
		return { buyurl = str }
	end ,
	["WPUB"] = function ( str ) -- Publishers official webpage
		return { buyurl = str }
	end ,
	["WXXX"] = function ( str ) -- Custom
		return { buyurl = str }
	end ,	
	
}

local function readframe ( fd )
	local t = vstruct.unpack ( "> id:s4 safesyncsize:m4 statusflags:m1 formatflags:m1" , fd )
	t.size = desafesync ( t.safesyncsize )
	t.safesyncsize = nil
	print( t.id , t.size , t.statusflags , t.formatflags )
	t.contents = fd:read ( t.size )
	print ( t.contents )
	if framedecode [ t.id ] then
		return framedecode [ t.id ] ( t.contents )
	else -- We don't know of this frame type
		return { }
	end
end

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
		print("FRAME" , readframe ( fd ))
		return item
	else
		return false
	end
end

function generatetag ( tags )

end

function edit ( )

end
