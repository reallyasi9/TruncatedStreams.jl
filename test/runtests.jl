using TestItemRunner

@testitem "Ambiguities" begin
    @test isempty(detect_ambiguities(Base, Core, TruncatedStreams))
end

@testitem "FixedLengthIO" begin
    using Random
    rng = MersenneTwister(42)

    content = rand(rng, UInt8, 1024)
    io = IOBuffer(content)
    fio = FixedLengthIO(io, 16)

    @test bytesavailable(fio) == 16
    a = read(fio, 8)
    @test a == content[1:8]

    @test bytesavailable(fio) == 8
    b = read(fio)
    @test b == content[9:16]
    
    @test bytesavailable(fio) == 0
    @test eof(fio)
end

@testitem "SentinelIO" begin
    using Random
    rng = MersenneTwister(42)

    content = rand(rng, UInt8, 1024)
    sentinel = rand(rng, UInt8, 16)
    content[257:272] = sentinel

    io = IOBuffer(content)
    sio = SentinelIO(io, sentinel)

    @test bytesavailable(sio) == 256
    a = read(sio, 128)
    @test a == content[1:128]

    @test bytesavailable(sio) == 128
    b = read(sio)
    @test b == content[129:256]
    
    @test bytesavailable(sio) == 0
    @test eof(sio)
end

@run_package_tests verbose = true