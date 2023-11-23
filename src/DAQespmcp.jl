module DAQespmcp

using Sockets
using DAQCore
import DataStructures: CircularBuffer
import Dates: now

#include("wificlient.jl")
include("xmlrpc.jl")
end


