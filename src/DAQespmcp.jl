module DAQespmcp

using DAQCore
import DataStructures: CircularBuffer
import Dates: now

#include("wificlient.jl")
include("xmlrpc.jl")
include("serial.jl")

end


