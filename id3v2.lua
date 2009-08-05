--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local ipairs , next , pairs , pcall , require , select , setmetatable , tonumber , tostring , type , unpack = ipairs , next , pairs , pcall , require , select , setmetatable , tonumber , tostring , type , unpack
local ioopen , iostderr = io.open , io.stderr
local osremove , osrename = os.remove , os.rename
local tblconcat , tblinherit = table.concat , table.inherit
local strexplode = string.explode

module ( "lomp.fileinfo.id3v2" , package.see ( lomp ) )

pcall ( require , "luarocks.require" ) -- Activates luarocks if available.
local vstruct = require "vstruct"
local genrelist = require ( select ( 1 , ... ):match ( "(.*%.)[^.]+$" ) .. "genrelist" )

_NAME = "ID3v2 tag reader/writer"
-- Specifications:
 -- http://www.id3.org/id3v2.4.0-structure
 -- http://www.id3.org/id3v2.4.0-frames
 -- http://www.id3.org/id3v2.4.0-changes
 -- http://www.id3.org/id3v2.3.0
 -- http://www.id3.org/id3v2-00
 
local function desafesync ( tbl )
	local new , nexti = { } , 1
	for i = 1 , #tbl do
		if i % 8 ~= 0 then
			new [ nexti ] = tbl [ i ]
			nexti = nexti + 1
		end
	end
	return vstruct.implode ( new )
end
local function makesafesync ( int )
	local tbl = vstruct.explode ( int )
	local new , nexti = { } , 1
	for i = 1 , #tbl do
		if i % 8 == 0 then
			new [ nexti ] = false
			nexti = nexti + 1
		end
		new [ nexti ] = tbl [ i ]
		nexti = nexti + 1
	end
	return new
end

-- Table of Encodings according to the Id3standard, names match with iconv
local encodings = {
	[ 0 ] = { name = "ISO-8859-1" , nulls = "1" } , 
	[ 1 ] = { name = "UTF-16" , nulls = "2" } , 
	[ 2 ] = { name = "UTF-16BE" , nulls = "2" } , 
	[ 3 ] = { name = "UTF-8" , nulls = "1" } , 
}

local picturetypes = {
	[ 0x00 ] = "Other" ; 
	[ 0x01 ] = "32x32 pixels 'file icon' (PNG only)" ;
	[ 0x02 ] = "Other file icon" ;
	[ 0x03 ] = "Cover (front)" ;
	[ 0x04 ] = "Cover (back)" ;
	[ 0x05 ] = "Leaflet page" ;
	[ 0x06 ] = "Media (e.g. lable side of CD)" ;
	[ 0x07 ] = "Lead artist/lead performer/soloist" ;
	[ 0x08 ] = "Artist/performer" ;
	[ 0x09 ] = "Conductor" ;
	[ 0x0A ] = "Band/Orchestra" ;
	[ 0x0B ] = "Composer" ;
	[ 0x0C ] = "Lyricist/text writer" ;
	[ 0x0D ] = "Recording Location" ;
	[ 0x0E ] = "During recording" ;
	[ 0x0F ] = "During performance" ;
	[ 0x10 ] = "Movie/video screen capture" ;
	[ 0x11 ] = "A bright coloured fish" ;
	[ 0x12 ] = "Illustration" ;
	[ 0x13 ] = "Band/artist logotype" ;
	[ 0x14 ] = "Publisher/Studio logotype" ;
}

local function readheader ( fd )
	local t = vstruct.unpack ( "> ident:s3 version:u1 revision:u1 flags:m1 safesyncsize:m4" , fd )
	if ( t.ident == "ID3" or t.ident == "3DI" ) then
		t.size = desafesync ( t.safesyncsize )
		t.safesyncsize = nil -- Don't need to keep this.
		t.firstframeoffset = fd:seek ( "cur" )
		t.unsynched = t.flags [ 8 ]
		if t.version > 4 then
			return false , "Newer id3v2 version"
		elseif t.version == 4 then
			t.frameheadersize = 10
			t.hasextendedheader = t.flags [ 7 ]
			t.experimental = t.flags [ 6 ]
			t.isfooter = t.flags [ 5 ]
		elseif t.version == 3 then
			t.frameheadersize = 10
			t.hasextendedheader = t.flags [ 7 ]
			t.experimental = t.flags [ 6 ]
		elseif t.version == 2 then
			t.frameheadersize = 6
		end
		if t.hasextendedheader then
			local safesyncsize = vstruct.unpack ( "> safesyncsize:m4" , fd ).safesyncsize
			if t.version == 4 then
				local contents = fd:read ( desafesync ( safesyncsize ) - 4 )
				t.e = { }
				t.e.numflags = vstruct.unpack ( "> u1" , contents )
				t.e.flags = vstruct.unpack ( "> " .. t.e.numflags .. " * m4" , contents:sub ( 2 ) )
				for i , v in ipairs ( t.e.flags ) do
					v.tagisupdate = v [ 7 ]
					v.hascrc = v [ 6 ]
					v.hastagrestrictions = v [ 5 ]
				end
			elseif t.version == 3 then
				local contents = fd:read ( vstruct.implode ( safesyncsize ) )
				t.e = vstruct.unpack ( "> flags:{ m4 m4 } sizeofpadding:u4" , contents )
				t.e.hascrc = t.e.flags[1][8]
				if t.e.hascrc then -- Has CRC
					t.e.crc = contents:sub ( 13 , 17 )
				end
			else
				fd:seek ( "cur" , -4 )
			end
		end
		return t
	else
		return false , "Not an ID3v2 header/footer"
	end
end

local function twodigit ( str )
	str = str:trim ( )
	if str and #str == 1 then
		return "0" .. str
	elseif str and #str == 2 then
		return str
	else
		return nil
	end
end

local function interpretdatestamp ( str )
	str = str:trim ( )
	
	local tbl = { }
	local d , t = unpack ( strexplode ( str , "T" ) )
	local s , e , y = d:find ( "^%s*(%d%d%d%d)%f[^%d]" )
	if y then
		tbl.year = y
		d = d:sub ( e + 1 ):gsub( "^%s*(.-)%s*$", "%1" )
	end
	local s , e , month , day = d:find ( "^%s*(%d%d)%s*[/- ]%s*(%d%d)"  )
	if s then
		tbl.month = twodigit ( month )
		tbl.day = twodigit ( day )
		d = d:sub ( e + 1 ):gsub( "^%s*(.-)%s*$", "%1" ) -- Cut off month/date then remove any surrounding whitespace
	end
	if t and #t > 0 then
		tbl.time = t:gsub( "^%s*(.-)%s*$", "%1" )
	elseif d:match ( ":" ) then -- Has a colon in it (probably a time)
		-- t = HH:mm:ss of subset there-of
		tbl.time = d
		d = ""
	end
	if tbl.time then
		tbl.hour = twodigit ( tbl.time:match ( "^[^%d](%d?%d):" ) or tbl.time:match ( "^[^%d](%d?%d)$" ) )
		tbl.minute = twodigit ( tbl.time:match ( ":(%d?%d):" ) or tbl.time:match ( "^[^:]:(%d?%d)$" ) )
		tbl.second = twodigit ( tbl.time:match ( ":(%d?%d)[^%d]" ) or tbl.time:match ( ":(%d?%d)$" ) )
	end
	
	tbl.left = d
	
	return tbl
end

-- An index for how to convert internal tags to their id3v2 frame ids. returns a table where the index is the corresponding frame's id for the indexed id3 version
local frameencode = {
	[ "unique file id" ] = function ( tags , id3version )
		local id = { false , "UFI" , "UFID" , "UFID" }
		local t = { }
		for i , v in ipairs ( tags [ "unique file id" ] or { } ) do
			local ownerid = ( tags [ "owner id" ] or { } ) [ i ] or "http://www.id3.org/dummy/ufid.html"
			t [ i ] = ascii ( ownerid , "UTF-8" ) .. "\0" .. v
		end
		return { { id [ id3version ] , t } } , false
	end ,
	[ "owner id" ] = function () return { } , false end ,
	[ "content group" ] = { false , "TT1" , "TIT1" , "TIT1" } ,
	[ "title" ] = { false , "TT2" , "TIT2" , "TIT2" } ,
	[ "subtitle" ] = { false , "TT3" , "TIT3" , "TIT3" } ,
	[ "album" ] = { false , "TAL" , "TALB" , "TALB" } ,
	[ "original album" ] = { false , "TOT" , "TOAL" , "TOAL" } ,
	[ "tracknumber" ] = function ( tags , id3version )
		local t = { }
		for i , v in ipairs ( tags [ "tracknumber" ] or { } ) do
			if tags [ "totaltracks" ] and tags [ "totaltracks" ] [ i ] then
				t [ i ] = tostring ( v ) .. "/" .. tags [ "totaltracks" ] [i]
			else
				t [ i ] = tostring ( v )
			end
		end
		local id = { false , "TRK" , "TRCK" , "TRCK" }
		return { { id [ id3version ] , t } } , false
	end ,
	[ "totaltracks" ] = function ( tags , id3version )
		local spare = #tags [ "totaltracks" ] - #tags [ "tracknumber" ]
		if spare > 0 then -- If not going to put in with tracknumber in TRCK, put in TXXX
			local id = { false , "TXX" , "TXXX" , "TXXX" }
			return { { id [ id3version ] , { unpack ( tags [ "totaltracks" ] , #tags [ "tracknumber" ] + 1 ) } } }, false
		else
			return { } , false
		end
	end ,
	[ "discnumber" ] = function ( tags , id3version )
		local t = { }
		for i , v in ipairs ( tags [ "discnumber" ] or { } ) do
			if tags [ "totaldiscs" ] and tags [ "totaldiscs" ] [ i ] then
				t [ i ] = tostring ( v ) .. "/" .. tags [ "totaldiscs" ] [i]
			else
				t [ i ] = tostring ( v )
			end	
		end
		local id = { false , "TPA" , "TPOS" , "TPOS" }
		return { { id [ id3version ] , t } } , false
	end ,	
	[ "totaldiscs" ] = function ( tags , id3version )
		local spare = #tags [ "totaldiscs" ] - #tags [ "discnumber" ]
		if spare > 0 then -- If not going to put in with discnumber in TPOS, put in TXXX
			local id = { false , "TXX" , "TXXX" , "TXXX" }
			return { { id [ id3version ] , { unpack ( tags [ "totaldiscs" ] , #tags [ "discnumber" ] + 1 ) } } }, false
		else
			return { } , false
		end
	end ,
	[ "set subtitle" ] = { false , "TXX" , "TSST" , "TSST" } ,
	[ "isrc" ] = { false , "TRC" , "TSRC" , "TSRC" } ,

	[ "artist" ] = { false , "TP1" , "TPE1" , "TPE1" } ,
	[ "band" ] = { false , "TP2" , "TPE2" , "TPE2" } ,
	[ "conductor" ] = { false , "TP3" , "TPE3" , "TPE3" } ,
	[ "remixed by" ] = { false , "TP4" , "TPE4" , "TPE4" } ,
	[ "original artist" ] = { false , "TOA" , "TOPE" , "TOPE" } ,
	[ "writer" ] = { false , "TXT" , "TEXT" , "TEXT" } ,
	[ "original writer" ] = { false , "TOL" , "TOLY" , "TOLY" } ,
	[ "composer" ] = { false , "TCM" , "TCOM" , "TCOM" } ,
	-- TODO: TMCL (list) -- Some sort of metatable? need to match things ending in "player"
	-- TODO: TIPL (list) -- metatable? could be anything though...
	[ "encoded by" ] = { false , "TEN" , "TENC" , "TENC" } ,
	
	[ "bpm" ] = { false , "TBP" , "TBPM" , "TBPM" } ,
	-- Don't do length, its a special field/tag
	[ "musical key" ] = { false , "TKE" , "TKEY" , "TKEY" } ,
	[ "language" ] = { false , "TLA" , "TLAN" , "TLAN" } ,
	[ "genre" ] = { false , "TCO" , "TCON" , "TCON" } , -- Special
	[ "file type" ] = { false , "TFT" , "TFLT" , "TFLT" } , -- Special
	[ "media type" ] = { false , "TMT" , "TMED" , "TMED" } , -- Special
	[ "mood" ] = { false , "TXX" , "TXXX" , "TMOO" } ,
	[ "copyright" ] = { false , "TCR" , "TCOP" , "TCOP" } , -- Special
	[ "produced" ] = { false , "TXX" , "TXXX" , "TPRO" } , -- Special
	[ "publisher" ] = { false , "TPB" , "TPUB" , "TPUB" } ,
	[ "owner" ] = { false , "TXX" , "TOWN" , "TOWN" } ,
	[ "radio station" ] = { false , "TXX" , "TRSN" , "TRSN" } ,
	[ "radio station owner" ] = { false , "TXX" , "TRSO" , "TRSP" } ,
	
	[ "original filename" ] = { false , "TOF" , "TOFN" , "TOFN" } ,
	--[ "delay" ] = { false , "TDLY" , -- Special
	[ "encoding time" ] = { false , "TXX" , "TXXX" , "TDEN" } , -- Special: Time
	[ "original release time" ] = { false , "TOR" , "TORY" , "TDOR" } , -- Special: Time
	[ "date" ] = function ( tags , id3version )
		if id3version == 4 then 
			return { { "TDRC" , tags [ "date" ] } } , false
		else 
			local year , date , time , recording , datadiscarded = { encoding = 0 } , { encoding = 0 } , { encoding = 0 } , { } , false
			for i , v in ipairs ( tags [ "date" ] ) do
				local d = interpretdatestamp ( ascii ( v , "UTF-16" ) )
				year [ #year + 1 ] = d.year
				date [ #date + 1 ] = d.month and ( ( d.day or "00" ) .. d.month )
				time [ #time + 1 ] = d.hour and d.hour .. ( d.minute or "00" )
				if d.left and #d.left > 0 then recording [ #recording + 1 ] = d.left end
			end
			local yearid = { false , "TYE" , "TYER" }
			local dateid = { false , "TDA" , "TDAT" }
			local timeid = { false , "TIM" , "TIME" }
			local recordingdatesid = { false , "TRD" , "TRDA" }
			
			local t , nexti = { } , 1
			if #year > 0 then
				t [ nexti ] = { yearid [ id3version ] , year }
				nexti = nexti + 1
			end
			if #date > 0 then
				t [ nexti ] = { dateid [ id3version ] , date }
				nexti = nexti + 1
			end
			if #time > 0 then
				t [ nexti ] = { timeid [ id3version ] , time } 
				nexti = nexti + 1
			end
			if #recording > 0 then
				t [ nexti ] = { recordingdatesid [ id3version ] , recording }
				nexti = nexti + 1
			end
			
			return t , datadiscarded
		end
	end ,
	[ "release time" ] = { false , "TXX" , "TXXX" , "TDRL" } , -- Special: Time
	[ "tagged" ] = { false , "TXX" , "TXXX" , "TDTG" } , -- Special: Time
	[ "encoder settings" ] = { false , "TSS" , "TSSE" , "TSSE" } ,
	[ "album sort order" ] = { false , "TXX" , "TXXX" , "TSOA" } ,
	[ "performer sort order" ] = { false , "TXX" , "TXXX" , "TSOP" } ,
	[ "title sort order" ] = { false , "TXX" , "TXXX" , "TSOT" } ,
	
	[ "commercial information url" ] = { false , "WCM" , "WCOM" , "WCOM" } ,
	[ "copyright url" ] = { false , "WCP" , "WCOP" , "WCOP" } ,
	[ "file webpage url" ] = { false , "WAF" , "WOAF" , "WOAF" } ,
	[ "artist webpage url" ] = { false , "WAR" , "WOAR" , "WOAR" } ,
	[ "source webpage url" ] = { false , "WAS" , "WOAS" , "WOAS" } ,
	[ "internet radio webpage url" ] = { false , "WXX" , "WORS" , "WORS" } ,
	[ "payment url" ] = { false , "WXX" , "WPAY" , "WPAY" } ,
	[ "publisher url" ] = { false , "WPB" , "WPUB" , "WPUB" } ,
	
	[ "cd toc" ] = { false , "MCI" , "MDCI" , "MDCI" } ,
	
	-- ETCO -- Event timing codes
	-- MLLT -- Not applicable
	-- SYTC -- Synchronised tempo codes
	
	--[[[ "lyrics" ] = function ( tags )
		-- TODO
		return "USLT" , nil , true
	end ,--]]
	
	-- SYLT -- Synchronised lyrics/text
	
	-- Comment
	["comment"] = function ( tags , id3version )
		local e = 1 -- Encoding, 1 is UTF-16
		local language = "eng" -- 3 character language
		local t = { }
		for i , v in ipairs ( tags [ "comment" ] ) do
			local shortdescription = utf16 ( i ) -- UTF-16 string
			t [ #t + 1 ] = e:char ( ) .. language .. shortdescription .. ( "\0" ):rep ( encodings [ e ].nulls ) .. utf16 ( v , "UTF-8" )
		end
		local id = { false , "COM" , "COMM" , "COMM" }
		return { { id [ id3version ] , t } } , false
	end ,
	
	-- RVA2 -- Relative volume adjustment (2)
	-- EQU2 -- Equalisation (2)
	-- RVRB -- Reverb
	
	-- APIC -- Attached pictures
	
	-- GEOB -- General encapsulated object

	-- PCNT -- Play counter
	-- POPM -- Popularimeter
	
	-- RBUF -- Recommended buffer size

	-- AENC -- Audio encryption

	-- LINK -- Linked information

	-- POSS -- Position synchronisation frame
	
	-- Terms of use frame
	[ "terms of use" ] = function ( tags , id3version )
		local e = 1 -- Encoding, 1 is UTF-16
		local language = "eng" -- 3 character language
		local s = e:char ( ) .. language .. utf16 ( tags [ "terms of use" ] [ 1 ] , "UTF-8")
		
		local id = { false , "TXX" , "USER" , "USER" }
		return { id [ id3version ] , { s } } , toboolean ( tags [ "terms of use" ] [ 2 ] )
	end ,
	
	-- OWNE -- Ownership frame
	-- COMR -- Commericial frame
	
	-- ENCR -- Encryption method registration
	-- GRID -- Group identification registration

	-- PRIV -- Private frame
	-- SIGN -- Signature frame

	-- SEEK -- Seek frame
	
	-- ASPI -- Audio seek point index
}

local function readtextframe ( str )
	local encoding = encodings [ str:byte ( 1 , 1 ) ]
	local text = str:sub ( 2 )
	local terminator = ( "\0" ):rep ( encoding.nulls )
	local st = strexplode ( text , terminator , true )
	local r , index = { } , 0
	for i , v in ipairs ( st ) do
		if #v ~= 0 then
			index = index + 1
			r [ index ] = utf8 ( v , encoding.name )
		end
	end
	return r
end

local ignoreframes = setmetatable ( 
	{ -- Ignore these frames
		["NCON"] = true ; -- MusicMatch adds stuff in an unknown format in the NCON frame. These can get quite large.
		["TCMP"] = true ; -- Itunes: When you check the "Part of a compilation" checkbox on the Info tab of the tag editor form, iTunes will add a non-standard TCMP frame to the tag.
		["TBPM"] = true ; -- Mixmeister BPM analyzer (among others it seems) writes floating point values to the TBPM (Beats Per Minute) frame.
		["CM1"] = true ; -- Tag that seems to pop its head in randomly
	} , { __index = function ( t , id )
		local a = id:sub ( 1 , 1 )
		if a == "X" or a == "Y" or a == "Z" then return true end -- Frames starting with X Y or Z are experimental
	end } 
)

local framedecode = {
	["UFID"] = function ( str )
			local t = vstruct.unpack ( "> ownerid:z uniquefileid:s64" , str )
			return { [ "owner id" ] = { utf8 ( t.ownerid , "ISO-8859-1" ) } , { [ "unique file id" ] = t.uniquefileid  } }
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
			local track , total , totnexti = { } , { } , 1
			for i , v in ipairs ( readtextframe ( str ) ) do
				track [ #track + 1 ] , total [ totnexti ] = v:match ( "([^/]*)/?(.*)" )
				if total [ totnexti ] and total [ totnexti ] == "" then total [ totnexti ] = nil else totnexti = totnexti + 1 end -- string match still fills in the total array
			end
			if not next ( total ) then total = nil end
			return { [ "tracknumber" ] = track , ["totaltracks"] = total }
		end ,
	["TPOS"] = function ( str ) -- Part of a set
			local disc , total , totnexti = { } , { } , 1
			for i , v in ipairs ( readtextframe ( str ) ) do
				disc [ #disc + 1 ] , total [ totnexti ] = v:match ( "([^/]*)/?(.*)" )
				if total [ totnexti ] and total [ totnexti ] == "" then total [ totnexti ] = nil else totnexti = totnexti + 1 end -- string match still fills in the total array
			end
			if not next ( total ) then total = nil end
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
		local t , field = {}
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
		local t , field = {}
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
		local t = { }
		for k , v in ipairs ( readtextframe ( str ) ) do
			if tonumber ( v ) then 
				t [ #t + 1 ] = tonumber ( v ) / 1000 
			end
		end
		return { [ "length" ] = t }
	end ,
	["TKEY"] = function ( str ) -- Initial key
		return { [ "musical key" ] = readtextframe ( str ) }
	end ,
	["TLAN"] = function ( str ) -- Language
		return { [ "language" ] = readtextframe ( str ) }
	end ,
	["TCON"] = function ( str ) -- Content type
		local t = readtextframe ( str )
		for i , v in ipairs ( t) do
			if v == "RX" then t [ i ] = "Remix"
			elseif v == "CR" then t [ i ] = "Cover" 
			elseif tonumber ( v ) then
				t [ i ] = genrelist [ tonumber ( v ) ]
			else
				t [ i ] = v
			end
		end
		return { [ "genre" ] = t }
	end ,
	["TFLT"] = function ( str ) -- File Type
		local t = readtextframe ( str )
		if not next ( t ) then t[1] = "MPG" end -- TODO: interpret further
		return { [ "file type" ] = t }
	end ,
	["TMED"] = function ( str ) -- Media type
		return { [ "media type" ] = readtextframe ( str ) } -- TODO: interpret media type
	end ,
	["TMOO"] = function ( str ) -- Mood
		return { [ "mood" ] = readtextframe ( str ) }
	end ,
	-- Rights and license frames
	["TCOP"] = function ( str ) -- Copyright message
		local c , nexti = { } , 1
		for i , v in ipairs ( readtextframe ( str ) ) do
			local m = v:match ( "(%d%d%d%d)%s" )
			if m then 
				c [ nexti ] = m
				nexti = nexti + 1
			end
		end
		return { [ "copyright" ] =  c }
	end ,
	["TPRO"] = function ( str ) -- Produced notice
		local p , nexti = { } , 1
		for i , v in ipairs ( readtextframe ( str ) ) do
			local m = v:match ( "(%d%d%d%d)%s" )
			if m then 
				p [ nexti ] = m
				nexti = nexti + 1
			end
		end
		return { [ "produced" ] =p }
	end ,
	["TPUB"] = function ( str ) -- Publisher
		return { [ "publisher" ] = readtextframe ( str ) }
	end ,
	["TOWN"] = function ( str ) -- File owner/licensee
		return { [ "owner" ] = readtextframe ( str ) }
	end ,
	["TRSN"] = function ( str ) -- Internet radio station name
		return { [ "radio station" ] = readtextframe ( str ) }
	end ,
	["TRSO"] = function ( str ) -- Internet radio station owner
		return { [ "radio station owner" ] = readtextframe ( str ) }
	end ,
	-- Other text frames
	["TOFN"] = function ( str ) -- Original filename
		return { [ "original filename" ] = readtextframe ( str ) }
	end ,
	["TDLY"] = function ( str ) -- Playlist delay
		-- Unsupported/Pointless
		-- return { [ "delay" ] = readtextframe ( str ) }
	end ,
	["TDEN"] = function ( str ) -- Encoding time
		-- TODO: is a timestamp
		return { [ "encoding time" ] = readtextframe ( str ) }
	end ,
	["TDOR"] = function ( str ) -- Original release time
		-- TODO: is a timestamp
		return { [ "original release time" ] = readtextframe ( str ) }
	end ,
	["TDRC"] = function ( str ) -- Recording time
		-- TODO: is a timestamp
		return { [ "date" ] = readtextframe ( str ) }
	end ,
	["TDRL"] = function ( str ) -- Release time
		-- TODO: is a timestamp
		return { [ "release time" ] = readtextframe ( str ) }
	end ,
	["TDTG"] = function ( str ) -- Tagging time
		-- TODO: is a timestamp
		return { [ "tagged" ] = readtextframe ( str ) }
	end ,
	["TSSE"] = function ( str ) -- Software/Hardware and settings used for encoding
		return { [ "encoder settings" ] = readtextframe ( str ) }
	end ,
	["TSOA"] = function ( str ) -- Album sort order
		return { [ "album sort order" ] = readtextframe ( str ) }
	end ,
	["TSOP"] = function ( str ) -- Performer sort order
		return { [ "performer sort order" ] = readtextframe ( str ) }
	end ,
	["TSOT"] = function ( str ) -- Title sort order
		return { [ "title sort order" ] = readtextframe ( str ) }
	end ,
	-- Special case, TXXX
	["TXXX"] = function ( str ) -- Custom text frame
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep (  encoding.nulls )
		local s , e = str:find ( terminator , 2 , true )
		if not s then return false end
		local field = ascii ( str:sub ( 2 , e - 1 ) , encoding.name ):lower ( )
		local text = str:sub ( e + 1 )
		
		local st = strexplode ( text , terminator , true )
		
		local r = { }
		for i , v in ipairs ( st ) do
			if #v ~= 0 then
				r [ #r + 1 ] = utf8 ( v , encoding.name )
			end
		end
		return { [ field ] =  r }
	end ,
	
	-- URL fields,
	["WCOM"] = function ( str ) -- Commerical information
		return { ["commercial information url"] = { str } }
	end ,
	["WCOP"] = function ( str ) -- Copyright/Legal information
		return { ["copyright url"] = { str } }
	end ,
	["WOAF"] = function ( str ) -- Official audio file webpage
		return { ["file webpage url"] = { str } }
	end ,
	["WOAR"] = function ( str ) -- Official artist/performer webpage
		return { ["artist webpage url"] = { str } }
	end ,
	["WOAS"] = function ( str ) -- Official audio source webpage
		return { ["source webpage url"] = { str } }
	end ,
	["WORS"] = function ( str ) -- Official Internet radio station homepage
		return { ["internet radio webpage url"] = { str } }
	end ,
	["WPAY"] = function ( str ) -- Payment
		return { ["payment url"] = { str } }
	end ,
	["WPUB"] = function ( str ) -- Publishers official webpage
		return { ["publisher url"] = { str } }
	end ,
	["WXXX"] = function ( str ) -- Custom
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep ( encoding.nulls )
		local s , e = str:find ( terminator , 2 , true )
		if not s then return false end
		local field = ascii ( str:sub ( 2 , e - 1 ) , encoding.name )
		local url = str:sub ( e + 1 )
		
		if #field == 0 or not field:find ( "%w" )  then 
			field = "url"
		else 
			field = field:lower ( )
			if not field:find ( "url$" ) then
				field = field .. " url"
			end
		end
		return { [ field ] = { url } }
	end ,	
	
	
	-- Misc fields
	["MCDI"] = function ( str ) -- Music CD identifier
		return { [ "cd toc"] = { str } }
	end ,
	
	["ETCO"] = function ( str ) -- Event timing codes
	end ,
	
	["MLLT"] = function ( str ) -- Not applicable
	end ,
	
	["SYTC"] = function ( str ) -- Synchronised tempo codes
	end ,
	
	-- Unsynchronised lyrics/text transcription
	["USLT"] = function ( str )
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep ( encoding.nulls )
		local language = str:sub ( 2 , 4 )
		local s , e = str:find ( terminator , 5 , true )
		if not s then return false end
		local description = str:sub ( 5 , e - 1 )
		local text = str:sub ( e + 1 )

		-- TODO: Can we do anything with language or description?
		return { [ "lyrics" ] = { text } }
	end ,
	
	["SYLT"] = function ( str ) -- Synchronised lyrics/text
	end ,
	
	-- Comment
	["COMM"] = function ( str )
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep ( encoding.nulls )
		local language = str:sub ( 2 , 4 )
		local s , e = str:find ( terminator , 5 , true )
		if not s then return false end
		local description = str:sub ( 5 , e - 1 )
		local text = str:sub ( e + 1 )
		text = utf8 ( text , encoding.name )
		-- TODO: Can we do anything with language or description?
		return { [ "comment" ] = { text } }
	end ,
	
	["RVA2"] = function ( str ) -- Relative volume adjustment
	end ,
	
	["EQU2"] = function ( str ) -- Equalisation (2)
	end ,
	
	["RVRB"] = function ( str ) -- Reverb
	end ,
	
	["APIC"] = function ( str ) -- Attached pictures
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep ( encoding.nulls )
		local a , b , mimetype = str:find ( "([^%z]*)" , 2 )
		local picturetype = str:byte ( b + 2 , b + 2 )
		local s , e = str:find ( terminator , b + 3 , true )
		local description = str:sub ( b + 3 , e - 1 )
		local picturedata = str:sub ( e + 1 )
		if mimetype == "-->" then updatelog ( "Id3 APIC mimetype is a link!" , 5 )
		elseif not mimetype:find ( "/" ) then mimetype = "image/" .. mimetype end
		picturetype = picturetypes [ picturetype ] or picturetype
		-- TODO: use pictures
	end ,
	
	["GEOB"] = function ( str ) -- General encapsulated object
	end ,

	["PCNT"] = function ( str ) -- Play counter
	end ,

	["POPM"] = function ( str ) -- Popularimeter
	end ,

	["RBUF"] = function ( str ) -- Recommended buffer size
	end ,

	["AENC"] = function ( str ) -- Audio encryption
	end ,

	["LINK"] = function ( str ) -- Linked information
	end ,

	["POSS"] = function ( str ) -- Position synchronisation frame
	end ,

	["USER"] = function ( str ) -- Terms of use frame
		local encoding = encodings [ str:byte ( 1 , 1 ) ]
		local terminator = ( "\0" ):rep ( encoding.nulls )
		local language = str:sub ( 2 , 4 )
		local s , e = str:find ( terminator , 5 , true )
		if not s then return false end
		local description = str:sub ( 5 , e - 1 )
		local text = str:sub ( e + 1 )
		
		-- TODO: Can we do anything with language or description?
		return { [ "terms of use" ] = { text } }
	end ,

	["OWNE"] = function ( str ) -- Ownership frame
	end ,
	
	["COMR"] = function ( str ) -- Commericial frame
	end ,
	
	["ENCR"] = function ( str ) -- Encryption method registration
	end ,
	
	["GRID"] = function ( str ) -- Group identification registration
	end ,
	
	["PRIV"] = function ( str ) -- Private frame
	end ,
	
	["SIGN"] = function ( str ) -- Signature frame
	end ,

	["SEEK"] = function ( str ) -- Seek frame
	end ,

	["ASPI"] = function ( str ) -- Audio seek point index
	end ,
}
do -- ID3v2.3 frames (Older frames)
	framedecode["EQUA"] = function ( str ) -- Equalization
	end
	framedecode["IPLS"] = function ( str ) -- Involved people list
	end
	framedecode["RVAD"] = function ( str ) -- Relative volume adjustment
	end
	
	framedecode["TDAT"] = function ( str ) -- Date in DDMM form
		local t = { }
		for i , v in ipairs ( readtextframe ( str ) ) do
			local day = twodigit ( v:sub ( v , 1 , 2 ) )
			local month = twodigit ( v:sub ( 3 , 4 ) )
			t [ #t + 1 ] = month .. "-" .. day
		end
		return { [ "date" ] = t }
	end
	framedecode["TIME"] = function ( str ) -- Time
		return { [ "date" ] = readtextframe ( str ) }
	end
	framedecode["TORY"] = function ( str ) -- Year
		return { [ "original release time" ] = readtextframe ( str ) }
	end
	framedecode["TRDA"] = function ( str ) -- Recording Dates
		return { [ "date" ] = readtextframe ( str ) }
	end
	framedecode["TSIZ"] = function ( str ) -- Size -- Pointless, completely deprecated
	end
	framedecode["TYER"] = function ( str ) -- Year
		return { [ "date" ] = readtextframe ( str ) }
	end
end
do -- ID3v2.2 frames -- Generally exactly maps to ID3v2.3 standard
	framedecode["BUF"] = framedecode["RBUF"]
	
	framedecode["CNT"] = framedecode["PCNT"]
	framedecode["COM"] = framedecode["COMM"]
	framedecode["CRA"] = framedecode["AENC"]
	--framedecode["CRM"] = 
	framedecode["EQU"] = framedecode["EQUA"]
	framedecode["ETC"] = framedecode["ETCO"]
	
	framedecode["GEO"] = framedecode["GEOB"]
	
	framedecode["IPL"] = framedecode["IPLS"]
	
	framedecode["MCI"] = framedecode["MDCI"]
	framedecode["MLL"] = framedecode["MLLT"]
	
	-- framedecode["PIC"] = 
	framedecode["POP"] = framedecode["POPM"]
	framedecode["REV"] = framedecode["RVRB"]
	framedecode["RVA"] = framedecode["RVAD"]
	
	framedecode["SLT"] = framedecode["SYLT"]
	framedecode["STC"] = framedecode["SYTC"]
	
	framedecode["TAL"] = framedecode["TALB"]
	framedecode["TBP"] = framedecode["TBPM"]
	framedecode["TCM"] = framedecode["TCOM"]
	framedecode["TCO"] = framedecode["TCON"]
	framedecode["TCR"] = framedecode["TCOP"]
	framedecode["TDA"] = framedecode["TDAT"]
	framedecode["TDY"] = framedecode["TDLY"]
	framedecode["TEN"] = framedecode["TENC"]
	framedecode["TFT"] = framedecode["TFLT"]
	framedecode["TIM"] = framedecode["TIME"]
	framedecode["TKE"] = framedecode["TKEY"]
	framedecode["TLA"] = framedecode["TLAN"]
	framedecode["TLE"] = framedecode["TLEN"]
	framedecode["TMT"] = framedecode["TMED"]
	framedecode["TOA"] = framedecode["TOPE"]
	framedecode["TOF"] = framedecode["TOFN"]
	framedecode["TOL"] = framedecode["TOLY"]
	framedecode["TOR"] = framedecode["TORY"]
	framedecode["TOT"] = framedecode["TOAL"]
	framedecode["TP1"] = framedecode["TPE1"]
	framedecode["TP2"] = framedecode["TPE2"]
	framedecode["TP3"] = framedecode["TPE3"]
	framedecode["TP4"] = framedecode["TPE4"]
	framedecode["TPA"] = framedecode["TPOS"]
	framedecode["TPB"] = framedecode["TPUB"]
	framedecode["TRC"] = framedecode["TSRC"]
	framedecode["TRD"] = framedecode["TRDA"]
	framedecode["TRK"] = framedecode["TRCK"]
	framedecode["TSI"] = framedecode["TSIZ"]
	framedecode["TSS"] = framedecode["TSSE"]
	framedecode["TT1"] = framedecode["TIT1"]
	framedecode["TT2"] = framedecode["TIT2"]
	framedecode["TT3"] = framedecode["TIT3"]
	framedecode["TXT"] = framedecode["TEXT"]
	framedecode["TXX"] = framedecode["TXXX"]
	framedecode["TYE"] = framedecode["TYER"]
	
	framedecode["UFI"] = framedecode["UFID"]
	framedecode["ULT"] = framedecode["USLT"]
	
	framedecode["WAF"] = framedecode["WOAF"]
	framedecode["WAR"] = framedecode["WOAR"]
	framedecode["WAS"] = framedecode["WOAS"]
	framedecode["WCM"] = framedecode["WCOM"]
	framedecode["WCP"] = framedecode["WCOP"]
	framedecode["WPB"] = framedecode["WPUB"]
	framedecode["WXX"] = framedecode["WXXX"]
end

-- Read frame header
local function readframeheader ( fd , header )
	if header.version >= 3 then
		local t = vstruct.unpack ( "> id:s4 safesyncsize:m4 statusflags:m1 formatflags:m1" , fd )
		if t.id == "\0\0\0\0" then -- padding
			fd:seek ( "cur" , -header.frameheadersize ) -- Rewind to what would have been start of frame
			return false , "padding"
		else
			t.framesize = vstruct.implode ( t.safesyncsize )
			if header.version == 4 then -- id3v2.4
				t.size = desafesync ( t.safesyncsize )
				-- Flags: %0abc0000 %0h00kmnp
				t.tagalterpreserv = t.statusflags [ 7 ]
				t.filealterpreserv = t.statusflags [ 6 ]
				t.readonly = t.statusflags [ 5 ]
				t.compressed = t.formatflags [  4 ]
				t.encrypted = t.formatflags [ 3 ]
				t.grouped = t.formatflags [ 7 ]
				t.unsynched = t.formatflags [ 2 ]
				t.hasdatalength = t.formatflags [ 1 ]
				if t.grouped then
					t.size = t.size - 1
					t.groupingbyte = fd:read ( 1 )
				end
				if t.encrypted then
					t.size = t.size - 1
					t.encryption = fd:read ( 1 )
				end
				if t.hasdatalength then
					t.size = t.size - 4
					local d = vstruct.unpack ( ">m4" , fd ) [ 1 ]
					t.datalength = desafesync ( d )
				end
			elseif header.version <= 3 then -- id3v2.3
				t.size = t.framesize
				-- Flags: %abc00000 %ijk00000 
				t.tagalterpreserv = t.statusflags [ 8 ]
				t.filealterpreserv = t.statusflags [ 7 ]
				t.readonly = t.statusflags [ 6 ]
				t.compressed = t.formatflags [  8 ]
				t.encrypted = t.formatflags [ 7 ]
				t.grouped = t.formatflags [ 6 ]
				if t.compressed then
					t.size = t.size - 4
					t.datalength = fd:read ( 4 )
				end
				if t.encrypted then
					t.size = t.size - 1
					t.encryption = fd:read ( 1 ) 
				end
				if t.grouped then 
					t.size = t.size - 1
					t.groupingbyte = fd:read ( 1 ) 
				end
			end
			t.startcontent = fd:seek ( "cur" )
			t.startheader = fd:seek ( "cur" , -header.frameheadersize )
			t.safesyncsize = nil
			return t
		end
	elseif header.version == 2 then -- id3v2.2
		local t = vstruct.unpack ( "> id:s3 size:u3" , fd )
		if t.id == "\0\0\0" then -- padding
			fd:seek ( "cur" , -header.frameheadersize ) -- Rewind to what would have been start of frame
			return false , "padding"
		else
			t.framesize = t.size
			t.startcontent = fd:seek ( "cur" )
			t.startheader = fd:seek ( "cur" , -header.frameheadersize )
			return t
		end
	end
end

local function decodeframe ( frame , header , frameheader )
	if frameheader.unsynched then -- Unsynch-safe the frame content
		frame = frame:gsub ( "\255%z([224-\255])" ,  "\255%1" )
			:gsub ( "\255%z%z" ,  "\255\0" )
	end
	if frameheader.encrypted then
		return false , "Encrypted frame, cannot decrypt"
	end
	if frameheader.compressed then -- Frame compressed with zlib
		local zlibok , z = pcall ( require , "zlib" )
		if zlibok and z then
			frame = z.decompress ( frame )
		else
			return false , "Compressed frame and no zlib available"
		end
	end
	return frame
end

-- Trys to find an id3tag in given file handle
 -- Returns the start of the tag as a file offset
function find ( fd )
	-- Look at start of file
	fd:seek ( "set" )
	local h
	h = readheader ( fd )
	if h then 
		fd:seek ( "set" )
		return 0 , h 
	end
	-- Look at end of file
	fd:seek ( "end" , -10 )
	h = readheader ( fd )
	if h then
		local offsetfooter = ( h.size + 20 ) -- Offset to start of footer from end of file
		local offsetheader = fd:seek ( "end" , -offsetfooter) 
		h = readheader ( fd )
		fd:seek ( "set" , offsetheader ) 
		if h and h.isfooter then return offsetheader , h end
	end
	-- No tag
	return false
end

function info ( fd , location , header )
	if not location then 
		location , header = find ( fd )
		fd:seek ( "cur" , header.firstframeoffset )
	elseif header then
		fd:seek ( "set" , location + header.firstframeoffset )
	else
		fd:seek ( "set" , location  )
		header = readheader ( fd )
	end
	
	local tags , extra = { } , { id3v2version = header.version }
	
	local id3tag = fd:read ( header.size )
	local sd = vstruct.cursor ( id3tag )
	while sd:seek ( "cur" ) < ( #id3tag - header.frameheadersize ) do
		local ok , err = readframeheader ( sd , header )
		if ok then
			sd:seek ( "set" , ok.startcontent )
			ok.unsynched = ok.unsynched or header.unsynched -- Frame is unsynched if flag set in frameheader or id3header
			local frame , err = decodeframe ( sd:read ( ok.size ) , header , ok )
			if frame then
				if framedecode [ ok.id ] then
					--updatelog ( _NAME .. ": v" .. header.version .. " Read frame: " .. ok.id .. " Size: " .. ok.size , 5 )
					local newtags = framedecode [ ok.id ] ( frame )
					tblinherit ( tags , ( newtags or { } ) , true )
				elseif ignoreframes [ ok.id ] then
					updatelog ( _NAME .. ": v" .. header.version .. " Frame Ignored: " .. ok.id .. " Size: " .. ok.size , 5 )
				else -- We don't know of this frame type
					local content
					if ok.size > 100 then
						content = frame:sub ( 1 , 80 ) .. " \t ...(Trimmed due to excessive length)"
					else
						content = frame
					end
					updatelog ( _NAME .. ": v" .. header.version .. " Unknown frame: " .. ok.id .. " Size: " .. ok.size .. " Contents: " .. content , 4 )
				end
			end
		elseif err == "padding" then
			break
		else
			updatelog ( err , 5 )
		end
	end
	return tags , extra
end

local function genWXXXframe ( humanname , v , id3version )
	local e = v.encoding or 1 -- Encoding, 1 is UTF-16
	humanname = humanname:match ( "(.*)url" ) or humanname
	local s = e:char ( ) .. utf16 ( humanname , "ISO-8859-1" ) .. ( "\0" ):rep ( encodings [ e ].nulls ) .. ascii ( v [ 1 ] or "" , "UTF-8" )
	return { id = ( ( id3version == 2 ) and "WXX" ) or "WXXX" , contents = s } , ( toboolean ( v [ 2 ] ) )
end
local function genTXXXframe ( humanname , v , id3version )
	local e = v.encoding or 1 -- Encoding, 1 is UTF-16
	local s = e:char ( ) .. utf16 ( humanname , "ISO-8859-1" ) .. ( "\0" ):rep ( encodings [ e ].nulls ) .. utf16 ( v [ 1 ] , "UTF-8" )
	for i =2 , #v do
		s = s .. ( "\0" ):rep ( encodings [ e ].nulls ) .. utf16 ( v [ i ] , "UTF-8" )
	end
	return { id = ( ( id3version == 2 ) and "TXX" ) or "TXXX" , contents = s }
end
-- Make frames from tags
 -- Returns a table where each entry is a frame
 local function generateframe ( humanname , r , v , id3version )
	local datadiscarded
	if type ( r ) == "string" and v and v [ 1 ] then
		if r:sub ( 1 , 1 ) == "T" then
			if r == "TXXX" or r == "TXX" then -- Standard defined Text field
				return genTXXXframe ( humanname , v , id3version )
			else
				local e = v.encoding or 1 -- Encoding, 1 is UTF-16
				local s = e:char ( ) .. utf16 ( v [ 1 ] , "UTF-8" )
				for i =2 , #v do
					s = s .. ( "\0" ):rep ( encodings [ e ].nulls ) .. utf16 ( v [ i ] , "UTF-8" )
				end
				return { id = r , contents = s } , datadiscarded
			end
		elseif r:sub ( 1 , 1 ) == "W" then
			if r == "WXXX" or r == "WXX" then -- Standard defined Link field
				genWXXXframe ( humanname , v , id3version )
			else
				return { id = r , contents = ascii ( v [ 1 ] , "UTF-8" ) } , ( v [ 2 ] or datadiscarded ) -- Only allowed one url per field
			end
		else -- Assume binary data
			for i , bin in ipairs ( v ) do
				return { id = r , contents = bin } , datadiscarded
			end
		end
	elseif not r and v and v [ 1 ] then
		if v [ 1 ]:find ( "^%w+%://.+$" ) or humanname:match ( ".*url$" ) then -- Is it a url? If so, chuck it in a WXXX -- TODO: improve url checker
			return genWXXXframe ( humanname , v , id3version )
		else	-- Put in a TXXX field
			return genTXXXframe ( humanname , v , id3version )
		end
	else
		-- empty frame, wtf >.<
		return
	end
end

-- Trys to add newvalue to table
local function clashfunc ( tbl , newvalue , overwrite , tblnodupes )
	local lostdata
	if not tblnodupes and tbl [ 2 ] then
		tbl , lostdata = clashfunc ( { unpack ( tbl , 2 ) } , tbl [ 1] , overwrite , false )
	end
	
	local result , nexti = { } , 1
	
	local uniquefuncs = {
		enc_encstring = function ( str )
			local encoding = encodings [ str:byte ( 1 , 1 ) ]
			local terminator = ( "\0" ):rep ( encoding.nulls )
			local s , e = str:find ( terminator , 2 , true )
			local description = ascii ( str:sub ( 2 , e - 1 )  , encoding.name ):lower ( )
			return description
		end ,
		enc_lang_encdesc = function ( str ) -- Unique language and description
			local encoding = encodings [ str:byte ( 1 , 1 ) ]
			local terminator = ( "\0" ):rep ( encoding.nulls )
			local language = str:sub ( 2 , 4 )
			local s , e = str:find ( terminator , 5 , true )
			local description = str:sub ( 5 , e - 1 )
			return language..description
		end ,
		nullterm = function ( str ) -- Unique is first null terminated string
			local s , e = str:find ( "\0" , 1 , true )
			return str:sub ( 1 , s - 1 )
		end ,
		onebyte_nullterm = function ( str ) -- Unique is first null terminated string
			local s , e = str:find ( "\0" , 2 , true )
			return str:sub ( 2 , s - 1 )
		end ,
		enc_lang = function ( str )
			return str:sub ( 2 , 4 )
		end ,
		anythingdifferent = function ( str )
			return str
		end ,
	}
	local idtouniquefunc = {
		["TXX"] = uniquefuncs.enc_encstring , 
		["TXXX"] = uniquefuncs.enc_encstring , 
		["WXX"] = uniquefuncs.enc_encstring , 
		["WXXX"] = uniquefuncs.enc_encstring ,
		["ULT"] = uniquefuncs.enc_lang_encdesc ,
		["USLT"] = uniquefuncs.enc_lang_encdesc ,
		["COM"] = uniquefuncs.enc_lang_encdesc ,
		["COMM"] = uniquefuncs.enc_lang_encdesc ,
		["UFI"] = uniquefuncs.nullterm ,
		["UFID"] = uniquefuncs.nullterm ,
		["WCM"] = uniquefuncs.nullterm ,
		["WCOM"] = uniquefuncs.nullterm ,
		["WCM"] = uniquefuncs.nullterm ,
		["WOAR"] = uniquefuncs.nullterm ,
		["WAR"] = uniquefuncs.nullterm ,
		["RVA"] = uniquefuncs.nullterm ,
		["RVAD"] = uniquefuncs.nullterm ,
		["RVA2"] = uniquefuncs.nullterm ,
		["POP"] = uniquefuncs.nullterm ,
		["POPM"] = uniquefuncs.nullterm ,
		["AENC"] = uniquefuncs.nullterm ,
		["EQU2"] = uniquefuncs.onebyte_nullterm ,
		["USER"] = uniquefuncs.enc_lang ,
		["PRIV"] = uniquefuncs.anythingdifferent ,
		["COMR"] = uniquefuncs.anythingdifferent ,
		["SIGN"] = uniquefuncs.anythingdifferent ,
	}
		
	local id = newvalue.id
	local unique = function ( v ) 
		local func = idtouniquefunc [ id ]
		if func then return func ( v.contents )
		else	return true end
	end
	
	for i , v in ipairs ( tbl ) do
		if not ( unique ( v ) == unique ( newvalue ) ) then
			-- No clash
			result [ nexti ] = v
			nexti = nexti + 1
  		end
	end
	if #result < #tbl then
		lostdata = true
	end
	result [ nexti ] = newvalue
	
	return result , lostdata
end

-- Generate frames for the new data
local function generateframes ( tags , id3version , overwrite )
	local frames , datadiscarded = { } , false
	for k , v in pairs ( tags ) do
		-- Get frame 
		local encoderule = frameencode [ k ]
		local preframe
		if type ( encoderule ) == "function" then
			local lostdata
			preframe , lostdata = encoderule ( tags , id3version )
			datadiscarded = lostdata or datadiscarded
		elseif type ( encoderule ) == "table" then
			preframe = { { encoderule [ id3version ] , v } }
		else -- No rule found
			preframe = { { false , v } }
		end
		
		-- k is name of tag (lomp internall)
		-- preframe[i][1] is id of resulting frame
		-- preframe[i][2] is table of values to be packed into frame called k
		
		-- Generate frame contents
		for i , v in ipairs ( preframe ) do
			local frame , lostdata = generateframe ( k , v[1] , v[2] , id3version ) 
			datadiscarded = datadiscarded or lostdata
			if frame and frame.id and frame.contents then
				frames [ #frames + 1 ] = frame
			end
		end
		for i , v in ipairs ( frames ) do
			-- Set flags
			v.formatflags = { false , false , false , false , false , false , false , false }
			v.statusflags = { false , false , false , false , false , false , false , false } -- Index three contains the frame flags, set all flags to false
		end
	end
	return frames , datadiscarded
end

-- Generate the id3v2 tag
 -- 	tags = {"k"={"v1","v2"}	=> table of new tags to write
 -- fd 						=> file descriptor of file to modify
 -- overwrite    	= false		=> don't change anything thats already set, only fill in missing values
 --			nil, non-string	=> read existing tags, attempt to merge, if only one value can be accepted, use one given
 --			= "overwrite"	=> overwrite existing tags of comparable fields
 --			= "new"		=> generate completely new tag
 -- id3version 	= 2-4 		=> id3 version to write
 -- footer 		= boolean 	=> write footer instead of header - id3version must be 4
 -- dontwrite 	= boolean 	=> just generate tag
function edit ( tags , path , overwrite , id3version , footer , dontwrite )
	local fd , err = ioopen ( path , "rb+" )
	if not fd then return ferror ( err , 3 ) end
	
	id3version = id3version or 4
	if footer and id3version ~= 4 then return ferror ( "Tried to write id3v2 tag to footer that wasn't version 4" , 3 ) end
	if type ( overwrite ) == "string" and overwrite ~= "overwite" and overwrite ~= "new" then return ferror ( "Invalid overwrite value" , 3 ) end
	
	local datadiscarded = false

	-- Look for details about where to put tag
	local starttag = find ( fd )
	local sizetofitinto = 0 -- Size available to fit into from value of starttag
	
	local knownids , nextidnum = { } , 1
	if starttag then -- File has existing tag
		local t
		-- Get existing tag
		fd:seek ( "set" , starttag )
		local header , err = readheader ( fd )
		if overwrite == "new" then
			fd:seek ( "set" , header.size )
		elseif header then
			t = { version = header.version }
			local nexti = 1
			
			local id3tag = fd:read ( header.size )
			local sd = vstruct.cursor ( id3tag )
			while sd:seek ( "cur" ) < ( header.size - header.frameheadersize  ) do
				local ok , err = readframeheader ( sd , header )
				if ok then
					sd:seek ( "set" , ok.startcontent )
					ok.unsynched = ok.unsynched or header.unsynched -- Frame is unsynched if flag set in frameheader or id3header
					local frame , err = decodeframe ( sd:read ( ok.size ) , header , ok )
						if err then -- If can't decode, skip over the frame
					else
						t [ nexti ] = { id = ok.id , contents = frame , statusflags = ok.statusflags , formatflags = ok.formatflags }
						nexti = nexti + 1
					end
				elseif err == "padding" then
					break
				end
			end
			t.paddingstart = fd:seek ( "cur" )
			t.paddingend = header.size - starttag
			sizetofitinto = 10 + header.size
			
			if t.version == id3version then -- Tag already correct version
				for i , v in ipairs ( t ) do
					if not knownids [ v.id ] then
						knownids [ v.id ] = { v }
					else
						knownids [ v.id ] [ #( knownids [ v.id ] ) + 1 ] = v
					end
				end
			
			else -- Convert tag to other version
				iostderr:write("wrong id3v2 version \t File:\t" , t.version , "\tWriting:\t" , id3version ,"\n")
				local tags = { }
				for i , v in ipairs ( t ) do 
					if framedecode [ v.id ] then
						local newtags = framedecode [ v.id ] ( v.contents )
						tblinherit ( tags , ( newtags or { } ) , true )
					end
				end
				local existing , dd = generateframes ( tags , id3version , overwrite )
				datadiscarded = dd or datadiscarded
				
				for i , v in ipairs ( existing ) do
					if not knownids [ v.id ] then
						knownids [ v.id ] = { v }
					else
						knownids [ v.id ] = clashfunc ( knownids [ v.id ] , v , overwrite )
					end
				end
			end
		end
	else -- File has no tag
		if footer then starttag = fd:seek ( "end" )
		else starttag = 0 end
	end
	
	local frames , dd = generateframes ( tags , id3version , overwrite )
	datadiscarded = dd or datadiscarded
	
	-- Merge in new frames
	for i , v in ipairs ( frames ) do
		if not knownids [ v.id ] then
			knownids [ v.id ] = { v }
		else
			if overwrite == "overwrite" then
				local tmp, lostdata = clashfunc ( { select ( 2 , unpack ( knownids [ v.id ] ) ) } , knownids [ v.id ] [ 1] , overwrite , false )
				datadiscarded = lostdata or datadiscarded
				if #tmp == #knownids [ v.id ] then
					local tmp2 , lostdata = clashfunc ( tmp , v , overwrite , true )
					if lostdata then
						knownids [ v.id ] = tmp
					else
						knownids [ v.id ] = tmp2
						datadiscarded = lostdata or datadiscarded
					end
				else
					knownids [ v.id ] = tmp
				end
			else
				local lostdata
				knownids [ v.id ] , lostdata = clashfunc ( knownids [ v.id ] , v , overwrite , false )
				datadiscarded = lostdata or datadiscarded
			end
		end
	end
	
	local readyframes , nextrf = { } , 1
	-- Add frame headers, make into real frames
	for id , tbl in pairs ( knownids ) do
		for i , v in pairs ( tbl ) do
			local size = #v.contents
			if size >= 268435456 then return ferror ( "Tag too large" , 3 ) end
			local tblsize
			if id3version == 4 then tblsize = makesafesync ( size ) 
			else tblsize = vstruct.explode ( size ) end
			
			if id3version == 2 then
				readyframes [ nextrf ] = vstruct.pack ( "> s m3 s" , { v.id  , tblsize , v.contents } )
			else
				readyframes [ nextrf ] = vstruct.pack ( "> s m4 m1 m1 s" , { v.id , tblsize , v.statusflags , v.formatflags , v.contents } )
			end
			nextrf = nextrf + 1
		end
	end
	
	-- Put frames together
	local allframes = tblconcat ( readyframes ) 

	-- TODO: compress,encrypt,unsync?
	
	-- Generate header
	local flags = { false , false , false , false , false , false , false , false }
	-- Put it all together
	local sizeheader = 10
	local amountofpadding
	if sizetofitinto > ( #allframes  + sizeheader ) then
		amountofpadding = sizetofitinto - sizeheader - #allframes -- TODO: detect extended headers
	else
		amountofpadding = #allframes -- Double the room we're already taking up
	end
	local padded = allframes .. ( "\0" ):rep ( amountofpadding  )
	
	local tag = vstruct.pack ( "> s3 u1 x1 m1 m4 s" , { ( ( footer and "3DI" ) or "ID3" ) , tostring ( id3version ), flags , makesafesync ( #padded ) , padded } )
	
	-- Write tag to file
	fd:seek ( "set" , starttag )
	iostderr:write("Write starts at\t" .. starttag .. "\tHave this much room:\t" .. sizetofitinto .. "\tNeed this much room:\t" .. sizeheader + #allframes .. "\tPadding this much:\t" .. amountofpadding .. "\tTag + padding=\t" .. #tag .. "\n" )
	if not dontwrite then
		if sizetofitinto == #tag then -- We fit exactly in, hooray!
			--iostderr:write("Tag fits!\n")
			fd:write ( tag )
			fd:flush ( )
			fd:close ( )
		elseif footer then -- Is a footer, we don't care about it's length.
			--iostderr:write("Tag should be appended, position\t" .. starttag .. "\n")
			fd:write ( tag )
			fd:flush ( )
			fd:close ( )
		elseif sizetofitinto < #tag then -- We don't fit, will have to rewrite file
			--iostderr:write("Damn, not enough room, rewriting tag\n")
			
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
				
			-- Write new tag to tmp file
			wd:write ( tag )
			
			fd:seek ( "cur" , sizetofitinto )
			
			local bytescopied = 0
			while true do
				local buff = fd:read ( 1024 )
				if not buff then break end
				wd:write ( buff )
				bytescopied = bytescopied + #buff
			end
			fd:close ( )
			
			wd:flush ( )
			wd:close ( )
			osremove ( path ) 
			osrename ( tmpfilename , path )
			osremove ( tmpfilename ) 
		end
	end
	
	return datadiscarded
end
