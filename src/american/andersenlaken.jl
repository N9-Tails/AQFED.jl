using AQFED.TermStructure
import AQFED.Black: blackScholesFormula
import Roots: find_zero, A42
export AndersenLakeNRepresentation, priceAmerican

#Andersen-Lake American option pricing under negative rates
struct AndersenLakeNRepresentation
    isCall::Bool
    model::ConstantBlackModel
    tauMax::Float64
    tauMaxOrig::Float64
    tauHat::Float64
    nC::Int
    nTS1::Int
    nTS2::Int
    capX::Float64
    capXD::Float64
    avec::Vector{Float64}
    avecD::Vector{Float64}
    qvec::Vector{Float64}
    qvecD::Vector{Float64}
    wvec::Vector{Float64}
    yvec::Vector{Float64}
end

function AndersenLakeNRepresentation(
    model::ConstantBlackModel,
    tauMax::Float64,
    atol::Float64,
    nC::Int,
    nIter::Int,
    nTS1::Int,
    nTS2::Int;
    isCall::Bool = false
)
    aUp = AndersenLakeRepresentation(model, tauMax, atol, nC, nIter, nTS1, nTS2, isCall = isCall, isLower = false)
    if (model.r < 0) && (model.q < model.r)
        aDown = AndersenLakeRepresentation(model, tauMax, atol, nC, nIter, nTS1, nTS2, isCall = isCall, isLower = true)
        tauHat = aUp.tauHat
        tauStar = tauHat
        #calculate intersection tauStar 
        logCapXD = log(aDown.capX)
        logCapX = log(aUp.capX)
        logBdown = logCapXD + sqrt(aDown.qvec[1])
        logBup = logCapX - sqrt(aUp.qvec[1])
        if logBdown > logBup
            obj = function (τ)
                z = 2 * sqrt((τ) / tauHat) - 1
                qck = max(chebQck(aUp.avec, z),0.0)
                lnBUp = logCapX - sqrt(qck)
                qck = max(chebQck(aDown.avec, z),0.0)
                lnBDown = logCapXD + sqrt(qck)
                return lnBUp - lnBDown
            end
            tauStar = find_zero(obj, (0, tauHat), A42())
            #  println("tauStar ", tauStar)
        end
        return AndersenLakeNRepresentation(isCall, model, tauStar, tauMax, tauHat, nC, nTS1, nTS2,
            aUp.capX, aDown.capX, aUp.avec, aDown.avec, aUp.qvec, aDown.qvec, aUp.wvec, aUp.yvec)
    else
        return AndersenLakeNRepresentation(isCall, model, tauMax, tauMax, tauMax, nC, nTS1, nTS2,
            aUp.capX, NaN, aUp.avec, Float64[], aUp.qvec, Float64[], aUp.wvec, aUp.yvec)
    end
end



function priceAmerican(p::AndersenLakeNRepresentation, K::Float64, S::Float64)::Float64
    if isempty(p.qvecD)
        return priceAmerican(AndersenLakeRepresentation(p.isCall, p.model, p.tauMax, p.tauMax, p.nC, p.nTS1, p.nTS2, p.capX, p.avec, p.qvec, p.wvec, p.yvec), K, S)
    end
    vol = p.model.vol
    local r::Float64 = p.model.r
    local q::Float64 = p.model.q
    if p.isCall #use McDonald and Schroder symmetry
        K, S = S, K
        r, q = q, r
    end
    capX, capXD = p.capX * K, p.capXD * K
    
    f0 = exp(-sqrt(p.qvec[1])) * capX
    f0D = exp(sqrt(p.qvecD[1])) * capXD
    if S <= f0 && S >= f0D && p.tauMax == p.tauMaxOrig
        # println(f0, " ",f0D)
        return max(K - S, 0.0)
    end

    tauMax, tauMaxOrig, tauHat, nTS2 = p.tauMax, p.tauMaxOrig, p.tauHat, p.nTS2
    wvec, yvec, avec, avecD = p.wvec, p.yvec, p.avec, p.avecD
    nC, rK, qS = p.nC, r * K, q * S

    uMax = tauMax
    uMin = 0.0
    uScale = (uMax - uMin) / 2
    uShift = (uMax + uMin) / 2
    sum4k = 0.0
    isCrossed = false
    euro = blackScholesFormula(
        false,
        K,
        S,
        vol * vol * tauMaxOrig,
        exp(-(r - q) * tauMaxOrig),
        exp(-r * tauMaxOrig),
    )
    if tauMax == tauMaxOrig
        #only 1 integral to compute
        isLower = S < f0D
        if isLower
            avec = avecD
            capX = capXD
        end
        for sk2 = nTS2:-1:1
            wk = wvec[sk2]
            yk = yvec[sk2]
            uk = uScale * yk + uShift
            if abs(yk) != 1
                zck = 2 * sqrt(uk / tauHat) - 1 #cheb from tauHat.
                qck = max(chebQck(avec, zck),0.0)
                Bzk = isLower ? capX * exp(sqrt(qck)) : capX * exp(-sqrt(qck))
                tauk = uMax - uk
                d1k, d2k = vaGBMd1d2(S, Bzk, r, q, tauk, vol)
                sum4k += wk * rK * exp(-r * tauk) * normcdf(-d2k)
                sum4k += -wk * qS * exp(-q * tauk) * normcdf(-d1k)
            end
        end
        if isLower
            sum4k = -sum4k
            euro = K-S
        end
    else
        # two integrals
        for sk2 = nTS2:-1:1
            wk = wvec[sk2]
            yk = yvec[sk2]
            uk = uScale * yk + uShift
            if abs(yk) != 1
                zck = 2 * sqrt(uk / tauHat) - 1 #cheb from tauHat.
                qck = max(chebQck(avec, zck),0.0)
                qckD = max(chebQck(avecD, zck),0.0)
                Bzk = capX * exp(-sqrt(qck))
                BzkD = capXD * exp(sqrt(qckD))
                if Bzk <= BzkD
                    isCrossed = true
                end
                if !isCrossed
                    tauk = uMax - uk + tauMaxOrig - tauMax
                    d1k, d2k = vaGBMd1d2(S, Bzk, r, q, tauk, vol)
                    sum4k += wk * rK * exp(-r * tauk) * normcdf(-d2k)
                    sum4k += -wk * qS * exp(-q * tauk) * normcdf(-d1k)
                    d1k, d2k = vaGBMd1d2(S, BzkD, r, q, tauk, vol)
                    sum4k -= wk * rK * exp(-r * tauk) * normcdf(-d2k)
                    sum4k += wk * qS * exp(-q * tauk) * normcdf(-d1k)
                end
            end
        end
    end
   
    price = euro + uScale * sum4k
    price = max(K - S, price)
    return price
end