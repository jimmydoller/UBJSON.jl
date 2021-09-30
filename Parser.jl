module Parser

include("bytes.jl")

# Using Mmap prevents the whole thing being in memory twice!!

mutable struct StreamingParserState{T <: IO}
	io::T
	cur::UInt8
	used::Bool
end

@inline incr!(ps::StreamingParserState) = (ps.used = true)

function byteat(ps::StreamingParserState)
	if ps.used
		ps.used = false
		if eof(ps.io)
            error("Unexpected EOF")
        else
            ps.cur = read(ps.io, UInt8)
        end
    end
    ps.cur
end

function read_stream(args...) # FIXME
	incr!(args[1]) # can I send ps.io but incr! ps?
	if length(args) < 1
		read(args[1].io)
	else
		read(args[1].io, args[2:end]...)
	end
end

# parse_funcs should always either read the byte or not read the byte

function parse_next(ps)
	byte = byteat(ps)
	type = get_type(byte)

	incr!(ps)

	p = parse_value(ps, type)

	p
end

parse_value(ps, type) = ntoh(read_stream(ps, type))

function parse_value(ps, type::Type{String})
	sz = parse_next(ps)
	if !(sz isa Integer)
		error("Length of string not an integer")
	end
	String(read_stream(ps, sz))
end

function parse_value(ps, type::Union{Type{Bool}, Type{Nothing}})
	byte = byteat(ps)

	byte == TRUE  ? true    :
	byte == FALSE ? false   :
	byte == NOOP  ? nothing :
	byte == NULL  ? nothing :
	error("Not single byte value")
end

function parse_value(ps, type::Type{Vector})
	byte = byteat(ps)

	if byte == TYPE
		incr!(ps)
		type = get_type(byteat(ps))
		incr!(ps)
		if byteat(ps) == COUNT
			incr!(ps)
		else
			error("malformed")
		end
		count = parse_next(ps) # @assert?
		optim_array(ps, type, count)
	elseif byte == COUNT
		count = parse_next(ps)
		parse_array(ps, count)
	else
		parse_array(ps)
	end
end

function parse_value(ps, type::Type{Dict})
	byte = byteat(ps)

	if byte == TYPE
		incr!(ps)
		type = get_type(byteat(ps))
		count = parse_next(ps) # Maybe i dont like this? Feel like it's pretty fine idk.
		optim_dict(ps, type, count)
	elseif byte == COUNT
		count = parse_next(ps)
		parse_object(ps, count)
	else
		parse_object(ps)
	end
end


optim_array(ps, type::Type{UInt8}, count) = read_stream(ps, count)

optim_array(ps, type::Type{String}, count) = [parse_value(ps, String) for _ in 1:count]

# Need BigInt, Bool, Null, and Noop

optim_array(ps, type, count) = [read_stream(ps, type) for _ in 1:count] # Can I generalize this? Vector takes 1 type and Dict two, but keys for Dict are always String]

parse_array(ps, count) = [parse_next(ps) for _ in 1:count]

function parse_array(ps)
	v = Vector()
	while (byte = byteat(ps)) ≠ ARRAY_END
		push!(v, parse_next(ps))
    end
    v
end

function parse_object(ps)
	d = Dict()

	while (byte = byteat(ps)) ≠ OBJECT_END
		key = parse_value(ps, String)

        d[key] =  parse_next(ps)
    end
    d
end

function optimize_container(ps, byte)
	type = get_type(byteat(ps))
	if byteat(ps) ≠ COUNT
		error("Set type but no count")
	end
	sz = parse_value(ps)
	optim_num(ps, type, sz)
end

function get_type(byte)

    byte == INT8         ? Int8    :
    byte == UINT8        ? UInt8   :
    byte == INT16        ? Int16   :
    byte == INT32        ? Int32   :
    byte == INT64        ? Int64   :
    byte == FLOAT32      ? Float32 :
    byte == FLOAT64      ? Float64 :
    byte == HPN          ? BigInt  : # Not sure about this one
    byte == CHAR         ? Char    :
    byte == STRING       ? String  :
    byte == FALSE        ? Bool    :
    byte == TRUE         ? Bool    :
	byte == OBJECT_BEGIN ? Dict    :
	byte == ARRAY_BEGIN  ? Vector  :
    error("Not a valid type ", byte) # Null and No-op
end

# Convert to little endian??
function parse(io::IOStream)

	ps = StreamingParserState(io, 0x00, true)

	if (byte = byteat(ps)) ≠ 0x7b # '{'
        error("Not UBJSON ", byte)
    end

    parse_next(ps)
end

end
