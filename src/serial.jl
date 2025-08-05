using LibSerialPort
import StaticArrays: SVector
export EspMcpSerial

mutable struct EspMcpSerial <: AbstractInputDev
    devname::String
    devtype::String
    com::String
    baudrate::Int32
    timeout::Float64
    buffer::CircularBuffer{SVector{80,UInt8}}
    task::DaqTask
    config::DaqConfig
    chans::DaqChannels{Vector{Int}}
    usethread::Bool
    vref::Float64
end


"Returns the serial com"
serialport(dev::EspMcpSerial) = dev.com



DAQCore.devtype(dev::EspMcpSerial) = "ESPMCP"

DAQCore.isreading(dev::EspMcpSerial) = isreading(dev.task)

"How many samples have been read?"
DAQCore.samplesread(dev::EspMcpSerial) = samplesread(dev.task)

function Base.show(io::IO, dev::EspMcpSerial)
    println(io, "EspMcpSerial")
    println(io, "    Dev Name: $(devname(dev))")
    println(io, "    COM: $(dev.com)")
    println(io, "    Baudrate: $(dev.baudrate)")
end



function EspMcpSerial(; devname="ESPMCP", com="/dev/ttyUSB0", timeout=1,
                      buflen=10, tag="", sn="",
                      baudrate=115200, usethread=true, vref=2.5)
    dtype = "ESPMCP"
    LibSerialPort.open(com, baudrate) do io
        println(io, ".A10")
        readline(io)
        println(io, ".F", 1)
        readline(io)
        println(io, ".P", 100)
        readline(io)
        
    end
    
    config = DaqConfig(com=com, baudrate=baudrate,
                       avg=10, fps=1, period=100, tag=tag, sn=sn,
                       vref=float(vref))
    buf = CircularBuffer{SVector{80,UInt8}}(buflen)
    task = DaqTask()
    
    ch = DaqChannels("E" .* numstring.(1:32), collect(1:32))
    return EspMcpSerial(devname, dtype, com, baudrate, float(timeout),
                        buf, task, config, ch, usethread, vref)
    
end


function DAQCore.daqaddinput(dev::EspMcpSerial, chans=1:32; names="E")
    
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


function DAQCore.daqconfigdev(dev::EspMcpSerial; kw...)
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
        LibSerialPort.open(dev.com, dev.baudrate) do io
            for a in args
                var = a.first
                val = a.second
                println(io, ".$(cmd[var])$(val))")
                readline(io)
                iparam!(dev.config, var, val)
            end
        end
    end
    return
end

function scan!(dev::EspMcpSerial)
    fps = iparam(dev.config, "fps")
    avg = iparam(dev.config, "avg")
    period = iparam(dev.config, "period")
    tps = 5*max(period,  avg*2) * 0.001  # Time per frame in seconds
    dev.buffer = CircularBuffer{SVector{80,UInt8}}(fps)

    tsk = dev.task
    isreading(tsk) && error("DSA is already reading!")
    cleartask!(tsk)
    
    LibSerialPort.open(dev.com, dev.baudrate) do io
        println(io, "*")
        tsk.isreading = true
        tsk.time = now()
        t0 = time_ns()
        for i in 1:fps
            # Read the response:
            push!(dev.buffer, read(io, 80))
            t1 = time_ns()
            settiming!(tsk, t0, t1, i)
            tsk.nread = i
        end
        tsk.isreading = false
    end
end

function read_voltages(buf, vref)

    N = length(buf)

    E = zeros(32, N)
    t = zeros(Int32, N)
    idx = zeros(Int32, N)
    
    for i in 1:N
        b = buf[i]
        ii = reinterpret(UInt16, b[13:76])
        E[:,i] .= ii .* (vref ./ 4095.0)
        t[i] = reinterpret(Int32, b[5:8])[1]
        idx[i] = reinterpret(Int32, b[9:12])[1]
    end
    
    return E, t, idx
end

function DAQCore.daqstart(dev::EspMcpSerial)
    if isreading(dev)
        error("EspMcp already reading!")
    end
    tsk = Threads.@spawn scan!(dev)
    dev.task.task = tsk
    
    return tsk
end

function DAQCore.daqread(dev::EspMcpSerial)

    wait(dev.task.task)

    E, t, idx = read_voltages(dev.buffer, dev.vref)
    unit = "V"
    hour = dev.task.time

    # fs = samplingrate(dev.task)
    Nt = length(t)
    if Nt == 1
        fs = iparam(dev.config, "period")
    else
        fs = 1000*(Nt-1) / (t[end] - t[begin])
    end
                                
    S = DaqSamplingRate(fs, size(E,2), hour)
    return MeasData(devname(dev), devtype(dev), S, E, dev.chans, fill(unit,32))
end

function DAQCore.daqacquire(dev::EspMcpSerial)
    if isreading(dev)
        error("EspMcp already reading!")
    end

    scan!(dev)

    return daqread(dev)
end

