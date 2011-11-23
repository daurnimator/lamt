-- Library for reading low level data

local hasffi , ffi = pcall ( require , "ffi" )
local hasbit , bit = pcall ( require , "bit" )

local ll = { }

if hasffi and hasbit then
	local uint_to_num = function ( s )
		return ffi.cast ( "uint32_t*" , s )[0]
	end

	local num_to_uint = function ( n )
		return ffi.string ( ffi.new ( "uint32_t[1]" , n ) , 4 )
	end

	if ffi.abi ( "le" ) then
		ll.le_uint_to_num = uint_to_num
		ll.num_to_le_uint = num_to_uint
	elseif ffi.abi ( "be" ) then
		ll.le_uint_to_num = function ( s ) return bit.bswap ( uint_to_num ( s ) ) end
		ll.num_to_le_uint = function ( n ) return num_to_uint ( bit.bswap ( n ) ) end
	else error ( "Unknown endianess" ) end
else
	local strbyte = string.byte
	local strchar = string.char
	local floor = math.floor

	ll.le_uint_to_num = function ( s )
		local b1 , b2 , b3 , b4 = strbyte ( s , 1 , 4 )
		return b4*2^24 + b3*2^16 + b2*2^8 + b1
	end
	ll.num_to_le_uint = function ( n )
		local b1 , b2 , b3 , b4
		b1 , n = n % 2^8 , floor ( n / 2^8 )
		b2 , n = n % 2^8 , floor ( n / 2^8 )
		b3 , n = n % 2^8 , floor ( n / 2^8 )
		b4 , n = n % 2^8 , floor ( n / 2^8 )
		assert ( n == 0 )
		return strchar ( b1 , b2 , b3 , b4 )
	end
end

return ll
