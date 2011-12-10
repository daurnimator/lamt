--"ID3v2 tag reader/writer"
-- Specifications:
 -- http://www.id3.org/id3v2.4.0-structure
 -- http://www.id3.org/id3v2.4.0-frames
 -- http://www.id3.org/id3v2.4.0-changes
 -- http://www.id3.org/id3v2.3.0
 -- http://www.id3.org/id3v2-00

local assert , error = assert , error
local tonumber = tonumber
local ipairs = ipairs
local strgsub , strmatch , strgmatch = string.gsub , string.match , string.gmatch
local strsub , strbyte = string.sub , string.byte
local tblinsert = table.insert
local tblconcat = table.concat
local ceil = math.ceil

local ll = require "ll"
local be_uint_to_num = ll.be_uint_to_num
local be_bpeek = ll.be_bpeek

local misc = require "misc"
local get_from_fd = misc.get_from_fd
local get_from_string = misc.get_from_string
local read_terminated_string = misc.read_terminated_string
local strexplode = misc.strexplode
local text_encoding = misc.text_encoding
local new_date = misc.new_date

local genrelist = require "genrelist"

-- Table of Encodings
local encodings = {
	[ 0 ] = { name = "ISO-8859-1" , terminator = "\0" } ,
	[ 1 ] = { name = "UTF-16" ,     terminator = "\0\0" } ,
	[ 2 ] = { name = "UTF-16BE" ,   terminator = "\0\0" } ,
	[ 3 ] = { name = "UTF-8" ,      terminator = "\0" } ,
}

local function toutf8 ( str , from )
	if from == "UTF-8" then
		return str
	else
		return text_encoding ( str , from , "UTF-8" )
	end
end

local function read_synchsafe_integer ( s )
	local b1 , b2 , b3 , b4 = strbyte ( s , 1 , 4 )
	return b1*2^21 + b2*2^14 + b3*2^7 + b4
end

local function read_header ( get )
	local identifier = get ( 3 )
	if identifier ~= "ID3" and identifier ~= "3DI" then
		return false
	end

	local version_major , version_minor = strbyte ( get ( 2 ) , 1 , 2 )
	local flags = get ( 1 )
	local size = read_synchsafe_integer ( get ( 4 ) )

	return {
		version_major = version_major ;
		version_minor = version_minor ;

		flags = flags ;
		size = size ;

		isfooter = ( identifier == "3DI" ) ;
	}
end

-- Trys to find an id3tag in given file handle
 -- Returns the start of the tag as a file offset
local function find ( fd )
	local get = get_from_fd ( fd )

	-- Look at start of file
	assert ( fd:seek ( "set" ) )
	local h = read_header ( get )
	if h then
		return 10 , h
	end

	-- Look at end of file
	local pos = assert ( fd:seek ( "end" , -10 ) )
	local h = read_header ( get )
	if h and h.isfooter then
		return pos - h.size , h
	end

	-- No tag
	return false
end

local function ununsynch ( str )
	--[[
	local replacements_special , replacements_nul
	str , replacements_special = strgsub ( str , "\255%z([224-\255])" ,  "\255%1" )
	str , replacements_nul = strgsub ( str , "\255%z%z" ,  "\255\0" )
	print("Ununsynch, made " .. replacements_nul .. "," .. replacements_special .. " replacements" )
	--]]
	str = strgsub ( str , "\255%z(.)" , "\255%1" )
	return str
end

local function get_frame ( get , version_major )
	local id
	if version_major == 4 or version_major == 3 then
		id = get ( 4 )
	elseif version_major == 2 then
		id = get ( 3 )
	end

	local frame
	local status_read_only , status_file_alter_discard , status_tag_alter_discard
	local format_unsynced , format_zlib_compressed
	local encryption_method , group_identifier , decoded_length
	if version_major == 4 then
		local size = read_synchsafe_integer ( get ( 4 ) )

		local status_flags = get ( 1 ) -- 0abc0000
		status_tag_alter_discard =     be_bpeek ( status_flags , 1 ) -- a
		status_file_alter_discard =    be_bpeek ( status_flags , 2 ) -- b
		status_read_only =             be_bpeek ( status_flags , 3 ) -- c

		local format_flags = get ( 1 ) -- 0h00kmnp
		local format_has_group_info =  be_bpeek ( format_flags , 1 ) -- h
		format_zlib_compressed =       be_bpeek ( format_flags , 4 ) -- k
		local format_encrypted =       be_bpeek ( format_flags , 5 ) -- m
		format_unsynced =              be_bpeek ( format_flags , 6 ) -- n
		local format_has_data_length = be_bpeek ( format_flags , 7 ) -- p

		if format_has_data_length then
			decoded_length = read_synchsafe_integer ( get ( 4 ) )
			size = size - 4
		end
		if format_encrypted then
			encryption_method = strbyte ( get ( 1 ) )
			size = size - 1
		end
		if format_has_group_info then
			group_identifier = strbyte ( get ( 1 ) )
			size = size - 1
		end

		frame = get ( size )
	elseif version_major == 3 then
		local size = be_uint_to_num ( get ( 4 ) )

		local status_flags = get ( 1 ) -- abc00000
		status_tag_alter_discard =     be_bpeek ( status_flags , 0 ) -- a
		status_file_alter_discard =    be_bpeek ( status_flags , 1 ) -- b
		status_read_only =             be_bpeek ( status_flags , 2 ) -- c

		local format_flags = get ( 1 ) -- ijk00000
		format_zlib_compressed =       be_bpeek ( format_flags , 0 ) -- k
		local format_encrypted =       be_bpeek ( format_flags , 1 ) -- j
		local format_has_group_info =  be_bpeek ( format_flags , 2 ) -- i

		if format_zlib_compressed then
			decoded_length = be_uint_to_num ( get ( 4 ) )
			size = size - 4
		end
		if format_encrypted then
			encryption_method = strbyte ( get ( 1 ) )
			size = size - 1
		end
		if format_has_group_info then
			group_identifier = strbyte ( get ( 1 ) )
			size = size - 1
		end

		frame = get ( size )
	elseif version_major == 2 then
		local size = be_uint_to_num ( get ( 3 ) )
		frame = get ( size )
	else
		error ( "Unknown ID3v2 version or non-conformant file" )
	end


	if format_unsynced then
		frame = ununsynch ( frame )
	end
	if encryption_method then
		error ( "Decryption not implemented" )
	end
	if format_zlib_compressed then
		error ( "Zlib decompression not implemented" )
	end

	return {
		id = id ;

		status_read_only = status_read_only;
		status_file_alter_discard = status_file_alter_discard ;
		status_tag_alter_discard = status_tag_alter_discard ;

		group_identifier = group_identifier ;

		frame = frame ;
	}
end

local function appendtag ( tags , field , value )
	if value ~= "" then
		local t = tags [ field ]
		if not t then
			t = { }
			tags [ field ] = t
		end

		tblinsert ( t , value )
	end
end

local function read_string ( get , encoding )
	local s = read_terminated_string ( get , encoding.terminator )
	if #encoding.terminator == 2 and #s % 2 == 1 then
		s = s .. "\0"
	end
	return toutf8 ( s , encoding.name )
end

local function read_text_frame ( s )
	local encoding = encodings [ strbyte ( s , 1 ) ]

	local r = { }
	local t = strexplode ( s , encoding.terminator , true , 2 )
	for i , text in ipairs ( t ) do
		if #encoding.terminator == 2 and #text % 2 == 1 then
			text = text .. "\0"
		end
		if #text > 0 then
			text = toutf8 ( text , encoding.name )
			tblinsert ( r , text )
		end
	end
	return r
end

local function reader_plain_text_frame ( field )
	return function ( s , tags )
		for i , v in ipairs ( read_text_frame ( s ) ) do
			appendtag ( tags , field , v )
		end
	end
end

local function reader_text_number_frame ( field )
	return function ( s , tags )
		for i , v in ipairs ( read_text_frame ( s ) ) do
			local num = tonumber ( v )
			appendtag ( tags , field , num or v )
		end
	end
end

local function reader_text_numeric_part ( num_field , den_field )
	return function ( s , tags )
		for i , v in ipairs ( read_text_frame ( s ) ) do
			local num , den = strmatch ( v , "^(%d+)/?(%d*)$" )
			if num then
				num = tonumber ( num )
				den = tonumber ( den )

				appendtag ( tags , num_field , num )
				if den then
					appendtag ( tags , den_field , num )
				end
			else
				appendtag ( tags , num_field , v )
			end
		end
	end
end

local reader_text_year_frame = reader_text_number_frame

local function reader_plain_url_frame ( field )
	return function ( s , tags )
		appendtag ( tags , field , s )
	end
end

-- Cut down ISO 8601 parser
-- returns a table ready for os.time
local function read_timestamp ( v )
	local date , time = strmatch ( v , "([%-%d]*)T?([:%d]*)" )
	if not ( date and time ) then
		error ( "Invalid timestamp: " .. v )
	end
	local year , month , day , hour , min , sec

	year = tonumber ( strsub ( date , 1 , 4 ) )
	if "-" == strsub ( date , 5 , 5 ) then
		month = tonumber ( strsub ( date , 6 , 7 ) )
		if "-" == strsub ( date , 8 , 8 ) then
			day = tonumber ( strsub ( date , 9 , 10 ) )
		end
	end

	hour = tonumber ( strsub ( time , 1 , 2 ) )
	if ":" == strsub ( time , 3 , 3 ) then
		min = tonumber ( strsub ( time , 4 , 5 ) )
		if ":" == strsub ( time , 6 , 6 ) then
			sec = tonumber ( strsub ( time , 7 , 8 ) )
		end
	end

	return new_date ( { year = year , month = month , day = day , hour = hour , min = min , sec = sec } )
end

local function reader_timestamp ( field )
	return function ( s , tags )
		for i , v in ipairs ( read_text_frame ( s ) ) do
			local tim = read_timestamp ( v )
			appendtag ( tags , field , tim )
		end
	end
end

-- Indexed by major_version; then tag id
local frame_decoders = { }

do -- v2
	frame_decoders[2] = { }

	--frame_decoders[2].BUF Recommended buffer size
	--frame_decoders[2].CNT Play counter
	frame_decoders[2].COM = function ( s , tags ) --  Comments
		local get = get_from_string ( s )
		local encoding = encodings [ strbyte ( get ( 1 ) ) ]
		local language = get ( 3 )
		local description = read_string ( get , encoding )
		local data = toutf8 ( get ( ) , encoding.name )

		appendtag ( tags , "comment" , data )
	end
	--frame_decoders[2].CRA Audio encryption
	--frame_decoders[2].CRM Encrypted meta frame
	--frame_decoders[2].ETC Event timing codes
	--frame_decoders[2].EQU Equalization
	--frame_decoders[2].GEO General encapsulated object
	--frame_decoders[2].IPL Involved people list
	--frame_decoders[2].LNK Linked information
	--frame_decoders[2].MCI Music CD Identifier
	--frame_decoders[2].MLL MPEG location lookup table
	--frame_decoders[2].PIC Attached picture
	frame_decoders[2].POP = function ( s , tags ) -- Popularimeter
		local get = get_from_string ( s )
		local email = read_terminated_string ( get )
		-- Note: email is ignored

		local rating = strbyte ( get ( 1 ) )
		if rating ~= 0 then
			appendtag ( tags , "rating" , rating )
		end
		local counter = be_uint_to_num ( get ( ) )
		appendtag ( tags , "play count" , counter )
	end
	--frame_decoders[2].REV Reverb
	frame_decoders[2].RVA = function ( s , tags ) -- Relative volume adjustment
			local get = get_from_string ( s )

			local inc_flags = get ( 1 )
			local inc_right      = be_bpeek ( inc_flags , 7 )
			local inc_left       = be_bpeek ( inc_flags , 6 )
			local inc_right_back = be_bpeek ( inc_flags , 5 )
			local inc_left_back  = be_bpeek ( inc_flags , 4 )
			local inc_centre     = be_bpeek ( inc_flags , 3 )
			local inc_bass       = be_bpeek ( inc_flags , 2 )

			local bits_used = strbyte ( get ( 1 ) )
			local bytes_used = ceil ( bits_used / 8 )

			-- TODO
			--[[
			local change_right = ( inc_right and 1 or -1 ) * be_uint_to_num ( get ( bytes_used ) )
			local change_left =  ( inc_left  and 1 or -1 ) * be_uint_to_num ( get ( bytes_used ) )

			local peak_right = be_uint_to_num ( get ( bytes_used ) )
			local peak_left =  be_uint_to_num ( get ( bytes_used ) )
			--]]
	end
	--frame_decoders[2].SLT Synchronized lyric/text
	--frame_decoders[2].STC Synced tempo codes
	frame_decoders[2].TAL = reader_plain_text_frame ( "album" ) -- Album/Movie/Show title
	frame_decoders[2].TBP = reader_text_number_frame ( "bpm" ) -- BPM (Beats Per Minute)
	frame_decoders[2].TCM = reader_plain_text_frame ( "composer" ) -- Composer
	frame_decoders[2].TCO = function ( s , tags ) -- Content type
		local field = "genre"

		for i , v in ipairs ( read_text_frame ( s ) ) do
			if strsub ( v , 1 , 1 ) == "(" then
				-- This is an awkward field; this parser will ignore any strings between bracketed expressions (eg, "(4)Eurodisco(5)Funky will ignore Eurodisco")
				local genre = { }
				for id3v1_genre , endbracket in strgmatch ( v , "%(([^%)]+)(%)?)" ) do
					local n = tonumber ( id3v1_genre )
					if n then
						tblinsert ( genre , genrelist [ n ] )
					elseif id3v1_genre == "RX" then
						tblinsert ( genre , "Remix" )
					elseif id3v1_genre == "CR" then
						tblinsert ( genre , "Cover" )
					elseif strsub ( id3v1_genre , 1 , 1 ) == "(" then -- Refinement with brackets in front of it
						tblinsert ( genre , "(" .. id3v1_genre .. endbracket )
					else

					end
				end
				-- Get trailing refinement
				tblinsert ( genre , strmatch ( v , "[^%(%)]+$" ) )
				appendtag ( tags , field , tblconcat ( genre , " " ) )
			else
				appendtag ( tags , field , v )
			end
		end
	end
	frame_decoders[2].TCR = reader_plain_text_frame ( "copyright" ) -- Copyright message
	frame_decoders[2].TDA = function ( s , tags ) -- Date
		for i , v in ipairs ( read_text_frame ( s ) ) do
			local day , month = strmatch ( v , "^(%d%d)(%d%d)$" )
			local d = new_date ( { month = month , day = day } )
			appendtag ( tags , "date" , d )
		end
	end
	frame_decoders[2].TDY = reader_text_number_frame ( "audio delay" ) -- Playlist delay
	frame_decoders[2].TEN = reader_plain_text_frame ( "encoder" ) -- Encoded by
	frame_decoders[2].TFT = reader_plain_text_frame ( "file type" ) -- File type
	--frame_decoders[2].TIM Time
	frame_decoders[2].TKE = reader_plain_text_frame ( "starting key" ) -- Initial key
	frame_decoders[2].TLA = reader_plain_text_frame ( "audio language" ) -- Language(s)
	frame_decoders[2].TLE = reader_text_number_frame ( "length" ) -- Length
	frame_decoders[2].TMT = reader_plain_text_frame ( "source media type" ) -- Media type
	frame_decoders[2].TOA = reader_plain_text_frame ( "original artist" ) -- Original artist(s)/performer(s)
	frame_decoders[2].TOF = reader_plain_text_frame ( "original filename" ) -- Original filename
	frame_decoders[2].TOL = reader_plain_text_frame ( "original lyricist" ) -- Original Lyricist(s)/text writer(s)
	frame_decoders[2].TOR = reader_text_year_frame ( "original release date" ) -- Original release year
	frame_decoders[2].TOT = reader_plain_text_frame ( "original album" ) -- Original album/Movie/Show title
	frame_decoders[2].TP1 = reader_plain_text_frame ( "artist" ) -- Lead artist(s)/Lead performer(s)/Soloist(s)/Performing group
	frame_decoders[2].TP2 = reader_plain_text_frame ( "band" ) -- Band/Orchestra/Accompaniment
	frame_decoders[2].TP3 = reader_plain_text_frame ( "conductor" ) -- Conductor/Performer refinement
	frame_decoders[2].TP4 = reader_plain_text_frame ( "remixer" ) -- Interpreted, remixed, or otherwise modified by
	frame_decoders[2].TPA = reader_text_numeric_part ( "disc" , "total discs" ) -- Part of a set
	frame_decoders[2].TPB = reader_plain_text_frame ( "publisher" ) -- Publisher
	frame_decoders[2].TRC = reader_plain_text_frame ( "isrc" ) -- ISRC (International Standard Recording Code)
	--frame_decoders[2].TRD Recording dates
	frame_decoders[2].TRK = reader_text_numeric_part ( "track" , "total tracks" ) -- Track number/Position in set
	frame_decoders[2].TSI = reader_text_number_frame ( "audio size" ) -- Size
	frame_decoders[2].TSS = reader_plain_text_frame ( "encoder settings" ) -- Software/hardware and settings used for encoding
	frame_decoders[2].TT1 = reader_plain_text_frame ( "content group description" ) -- Content group description
	frame_decoders[2].TT2 = reader_plain_text_frame ( "title" ) -- Title/Songname/Content description
	frame_decoders[2].TT3 = reader_plain_text_frame ( "subtitle" ) -- Subtitle/Description refinement
	frame_decoders[2].TXT = reader_plain_text_frame ( "lyricist" ) -- Lyricist/text writer
	frame_decoders[2].TXX = function ( s , tags ) --  User defined text information frame
		local get = get_from_string ( s )
		local encoding = encodings [ strbyte ( get ( 1 ) ) ]
		local description = read_string ( get , encoding )
		local value = get ( )

		local field = description
		appendtag ( tags , field , value )
	end
	frame_decoders[2].TYE = reader_text_year_frame ( "date" ) -- Year
	frame_decoders[2].UFI = function ( s , tags ) -- Unique file identifier
		local get = get_from_string ( s )
		local owner = read_terminated_string ( get )
		local data = get ( )
		-- TODO: use data
	end
	--frame_decoders[2].ULT Unsychronized lyric/text transcription
	frame_decoders[2].WAF = reader_plain_url_frame ( "file url" ) -- Official audio file webpage
	frame_decoders[2].WAR = reader_plain_url_frame ( "artist url" ) -- Official artist/performer webpage
	frame_decoders[2].WAS = reader_plain_url_frame ( "audio source url" ) -- Official audio source webpage
	frame_decoders[2].WCM = reader_plain_url_frame ( "commerical url" ) -- Commercial information
	frame_decoders[2].WCP = reader_plain_url_frame ( "copyright url" ) -- Copyright/Legal information
	frame_decoders[2].WPB = reader_plain_url_frame ( "publisher url" ) -- Publishers official webpage
	frame_decoders[2].WXX = function ( s , tags ) -- User defined URL link frame
		local get = get_from_string ( s )
		local encoding = encodings [ strbyte ( get ( 1 ) ) ]
		local description = read_string ( get , encoding )
		local url = get ( )

		local field = description .. " url"
		appendtag ( tags , field , url )
	end
end

do -- v3
	frame_decoders[3] = { }

	frame_decoders[3].AENC = frame_decoders[2].CRA -- Audio encryption
	frame_decoders[3].APIC = function ( s , tags ) -- Attached picture
		local get = get_from_string ( s )
		local encoding = encodings [ strbyte ( get ( 1 ) ) ]
		local mimetype = read_terminated_string ( get )
		local picturetype = strbyte ( get ( 1 ) )
		local description = read_string ( get , encoding )
		local data = get ( )
		-- TODO: use data
	end
	frame_decoders[3].COMM = frame_decoders[2].COM -- Comments
	--frame_decoders[3].COMR = -- Commercial frame
	--frame_decoders[3].ENCR = -- Encryption method registration
	frame_decoders[3].EQUA = frame_decoders[2].EQU -- Equalization
	frame_decoders[3].ETCO = frame_decoders[2].ETC -- Event timing codes
	frame_decoders[3].GEOB = frame_decoders[2].GEO -- General encapsulated object
	--frame_decoders[3].GRID = -- Group identification registration
	frame_decoders[3].IPLS = frame_decoders[2].IPL -- Involved people list
	--frame_decoders[3].LINK = -- Linked information
	frame_decoders[3].MCDI = frame_decoders[2].MCI -- Music CD identifier
	frame_decoders[3].MLLT = frame_decoders[2].MLL -- MPEG location lookup table
	--frame_decoders[3].OWNE = -- Ownership frame
	frame_decoders[3].PRIV = function ( s , tags ) -- Private frame
		local get = get_from_string ( s )
		local ownerid = read_terminated_string ( get )
		local data = get ( )
		-- TODO
	end
	frame_decoders[3].PCNT = frame_decoders[2].CNT -- Play counter
	frame_decoders[3].POPM = frame_decoders[2].POP -- Popularimeter
	--frame_decoders[3].POSS = -- Position synchronisation frame
	frame_decoders[3].RBUF = frame_decoders[2].BUF -- Recommended buffer size
	frame_decoders[3].RVAD = frame_decoders[2].RVA -- Relative volume adjustment
	frame_decoders[3].RVRB = frame_decoders[2].REV -- Reverb
	frame_decoders[3].SYLT = frame_decoders[2].SLT -- Synchronized lyric/text
	frame_decoders[3].SYTC = frame_decoders[2].STC -- Synchronized tempo codes
	frame_decoders[3].TALB = frame_decoders[2].TAL -- Album/Movie/Show title
	frame_decoders[3].TBPM = frame_decoders[2].TBP -- BPM (beats per minute)
	frame_decoders[3].TCOM = frame_decoders[2].TCM -- Composer
	frame_decoders[3].TCON = frame_decoders[2].TCO -- Content type
	frame_decoders[3].TCOP = frame_decoders[2].TCR -- Copyright message
	frame_decoders[3].TDAT = frame_decoders[2].TDA -- Date
	frame_decoders[3].TDLY = frame_decoders[2].TDY -- Playlist delay
	frame_decoders[3].TENC = frame_decoders[2].TEN -- Encoded by
	frame_decoders[3].TEXT = frame_decoders[2].TXT -- Lyricist/Text writer
	frame_decoders[3].TFLT = frame_decoders[2].TFT -- File type
	frame_decoders[3].TIME = frame_decoders[2].TIM -- Time
	frame_decoders[3].TIT1 = frame_decoders[2].TT1 -- Content group description
	frame_decoders[3].TIT2 = frame_decoders[2].TT2 -- Title/songname/content description
	frame_decoders[3].TIT3 = frame_decoders[2].TT3 -- Subtitle/Description refinement
	frame_decoders[3].TKEY = frame_decoders[2].TKE -- Initial key
	frame_decoders[3].TLAN = frame_decoders[2].TLA -- Language(s)
	frame_decoders[3].TLEN = frame_decoders[2].TLE -- Length
	frame_decoders[3].TMED = frame_decoders[2].TMT -- Media type
	frame_decoders[3].TOAL = frame_decoders[2].TOT -- Original album/movie/show title
	frame_decoders[3].TOFN = frame_decoders[2].TOF -- Original filename
	frame_decoders[3].TOLY = frame_decoders[2].TOL -- Original lyricist(s)/text writer(s)
	frame_decoders[3].TOPE = frame_decoders[2].TOA -- Original artist(s)/performer(s)
	frame_decoders[3].TORY = frame_decoders[2].TOR -- Original release year
	frame_decoders[3].TOWN = reader_plain_text_frame ( "owner" ) -- File owner/licensee
	frame_decoders[3].TPE1 = frame_decoders[2].TP1 -- Lead performer(s)/Soloist(s)
	frame_decoders[3].TPE2 = frame_decoders[2].TP2 -- Band/orchestra/accompaniment
	frame_decoders[3].TPE3 = frame_decoders[2].TP3 -- Conductor/performer refinement
	frame_decoders[3].TPE4 = frame_decoders[2].TP4 -- Interpreted, remixed, or otherwise modified by
	frame_decoders[3].TPOS = frame_decoders[2].TPA -- Part of a set
	frame_decoders[3].TPUB = frame_decoders[2].TPB -- Publisher
	frame_decoders[3].TRCK = frame_decoders[2].TRK -- Track number/Position in set
	frame_decoders[3].TRDA = frame_decoders[2].TRD -- Recording dates
	frame_decoders[3].TRSN = reader_plain_text_frame ( "internet radio station name" ) -- Internet radio station name
	frame_decoders[3].TRSO = reader_plain_text_frame ( "internet radio station owner" ) -- Internet radio station owner
	frame_decoders[3].TSIZ = frame_decoders[2].TSI -- Size]
	frame_decoders[3].TSRC = frame_decoders[2].TRC -- ISRC (international standard recording code)
	frame_decoders[3].TSSE = frame_decoders[2].TSS -- Software/Hardware and settings used for encoding
	frame_decoders[3].TYER = frame_decoders[2].TYE -- Year
	frame_decoders[3].TXXX = frame_decoders[2].TXX -- User defined text information frame
	frame_decoders[3].UFID = frame_decoders[2].UFI  -- Unique file identifier
	--frame_decoders[3].USER =  -- Terms of use
	frame_decoders[3].USLT = frame_decoders[2].ULT  -- Unsychronized lyric/text transcription
	frame_decoders[3].WCOM = frame_decoders[2].WCM  -- Commercial information
	frame_decoders[3].WCOP = frame_decoders[2].WCP  -- Copyright/Legal information
	frame_decoders[3].WOAF = frame_decoders[2].WAF  -- Official audio file webpage
	frame_decoders[3].WOAR = frame_decoders[2].WAR  -- Official artist/performer webpage
	frame_decoders[3].WOAS = frame_decoders[2].WAS  -- Official audio source webpage
	frame_decoders[3].WORS = reader_plain_url_frame ( "radio url" ) -- Official internet radio station homepage
	frame_decoders[3].WPAY = reader_plain_url_frame ( "payment url" ) -- Payment
	frame_decoders[3].WPUB = frame_decoders[2].WPB  -- Publishers official webpage
	frame_decoders[3].WXXX = frame_decoders[2].WXX  -- User defined URL link frame
end

do -- v4
	frame_decoders[4] = { }

	frame_decoders[4].AENC = frame_decoders[3].AENC -- Audio encryption
	frame_decoders[4].APIC = frame_decoders[3].APIC -- Attached picture
	--frame_decoders[4].ASPI Audio seek point index
	frame_decoders[4].COMM = frame_decoders[3].COMM -- Comments
	frame_decoders[4].COMR = frame_decoders[3].COMR -- Commercial frame
	frame_decoders[4].ENCR = frame_decoders[3].ENCR -- Encryption method registration
	--frame_decoders[4].EQU2 Equalisation (2)
	frame_decoders[4].ETCO = frame_decoders[3].ETCO -- Event timing codes
	frame_decoders[4].GEOB = frame_decoders[3].GEOB -- General encapsulated object
	frame_decoders[4].GRID = frame_decoders[3].GRID -- Group identification registration
	frame_decoders[4].LINK = frame_decoders[3].LINK -- Linked information
	frame_decoders[4].MCDI = frame_decoders[3].MCDI -- Music CD identifier
	frame_decoders[4].MLLT = frame_decoders[3].MLLT -- MPEG location lookup table
	frame_decoders[4].OWNE = frame_decoders[3].OWNE -- Ownership frame
	frame_decoders[4].PRIV = frame_decoders[3].PRIV -- Private frame
	frame_decoders[4].PCNT = frame_decoders[3].PCNT -- Play counter
	frame_decoders[4].POPM = frame_decoders[3].POPM -- Popularimeter
	frame_decoders[4].POSS = frame_decoders[3].POSS -- Position synchronisation frame
	frame_decoders[4].RBUF = frame_decoders[3].RBUF -- Recommended buffer size
	--frame_decoders[4].RVA2 Relative volume adjustment (2)
	frame_decoders[4].RVRB = frame_decoders[3].RVRB --  Reverb
	--frame_decoders[4].SEEK Seek frame
	--frame_decoders[4].SIGN Signature frame
	frame_decoders[4].SYLT = frame_decoders[3].SYLT -- Synchronised lyric/text
	frame_decoders[4].SYTC = frame_decoders[3].SYTC -- Synchronised tempo codes
	frame_decoders[4].TALB = frame_decoders[3].TALB -- Album/Movie/Show title
	frame_decoders[4].TBPM = frame_decoders[3].TBPM -- BPM (beats per minute)
	frame_decoders[4].TCOM = frame_decoders[3].TCOM -- Composer
	frame_decoders[4].TCON = frame_decoders[3].TCON -- Content type
	frame_decoders[4].TCOP = frame_decoders[3].TCOP -- Copyright message
	frame_decoders[4].TDEN = reader_timestamp ( "encoding time" ) -- Encoding time
	frame_decoders[4].TDLY = frame_decoders[3].TDLY -- Playlist delay
	frame_decoders[4].TDOR = reader_timestamp ( "original release time" ) -- Original release time
	frame_decoders[4].TDRC = reader_timestamp ( "recording time" ) -- Recording time
	frame_decoders[4].TDRL = reader_timestamp ( "release time" ) -- Release time
	frame_decoders[4].TDTG = reader_timestamp ( "tagging time" ) -- Tagging time
	frame_decoders[4].TENC = frame_decoders[3].TENC -- Encoded by
	frame_decoders[4].TEXT = frame_decoders[3].TEXT -- Lyricist/Text writer
	frame_decoders[4].TFLT = frame_decoders[3].TFLT -- File type
	--frame_decoders[4].TIPL Involved people list
	frame_decoders[4].TIT1 = frame_decoders[3].TIT1 -- Content group description
	frame_decoders[4].TIT2 = frame_decoders[3].TIT2 -- Title/songname/content description
	frame_decoders[4].TIT3 = frame_decoders[3].TIT3 -- Subtitle/Description refinement
	frame_decoders[4].TKEY = frame_decoders[3].TKEY -- Initial key
	frame_decoders[4].TLAN = frame_decoders[3].TLAN -- Language(s)
	frame_decoders[4].TLEN = frame_decoders[3].TLEN -- Length
	--frame_decoders[4].TMCL Musician credits list
	frame_decoders[4].TMED = frame_decoders[3].TMED -- Media type
	frame_decoders[4].TMOO = reader_plain_text_frame ( "mood" ) --  Mood
	frame_decoders[4].TOAL = frame_decoders[3].TOAL -- Original album/movie/show title
	frame_decoders[4].TOFN = frame_decoders[3].TOFN -- Original filename
	frame_decoders[4].TOLY = frame_decoders[3].TOLY -- Original lyricist(s)/text writer(s)
	frame_decoders[4].TOPE = frame_decoders[3].TOPE -- Original artist(s)/performer(s)
	frame_decoders[4].TOWN = frame_decoders[3].TOWN -- File owner/licensee
	frame_decoders[4].TPE1 = frame_decoders[3].TPE1 -- Lead performer(s)/Soloist(s)
	frame_decoders[4].TPE2 = frame_decoders[3].TPE2 -- Band/orchestra/accompaniment
	frame_decoders[4].TPE3 = frame_decoders[3].TPE3 -- Conductor/performer refinement
	frame_decoders[4].TPE4 = frame_decoders[3].TPE4 -- Interpreted, remixed, or otherwise modified by
	frame_decoders[4].TPOS = frame_decoders[3].TPOS --  Part of a set
	frame_decoders[4].TPRO = reader_plain_text_frame ( "produced" ) -- Produced notice
	frame_decoders[4].TPUB = frame_decoders[3].TPUB -- Publisher
	frame_decoders[4].TRCK = frame_decoders[3].TRCK --  Track number/Position in set
	frame_decoders[4].TRSN = frame_decoders[3].TRSN -- Internet radio station name
	frame_decoders[4].TRSO = frame_decoders[3].TRSO -- Internet radio station owner
	frame_decoders[4].TSOA = reader_plain_text_frame ( "album sort order key" ) -- Album sort order
	frame_decoders[4].TSOP = reader_plain_text_frame ( "artist sort order key" ) -- Performer sort order
	frame_decoders[4].TSOT = reader_plain_text_frame ( "title sort order key" ) -- Title sort order
	frame_decoders[4].TSRC = frame_decoders[3].TSRC -- ISRC (international standard recording code)
	frame_decoders[4].TSSE = frame_decoders[3].TSSE -- Software/Hardware and settings used for encoding
	frame_decoders[4].TSST = reader_plain_text_frame ( "set subtitle" ) -- Set subtitle
	frame_decoders[4].TXXX = frame_decoders[3].TXXX --  User defined text information frame
	frame_decoders[4].UFID = frame_decoders[3].UFID --  Unique file identifier
	frame_decoders[4].USER = frame_decoders[3].USER --  Terms of use
	frame_decoders[4].USLT = frame_decoders[3].USLT --  Unsynchronised lyric/text transcription
	frame_decoders[4].WCOM = frame_decoders[3].WCOM --  Commercial information
	frame_decoders[4].WCOP = frame_decoders[3].WCOP --  Copyright/Legal information
	frame_decoders[4].WOAF = frame_decoders[3].WOAF --  Official audio file webpage
	frame_decoders[4].WOAR = frame_decoders[3].WOAR --  Official artist/performer webpage
	frame_decoders[4].WOAS = frame_decoders[3].WOAS --  Official audio source webpage
	frame_decoders[4].WORS = frame_decoders[3].WORS --  Official Internet radio station homepage
	frame_decoders[4].WPAY = frame_decoders[3].WPAY --  Payment
	frame_decoders[4].WPUB = frame_decoders[3].WPUB --  Publishers official webpage
	frame_decoders[4].WXXX = frame_decoders[3].WXXX --  User defined URL link frame
end

-- Compatability
-- iTunes
-- TCP
-- TCMP
-- TSO2
-- TSOC

local function read ( get , header , tags , extra )
	tags = tags or { }
	extra = extra or { }

	extra.version_major = header.version_major
	extra.version_minor = header.version_minor

	--%abcd0000
	local unsynched =         be_bpeek ( header.flags , 0 ) -- a
	local hasextendedheader = be_bpeek ( header.flags , 1 ) -- b
	local experimental =      be_bpeek ( header.flags , 2 ) -- c
	local footerpresent =     be_bpeek ( header.flags , 3 ) -- d

	extra.experimental = experimental

	local tag = get ( header.size )
	if unsynched and header.version_major == 2 then
		tag = ununsynch ( tag )
	end

	local tag_get , tag_pos = get_from_string ( tag )

	local ext_header_data
	if hasextendedheader then
		local ext_header_size = tag_get ( 4 )
		if header.version_major == 4 then
			ext_header_size = read_synchsafe_integer ( ext_header_size ) - 4
		elseif header.version_major == 3 then
			ext_header_size = be_uint_to_num ( ext_header_size )
		elseif header.version_major == 2 then -- In version 2, this was a flag indicating an unknown compression scheme
			error ( "ID3v2.2 compression flag set" )
		else
			error ( "Unknown ID3v2 version or non-conformant file" )
		end
		ext_header_data = tag_get ( ext_header_size )
	end

	extra.ext_header = ext_header_data

	while tag_pos ( ) < header.size do
		local frameinfo = get_frame ( tag_get , header.version_major )

		local frame_get = get_from_string ( frameinfo.frame )
		local decoder = frame_decoders [ header.version_major ] [ frameinfo.id ]
		if decoder then
			decoder ( frameinfo.frame , tags )
		else
			local id_1 = strsub ( frameinfo.id , 1 , 1 )
			if strmatch ( frameinfo.id , "^%z+$" ) then -- Null tag
				-- Probably padding at end of tag... or we're lost; either way: lets bail
				break
			elseif experimental or id_1 == "X" or id_1 == "Y" or id_1 == "Z" then -- Ignore
			else
				error ( "No decoder for frame id: " .. frameinfo.id )
			end
		end
	end

	return tags , extra
end

return {
	find = find ;
	read = read ;
}
