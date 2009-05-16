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
local genrelist = require "modules.fileinfo.genrelist"

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

local function utf8 ( str , encoding )
	if not encoding then encoding = "ISO-8859-1" end
	return iconv.new ( "UTF-8" ,  encoding ):iconv ( str )
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
	[ "uniquefileid" ] = "UFID" ,
	[ "content group" ] = "TIT1" ,
	[ "title" ] = "TIT2" ,
	[ "subtitle" ] = "TIT3" ,
	[ "album" ] = "TALB" ,
	[ "original album" ] = "TOAL" ,
	[ "tracknumber" ] = function ( item )
						local t = { }
						for i , v in ipairs ( item ["tracknumber"] or { } ) do
							if item ["totaltracks"] [i] then
								table.insert ( t , tostring ( v ) .. "/" .. item ["totaltracks"] [i] )
							else
								table.insert ( t , tostring ( v ) ) 
							end	
						end
						return "TRCK" , t
					end ,
	[ "totaltracks" ] = function ( item )
						if not item ["tracknumber"] [i] then -- If not going to put in with tracknumber in TRCK, put in TXXX
							return "TXXX"
						end
					end ,
	[ "discnumber" ] = function ( item )
						local t = { }
						for i , v in ipairs ( item ["discnumber"] or { } ) do
							if item ["totaldiscs"] [i] then
								table.insert ( t , tostring ( v ) .. "/" .. item ["totaldiscs"] [i] )
							else
								table.insert ( t , tostring ( v ) ) 
							end	
						end
						return "TPOS" , t
					end ,	
	[ "totaldiscs" ] = function ( item )
						if not item ["discnumber"] [i] then -- If not going to put in with discnumber in TPOS, put in TXXX
							return "TXXX"
						end
					end ,
	[ "set subtitle" ] = "TSST" ,
	[ "isrc" ] = "TSRC" ,

	[ "artist" ] = "TPE1" ,
	[ "band" ] = "TPE2" ,
	[ "conductor" ] = "TPE3" , 
	[ "remixed by" ] = "TPE4" ,
	[ "original artist" ] = "TOPE" ,
	[ "writer" ] = "TEXT" ,
	[ "original writer" ] = "TOLY" ,
	[ "composer" ] = "TCOM" ,
	-- TODO: TMCL, TIPL (lists)
	[ "encoded by" ] = "TENC" ,
	
	
	
	[ "commercial information url" ] = "WCOM" ,
	[ "copyright url" ] = "WCOP" ,
	[ "file webpage url" ] = "WOAF" ,
	[ "artist webpage url" ] = "WOAR" ,
	[ "source webpage url" ] = "WOAS" , 
	[ "internet radio webpage url" ] = "WORS" , 
	[ "payment url" ] = "WPAY" , 
	[ "publisher url" ] = "WPUB" ,
}

local encodings = {
	[ 0 ] = { name = "ISO-8859-1" , nulls = "1" } , 
	[ 1 ] = { name = "UTF-16" , nulls = "2" } , 
	[ 2 ] = { name = "UTF-16BE" , nulls = "2" } , 
	[ 3 ] = { name = "UTF-8" , nulls = "1" } , 
}

local function readtextframe ( str )
	local t = vstruct.unpack ( "> encoding:u1 text:s" , str )
	local st = string.explode ( t.text )
	for i , v in ipairs ( st ) do
		st [ i ] = utf8 ( v , encodings [ t.encoding ].name )
	end
	return st
end

local framedecode = {
	["UFID"] = function ( str )
			return vstruct.unpack ( "> ownerid:z uniquefileid:s64" , str )
		end ,
		
	-- TEXT fields
	-- Identification frames
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
			local track , total = { } , { }
			for i , v in ipairs ( readtextframe ( str ) ) do
				track [ #track + 1 ] , total [ #total + 1 ] = string.match ( v , "([^/*])/?(.-*)" )
			end
			return { [ "tracknumber" ] = track , ["totaltracks"] = total }
		end ,
	["TPOS"] = function ( str ) -- Part of a set
			local disc , total = { } , { }
			for i , v in ipairs ( readtextframe ( str ) ) do
				disc [ #disc + 1 ] , total [ #total + 1 ] = string.match ( v , "([^/*])/?(.-*)" )
			end
			return { [ "discnumber" ] = disc , ["totaldiscs"] = total }
		end ,
	["TSST"] = function ( str ) -- Set subtitle
			return { [ "set subtitle" ] = readtextframe ( str ) }
		end ,
	["TSRC"] = function ( str ) -- ISRC
			return { [ "ISRC" ] = readtextframe ( str ) }
		end ,
	-- Involved persons frames
	["TPE1"] = function ( str ) -- Lead artist/Lead performer/Soloist/Performing group
		return { [ "artist" ] = readtextframe ( str ) }
	end ,
	["TPE2"] = function ( str ) -- Band/Orchestra/Accompaniment
		return { [ "band" ] = readtextframe ( str ) }
	end ,
	["TPE3"] = function ( str ) -- Conductor
		return { [ "conductor" ] = readtextframe ( str ) }
	end ,
	["TPE4"] = function ( str ) -- Interpreted, remixed, or otherwise modified by
		return { [ "remixed by" ] = readtextframe ( str ) }
	end ,
	["TOPE"] = function ( str ) -- Original artist/performer
		return { [ "original artist" ] = readtextframe ( str ) }
	end ,
	["TEXT"] = function ( str ) -- Lyricist/Text writer
		return { [ "writer" ] = readtextframe ( str ) }
	end ,
	["TOLY"] = function ( str ) -- Original lyricist/text writer
		return { [ "original writer" ] = readtextframe ( str ) }
	end ,
	["TCOM"] = function ( str ) -- Composer
		return { [ "composer" ] = readtextframe ( str ) }
	end ,
	["TMCL"] = function ( str ) -- Musician credits list
		local t , field = {} , ""
		for i , v in ipairs ( readtextframe ( str ) ) do
			if i % 2 == 1 then -- odd, field is instrument
				field = v .. " player"
				t [ field ] = t [ field ] or { }
			else -- even, is musician's name
				t [ field ] [ #t [ field ] ] = v
			end
		end
		return t
	end ,
	["TIPL"] = function ( str ) -- Involved people list
		local t , field = {} , ""
		for i , v in ipairs ( readtextframe ( str ) ) do
			if i % 2 == 1 then -- odd, field is instrument
				field = v
				t [ field ] = t [ field ] or { }
			else -- even, is musician's name
				t [ field ] [ #t [ field ] ] = v
			end
		end
		return t
	end ,
	["TENC"] = function ( str ) -- Encoded by
		return { [ "encoded by" ] = readtextframe ( str ) }
	end ,
	-- Derived and subjective properties frames
	["TBPM"] = function ( str ) -- BPM
		return { [ "bpm" ] = readtextframe ( str ) }
	end ,
	["TLEN"] = function ( str ) -- Length
		return { [ "length" ] = readtextframe ( str ) }
	end ,
	["TKEY"] = function ( str ) -- Initial key
		return { [ "musical key" ] = readtextframe ( str ) }
	end ,
	["TLAN"] = function ( str ) -- Language
		return { [ "language" ] = readtextframe ( str ) }
	end ,
	["TCON"] = function ( str ) -- Content type
		local t = readtextframe ( str )
		for k , v in ipairs ( t) do
			if v == "RX" then t [ k ] = "Remix"
			elseif v == "CR" then t [ k ] = "Cover" 
			elseif tonumber ( v ) then
				t [ k ] = genrelist [ tonumber ( v ) ]
			end
		end
		return { [ "genre" ] = t }
	end ,
	["TFLT"] = function ( str ) -- File Type
		return { [ "FIELD" ] = readtextframe ( str ) }
	end ,
	["TXXX"] = function ( str ) -- 
		return { [ "FIELD" ] = readtextframe ( str ) }
	end ,
	["TXXX"] = function ( str ) -- 
		return { [ "FIELD" ] = readtextframe ( str ) }
	end ,
	["TXXX"] = function ( str ) -- 
		return { [ "FIELD" ] = readtextframe ( str ) }
	end ,
	
	-- URL fields,
	["WCOM"] = function ( str ) -- Commerical information
		return { ["commercial information url"] = str }
	end ,
	["WCOP"] = function ( str ) -- Copyright/Legal information
		return { ["copyright url"] = str }
	end ,
	["WOAF"] = function ( str ) -- Official audio file webpage
		return { ["file webpage url"] = str }
	end ,
	["WOAR"] = function ( str ) -- Official artist/performer webpage
		return { ["artist webpage url"] = str }
	end ,
	["WOAS"] = function ( str ) -- Official audio source webpage
		return { ["source webpage url"] = str }
	end ,
	["WORS"] = function ( str ) -- Official Internet radio station homepage
		return { ["internet radio webpage url"] = str }
	end ,
	["WPAY"] = function ( str ) -- Payment
		return { ["payment url"] = str }
	end ,
	["WPUB"] = function ( str ) -- Publishers official webpage
		return { ["publisher url"] = str }
	end ,
	["WXXX"] = function ( str ) -- Custom
		return { ["custom url"] = str }
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
