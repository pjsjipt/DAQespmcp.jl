mutable struct EspMcp <: AbstractInputDev
    devname::String
    devtype::String
    ipaddr::IPv4
    port::Int
    buffer::CircularBuffer{NTuple{80,UInt8}}
    task::DaqTask
    config::DaqConfig
    chans::DaqChannels{Vector{Int}}
    usethread::Bool
    vref::Float64
end

"Returns the IP address of the device"
ipaddr(dev::EspMcp) = dev.ipaddr

"Returns the port number used for TCP/IP communication"
portnum(dev::EspMcp) = dev.port

DAQCore.devtype(dev::EspMcp) = "ESPMCP"

"Is JAnem acquiring data?"
DAQCore.isreading(dev::EspMcp) = isreading(dev.task)

"How many samples have been read?"
DAQCore.samplesread(dev::EspMcp) = samplesread(dev.task)

function Base.show(io::IO, dev::EspMcp)
    println(io, "EspMcp")
    println(io, "    Dev Name: $(devname(dev))")
    println(io, "    IP: $(string(dev.ipaddr))")
    println(io, "    port: $(string(dev.port))")
end

function openespmcp(ipaddr::IPv4, port=9523,  timeout=5)
        
    sock = TCPSocket()
    t = Timer(_ -> close(sock), timeout)
    try
        connect(sock, ipaddr, port)
    catch e
        if isa(e, InterruptException)
            throw(InterruptException())
        else
            error("Could not connect to $ipaddr ! Turn on the device or set the right IP address!")
        end
    finally
        close(t)
    end
    
    return sock
end

openespmcp(dev::EspMcp,  timeout=5) = openespmcp(ipaddr(dev), portnum(dev), timeout)


function openespmcp(fun::Function, ip, port=9525, timeout=5)
    io = openespmcp(ip, port, timeout)
    try
        fun(io)
    catch e
        throw(e)
    finally
        close(io)
    end
end

function openespmcp(fun::Function, dev::EspMcp, timeout=5)
    io = openespmcp(ipaddr(dev), portnum(dev), timeout)
    try
        fun(io)
    catch e
        throw(e)
    finally
        close(io)
    end
end


function EspMcp(; devname="ESPMCP", ip="192.168.0.102", timeout=10, buflen=100_000,
                port=9523, tag="", sn="", usethread=true, vref=2.5)
    dtype = "ESPMCP"
    ipaddr = IPv4(ip)
    openespmcp(ipaddr, port, timeout) do io
        println(io, "!A", 100)
        readline(io)
        println(io, "!F", 1)
        readline(io)
        println(io, "!P", 100)
        readline(io)
    end
    
    config = DaqConfig(ip=ip, port=port, avg=100, fps=1, period=100, tag=tag, sn=sn)
    buf = CircularBuffer{NTuple{80,UInt8}}(buflen)
    task = DaqTask()
    
    ch = DaqChannels("E" .* numstring.(1:32), collect(1:32))

    return EspMcp(devname, dtype, ipaddr, port, buffer, task,
                  config, ch, usethread, vref)
    
end

function DAQCore.daqaddinput(dev::EspMcp, chans=1:32; names="E")
    
    cmin, cmax = extrema(chans)
    if cmin < 1 || cmax > 32
        throw(ArgumentError("Only channels 1-32 are available to ESPMCP"))
    end

    if isa(names, AbstractString) || isa(names, Symbol) || isa(names, AbstractChar)
        chn = string(names) .* numstring.(chans, 2)
    elseif length(names) == length(chans)
        chn = string.(names)
    else
        throw(ArgumentError("Argument `names` should have length 1 or the length of `chans`"))
    end

    ch = DaqChannels(chn, collect(chans))
    dev.chans = ch
    return
end

function DAQCore.daqconfigdev(dev::EspMcp; kw...)
    k = keys(kw)
    cmd = Dict("avg"=>"A", "fps"=>"F", "period"=>"P")
    args = Pair{String,Int}[]

    if :avg ∈ k
        x = kw[:avg]
        if x < 1 || x > 500
            throw(DomainError(x, "avg outside range (1-500)!"))
        end
        push!(args, "avg"=>x)
    end

    if :fps ∈ k
        x = kw[:fps]
        if x < 1 || x > 60_000
            throw(DomainError(x, "fps outside range (1-60000)!"))
        end
        push!(args, "fps"=>x)
    end
    if :period ∈ k
        x = kw[:period]
        if x < 10 || x > 1000
            throw(DomainError(x, "period outside range (1-60000)!"))
        end
        push!(args, "period"=>x)
    end

    if length(args) > 0
        openespmcp(dev) do io
            for a in args
                var = first(a)
                val = second(a)
                readline(io)
                println(io, string("!" * cmd[var] * val))
                iparam!(dev.config, var, val)
            end
        end
    end
    return
end

function scan!(dev::EspMcp)
    fps = iparam(dev.config, "fps")
    avg = iparam(dev.config, "avg")
    period = iparam(dev.config, "period")
    tps = max(period, 10, avg*2) * 0.001  # Time per frame in secoinds
    
    #openespmcp(dev, tps*10) do io
    #    println(io, "*")
end

