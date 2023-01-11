export DividendPolicy, priceTRBDF2, NoCalibration, ForwardCalibration
using AQFED.TermStructure
using LinearAlgebra
using PPInterpolation
@enum DividendPolicy begin
    Liquidator
    Survivor
    Shift
end



#TODO use term structure of rates and vols from a model.
#TODO use upstream/downstream deriv/expo fitting if convect dominates.
function priceTRBDF2(definition::StructureDefinition,
    spot::T,
    rawForward::T, #The raw forward to τ (without cash dividends)
    variance::T, #variance to maturity
    discountDf::T, #discount factor to payment date
    dividends::AbstractArray{CapitalizedDividend{T}};
    solverName="TDMA", M=400, N=100, ndev=4, Smax=zero(T), Smin=zero(T), dividendPolicy::DividendPolicy=Liquidator, calibration=NoCalibration(), varianceConditioner::PecletConditioner=NoConditioner()) where {T}
    obsTimes = observationTimes(definition)
    τ = last(obsTimes)
    varianceSurface = FlatSurface(sqrt(variance / τ))
    discountCurve = ConstantRateCurve(-log(discountDf) / τ)
    driftCurve = ConstantRateCurve(log(rawForward / spot) / τ)
    return priceTRBDF2(definition, spot, driftCurve, varianceSurface, discountCurve, dividends, solverName=solverName, M=M, N=N, ndev=ndev, Smax=Smax, Smin=Smin, dividendPolicy=dividendPolicy, calibration=calibration, varianceConditioner=varianceConditioner)
end

function priceTRBDF2(definition::StructureDefinition,
    spot::T,
    driftCurve::Curve, #The raw forward to τ (without cash dividends)
    varianceSurface::VarianceSurface, #variance to maturity
    discountCurve::Curve, #discount factor to payment date
    dividends::AbstractArray{CapitalizedDividend{T}};
    solverName="TDMA", M=400, N=100, ndev=4, Smax=zero(T), Smin=zero(T), dividendPolicy::DividendPolicy=Liquidator, grid="", alpha=0.01, useSpline=true, varianceConditioner::PecletConditioner=NoConditioner(), calibration=NoCalibration()) where {T}
    obsTimes = observationTimes(definition)
    τ = last(obsTimes)
    t = collect(range(τ, stop=zero(T), length=N))
    dividends = filter(x -> x.dividend.exDate <= τ, dividends)
    sort!(dividends, by=x -> x.dividend.exDate)
    divDates = [x.dividend.exDate for x in dividends]
    t = vcat(t, divDates, obsTimes)
    sort!(t, order=Base.Order.Reverse)
    specialPoints = nonSmoothPoints(definition)
    xi = (range(zero(T), stop=one(T), length=M))
    rawForward = spot / df(driftCurve, τ)
    Ui = if Smax == zero(T) || isnan(Smax)
        rawForward * exp(ndev * sqrt(varianceByLogmoneyness(varianceSurface, 0.0, τ)))
    else
        Smax
    end
    Li = if Smin < zero(T) || isnan(Smin)
        rawForward^2 / Smax
    else
        Smin
    end
    if !isempty(specialPoints)
    Ui = max(Ui, maximum(specialPoints))
    Li = min(Li, minimum(specialPoints))
    end
    if grid == "Cubic"
        Si = makeCubicGrid(xi, Li, Ui, specialPoints, alpha) #TODO shift/interpolate
        strikeIndex = searchsortedlast(Si, specialPoints[1]) 
        diff = specialPoints[1] - (Si[strikeIndex]+Si[strikeIndex+1])/2
        if diff^2 > eps(T)
            @. Si += diff
            if diff < 0
                append!(Si, Ui)
            else
                prepend!(Si, Li)
            end
        end
    elseif grid == "Shift" #Shift up, max is changed, not min.
        Si = @. Li + xi * (Ui - Li)
        
        if !isempty(specialPoints)
            strikeIndex = searchsortedlast(Si, specialPoints[1]) #FIXME handle strikeIndex=end
            diff = specialPoints[1] - (Si[strikeIndex]+Si[strikeIndex+1])/2
            if diff^2 > eps(T)
                @. Si += diff
                if diff < 0
                    append!(Si, Ui)
                else
                    prepend!(Si, Li)
                end
            end
        end
        if Smin < zero(T) || isnan(Smin)
            prepend!(Si, zero(T))
        end
    elseif grid == "LogShift" #Li must not be 0...
        Si = @. exp( log(Li) + xi * (log(Ui) - log(Li)))
        if !isempty(specialPoints)
            strikeIndex = searchsortedlast(Si, specialPoints[1]) #FIXME handle strikeIndex=end
            diff = exp(log(specialPoints[1]) - log((Si[strikeIndex]+Si[strikeIndex+1])/2))
            if diff^2 > eps(T)
                @. Si *= diff
                if diff < 1
                    append!(Si, Ui)
                else
                    prepend!(Si, Li)
                end
            end
        end
    else #Unifrom + zero if Smin not defined
        Si = @. Li + xi * (Ui - Li)
        if Smin < zero(T) || isnan(Smin)
            prepend!(Si, zero(T))
        end
    end
   #    println("S ",Si)
    #    println("t ",t)
    tip = t[1]
    payoff = makeFDMStructure(definition, Si)
    advance(payoff, tip)
    evaluate(payoff, Si)
    vLowerBound = zeros(T, length(Si))
    isLBActive = isLowerBoundActive(payoff)
    if isLBActive
        lowerBound!(payoff, vLowerBound)
    else
        ##FIXME how does the solver knows it is active or not?
    end
    vMatrix = currentValue(payoff)
    Jhi = @. (Si[2:end] - Si[1:end-1])
    rhsd = Array{T}(undef, length(Si))
    lhsd = ones(T, length(Si))
    rhsdl = Array{T}(undef, length(Si) - 1)
    lhsdl = Array{T}(undef, length(Si) - 1)
    rhsdu = Array{T}(undef, length(Si) - 1)
    lhsdu = Array{T}(undef, length(Si) - 1)
    lhs = Tridiagonal(lhsdl, lhsd, lhsdu)
    solverLB = if solverName == "TDMA" || solverName == "Thomas"
        TDMAMax{T}()
    elseif solverName == "DoubleSweep"
        DoubleSweep{T}(length(vLowerBound)) #not so great we need to length-can not use it as param to method
    elseif solverName == "LUUL"
        LUUL{T}(length(vLowerBound))
    elseif solverName == "SOR" || solverName == "PSOR"
        PSOR{T}(length(vLowerBound))
    elseif solverName == "BrennanSchwartz"
        BrennanSchwartz{T}(length(vLowerBound))
    else #solverName==PolicyIteration
        TDMAPolicyIteration{T}(length(vLowerBound))
    end
    solver = LowerBoundSolver(solverLB, isLBActive, lhs, vLowerBound)
    rhs = Tridiagonal(rhsdl, rhsd, rhsdu)
    v0Matrix = similar(vMatrix)
    v1 = Array{T}(undef, length(Si))
    #pp = PPInterpolation.PP(3, T, T, length(Si))
    currentDivIndex = length(dividends)
    if (currentDivIndex > 0 && tip == divDates[currentDivIndex])
        #jump and interpolate        
        for v in eachcol(vMatrix)
            # PPInterpolation.computePP(pp, Si, v, PPInterpolation.SECOND_DERIVATIVE, zero(T), PPInterpolation.SECOND_DERIVATIVE, zero(T), C2())       
            pp = QuadraticLagrangePP(Si, copy(v))

            if dividendPolicy == Shift
                @. v = pp(Si - dividends[currentDivIndex].dividend.amount)
            elseif dividendPolicy == Survivor
                @. v = pp(ifelse(Si - dividends[currentDivIndex].dividend.amount < zero(T), Si, Si - dividends[currentDivIndex].dividend.amount))
            else #liquidator
                @. v1 = max(Si - dividends[currentDivIndex].dividend.amount, zero(T))
                evaluateSorted!(pp, v, v1)
                # println("jumped ",currentDivIndex, " of ",dividends[currentDivIndex].dividend.amount," tip ",tip)
            end
        end
        currentDivIndex -= 1
    end
    beta = 2 * one(T) - sqrt(2 * one(T))
    for i = 2:length(t)
        ti = t[i]
        dt = tip - ti
        if dt < 1e-8
            continue
        end
        dfi = df(discountCurve, ti)
        dfip = df(discountCurve, tip)
        ri = calibrateRate(calibration, beta, dt, dfi, dfip)
        driftDfi = df(driftCurve, ti)
        driftDfip = df(driftCurve, tip)
        μi = calibrateDrift(calibration, beta, dt, dfi, dfip, driftDfi, driftDfip, ri)
        σi2 = (varianceByLogmoneyness(varianceSurface, 0.0, tip) * tip - varianceByLogmoneyness(varianceSurface, 0.0, ti) * ti) / (tip - ti)

        @inbounds for j = 2:M-1
            s2S = σi2 * Si[j]^2
            muS = μi * Si[j]
            s2S = conditionedVariance(varianceConditioner, s2S, muS, Si[j], Jhi[j-1], Jhi[j])
            rhsd[j] = one(T) - dt * beta / 2 * ((muS * (Jhi[j-1] - Jhi[j]) + s2S) / (Jhi[j] * Jhi[j-1]) + ri)
            rhsdu[j] = dt * beta / 2 * (s2S + muS * Jhi[j-1]) / (Jhi[j] * (Jhi[j] + Jhi[j-1]))
            rhsdl[j-1] = dt * beta / 2 * (s2S - muS * Jhi[j]) / (Jhi[j-1] * (Jhi[j] + Jhi[j-1]))
        end
        #linear or Ke-rt same thing
        rhsd[1] = one(T) - dt * beta / 2 * (ri + μi * Si[1] / Jhi[1])
        rhsdu[1] = dt * beta / 2 * μi * Si[1] / Jhi[1]

        rhsd[M] = one(T) - dt * beta / 2 * (ri - μi * Si[end] / Jhi[end])
        rhsdl[M-1] = -dt * beta / 2 * μi * Si[end] / Jhi[end]

        v0Matrix[1:end, 1:end] = vMatrix
        advance(payoff, tip - dt * beta)
        for (iv, v) in enumerate(eachcol(vMatrix))
            mul!(v, rhs, @view v0Matrix[:, iv])
            #  evaluate(payoff, Si, iv)  #necessary to update knockin values from vanilla.

        end

        @. lhsd = one(T) - (rhsd - one(T))
        @. lhsdu = -rhsdu
        @. lhsdl = -rhsdl
        # lhsf = lu!(lhs)
        # lhsf = factorize(lhs)
        # ldiv!(v, lhsf , v1)
        decompose(solver, lhs)
        advance(payoff, tip - dt * beta)
        for (iv, v) in enumerate(eachcol(vMatrix))
            isLBActive = isLowerBoundActive(payoff)
            setLowerBoundActive(solver, isLBActive)
            solve!(solver, v1, v)
            v[1:end] = v1
            # evaluate(payoff, Si, iv)  #necessary to update knockin values from vanilla.
            if isLBActive
                lowerBound!(payoff, vLowerBound)
            end
        end

        #BDF2 step
        advance(payoff, ti)
        for (iv, v) in enumerate(eachcol(vMatrix))
            @. v1 = (v - (1 - beta)^2 * @view v0Matrix[:, iv]) / (beta * (2 - beta))
            # ldiv!(v , lhsf ,v1)
            isLBActive = isLowerBoundActive(payoff)
            setLowerBoundActive(solver, isLBActive)
            solve!(solver, v, v1)
            evaluate(payoff, Si, iv)  #necessary to update knockin values from vanilla.
            if isLBActive
                lowerBound!(payoff, vLowerBound)
            end
        end

        tip = ti
        if (currentDivIndex > 0 && tip == divDates[currentDivIndex])
            #jump and interpolate        
            for v in eachcol(vMatrix)
                # PPInterpolation.computePP(pp, Si, v, PPInterpolation.SECOND_DERIVATIVE, zero(T), PPInterpolation.SECOND_DERIVATIVE, zero(T), C2())       
                pp = QuadraticLagrangePP(Si, copy(v))

                if dividendPolicy == Shift
                    @. v = pp(Si - dividends[currentDivIndex].dividend.amount)
                elseif dividendPolicy == Survivor
                    @. v = pp(ifelse(Si - dividends[currentDivIndex].dividend.amount < zero(T), Si, Si - dividends[currentDivIndex].dividend.amount))
                else #liquidator
                    @. v1 = max(Si - dividends[currentDivIndex].dividend.amount, zero(T))
                    evaluateSorted!(pp, v, v1)
                    # println("jumped ",currentDivIndex, " of ",dividends[currentDivIndex].dividend.amount," tip ",tip)
                end
            end
            currentDivIndex -= 1
        end
    end
    #PPInterpolation.computePP(pp,Si, @view(vMatrix[:,end]), PPInterpolation.SECOND_DERIVATIVE, zero(T), PPInterpolation.SECOND_DERIVATIVE, zero(T), C2())
    #return pp
    return QuadraticLagrangePP(Si, vMatrix[:, end])
end

using PolynomialRoots
function makeCubicGrid(xi::AbstractArray{T}, Smin::T, Smax::T, starPoints::AbstractArray{T}, alpha::T; shift=0.0) where {T}
    alphaScaled = alpha * (Smax - Smin)
    coeff = one(T) / 6
    starMid = zeros(T, length(starPoints) + 1)
    starMid[1] = Smin
    starMid[2:end-1] = (starPoints[1:end-1] + starPoints[2:end]) / 2
    starMid[end] = Smax
    c1 = zeros(T, length(starPoints))
    c2 = zeros(T, length(starPoints))
    for i = 1:length(starPoints)
        local r = filter(isreal, PolynomialRoots.roots([(starPoints[i] - starMid[i]) / alphaScaled, one(T), zero(T), coeff]))
        c1[i] = real(sort(r)[1])
        local r = filter(isreal, PolynomialRoots.roots([(starPoints[i] - starMid[i+1]) / alphaScaled, one(T), zero(T), coeff]))
        c2[i] = real(sort(r)[1])
    end
    dd = Array{T}(undef, length(starPoints) + 1)
    dl = Array{T}(undef, length(starPoints))
    dr = Array{T}(undef, length(starPoints))
    @. dl[1:end-1] = -alphaScaled * (3 * coeff * (c2[2:end] - c1[2:end]) * c1[2:end]^2 + c2[2:end] - c1[2:end])
    @. dr[2:end] = -alphaScaled * (3 * coeff * (c2[1:end-1] - c1[1:end-1]) * c2[1:end-1]^2 + c2[1:end-1] - c1[1:end-1])
    dd[2:end-1] = -dl[1:end-1] - dr[2:end]
    dd[1] = one(T)
    dd[end] = one(T)
    rhs = zeros(Float64, length(dd))
    rhs[end] = one(T)
    lhs = Tridiagonal(dl, dd, dr)
    local d = lhs \ rhs
    #  println("d ",d)
    @. c1 /= d[2:end] - d[1:end-1]
    @. c2 /= d[2:end] - d[1:end-1]
    #now transform
    dIndex = 2
    Sip = Array{Float64}(undef, length(xi))
    for i = 2:length(xi)-1
        ui = xi[i]
        while (dIndex <= length(d) && d[dIndex] < ui)
            dIndex += 1
        end
        dIndex = min(dIndex, length(d))
        t = c2[dIndex-1] * (ui - d[dIndex-1]) + c1[dIndex-1] * (d[dIndex] - ui)
        Sip[i] = starPoints[dIndex-1] + alphaScaled * t * (coeff * t^2 + 1)
    end
    Sip[1] = Smin
    if (shift != 0)
        Sip[1] -= (Sip[2] - Smin)
    end
    Sip[end] = Smax
    if (shift != 0)
        Sip[end] += (Smax - Sip[end-1])
    end
    return Sip
end

abstract type DiscreteCalibration end
struct NoCalibration <: DiscreteCalibration
end

function calibrateRate(c::NoCalibration, beta, dt, dfi, dfip)
    log(dfi / dfip) / dt
end

function calibrateDrift(c::NoCalibration, beta, dt, dfi, dfip, driftDfi, driftDfip, r)
    log(driftDfi / driftDfip) / dt
end

struct ForwardCalibration <: DiscreteCalibration
end

calibrateRate(c::ForwardCalibration, beta, dt, dfi, dfip) = calibrateRate(c, beta, dt, dfip / dfi)

function calibrateRate(c::ForwardCalibration, beta, dt, factor)
    a = beta * (1 - beta) * factor / 2
    b = ((2 - beta^2) * factor + 1 + (1 - beta)^2) / 2
    c = (2 - beta) * (factor - 1)
    r = (-b + sqrt(max(0, b^2 - 4 * a * c))) / (2 * a * dt)
    r
end

calibrateDrift(c::ForwardCalibration, beta, dt, dfi, dfip, driftDfi, driftDfip, r) = r - calibrateRate(c, beta, dt, dfip / dfi * driftDfi / driftDfip)

