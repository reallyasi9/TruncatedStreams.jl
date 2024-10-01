"""
    FixedLengthSource(io, length) <: TruncatedSource

A truncated source that reads `io` up to `length` bytes.

```jldoctest fixedlengthio_1
julia> io = IOBuffer(collect(0x00:0xff));

julia> fio = FixedLengthSource(io, 10);

julia> read(fio)
10-element Vector{UInt8}:
 0x00
 0x01
 0x02
 0x03
 0x04
 0x05
 0x06
 0x07
 0x08
 0x09

julia> eof(fio)
true
```

As soon as a read from a `FixedLengthSource` object would read past `length` bytes of the
underlying IO stream, EOF is signalled, potentially leading to an `EOFError` being thrown.

```jldoctest fixedlengthio_1
julia> read(fio, Int)
ERROR: EOFError: read end of file
[...]
```

Seeking does not affect the length at which the stream is truncated, but may affect how many
bytes are available to read.

```jldoctest fixedlengthio_1
julia> seek(fio, 8); read(fio)
2-element Vector{UInt8}:
 0x08
 0x09
```
"""
mutable struct FixedLengthSource{S<:IO} <: TruncatedSource
    wrapped::S
    length::Int64
    remaining::Int64

    FixedLengthSource(io::S, length::Integer) where {S} = new{S}(io, length, length)
end

unwrap(s::FixedLengthSource) = s.wrapped

Base.bytesavailable(s::FixedLengthSource) = min(s.remaining, bytesavailable(unwrap(s)))

Base.eof(s::FixedLengthSource) = eof(unwrap(s)) || s.remaining <= 0

function Base.unsafe_read(s::FixedLengthSource, p::Ptr{UInt8}, n::UInt)
    # note that the convention from IOBuffer is to read as much as possible first,
    # then throw EOF if the requested read was beyond the number of bytes available.
    @assert !signbit(s.remaining)
    p_end = p + n
    while p != p_end && !eof(s)
        m = UInt(min(p_end - p, bytesavailable(s)))
        if iszero(m)
            b = read(unwrap(s), UInt8)
            unsafe_store!(p, b)
            p += UInt(1)
            s.remaining -= 1
        else
            # This must not throw due to bytesavailable check
            unsafe_read(unwrap(s), p, m)
            p += m
            s.remaining -= m
        end
    end
    @assert !signbit(s.remaining)
    if p != p_end
        throw(EOFError())
    end
    return nothing
end

function Base.seek(s::FixedLengthSource, n::Integer)
    pos = clamp(Int64(n), Int64(0), s.length)
    s.remaining = s.length - pos
    seek(unwrap(s), pos)
    return s
end

Base.seekend(s::FixedLengthSource) = seek(s, s.length)

function Base.skip(s::FixedLengthSource, n::Integer)
    # negative numbers will add bytes back to bytesremaining
    bytes = clamp(Int64(n), s.remaining - s.length, s.remaining)
    s.remaining -= bytes
    skip(unwrap(s), bytes)
    return s
end

function Base.reset(s::FixedLengthSource)
    pos = reset(unwrap(s))
    seek(s, pos) # seeks the underlying stream as well, but that should be a noop
    return pos
end

function Base.peek(s::FixedLengthSource, T::Type = UInt8)
    if sizeof(T) > bytesavailable(s)
        throw(EOFError())
    end
    return peek(unwrap(s), T)
end