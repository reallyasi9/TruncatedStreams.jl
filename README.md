# TruncatedStreams

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://reallyasi9.github.io/TruncatedStreams.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://reallyasi9.github.io/TruncatedStreams.jl/dev/)
[![Build Status](https://github.com/reallyasi9/TruncatedStreams.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/reallyasi9/TruncatedStreams.jl/actions/workflows/CI.yml?query=branch%3Amain)

> "...where ignorance is bliss, 'tis folly to be wise"
>
> *-Thomas Gray, "Ode on a Distant Prospect of Eton College"*

## Synopsis
```julia
using TruncatedStreams

io = IOBuffer(collect(0x00:0xff))

fixed_io = FixedLengthIO(io, 10)  # only read the first 10 bytes
@assert length(read(fixed_io)) == 10
@assert eof(fixed_io) == true
@assert eof(io) == false

sentinel_io = SentinelIO(io, [0x10, 0x11])  # only read until the sentinel is read
@assert length(read(sentinel_io)) == 5
@assert eof(sentinel_io) == true
@assert eof(io) == false

close(io)
```

## Lie to me

Julia basically offers two methods for reading some but not all the bytes from an IO object:
- `read(::IO, ::Integer)`, which reads up to some number of bytes from an IO object, allocating and appending to a `Vector{UInt8}` to hold everything it reads; or
- `readuntil(::IO, ::Vector{UInt8})`, which reads bytes from an IO object until a sentinel vector is found, again allocating and appending to a `Vector{UInt8}` to hold everything it reads.

But what if you find yourself in the following situation:
1. You want to read values of many different types from from an IO object.
2. You know you can safely read some number of bytes from the IO object, but no more (either a fixed number or until some sentinel is reached).
3. You do not want to (or cannot) read everything from the IO object into memory at once.

This may seem like a contrived situation, but consider an IO object representing a concatenated series of very large files, like what you might see in a TAR or ZIP archive:
1. You want to treat each file in the archive like a file on disk, reading an arbitrary number of values of arbitrary types from the file.
2. The file either starts with a header that tells you how many bytes long the file is or ends with a sentinel so you know to stop reading.
3. You do not want to (or cannot) read the entire file into memory before parsing.

Enter `TruncatedStreams`. This package exports types that inherit from `Base.IO` and wrap other `Base.IO` objects with one purpose in mind: to lie about EOF. This means you can wrap your IO object and blindly read from it until it signals EOF, just like you would any other IO object. And, if the wrapped IO object supports it, you can write to the stream, seek to a position, skip bytes, mark and reset positions, or do whatever basic IO operation you can think of and not have to worry about whether you remembered to add or subtract the right number of bytes from your running tally, or whether your buffered read accidentally captured half of the sentinel at the end.

Ignorance is bliss.

## Installation
```julia
using Pkg; Pkg.install("TruncatedStreams")
```

## Use

### `FixedLengthIO`
`FixedLengthIO` wraps an `IO` object and will read from it until a certain number of bytes is read, after which `FixedLengthIO` will act as if it has reach end of file:

```julia
julia> using TruncatedStreams

julia> io = IOBuffer(collect(0x00:0xff));

julia> fio = FixedLengthIO(io, 10);  # Only read the next 10 bytes

julia> read(fio, UInt64)  # First 8 bytes
0x0706050403020100

julia> read(fio)  # Everything else
2-element Vector{UInt8}:
 0x08
 0x09

julia> eof(fio)
true
```
### `SentinelIO`
`SentinelIO` wraps an `IO` object and will read from in until a sentinel is found, after which `SentinelIO` will act as if it has reach end of file:

```julia
julia> using TruncatedStreams

julia> io = IOBuffer(collect(0x00:0xff));

julia> sio = SentinelIO(io, [0x10, 0x11, 0x12]);  # Only read until [0x10, 0x11, 0x12] is found

julia> read(sio, UInt64)  # First 8 bytes
0x0706050403020100

julia> read(sio)  # Everything else
8-element Vector{UInt8}:
 0x08
 0x09
 0x0a
 0x0b
 0x0c
 0x0d
 0x0e
 0x0f

julia> eof(sio)
true
```