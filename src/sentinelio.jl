"""
    SentinelIO(io, sentinel) <: TruncatedIO

A truncated source that reads `io` until `sentinel` is found.

```jldoctest sentinelio_1
julia> io = IOBuffer(collect(0x00:0xff));

julia> sio = SentinelIO(io, [0x0a, 0x0b]);

julia> read(sio)
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

julia> eof(sio)
true
```

As soon as a read from a `SentinelIO` object would read the start of a byte sequence
matching `sentinel` from the underlying IO stream, EOF is signalled, potentially leading to
an `EOFError` being thrown.

```jldoctest sentinelio_1
julia> read(sio, Int)
ERROR: EOFError: read end of file
[...]
```

Seeking does not affect reading of the sentinel, but may affect how many bytes are available
to read.

```jldoctest sentinelio_1
julia> seek(sio, 8); read(sio)
2-element Vector{UInt8}:
 0x08
 0x09
```

Writing to a `SentinelIO` object does not affect the length at which the stream is
truncated, but may affect how many bytes are available to read.


```jldoctest sentinelio_2
julia> io = IOBuffer(collect(0x00:0x07); read=true, write=true); sio = SentinelIO(io, [0x06, 0x07]);

julia> read(sio)
6-element Vector{UInt8}:
 0x00
 0x01
 0x02
 0x03
 0x04
 0x05

julia> write(sio, collect(0x01:0xff));

julia> seekstart(sio);  # writing advances the IOBuffer's read pointer

julia> read(sio)  # still the same output because the sentinel is still there
6-element Vector{UInt8}:
 0x00
 0x01
 0x02
 0x03
 0x04
 0x05
```

Detection of eof can be reset with the `Base.reseteof()` method. Use this if the sentinel
that was read is determined upon further inspection to be bogus.

```jldoctest sentinelio_2
julia> Base.reseteof(sio)  # that last sentinel was fake, so reset EOF and read again

julia> read(sio)  # returns the first sentinel found and continues to read until the next one is found
7-element Vector{UInt8}:
 0x06
 0x07
 0x01
 0x02
 0x03
 0x04
 0x05
```

!!! note
    If the wrapped stream does not contain a sentinel, reading to the end of the stream will
    throw `EOFError`.

```jldoctest sentinelio_3
julia> io = IOBuffer(collect(0x00:0x07)); sio = SentinelIO(io, [0xff, 0xfe]);

julia> read(sio)
ERROR: EOFError: read end of file
[...]
```
"""
mutable struct SentinelIO{S<:IO} <: TruncatedIO
    wrapped::S
    sentinel::Vector{UInt8}
    buffer::Vector{UInt8}
    failure_function::Vector{Int}
    skip_next_eof::Bool
    buffer_length_at_mark::Int

    function SentinelIO(io::S, sentinel::AbstractVector{UInt8}) where {S<:IO}
        sen = Vector{UInt8}(sentinel) # so I have a real Vector
        ns = length(sen)
        # generate the failure function for the Knuth–Morris–Pratt algorithm
        ff = Vector{Int}(undef, ns)
        ff[1] = 0
        pos = 2
        cnd = 1
        while pos <= ns
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
        # lazily fill the buffer only when needed
        buffer = UInt8[]
        return new{S}(io, sen, buffer, ff, false, 0)
    end
end

SentinelIO(io::IO, sentinel::AbstractString) = SentinelIO(io, codeunits(sentinel))

unwrap(s::SentinelIO) = s.wrapped

# count the number of bytes before a prefix match on the next sentinel
function count_safe_bytes(s::SentinelIO, stop_early::Bool=false)
    nb = length(s.buffer)

    if eof(unwrap(s))
        # make sure the last bytes in the buffer can be read
        if s.buffer != s.sentinel
            return nb
        else
            return 0
        end
    end

    # an empty buffer needs to be filled before searching for the sentinel
    if nb < length(s.sentinel)
        nb = readbytes!(unwrap(s), s.buffer, length(s.sentinel))
    end

    # search the buffer for the longest prefix match of the sentinel
    jb = 1 # buffer index
    ks = 1 # sentinel index

    while jb <= nb
        if s.sentinel[ks] == s.buffer[jb]
            # byte matches sentinel, move to next
            jb += 1
            ks += 1
        else
            if stop_early
                return jb
            end
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
    remaining = nb - ks + 1
    if remaining == 0 && s.skip_next_eof
        return 1 # allow a single byte to be read
    else
        return remaining
    end
end

Base.bytesavailable(s::SentinelIO) = count_safe_bytes(s)

Base.eof(s::SentinelIO) = count_safe_bytes(s, true) == 0

# fill the first n bytes of the buffer from the wrapped stream, overwriting what is there
function fill_buffer(s::SentinelIO, n::Integer=length(s.sentinel))
    to_read = min(n, length(s.sentinel))
    nb = readbytes!(unwrap(s), s.buffer, to_read)
    return nb
end

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

        n_read = fill_buffer(s, this_read)
        # buffer: [ new_1, new_2, ..., new_(this_read), safe_(this_read+1), ..., safe_(available), unsafe_1, unsafe_2, ..., unsafe_(end)]

        circshift!(buf, -this_read)
        # buffer: [ safe_(this_read + 1), safe_(this_read + 2), ..., safe_(available), unsafe_1, unsafe_2, ..., unsafe_(end), new_1, new_2, ..., new_(this_read)]

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
        nb = fill_buffer(s)
        if nb != length(s.sentinel)
            throw(EOFError())
        end
    else
        # drop remainder on the floor
        while bytes > 0 && !eof(s)
            # if the number of bytes is too large, reading everything at once will cause a out-of-memory error, so read to EOF instead
            read(s, UInt8)
            bytes -= 1
        end
    end
    return s
end

function Base.seekend(s::SentinelIO)
    write(devnull, s) # read until the end
    return s
end

function Base.skip(s::SentinelIO, bytes::Integer)
    # skipping backwards is only possible if the wrapped stream allows it.
    # skipping forwards is easier done as reading and dumping data.
    if bytes <= 0
        # skip back, including the length of the sentinel, because we have to dump the buffer and reload
        skip(unwrap(s), bytes - length(s.buffer))
        # fill the buffer again, which should be guaranteed to work, but check just in case
        nb = fill_buffer(s)
        if nb != length(s.sentinel)
            throw(EOFError())
        end
    else
        # drop remainder on the floor
        read(s, bytes)
    end
    return s
end

function Base.mark(s::SentinelIO)
    pos = mark(unwrap(s))
    # lie about where we are in the stream
    # noting that the length of the buffer might change
    nb = length(s.buffer)
    s.buffer_length_at_mark = nb
    return pos - nb
end

function Base.reset(s::SentinelIO)
    pos = reset(unwrap(s))
    # refill the buffer manually, which should be guaranteed to work, but check just in case
    seek(unwrap(s), pos - s.buffer_length_at_mark)
    nb = fill_buffer(s)
    if nb != length(s.sentinel)
        throw(EOFError())
    end
    # lie about where the current position is
    return pos - s.buffer_length_at_mark
end

function Base.reseteof(s::SentinelIO)
    Base.reseteof(unwrap(s))
    s.skip_next_eof = true
    return nothing
end