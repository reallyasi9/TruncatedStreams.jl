"""
TruncatedIO <: IO

Wraps a streaming IO object that reads only as much as should be read and not a byte more.

Objects inheriting from this abstract type pass along all IO methods to the wrapped stream
except for `bytesavailable(io)` and `eof(io)`. Inherited types _must_ implement:
- `TruncatedStreams.unwrap(::TruncatedIO)::IO`: return the wrapped IO stream.
- `Base.eof(::TruncatedIO)::Bool`: report whether the stream cannot produce any more bytes.

In order to implement truncation, some number of these methods will likely need to be
implemented:
- `Base.unsafe_read(::TruncatedIO, p::Ptr{UInt8}, n::UInt)::Nothing`: copy `n` bytes from the stream into memory pointed to by `p`.
- `Base.read(::TruncatedIO, T::Type)::T`: read and return an object of type `T` from the stream.
- `Base.bytesavailable(::TruncatedIO)::Int`: report the number of bytes available to read from the stream until EOF or a buffer refill.
- `Base.seek(::TruncatedIO, p::Integer)` and `Base.seekend(::TruncatedIO)`: seek stream to position `p` or end of stream.
- `Base.reset(::TruncatedIO)`: reset a marked stream to the saved position.
- `Base.reseteof(::TruncatedIO)::Nothing`: reset EOF status.

Note that writing to the stream does not affect truncation.
"""
abstract type TruncatedIO <: IO end

"""
unwrap(s<:TruncatedIO) -> IO

Return the wrapped source.
"""
function unwrap end

# unary functions
for func in (
    :lock,
    :unlock,
    :isopen,
    :close,
    :flush,
    :position,
    :mark,
    :unmark,
    :reset,
    :ismarked,
    :isreadable,
    :iswritable,
    :seekend,
)
    @eval Base.$func(s::TruncatedIO) = Base.$func(unwrap(s))
end

# newer functions for half-duplex close
@static if VERSION >= v"1.8"
    for func in (:closewrite,)
        @eval Base.$func(s::TruncatedIO) = Base.$func(unwrap(s))
    end
end

# n-ary functions
Base.seek(s::TruncatedIO, n::Integer) = seek(unwrap(s), n)
Base.skip(s::TruncatedIO, n::Integer) = skip(unwrap(s), n)
Base.unsafe_read(s::TruncatedIO, p::Ptr{UInt8}, n::UInt) = unsafe_read(unwrap(s), p, n)
Base.unsafe_write(s::TruncatedIO, p::Ptr{UInt8}, n::UInt) = unsafe_write(unwrap(s), p, n)

# required to override byte-level reading of objects by delegating to unsafe_read
function Base.read(s::TruncatedIO, ::Type{UInt8})
    r = Ref{UInt8}()
    unsafe_read(s, r, 1)
    return r[]
end

"""
FixedLengthIO(io, length) <: TruncatedIO

A truncated source that reads `io` up to `length` bytes.

```jldoctest fixedlengthio_1
julia> io = IOBuffer(collect(0x00:0xff));

julia> fio = FixedLengthIO(io, 10);

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

As soon as a read from a `FixedLengthIO` object would read past `length` bytes of the
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

Writing to a `FixedLengthIO` object does not affect the length at which the stream is
truncated, but may affect how many bytes are available to read.

```jldoctest fixedlengthio_2
julia> io = IOBuffer(collect(0x00:0x05); read=true, write=true); fio = FixedLengthIO(io, 10);

julia> read(fio)
6-element Vector{UInt8}:
 0x00
 0x01
 0x02
 0x03
 0x04
 0x05

julia> write(fio, collect(0x06:0xff));

julia> seekstart(fio);  # writing advances the IOBuffer's read pointer

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
```
"""
mutable struct FixedLengthIO{S<:IO} <: TruncatedIO
    wrapped::S
    length::Int
    remaining::Int

    FixedLengthIO(io::S, length::Integer) where {S} = new{S}(io, length, length)
end

unwrap(s::FixedLengthIO) = s.wrapped

Base.bytesavailable(s::FixedLengthIO) = min(s.remaining, bytesavailable(unwrap(s)))

Base.eof(s::FixedLengthIO) = eof(unwrap(s)) || s.remaining <= 0

function Base.unsafe_read(s::FixedLengthIO, p::Ptr{UInt8}, n::UInt)
    # note that the convention from IOBuffer is to read as much as possible first,
    # then throw EOF if the requested read was beyond the number of bytes available.
    available = bytesavailable(s)
    to_read = min(available, n)
    unsafe_read(unwrap(s), p, to_read)
    s.remaining -= to_read
    if to_read < n
        throw(EOFError())
    end
    return nothing
end

function Base.seek(s::FixedLengthIO, n::Integer)
    pos = clamp(n, 0, s.length)
    s.remaining = s.length - pos
    return seek(unwrap(s), n)
end

Base.seekend(s::FixedLengthIO) = seek(s, s.length)

function Base.skip(s::FixedLengthIO, n::Integer)
    # negative numbers will add bytes back to bytesremaining
    bytes = clamp(Int(n), s.remaining - s.length, s.remaining)
    return seek(s, position(s) + bytes)
end

function Base.reset(s::FixedLengthIO)
    pos = reset(unwrap(s))
    seek(s, pos) # seeks the underlying stream as well, but that should be a noop
    return pos
end

"""
SentinelIO(io, sentinel) <: TruncatedIO

A truncated source that reads `io` until `sentinel` is found.

Can be reset with the `reseteof()` method if the sentinel read is discovered upon further
inspection to be bogus.
"""
mutable struct SentinelIO{S<:IO} <: TruncatedIO
    wrapped::S
    sentinel::Vector{UInt8}
    buffer::Vector{UInt8}
    failure_function::Vector{Int}
    skip_next_eof::Bool

    function SentinelIO(io::S, sentinel::AbstractVector{UInt8}) where {S<:IO}
        buffer = read(io, length(sentinel))
        if length(buffer) < length(sentinel)
            throw(EOFError())
        end
        # generate the failure function for the Knuth–Morris–Pratt algorithm
        ff = Vector{Int}(undef, length(sentinel))
        ff[1] = 0
        pos = 2
        cnd = 1
        while pos <= length(sentinel)
            if sentinel[pos] == sentinel[cnd]
                ff[pos] = ff[cnd]
            else
                ff[pos] = cnd
                while cnd > 0 && ff[pos] != ff[cnd]
                    cnd = ff[cnd]
                end
            end
            pos += 1
            cnd += 1
        end
        return new{S}(io, sentinel, buffer, ff, false)
    end
end

unwrap(s::SentinelIO) = s.wrapped

function Base.bytesavailable(s::SentinelIO)
    if eof(unwrap(s))
        # make sure the last bytes in the buffer can be read
        if s.buffer != s.sentinel
            return length(s.buffer)
        else
            return 0
        end
    end

    # search the buffer for the longest prefix match of the sentinel
    jb = 1 # buffer index
    ks = 1 # sentinel index

    while jb <= length(s.buffer)
        if s.sentinel[ks] == s.buffer[jb]
            # byte matches sentinel, move to next
            jb += 1
            ks += 1
        else
            # byte does not match, determine where in the sentinel to restart the search
            ks = s.failure_function[ks]
            if ks == 0
                # next byte not in sentinel, reset to beginning
                jb += 1
                ks = 1
            end
        end
    end

    # at this point, ks-1 bytes have matched at the end of the buffer
    remaining = length(s.buffer) - ks + 1
    if remaining == 0 && s.skip_next_eof
        return 1 # allow a single byte to be read
    else
        return remaining
    end
end

Base.eof(s::SentinelIO) = bytesavailable(s) == 0

function Base.unsafe_read(s::SentinelIO, p::Ptr{UInt8}, n::UInt)
    # read available bytes, checking for sentinel each time
    to_read = n
    ptr = 0
    available = bytesavailable(s)
    while to_read > 0 && available > 0
        this_read = min(to_read, available)
        # buffer: [ safe_1, safe_2, ..., safe_(available), unsafe_1, unsafe_2, ..., unsafe_(end)]
        buf = s.buffer
        GC.@preserve buf unsafe_copyto!(p + ptr, pointer(buf), this_read)
        ptr += this_read
        circshift!(buf, -this_read)
        # buffer: [ safe_(this_read + 1), safe_(this_read + 2), ..., safe_(available), unsafe_1, unsafe_2, ..., unsafe_(end), safe_1, safe_2, ..., safe_(this_read)]
        n_read = readbytes!(unwrap(s), @view(buf[end-this_read+1:end]), this_read)
        # a successful read of anything resets the eof skip
        s.skip_next_eof = false
        if n_read < this_read
            # this happens because we fell off the face of the planet, so clear the buffer
            copyto!(s.buffer, s.sentinel)
            throw(EOFError())
        end
        to_read -= this_read
        available = bytesavailable(s)
    end

    if to_read > 0
        # this happens because we couldn't read everything we wanted to read, so clear the buffer
        copyto!(s.buffer, s.sentinel)
        throw(EOFError())
    end

    return nothing
end

Base.position(s::SentinelIO) = position(unwrap(s)) - length(s.buffer)  # lie about where we are in the stream

function Base.seek(s::SentinelIO, n::Integer)
    # seeking backwards is only possible if the wrapped stream allows it.
    # seeking forwards is easier done as reading and dumping data.
    pos = max(n, 0)
    p = position(s)
    bytes = pos - p
    if bytes <= 0
        seek(unwrap(s), pos)
        # fill the buffer again, which should be guaranteed to work, but check just in case
        nb = readbytes!(unwrap(s), s.buffer, length(s.buffer))
        if nb != length(s.buffer)
            throw(EOFError())
        end
    else
        # drop remainder on the floor
        read(s, bytes)
    end
    return s
end

Base.seekend(s::SentinelIO) = read(s) # read until the end

Base.skip(s::SentinelIO, n::Integer) = seek(s, position(s) + n)

function Base.mark(s::SentinelIO)
    pos = mark(unwrap(s))
    # lie about where we are in the stream
    return pos - length(s.buffer)
end

function Base.reset(s::SentinelIO)
    pos = reset(unwrap(s))
    # refill the buffer manually
    seek(unwrap(s), pos - length(s.buffer))
    nb = readbytes!(unwrap(s), s.buffer, length(s.buffer))
    if nb != length(s.buffer)
        throw(EOFError())
    end
    # lie about where the current position is
    return pos - length(s.buffer)
end

function Base.reseteof(s::SentinelIO)
    Base.reseteof(unwrap(s))
    s.skip_next_eof = true
    return nothing
end