#Brownian Bridge path construction
export BrownianBridgeConstruction, transform!, transformToUnit!

mutable struct BrownianBridgeConstruction
    sqrtdt::Vector{Float64}
    stdDev::Vector{Float64}
    bridgeIndex::Vector{Int}
    leftIndex::Vector{Int}
    rightIndex::Vector{Int}
    leftWeight::Vector{Float64}
    rightWeight::Vector{Float64}
    pmap::Vector{Int}
end
#=
This is a port of Quantlib code

 Copyright (C) 2003 Ferdinando Ametrano
 Copyright (C) 2006 StatPro Italia srl
 Copyright (C) 2009 Bojan Nikolic

 This file is part of QuantLib, a free-software/open-source library
 for financial quantitative analysts and developers - http://quantlib.org/

 QuantLib is free software: you can redistribute it and/or modify it
 under the terms of the QuantLib license.  You should have received a
 copy of the license along with this program; if not, please email
 <quantlib-dev@lists.sf.net>. The license is also available online at
 <http://quantlib.org/license.shtml>.

 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE.  See the license for more details.
=#
#===========================================================================
 The following copyright notice applies to the original code,

 Copyright (C) 2002 Peter Jäckel "Monte Carlo Methods in Finance".
 All rights reserved.

 Permission to use, copy, modify, and distribute this software is freely
 granted, provided that this notice is preserved.
 ===========================================================================#

#t[1] is first non-zero time, implicitly assumes that first time = 0
function BrownianBridgeConstruction(t::Vector{Float64})
    size = length(t)
    sqrtdt = Vector{Float64}(undef, size)
    sqrtdt[1] = sqrt(t[1])
    @inbounds for i = 2:size
        sqrtdt[i] = sqrt(t[i] - t[i-1])
    end

    # map is used to indicate which points are already constructed.
    # If map[i] is one, path point i is yet unconstructed.
    # map[i]-1 is the index of the variate that constructs
    # the path point i.
    pmap = Vector{Int}(undef, size)
    fill!(pmap, 1)
    bridgeIndex = Vector{Int}(undef, size)
    leftIndex = Vector{Int}(undef, size)
    rightIndex = Vector{Int}(undef, size)
    stdDev = Vector{Float64}(undef, size)
    leftWeight = Vector{Float64}(undef, size)
    rightWeight = Vector{Float64}(undef, size)

    #  The first point in the construction is the global step.
    pmap[size] = 2
    #  The global step is constructed from the first variate.
    bridgeIndex[1] = size
    #  The variance of the global step
    stdDev[1] = sqrt(t[size])
    #  The global step to the last point in time is special.
    leftWeight[1] = 0.0
    rightWeight[1] = 0.0
    j = 1
    for i = 2:size
        # Find the next unpopulated entry in the map.
        while pmap[j] != 1
            j += 1
        end
        k = j
        # Find the next populated entry in the map from there.
        while pmap[k] == 1
            k += 1
        end
        # l-1 is now the index of the point to be constructed next.
        l = j + ((k - 1 - j) >> 1)
        pmap[l] = i
        # The i-th Gaussian variate will be used to set point l-1.
        bridgeIndex[i] = l
        leftIndex[i] = j
        rightIndex[i] = k
        if j != 1
            leftWeight[i] = (t[k] - t[l]) / (t[k] - t[j-1])
            rightWeight[i] = (t[l] - t[j-1]) / (t[k] - t[j-1])
            stdDev[i] = sqrt(((t[l] - t[j-1]) * (t[k] - t[l])) / (t[k] - t[j-1]))
        else
            leftWeight[i] = (t[k] - t[l]) / t[k]
            rightWeight[i] = t[l] / t[k]
            stdDev[i] = sqrt(t[l] * (t[k] - t[l]) / t[k])
        end
        j = k + 1
        if j > size
            j = 1 #  wrap around
        end
    end
    return BrownianBridgeConstruction(
        sqrtdt,
        stdDev,
        bridgeIndex,
        leftIndex,
        rightIndex,
        leftWeight,
        rightWeight,
        pmap,
    )
end

function transformToUnit!(
    bb::BrownianBridgeConstruction,
    in::Vector{Float64},
    out::Vector{Float64},
)
    transform!(bb, in, out)
    size = length(bb.stdDev)
    @. out /= bb.sqrtdt
    return out
end

function transform!(
    bb::BrownianBridgeConstruction,
    in::Vector{Float64},
    out::Vector{Float64},
)
    size = length(bb.stdDev)
    # We use output to store the path...
    @inbounds out[size] = bb.stdDev[1] * in[1]
    @inbounds for i = 2:size
        j = bb.leftIndex[i]
        k = bb.rightIndex[i]
        l = bb.bridgeIndex[i]
        if j != 1
            @inbounds out[l] =
                bb.leftWeight[i] * out[j-1] +
                bb.rightWeight[i] * out[k] +
                bb.stdDev[i] * in[i]
        else
            @inbounds out[l] = bb.rightWeight[i] * out[k] + bb.stdDev[i] * in[i]
        end
    end
    # ...after which, we calculate the variations
    @inbounds for i = size:-1:2
        out[i] -= out[i-1]
    end
    return out
end

#return the dW_i
function transform!(
    bb::BrownianBridgeConstruction,
    in::Vector{Float64},  #of (d * ntimes). 1,...,d used for first time, d+1,...d+d for second time.
    out::Array{Float64,2}, #size (d,ntimes) retrieve column(ti) = out[:,ti] (column major order)
)
    transformToPath!(bb,in,out)
    # ...after which, we calculate the variations
    d = size(out, 1) #number of rows
    bsize = length(bb.stdDev)
    @inbounds for i = bsize:-1:2
        for di = 1:d
            out[di, i] -= out[di, i-1]
        end
    end
    return out
end


function transformToPath!(
    bb::BrownianBridgeConstruction,
    in::Vector{Float64},  #of (d * ntimes). 1,...,d used for first time, d+1,...d+d for second time.
    out::Array{Float64,2}, #size (d,ntimes) retrieve column(ti) = out[:,ti] (column major order)
)
    d = size(out, 1) #number of rows
    bsize = length(bb.stdDev)
    # We use output to store the path...
    @inbounds for di = 1:d
        out[di, bsize] = bb.stdDev[1] * in[di]
    end
    @inbounds for i = 2:bsize
        j = bb.leftIndex[i]
        k = bb.rightIndex[i]
        l = bb.bridgeIndex[i]
        if j != 1
            for di = 1:d
                out[di, l] =
                    bb.leftWeight[i] * out[di, j-1] +
                    bb.rightWeight[i] * out[di, k] +
                    bb.stdDev[i] * in[(i-1)*d+di]
            end
        else
            for di = 1:d
                out[di, l] =
                    bb.rightWeight[i] * (out[di, k]) + bb.stdDev[i] * in[(i-1)*d+di]
            end
        end
    end
  
    return out
end
