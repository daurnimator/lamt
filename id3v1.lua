--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.id3v1" , package.see ( lomp ) )

pcall ( require , "luarocks.require" ) -- Activates luarocks if available.
require "iconv"
local genreindex = require ( select ( 1 , ... ):match ( "(.*%.)[^.]+$" ) .. "genrelist" )

local Locale = "ISO-8859-1"
local toid3 = iconv.new ( Locale , "UTF-8" )
local fromid3 = iconv.new ( "UTF-8" , Locale )

_NAME = "ID3v1 tag utils"

local speedindex = {
	[1] = "slow" ,
	[2] = "medium" ,
	[3] = "fast" ,
	[4] = "hardcore"
}

local function readstring ( str )
	str = str:gsub ( "[%s%z]*$" , "" )
	if #str == 0 then return nil end
	return fromid3:iconv ( str )
end

function find ( fd )
	fd:seek ( "end" , -128 ) -- Look at end of file
	if fd:read ( 3 ) == "TAG" then
		return fd:seek ( "end" , -128 )
	else
		return false
	end
end

function info ( fd , offset )
	--  offset should always be (size of file-128)
	if offset then fd:seek ( "set" , offset ) end
	
	if fd:read ( 3 ) ==  "TAG" then 
		tags = { }
		tags.title = { readstring ( fd:read( 30 ) ) } 
		tags.artist = { readstring ( fd:read ( 30 ) ) } 
		tags.album = { readstring ( fd:read ( 30 ) ) } 
		tags.date = { readstring ( fd:read ( 4 ) ) }
		
		do -- ID3v1 vs ID3v1.1
			local a = fd:read ( 28 )
			local b = fd:read ( 1 )
			if b == "\0" then -- Check if comment is 28 or 30 characters
				-- Get up to 28 character comment
				fd:seek ( "cur" , -29 )
				tags.comment = { readstring ( a , 28 ) }
				
				-- Get track number
				local track = string.byte ( fd:read ( 1 ) )
				if track ~= 0 then tags.tracknumber = { track } end
			else -- Is ID3v1, could have a 30 character comment tag
				tags.comment = { readstring ( a .. b .. fd:read ( 1 ) ) } 
			end
		end
		
		tags.genre = { genreindex [ tonumber ( string.byte( fd:read ( 1 ) ) ) ] }
		
		-- Check for extended tags (Note: these are damn rare, worthwhile supporting them??)
		fd:seek ( "end" , -355 )
		if fd:read ( 4 ) == "TAG+" then
			tags.title [ 1 ] = tags.title[1] .. readstring ( fd:read ( 60 ) )
			tags.artist [ 1 ] = tags.artist[1] .. readstring ( fd:read ( 60 ) )
			tags.album [ 1 ] = tags.album[1] .. readstring ( fd:read ( 60 ) )
			tags.speed = { speedindex [ tonumber ( string.byte ( fd:read ( 1 ) ) ) ] }
			tags.genre [ 2 ] = readstring ( fd:read ( 30 ) )
			do
				local start = readstring ( fd:read ( 30 ) )
				if #start == 6 and start:sub ( 4 , 4 ) == ":" then
					tags["start-time"] = { tostring ( tonumber ( start:sub ( 1 , 3 ) ) * 60 + start:sub ( 5 , 6 ) ) }
				end
				local fin = readstring ( fd:read ( 30 ) )
				if #fin == 6 and fin:sub ( 4 , 4 ) == ":" then
					tags["end-time"] = { tostring ( tonumber ( fin:sub ( 1 , 3 ) ) * 60 + fin:sub ( 5 , 6 ) ) }
				end
			end
			
		end
		return tags , { }
	else
		-- File doesn't have an ID3v1 Tag
		return false
	end
end

local function guessyear ( datestring )
	function twodigityear ( capture )
		if tonumber ( capture ) < 30 then -- Break on 30s
			return "20"..capture 
		else return "19" .. capture
		end
	end
	local patterns = {
		[".*%f[%d](%d%d%d%d)%f[%D].*"] = { matches = 1 , replace = "%1" }, -- MAGICAL FRONTIER PATTERN (undocumented)
		["^%W*(%d%d)%W*$"] = { matches = 1 , replace = twodigityear }, -- Eg: 70 or '70
		["^%s*%d%d?%s*[/-%s]%s*%d%d?%s*[/-%s]%W*(%d%d)%s*$"] = { matches = 1 , replace = twodigityear }, -- Eg: 20/4/87
		[".*Year%W*(%d%d)%W.-"] = { matches = 1 , replace = twodigityear }, -- Eg: Month: October, Year: 69
		[".*%W(%d%d)%W*$"] = { matches = 1 , replace = twodigityear }, -- Eg: Concert of '97.
	}
	for k , v in pairs ( patterns ) do
		local s , m = string.gsub ( datestring , k , v.replace )
		if m == v.matches then return s end
	end
	return false
end

local function makestring ( str , tolength )
	str = toid3:iconv ( str )
	str = string.sub ( str , 1 , tolength )
	return str .. string.rep ( "\0" , tolength-#str )
end

function generatetag ( tags )	
	local title , artist , album, year , comment , track , genre
	
	-- Title
	if type( tags.title ) == "table" then 
		title = tags.title
	else title = { "" }
	end
	title = makestring ( title [ 1 ] , 30 )
	
	do -- Artist
		local t
		if type( tags.artist ) == "table" then 
			t= tags.artist
		else t = { "" }
		end
		artist = string.sub ( t [ 1 ] , 1 , 30 )
		for i=2 , #t-1 do
			if ( #artist + 3 + #t [ i ] ) > 30 then break end
			artist = artist .. " & " .. t [ i ]
		end
		artist = makestring ( artist , 30 )
	end
	
	-- Album
	if type( tags.album ) == "table" then 
		album = tags.album
	else album = { "" }
	end
	album = makestring ( album [ 1 ] , 30 )

	-- Year
	if type( tags.date ) == "table" then 
		year = tags.date
	else year = { "" }
	end
	year = makestring ( ( guessyear ( year [ 1 ] ) or "" ) , 4 )
	
	-- Comment
	if tags.comment and #tags.comment [ 1 ] <= 28 then
		comment = tags.comment [ 1 ]
	else
		comment = ""
	end
	-- No one likes 28 character comments
	comment = makestring ( comment , 28 )

	-- Track
	if type( tags.track ) == "table" then 
		track = tags.tracknumber
	else track = { "" }
	end
	track = string.char ( tonumber ( track [ 1 ] ) or 0 )
	
	-- Genre
	if type( tags.genre ) == "table" then 
		genre = toid3:iconv ( tags.genre [ 1 ] )
	else 
		genre = ""
	end
	do
		local t = 12 -- "Other"
		for i , v in ipairs ( genreindex ) do
			if string.find ( genre:lower ( ) , string.gsub ( v:lower ( ) , "%W" , "." ) ) then t = i break end 
		end
		genre = string.char ( t )
	end
	
	local datadiscarded = false
	for k , v in pairs ( tags ) do
		if k == "title" or k == "artist" or k == "album" or k == "date" or k == "tracknumber" or k == "genre" then
			if v [ 2 ] then
				datadiscarded = true
				break
			end
		else
			datadiscarded = true
			break
		end
	end
	local tag = "TAG" .. title .. artist .. album .. year .. comment .. "\0" .. track .. genre -- String format doesn't like \0. --string.format ( "TAG%s%s%s%s%s\0%s%s" , title , artist , album , year , comment , track , genre)
	return tag , datadiscarded
end

function edit ( path , tags , inherit )
	local fd , err = io.open ( path , "rb+" )
	if not fd then return ferror ( err , 3 ) end
	
	if inherit then 
		local currenttags= info ( fd ) -- inherit from current data
		for k , v in pairs ( currenttags ) do
			for i , v in ipairs ( v ) do
				table.insert ( tags [ k ] , v )
			end
		end
	end
	
	local id3 = generatetag ( tags )
	
	if #id3 ~= 128 then return ferror ( "Unknown error" , 3 ) end
	
	-- Check if file already has an ID3 tag
	local starttag = find ( fd )
	if not starttag then -- If file has no id3v1 tag
		fd:seek ( "end" ) -- make tag at end of file
	end
	local ok , err = fd:write ( id3 )
	if not ok then return ok , fail end
	fd:flush ( )
	
	return 
end
