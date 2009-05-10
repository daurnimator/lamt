--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.id3v1" , package.see ( lomp ) )

_NAME = "ID3v1 tag utils"

local genreindex = {
	[0] = "Blues" ,
	[1] = "Classic Rock" ,
	[2] = "Country" ,
	[3] = "Dance" ,
	[4] = "Disco" ,
	[5] = "Funk" ,
	[6] = "Grunge" ,
	[7] = "Hip-Hop" ,
	[8] = "Jazz" ,
	[9] = "Metal" ,
	[10] = "New Age" ,
	[11] = "Oldies" ,
	[12] = "Other" ,
	[13] = "Pop" ,
	[14] = "R&B" ,
	[15] = "Rap" ,
	[16] = "Reggae" ,
	[17] = "Rock" ,
	[18] = "Techno" ,
	[19] = "Industrial" ,
	[20] = "Alternative" ,
	[21] = "Ska" ,
	[22] = "Death Metal" ,
	[23] = "Pranks" ,
	[24] = "Soundtrack" ,
	[25] = "Euro-Techno" ,
	[26] = "Ambient" ,
	[27] = "Trip-Hop" ,
	[28] = "Vocal" ,
	[29] = "Jazz+Funk" ,
	[30] = "Fusion" ,
	[31] = "Trance" ,
	[32] = "Classical" ,
	[33] = "Instrumental" ,
	[34] = "Acid" ,
	[35] = "House" ,
	[36] = "Game" ,
	[37] = "Sound Clip" ,
	[38] = "Gospel" ,
	[39] = "Noise" ,
	[40] = "AlternRock" ,
	[41] = "Bass" ,
	[42] = "Soul" ,
	[43] = "Punk" ,
	[44] = "Space" ,
	[45] = "Meditative" ,
	[46] = "Instrumental Pop" ,
	[47] = "Instrumental Rock" ,
	[48] = "Ethnic" ,
	[49] = "Gothic" ,
	[50] = "Darkwave" ,
	[51] = "Techno-Industrial" ,
	[52] = "Electronic" ,
	[53] = "Pop-Folk" ,
	[54] = "Eurodance" ,
	[55] = "Dream" ,
	[56] = "Southern Rock" ,
	[57] = "Comedy" ,
	[58] = "Cult" ,
	[59] = "Gangsta" ,
	[60] = "Top 40" ,
	[61] = "Christian Rap" ,
	[62] = "Pop/Funk" ,
	[63] = "Jungle" ,
	[64] = "Native American" ,
	[65] = "Cabaret" ,
	[66] = "New Wave" ,
	[67] = "Psychadelic" ,
	[68] = "Rave" ,
	[69] = "Showtunes" ,
	[70] = "Trailer" ,
	[71] = "Lo-Fi" ,
	[72] = "Tribal" ,
	[73] = "Acid Punk" ,
	[74] = "Acid Jazz" ,
	[75] = "Polka" ,
	[76] = "Retro" ,
	[77] = "Musical" ,
	[78] = "Rock & Roll" ,
	[79] = "Hard Rock" ,
	[-- From here on are not in the official spec,but are widely supported (added by winamp)" ,
	[80] = "Folk" ,
	[81] = "Folk-Rock" ,
	[82] = "National Folk" ,
	[83] = "Swing" ,
	[84] = "Fast Fusion" ,
	[85] = "Bebob" ,
	[86] = "Latin" ,
	[87] = "Revival" ,
	[88] = "Celtic" ,
	[89] = "Bluegrass" ,
	[90] = "Avantgarde" ,
	[91] = "Gothic Rock" ,
	[92] = "Progressive Rock" ,
	[93] = "Psychedelic Rock" ,
	[94] = "Symphonic Rock" ,
	[95] = "Slow Rock" ,
	[96] = "Big Band" ,
	[97] = "Chorus" ,
	[98] = "Easy Listening" ,
	[99] = "Acoustic" ,
	[100] = "Humour" ,
	[101] = "Speech" ,
	[102] = "Chanson" ,
	[103] = "Opera" ,
	[104] = "Chamber Music" ,
	[105] = "Sonata" ,
	[106] = "Symphony" ,
	[107] = "Booty Bass" ,
	[108] = "Primus" ,
	[109] = "Porn Groove" ,
	[110] = "Satire" ,
	[111] = "Slow Jam" ,
	[112] = "Club" ,
	[113] = "Tango" ,
	[114] = "Samba" ,
	[115] = "Folklore" ,
	[116] = "Ballad" ,
	[117] = "Power Ballad" ,
	[118] = "Rhythmic Soul" ,
	[119] = "Freestyle" ,
	[120] = "Duet" ,
	[121] = "Punk Rock" ,
	[122] = "Drum Solo" ,
	[123] = "A capella" ,
	[124] = "Euro-House" ,
	[125] = "Dance Hall"
}

local speedindex = {
	[1] = "slow" ,
	[2] = "medium" ,
	[3] = "fast" ,
	[4] = "hardcore"
}

local function readstring ( fd , length )
	local fin = fd:seek ( "cur" , length ) -- Get offset of end of string area
	local endstring
	for i = 1 , length do -- Work backwards from end of string, stopping when you get to the first character.
		fd:seek ( fin  , -i )
		local c = fd:read ( 1 )
		if c ~= "\0" and c ~= " " then -- Some older programs padded with space instead of binary zero
			endstring = length - i
			fd:seek ( fin , - length ) -- Seek to start of string area
			break
		end
	end
	local result = fd:read ( endstring )
	fd:seek ( fin + 1 ) -- Seek past end of string area.
	return result , endstring
end

function info ( fd )
	fd:seek ( "end" , -128 ) -- Seek to start of ID3 tag.
	
	if fd:read ( 3 ) ==  "TAG" then 
		local item = { format = "flac" , extra = { } }
		
		--item.tagtype = "id3v1"
		
		item.tags = { }
		item.tags.title = { readstring ( fd , 30 ) } 
		item.tags.artist = { readstring ( fd , 30 ) } 
		item.tags.album = { readstring ( fd , 30 ) } 
		item.tags.title = { readstring ( fd , 30 ) }
		item.tags.date = { readstring ( fd , 4 ) }
		
		do -- ID3v1 vs ID3v1.1
			local zerobyte = fd:seek ( "cur" , 28 )
			if fd:read ( 1 ) == "\0" then -- Check if comment is 28 or 30 characters
				-- Get up to 28 character comment
				fd:seek ( "cur" , -29 )
				item.tags.comment = { readstring ( fd , 28 ) }
				
				-- Get track number
				item.tags.tracknumber = { string.byte( fd:read ( 1 ) ) }
			else -- Is ID3v1, could have a 30 character comment tag
				fd:seek ( "cur" , -29 )
				item.tags.comment = { readstring ( fd , 30 ) } 
			end
		end
		
		item.tags.genre = { genreindex [ tonumber ( string.byte( fd:read ( 1 ) ) ) ] }
		
		-- Check for extended tags (Note: these are damn rare, worthwhile supporting them??)
		fd:seek ( "end" , -355 )
		if fd:read ( 4 ) == "TAG+" then
			item.tags.title [ 1 ] = item.tags.title[1] .. readstring ( fd , 60 )
			item.tags.artist [ 1 ] = item.tags.artist[1] .. readstring ( fd , 60 )
			item.tags.album [ 1 ] = item.tags.album[1] .. readstring ( fd , 60 )
			item.tags.speed = { speedindex [ tonumber ( string.byte ( fd:read ( 1 ) ) ) ] }
			item.tags.genre [ 2 ] = readstring ( fd , 30 )
			do
				local start = readstring ( fd , 30 )
				if #start = 6 and start:sub ( 4 , 4 ) == ":" then
					item.tags.start-time = { tostring ( tonumber ( start:sub ( 1 , 3 ) ) * 60 + start:sub ( 5 , 6 ) }
				end
				local fin = readstring ( fd , 30 )
				if #fin = 6 and fin:sub ( 4 , 4 ) == ":" then
					item.tags.end-time = { tostring ( tonumber ( fin:sub ( 1 , 3 ) ) * 60 + fin:sub ( 5 , 6 ) }
				end
			end
			
		end
		return item
	else
		-- File doesn't have an ID3v1 Tag
		return false
	end
end

function edit ( fd , tags )
	local item = info ( fd )
	if not item then return item end
		
end
