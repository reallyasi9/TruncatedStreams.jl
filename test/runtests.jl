using TestItemRunner

@testitem "Ambiguities" begin
    @test isempty(detect_ambiguities(Base, Core, TruncatedStreams))
end

@testitem "FixedLengthIO" begin
    using Random
    rng = MersenneTwister(42)

    content_length = 1024
    content = rand(rng, UInt8, content_length)

    fixed_length = 16
    io = IOBuffer(content; read=true, write=true)
    fio = FixedLengthIO(io, fixed_length)
    @test bytesavailable(fio) == fixed_length

    # read < fixed_length bytes
    n = 8
    a = read(fio, n)
    @test a == first(content, n)
    @test bytesavailable(fio) == fixed_length - n

    # read everything else
    b = read(fio)
    @test b == content[n+1:fixed_length]
    @test bytesavailable(fio) == 0
    @test eof(fio)

    # try reading again
    c = read(fio)
    @test isempty(c)
    @test eof(fio)

    # try really hard to read again
    d = read(fio, 1)
    @test isempty(d)
    @test eof(fio)

    # try really, really hard to read again
    @test_throws EOFError read(fio, UInt8)
    @test eof(fio)

    # seek and try again
    @test seek(fio, n) === fio
    @test bytesavailable(fio) == fixed_length - n
    e = read(fio)
    @test e == content[n+1:fixed_length]
    @test eof(fio)

    # seek more and try again
    @test seekstart(fio) === fio
    @test bytesavailable(fio) == fixed_length
    f = read(fio)
    @test f == first(content, fixed_length)
    @test eof(fio)

    # skip and try again
    @test skip(fio, -n) === fio
    @test bytesavailable(fio) == n
    g = read(fio)
    @test g == content[n+1:fixed_length]
    @test eof(fio)

    # pass through mark, reset, and unmark
    seek(fio, n)
    @test !ismarked(fio)
    @test mark(fio) == n
    @test ismarked(fio)
    seekstart(fio)
    @test read(fio) == first(content, fixed_length)
    @test reset(fio) == n
    @test read(fio) == content[n+1:fixed_length]
    @test !ismarked(fio)
    @test_throws ArgumentError reset(fio)
    @test unmark(fio) == false
    mark(fio)
    @test ismarked(fio)
    @test unmark(fio) == true
    @test !ismarked(fio)

    # pass through position
    seek(fio, n)
    @test position(fio) == n
    seekstart(fio)
    @test position(fio) == 0
    @test seekend(fio) === fio
    @test position(fio) == fixed_length
end

@testitem "SentinelIO" begin
    using Random
    rng = MersenneTwister(42)

    content_length = 1024
    content = rand(rng, UInt8, content_length)
    sentinel_length = 16
    sentinel = rand(rng, UInt8, sentinel_length)
    fixed_length = 256
    content[fixed_length+1:fixed_length+sentinel_length] = sentinel

    # add a second sentinel for reseteof test
    content[fixed_length*2+sentinel_length+1:fixed_length*2+sentinel_length*2] = sentinel

    io = IOBuffer(content)
    sio = SentinelIO(io, sentinel)
    @test bytesavailable(sio) <= fixed_length  # likely going to be length(sentinel), but always <= fixed_length

    # read < fixed_length bytes
    n = 8
    a = read(sio, n)
    @test a == first(content, n)
    @test bytesavailable(sio)  <= fixed_length - n

    # read everything else
    b = read(sio)
    @test b == content[n+1:fixed_length]
    @test bytesavailable(sio) == 0
    @test eof(sio)

    # try reading again
    c = read(sio)
    @test isempty(c)
    @test eof(sio)

    # try really hard to read again
    d = read(sio, 1)
    @test isempty(d)
    @test eof(sio)

    # try really, really hard to read again
    @test_throws EOFError read(sio, UInt8)
    @test eof(sio)

    # seek and try again
    @test seek(sio, n) === sio
    @test bytesavailable(sio) <= fixed_length - n
    e = read(sio)
    @test e == content[n+1:fixed_length]
    @test eof(sio)

    # seek more and try again
    @test seekstart(sio) === sio
    @test bytesavailable(sio) <= fixed_length
    f = read(sio)
    @test f == first(content, fixed_length)
    @test eof(sio)

    # skip and try again
    @test skip(sio, -n) === sio
    @test bytesavailable(sio) <= n
    g = read(sio)
    @test g == content[fixed_length-n+1:fixed_length]
    @test eof(sio)

    # pass through mark, reset, and unmark
    seek(sio, n)
    @test !ismarked(sio)
    @test mark(sio) == n
    @test ismarked(sio)
    seekstart(sio)
    @test read(sio) == first(content, fixed_length)
    @test reset(sio) == n
    @test read(sio) == content[n+1:fixed_length]
    @test !ismarked(sio)
    @test_throws ArgumentError reset(sio)
    @test unmark(sio) == false
    mark(sio)
    @test ismarked(sio)
    @test unmark(sio) == true
    @test !ismarked(sio)

    # pass through position
    seek(sio, n)
    @test position(sio) == n
    seekstart(sio)
    @test position(sio) == 0
    @test seekend(sio) === sio
    @test position(sio) == fixed_length

    # check reseteof and find next sentinel
    @test eof(sio)
    Base.reseteof(sio)
    @test !eof(sio)
    @test read(sio) == content[fixed_length+1:2*fixed_length + sentinel_length]
    @test eof(sio)
    # clear the second sentinel and try to read to end, which should cause an error because the last sentinel was never found
    Base.reseteof(sio)
    @test !eof(sio)
    @test_throws EOFError read(sio)
    @test eof(sio)
    # clearing the second sentinel should keep us at eof
    Base.reseteof(sio)
    @test eof(sio)
    @test isempty(read(sio))
end

@testitem "SentinelIO lazy buffer" begin
    using Random
    rng = MersenneTwister(42)

    content_length = 1024
    content = rand(rng, UInt8, content_length)
    sentinel_length = 16
    sentinel = rand(rng, UInt8, sentinel_length)
    fixed_length = 256
    content[fixed_length+1:fixed_length+sentinel_length] = sentinel

    io = IOBuffer(content)
    sio = SentinelIO(io, sentinel)

    # immediately check position, which should be 0, even though the buffer hasn't been filled yet
    @test position(sio) == 0

    # mark this position, read to fill the buffer, then reset to see if the position is correct
    @test mark(sio) == 0
    a = read(sio)
    @test a == content[begin:fixed_length]
    @test position(sio) == fixed_length
    @test reset(sio) == 0
    @test position(sio) == 0
end

@testitem "SentinelIO strings" begin
    content = "Hello, Julia!"
    sentinel = SubString(content, 6:7)
    io = IOBuffer(content)
    sio = SentinelIO(io, sentinel)

    @test read(sio, String) == "Hello"
    @test eof(sio)
end

@testitem "skip only and seek only" begin
    # in response to https://github.com/reallyasi9/TruncatedStreams.jl/issues/2
    struct SeekOnly{T <: IO} <: IO
        io::T
    end
    Base.seek(so::SeekOnly, pos::Integer) = seek(so.io, pos)
    Base.skip(::SeekOnly, ::Integer) = error("not implemented")
    Base.position(so::SeekOnly) = position(so.io)
    Base.eof(so::SeekOnly) = eof(so.io)
    Base.read(so::SeekOnly, ::Type{UInt8}) = read(so.io, UInt8)

    struct SkipOnly{T <: IO} <: IO
        io::T
    end
    Base.seek(::SkipOnly, ::Integer) = error("not implemented")
    Base.skip(so::SkipOnly, n::Integer) = skip(so.io, n)
    Base.position(so::SkipOnly) = position(so.io)
    Base.eof(so::SkipOnly) = eof(so.io)
    Base.read(so::SkipOnly, ::Type{UInt8}) = read(so.io, UInt8)

    using Random
    rng = MersenneTwister(42)

    content_length = 1024
    content = rand(rng, UInt8, content_length)
    sentinel_length = 16
    sentinel = rand(rng, UInt8, sentinel_length)
    fixed_length = 256
    content[fixed_length+1:fixed_length+sentinel_length] = sentinel

    # FixedLengthIO, skip only
    io = IOBuffer(content)
    skip_io = SkipOnly(io)
    fixed_skip_only = FixedLengthIO(skip_io, fixed_length)
    
    n = 8
    skip(fixed_skip_only, n)
    @test position(fixed_skip_only) == n
    skip(fixed_skip_only, typemax(Int))
    @test position(fixed_skip_only) == fixed_length
    @test eof(fixed_skip_only)

    @test_throws ErrorException seek(fixed_skip_only, n)

    # FixedLengthIO, seek only
    seekstart(io)
    seek_io = SeekOnly(io)
    fixed_seek_only = FixedLengthIO(seek_io, fixed_length)
    
    seek(fixed_seek_only, n)
    @test position(fixed_seek_only) == n
    seek(fixed_seek_only, typemax(Int))
    @test position(fixed_seek_only) == fixed_length
    @test eof(fixed_seek_only)
    seekstart(fixed_seek_only)

    @test_throws ErrorException skip(fixed_seek_only, -n)

    # SentinelIO, skip only
    seekstart(io)
    skip_io = SkipOnly(io)
    sentinel_skip_only = SentinelIO(skip_io, sentinel)
    
    n = 8
    skip(sentinel_skip_only, n)
    @test position(sentinel_skip_only) == n
    skip(sentinel_skip_only, typemax(Int))
    @test position(sentinel_skip_only) == fixed_length
    @test eof(sentinel_skip_only)

    @test_throws ErrorException seek(sentinel_skip_only, n)

    # SentinelIO, seek only
    seekstart(io)
    seek_io = SeekOnly(io)
    sentinel_seek_only = SentinelIO(seek_io, sentinel)
    
    seek(sentinel_seek_only, n)
    @test position(sentinel_seek_only) == n
    seek(sentinel_seek_only, typemax(Int))
    @test position(sentinel_seek_only) == fixed_length
    @test eof(sentinel_seek_only)
    seekstart(sentinel_seek_only)

    @test_throws ErrorException skip(sentinel_seek_only, -n)
end

@testitem "FixedLengthIO large streams on 32-bit systems" begin
    content_length = Int64(1<<32 + 2)
    fixed_length = content_length - 1
    content = Vector{UInt8}(undef, content_length)
    io = IOBuffer(content)
    fio = FixedLengthIO(io, fixed_length)
    
    seekend(fio)
    @test position(fio) == fixed_length
    @test eof(fio)
end

@run_package_tests verbose = true