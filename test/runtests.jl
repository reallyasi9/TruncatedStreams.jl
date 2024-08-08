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
    seek(fio, n)
    @test bytesavailable(fio) == fixed_length - n
    e = read(fio)
    @test e == content[n+1:fixed_length]
    @test eof(fio)

    # seek more and try again
    seekstart(fio)
    @test bytesavailable(fio) == fixed_length
    f = read(fio)
    @test f == first(content, fixed_length)
    @test eof(fio)

    # skip and try again
    skip(fio, -n)
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
    seekend(fio)
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

    io = IOBuffer(content)
    sio = SentinelIO(io, sentinel)
    @test bytesavailable(sio) == fixed_length

    # read < fixed_length bytes
    n = 8
    a = read(sio, n)
    @test a == first(content, n)
    @test bytesavailable(sio) == fixed_length - n

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
    seek(sio, n)
    @test bytesavailable(sio) == fixed_length - n
    e = read(sio)
    @test e == content[n+1:fixed_length]
    @test eof(sio)

    # seek more and try again
    seekstart(sio)
    @test bytesavailable(sio) == fixed_length
    f = read(sio)
    @test f == first(content, fixed_length)
    @test eof(sio)

    # skip and try again
    skip(sio, -n)
    @test bytesavailable(sio) == n
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
    seekend(sio)
    @test position(sio) == fixed_length
end

@run_package_tests verbose = true