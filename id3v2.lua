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
		if ( i ) % 8 ~= 0 then
			new [ #new + 1 ] = tbl [ i ]
		end
	end
	return vstruct.implode ( new )
end
local function makesafesync ( int )
	local tbl = vstruct.explode ( int )
	local new = { }
	for i = 1 , #tbl do
		if ( i ) % 8 == 0 then
			new [ #new + 1 ] = false
		end
		new [ #new + 1 ] = tbl [ i ]
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
-- Converts string in specified encoding to utf8
local function utf8 ( str , encoding )
	if not encoding then encoding = "ISO-8859-1" end
	return iconv.new ( "UTF-8" ,  encoding ):iconv ( str )
end
-- Converts string in specified encoding to ascii (iso-8859-1)
local function ascii ( str , encoding )
	if not encoding then encoding = "UTF-8" end
	return iconv.new ( "ISO-8859-1" ,  encoding ):iconv ( str )
end

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
			t.hasextendedheader = t.flags [ 7 ]
			t.experimental = t.flags [ 6 ]
			t.isfooter = t.flags [ 5 ]
		elseif t.version == 3 then
			t.hasextendedheader = t.flags [ 7 ]
			t.experimental = t.flags [ 6 ]
		elseif t.version == 2 then
		end
		if t.hasextendedheader then
			local safesyncsize = vstruct.unpack ( "> safesyncsize:m4" , fd ).safesyncsize
			if t.version == 4 then
				local contents = fd:read ( desafesync ( safesyncsize ) - 4 )
				t.e = { }
				t.e.numflags = vstruct.unpack ( "> u1" , contents )
				t.e.flags = vstruct.unpack ( "> " .. t.e.numflags .. " * m4" , string.sub ( contents , 2 ) )
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
					t.e.crc = string.sub ( contents , 13 , 17 )
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

local frameencode = {
	[ "uniquefileid" ] = "UFID" ,
	[ "content group" ] = "TIT1" ,
	[ "title" ] = "TIT2" ,
	[ "subtitle" ] = "TIT3" ,
	[ "album" ] = "TALB" ,
	[ "original album" ] = "TOAL" ,
	[ "tracknumber" ] = function ( tags )
		local t = { }
		for i , v in ipairs ( tags [ "tracknumber" ] or { } ) do
			if tags [ "totaltracks" ] [ i ] then
				table.insert ( t , tostring ( v ) .. "/" .. tags [ "totaltracks" ] [i] )
			else
				table.insert ( t , tostring ( v ) ) 
			end	
		end
		return "TRCK" , t , false
	end ,
	[ "totaltracks" ] = function ( tags )
		if not tags [ "tracknumber" ] [ i ] then -- If not going to put in with tracknumber in TRCK, put in TXXX
			return "TXXX" , nil , false
		end
	end ,
	[ "discnumber" ] = function ( tags )
		local t = { }
		for i , v in ipairs ( tags [ "discnumber" ] or { } ) do
			if tags [ "totaldiscs" ] [ i ] then
				table.insert ( t , tostring ( v ) .. "/" .. tags [ "totaldiscs" ] [i] )
			else
				table.insert ( t , tostring ( v ) ) 
			end	
		end
		return "TPOS" , t , false
	end ,	
	[ "totaldiscs" ] = function ( tags )
		if not tags ["discnumber"] [i] then -- If not going to put in with discnumber in TPOS, put in TXXX
			return "TXXX" , nil , false
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
	-- TODO: TMCL (list) -- Some sort of metatable? need to match things ending in "player"
	-- TODO: TIPL (list) -- metatable? could be anything though...
	[ "encoded by" ] = "TENC" ,
	
	[ "bpm" ] = "TBPM" ,
	[ "length" ] = "TLEN" ,
	[ "musical key" ] = "TKEY" ,
	[ "language" ] = "TLAN" ,
	[ "genre" ] = "TCON" , -- Special
	[ "file type" ] = "TFLT" , -- Special
	[ "media type" ] = "TMED" , -- Special
	[ "mood" ] = "TMOO" ,
	[ "copyright" ] = "TCOP" , -- Special
	[ "produced" ] = "TPRO" , -- Special
	[ "publisher" ] = "TPUB" ,
	[ "owner" ] = "TOWN" ,
	[ "radio station" ] = "TRSN" ,
	[ "radio station owner" ] = "TRSO" ,
	
	[ "publisher" ] = "TOFN" ,
	--[ "delay" ] = "TDLY" , -- Special
	[ "encoding time" ] = "TDEN" , -- Special: Time
	[ "original release time" ] = "TDOR" , -- Special: Time
	[ "date" ] = "TDRC" , -- Special: Time
	[ "release time" ] = "TDRL" , -- Special: Time
	[ "tagged" ] = "TDTG" , -- Special: Time
	[ "encoder settings" ] = "TSSE" ,
	[ "album sort order" ] = "TSOA" ,
	[ "performer sort order" ] = "TSOP" ,
	[ "title sort order" ] = "TSOT" ,
	
	[ "commercial information url" ] = "WCOM" ,
	[ "copyright url" ] = "WCOP" ,
	[ "file webpage url" ] = "WOAF" ,
	[ "artist webpage url" ] = "WOAR" ,
	[ "source webpage url" ] = "WOAS" , 
	[ "internet radio webpage url" ] = "WORS" , 
	[ "payment url" ] = "WPAY" , 
	[ "publisher url" ] = "WPUB" ,
	
	[ "cd toc" ] = "MCDI" ,
	
	-- ETCO -- Event timing codes
	-- MLLT -- Not applicable
	-- SYTC -- Synchronised tempo codes
	
	--[[[ "lyrics" ] = function ( tags )
		-- TODO
		return "USLT" , nil , true
	end ,--]]
	
	-- SYLT -- Synchronised lyrics/text
	
	-- Comment
	["comment"] = function ( tags )
		local e = 3 -- Encoding, 3 is UTF-8
		local language = "eng" -- 3 character language
		local t = { }
		for i , v in ipairs ( tags [ "comment" ] ) do
			local shortdescription = utf8 ( "Comment #" .. i ) -- UTF-8 string
			t [ #t + 1 ] = string.char ( e ) .. language .. shortdescription .. string.rep ( "\0" , encodings [ e ].nulls ) .. utf8 ( v ) .. string.rep ( "\0" , encodings [ e ].nulls )
		end
		return "COMM" , t , false
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
	[ "terms of use" ] = function ( tags )
		local e = 3 -- Encoding, 3 is UTF-8
		local language = "eng" -- 3 character language
		local s = string.char ( e ) .. language .. utf8 (  tags [ "terms of use" ] [ 1 ] ) .. string.rep ( "\0" , encodings [ e ].nulls )
		return "USER" , { s } , toboolean ( v [ 2 ] )
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
	local t = vstruct.unpack ( "> encoding:u1 text:s" .. #str - 1 , str )
	local st = string.explode ( t.text , string.rep ( "\0" , encodings [ t.encoding ].nulls ) )
	local r = { }
	for i , v in ipairs ( st ) do
		if #v ~= 0 then
			r [ #r + 1 ] = utf8 ( v , encodings [ t.encoding ].name )
		end
	end
	return r
end

local framedecode = {
	["UFID"] = function ( str )
			return vstruct.unpack ( "> ownerid:{ z } uniquefileid:{ s64 }" , str )
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
				track [ #track + 1 ] , total [ #total + 1 ] = string.match ( v , "([^/]*)/?(.*)" )
				if total [ #total ] == "" then total [ #total ] = nil end -- string match still fills in the total array
			end
			return { [ "tracknumber" ] = track , ["totaltracks"] = total }
		end ,
	["TPOS"] = function ( str ) -- Part of a set
			local disc , total = { } , { }
			for i , v in ipairs ( readtextframe ( str ) ) do
				disc [ #disc + 1 ] , total [ #total + 1 ] = string.match ( v , "([^/]*)/?(.*)" )
				if total [ #total ] == "" then total [ #total ] = nil end -- string match still fills in the total array
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
		for i , v in ipairs ( t) do
			if v == "RX" then t [ i ] = "Remix"
			elseif v == "CR" then t [ i ] = "Cover" 
			elseif tonumber ( v ) then
				t [ i ] = genrelist [ tonumber ( v ) ]
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
		local c = { }
		for i , v in ipairs ( readtextframe ( str ) ) do
			local m = string.match ( v , "(%d%d%d%d)%s" )
			if m then 
				c [ #c + 1 ] = "Copyright " .. m
			end
		end
		return { [ "copyright" ] =  c }
	end ,
	["TPRO"] = function ( str ) -- Produced notice
		local p = { }
		for i , v in ipairs ( readtextframe ( str ) ) do
			local m = string.match ( v , "(%d%d%d%d)%s" )
			if m then 
				p [ #p + 1 ] = "Produced " .. m
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
		local t = vstruct.unpack ( "> encoding:u1 field:z text:s" .. #str - 2 , str )
		t.text = string.match ( t.text or ""  , "^%z*(.*)" ) or "" -- Strip any leading nulls
		local st = string.explode ( t.text , string.rep ( "\0" , encodings [ t.encoding ].nulls ) )
		local r = { }
		for i , v in ipairs ( st ) do
			if #v ~= 0 then
				r [ #r + 1 ] = utf8 ( v , encodings [ t.encoding ].name )
			end
		end
		return { [ string.lower ( t.field ) ] =  r }
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
		local t = vstruct.unpack ( "> field:z url:s" .. #str - 1 , str )
		t.url = string.match ( t.url  or "" , "^%z*(.*)" ) or "" -- Strip any leading nulls
		if #t.field == 0 then t.field = "url"
		else t.field = string.lower ( t.field ) .. " url" end
		return { [ t.field ] = { t.url } }
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
		local t = vstruct.unpack ( "> encoding:u1 language:s3 description:z text:s" .. #str - 5 , str )
		t.text = string.match ( t.text  or "" , "^%z*(.*)" ) or "" -- Strip any leading nulls
		-- TODO: Can we do anything with language or description?
		return { [ "lyrics" ] = { t.text } }
	end ,
	
	["SYLT"] = function ( str ) -- Synchronised lyrics/text
	end ,
	
	-- Comment
	["COMM"] = function ( str )
		local t = vstruct.unpack ( "> encoding:u1 language:s3 description:z text:s" .. #str - 5 , str )
		t.text = string.match ( t.text or "" , "^%z*(.*)" ) or "" -- Strip any leading nulls
		-- TODO: Can we do anything with language or description?
		return { [ "comment" ] = { t.text } }
	end ,
	
	["RVA2"] = function ( str ) -- Relative volume adjustment
	end ,
	
	["EQU2"] = function ( str ) -- Equalisation (2)
	end ,
	
	["RVRB"] = function ( str ) -- Reverb
	end ,
	
	["APIC"] = function ( str ) -- Attached pictures
		-- TODO: interpret pictures
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
		local t = vstruct.unpack ( "> encoding:u1 language:s3 description:z text:s" .. #str - 5 , str )
		t.text = string.match ( t.text or "" , "^%z*(.*)" ) or "" -- Strip any leading nulls
		-- TODO: Can we do anything with language or description?
		return { [ "terms of use" ] = { t.text } }
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

	-- ID3v2.3 frames (Older frames)
	["TORY"] = function ( str ) -- Year
		return { [ "original release time" ] = readtextframe ( str ) }
	end ,
	["TYER"] = function ( str ) -- Year
		return { [ "date" ] = readtextframe ( str ) }
	end ,
}
do -- ID3v2.2 frames -- RAWWWWWWWRRRRRRR
	framedecode["BUF"] = framedecode["RBUF"]
	
	framedecode["CNT"] = framedecode["PCNT"]
	framedecode["COM"] = framedecode["COMM"]
	framedecode["CRA"] = framedecode["AENC"]
	-- CRM
	framedecode["EQU"] = framedecode["EQUA"]
	framedecode["ETC"] = framedecode["ETCO"]
	
	framedecode["GEO"] = framedecode["GEOB"]
	
	framedecode["IPL"] = framedecode["IPLS"]
	
	framedecode["MCI"] = framedecode["MDCI"]
	framedecode["MLL"] = framedecode["MLLT"]
	
	-- PIC
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

-- Read 6 or 10 byte frame header
local function readframeheader ( fd , header )
	if header.version >= 3 then
		local t = vstruct.unpack ( "> id:s4 safesyncsize:m4 statusflags:m1 formatflags:m1" , fd )
		if t.id == "\0\0\0\0" then -- padding
			fd:seek ( "cur" , - 10 ) -- Rewind to what would have been start of frame
			return false , "padding"
		else
			t.framesize = vstruct.implode ( t.safesyncsize )
			if header.version == 4 then	
				t.size = desafesync ( t.safesyncsize )
				-- %0abc0000 %0h00kmnp
				t.tagalterpreserv = t.statusflags [ 7 ]
				t.filealterpreserv = t.statusflags [ 6 ]
				t.readonly = t.statusflags [ 5 ]
				t.compressed = t.formatflags [  4 ]
				t.encrypted = t.formatflags [ 3 ]
				t.grouped = t.formatflags [ 7 ]
				t.unsynched = t.formatflags [ 2 ]
				t.hasdatalength = t.formatflags [ 1 ]
				if t.grouped then t.groupingbyte = fd:read ( 1 ) end
				if t.encrypted then t.encryption = fd:read ( 1 ) end
				if t.hasdatalength then t.datalength = fd:read ( 4 ) end
			elseif header.version <= 3 then
				t.size = t.framesize
				-- %abc00000 %ijk00000 
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
			t.startheader = fd:seek ( "cur" , -10 )
			t.safesyncsize = nil
			return t
		end
	elseif header.version == 2 then
		local t = vstruct.unpack ( "> id:s3 size:u3" , fd )
		if t.id == "\0\0\0" then -- padding
			fd:seek ( "cur" , -6 ) -- Rewind to what would have been start of frame
			return false , "padding"
		else
			t.framesize = t.size
			t.startcontent = fd:seek ( "cur" )
			t.startheader = fd:seek ( "cur" , -6 )
			return t
		end
	end
end
local function readframe ( fd , header )
	local ok , err = readframeheader ( fd , header )
	if ok then
		local t = { }
		fd:seek ( "set" , ok.startcontent )
		t.framecontents = fd:read ( ok.size )
		t.contents = t.framecontents
		if ok.unsynched then -- Unsynch-safe the frame content
			t.contents = t.contents:gsub ( "\255%z([224-\255])" ,  "\255%1" )
				:gsub ( "\255%z%z" ,  "\255\0" )
		end
		if ok.encrypted then
			return false , "Encrypted frame, cannot decrypt"
		end
		if ok.compressed then -- Frame compressed with zlib
			local zlibok , z = pcall ( require , "zlib" )
			if zlibok and z then
				t.contents = z.decompress ( t.contents )
			else
				return false , "Compressed frame and no zlib available"
			end
		end
		if framedecode [ ok.id ] then
			--updatelog ( _NAME .. ": v" .. header.version .. " Read frame: " .. ok.id .. " Size: " .. ok.size , 5 )
			return t , ( framedecode [ ok.id ] ( t.contents ) or { } )
		else -- We don't know of this frame type
			updatelog ( _NAME .. ": v" .. header.version .. " Unknown frame: " .. ok.id .. " Size: " .. ok.size .. " Contents: " .. t.contents , 5 )
			return t , { }
		end
	else
		return ok , err
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
		if h and h.isfooter then return fd:seek ( "end" , -offsetfooter ) end
	end
end

function info ( fd , location , item )
	fd:seek ( "set" , location )
	local header = readheader ( fd )
	if header then
		item.tags = { }
		item.extra = { id3v2version = header.version }
		local id3tag = fd:read ( header.size )
		if header.unsynched then
			id3tag = id3tag:gsub ( "\255%z([224-\255])" ,  "\255%1" )
				:gsub ( "\255%z%z" ,  "\255\0" )
		end
		local sd = vstruct.cursor ( id3tag )
		while sd:seek ( "cur" ) < ( header.size - 6 ) do
			local ok , err = readframe ( sd , header )
			if ok then
				table.inherit ( item.tags , err , true )
			elseif err == "padding" then
				break
			end
		end
		return item
	else
		return false
	end
end

function generatetag ( tags , fd , footer )
	--[[local
	if io.type ( fd ) then -- Get existing tag
		fd:seek ( "set" , location )
		local header = readheader ( fd )
		if header then
			t = { }
			local id3tag = fd:read ( header.size )
			if header.unsynched then
				id3tag = id3tag:gsub ( "\255%z([224-\255])" ,  "\255%1" )
					:gsub ( "\255%z%z" ,  "\255\0" )
			end
			local sd = vstruct.cursor ( id3tag )
			while sd:seek ( "cur" ) < ( header.size - 6 ) do
				local ok , err = readframeheader ( sd , header )
				if ok then
					if ok.tagalterpreserv then -- Preserve as is
						t [ #t + 1 ] = { ok , fd:read ( ok.size ) }
					elseif
					else
						sd:seek ( "cur" , ok.size )
					end
				elseif err == "padding" then
					break
				end
			end
			t.paddingstart = fd:seek ( "cur" )
			t.paddingend = t.paddingstart - location + header.size
		end
	end
	if not t then -- New tag from scratch
		t = { }

	end--]]
	
	local datadiscarded = false
	
	local newframes = { }
	for k , v in pairs ( tags ) do
		local r = frameencode [ k ]
		if type ( r ) == "function" then
			local a , b
			r , a , b = r ( tags )
			v = a or v
			datadiscarded = b or datadiscarded
		end
		if type ( r ) == "string" then
			if string.sub ( r , 1 , 1 ) == "T"  and r ~= "TXXX" then -- Standard defined Text field
				local e = 3 -- Encoding, 3 is UTF-8
				local s = string.char ( e )
				for i , text in ipairs ( v ) do
					s = s .. text .. string.rep ( "\0" , encodings [ e ].nulls )
				end
				newframes [ #newframes + 1 ] = { r , s }
			elseif string.sub ( r , 1 , 1 ) == "W" and r ~= "WXXX" then -- Standard defined Link field
				newframes [ #newframes + 1 ] = { r , ascii ( v [ 1 ] , "UTF-8" ) } -- Only allowed one url per field
				if v [ 2 ] then datadiscarded = true end
			else -- Assume binary data
				for i , bin in ipairs ( v ) do
					newframes [ #newframes + 1 ] = { r , bin }
				end
			end
		elseif not r then
			if string.match ( v [ 1 ] , "(%w+)://" ) or string.match ( k , ".*url$" ) then -- Is it a url? If so, chuck it in a WXXX -- TODO: improve url checker
				r = "WXXX"
				local e = 3 -- Encoding, 3 is UTF-8
				newframes [ #newframes + 1 ] = { r , string.char ( e ) .. utf8 ( k ) .. string.rep ( "\0" , encodings [ e ].nulls ) .. ( v [ 1 ] or "" ) }
				if v [ 2 ] then datadiscarded = true end
			else	-- Put in a TXXX field
				r = "TXXX"
				local e = 3 -- Encoding, 3 is UTF-8
				local s = string.char ( e ) .. utf8 ( k ) .. string.rep ( "\0" , encodings [ e ].nulls )
				for i , text in ipairs ( v ) do
					s = s .. text .. string.rep ( "\0" , encodings [ e ].nulls )
				end
				newframes [ #newframes + 1 ] = { r , s }
			end
		end
	end
	-- Check for doubled up frames
	local readyframes = newframes
	
	-- Add frame headers
	for i , v in ipairs ( readyframes ) do
		local size = #v [ 2 ]
		readyframes [ i ] = vstruct.pack ( "> s m4 x2 s" , { v [ 1 ] , makesafesync ( size ) , v [ 2 ] } )
	end
	
	-- Put frames together
	local allframes = table.concat ( readyframes ) 
	local amountofpadding = #allframes
	local padded = allframes .. string.rep ( "\0" , amountofpadding  )
	-- compress,encrypt,unsync?
	
	-- Generate header
	local h
	if footer then h = "3DI\4\0"
	else h = "ID3\4\0" end
	
	-- Put it all together
	return vstruct.pack ( "> s m4 s" , { h , makesafesync ( #padded ) , padded } )
end

function edit ( )

end
