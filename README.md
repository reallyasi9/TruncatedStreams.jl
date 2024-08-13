# TruncatedStreams

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://reallyasi9.github.io/TruncatedStreams.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://reallyasi9.github.io/TruncatedStreams.jl/dev/)
[![Build Status](https://github.com/reallyasi9/TruncatedStreams.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/reallyasi9/TruncatedStreams.jl/actions/workflows/CI.yml?query=branch%3Amain)

## Read to end-of-stream, not to end-of-file.

Julia IO objects offer two methods for reading a number of bytes: `read(io, n)`, which reads `n` bytes from `io` into a `Vector{UInt8}`, and `readuntil(io, s)`, which reads bytes from `io` until a sentinel `s` is found, returning all of the bytes read as a `Vector{UInt8}`.

But what if you want to read many objects from `io` up until you have read `n` bytes, and `n` is larger than available memory? You can't just read everything into a `Vector{UInt8}`, and keeping treack of how many bytes you consume with each call to `read(io, ::Type)` is annoying and not very flexible.

And what if you do not know how many bytes to expect to consume from `io` before you reach the sentinel `s`? It's risky to keep reading everything into a `Vector{UInt8}` until the sentinel is found, because what if that consumes all your available memory? You could read individual objects from `io` using `read(io, ::Type)`, but you would have to check every with every read operation whether you just consumed the sentinel, which is annoying and not very flexible. And what if you accidentally consume part of the sentinel with one `read(io, ::Type)`?

Enter `TruncatedStreams`, and specifically the `FixedLengthIO` and `SentinelIO` types. `FixedLengthIO` wraps an `IO` object and will read from it until a certain number of bytes is read, after which `FixedLengthIO` will act as if it has reach end of file:

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