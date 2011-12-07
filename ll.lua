-- Library for reading low level data

local assert = assert
local unpack = unpack
local floor = math.floor
local strbyte , strchar = string.byte , string.char

local ll = { }

local le_uint_to_num = function ( s , i , j )
	i , j = i or 1 , j or -1
	local b = { strbyte ( s , i , j ) }
	local n = 0
	for i=#b , 1 , -1 do
		n = n*2^8 + b [ i ]
	end
	return n
end
local num_to_le_uint = function ( n , bytes )
	bytes = bytes or 4
	local b = { }
	for i=1 , bytes do
		b [ i ] , n = n % 2^8 , floor ( n / 2^8 )
	end
	assert ( n == 0 )
	return strchar ( unpack ( b ) )
end
local be_uint_to_num = function ( s , i , j )
	i , j = i or 1 , j or -1
	local b = { strbyte ( s , i , j ) }
	local n = 0
	for i=1 , #b do
		n = n*2^8 + b [ i ]
	end
	return n
end
local num_to_be_uint = function ( n , bytes )
	bytes = bytes or 4
	local b = { }
	for i=bytes , 1 , -1 do
		b [ i ] , n = n % 2^8 , floor ( n / 2^8 )
	end
	assert ( n == 0 )
	return strchar ( unpack ( b ) )
end

-- Returns (as a number); bits i to j (indexed from 0)
local extract_bits = function ( s , i , j )
	j = j or i
	local i_byte = floor ( i / 8 ) + 1
	local j_byte = floor ( j / 8 ) + 1

	local n = be_uint_to_num ( s , i_byte , j_byte )
	n = n % 2^( j_byte*8 - i )
	n = floor ( n / 2^( (-(j+1) ) % 8 ) )
	return n
end

-- Look at ith bit in given string (indexed from 0)
-- Returns boolean
local le_bpeek = function ( s , bitnum )
	local byte = floor ( bitnum / 8 ) + 1
	local bit = bitnum % 8
	local char = strbyte ( s , byte )
	return floor ( ( char % 2^(bit+1) ) / 2^bit ) == 1
end
-- Test with:
--local sum = 0 for i=0,31 do v = le_bpeek ( num_to_le_uint ( N , 4 ) , i ) sum=sum + ( v and 1 or 0 )*2^i end assert ( sum == N )

local be_bpeek = function ( s , bitnum )
	local byte = floor ( bitnum / 8 ) + 1
	local bit = 7-bitnum % 8
	local char = strbyte ( s , byte )
	return floor ( ( char % 2^(bit+1) ) / 2^bit ) == 1
end
-- Test with:
--local sum = 0 for i=0,31 do v = be_bpeek ( num_to_be_uint ( N , 4 ) , i ) sum=sum + ( v and 1 or 0 )*2^(31-i) end assert ( sum == N )


return {
	le_uint_to_num = le_uint_to_num ;
	num_to_le_uint = num_to_le_uint ;
	be_uint_to_num = be_uint_to_num ;
	num_to_be_uint = num_to_be_uint ;

	extract_bits = extract_bits ;

	le_bpeek = le_bpeek ;
	be_bpeek = be_bpeek ;
}
