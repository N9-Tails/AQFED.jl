using AQFED, Test
using StatsBase
using AQFED.Black
using AQFED.Collocation
import Polynomials: coeffs
using AQFED.Math
#using Plots


@testset "FilterConvex" begin
    strikes =
        Float64.([
            20,
            25,
            50,
            55,
            75,
            100,
            120,
            125,
            140,
            150,
            160,
            175,
            180,
            195,
            200,
            210,
            230,
            240,
            250,
            255,
            260,
            270,
            275,
            280,
            285,
            290,
            300,
            310,
            315,
            320,
            325,
            330,
            335,
            340,
            350,
            360,
            370,
            380,
            390,
            400,
            410,
            420,
            430,
            440,
            450,
            460,
            470,
            480,
            490,
            500,
            510,
            520,
            550,
            580,
            590,
            600,
            650,
            670,
            680,
            690,
            700,
        ])
    vols = [
        1.21744983334323,
        1.1529735541872308,
        1.0013512993166844,
        1.0087013871410198,
        0.9055919576135943,
        0.8196499269009432,
        0.779704840770866,
        0.753927847741657,
        0.7255349986293694,
        0.7036962946028743,
        0.6870907597202961,
        0.6631489459500445,
        0.6542809839143336,
        0.6310048431894977,
        0.6231979513191437,
        0.6154526014300009,
        0.5866214834144697,
        0.5783751483731193,
        0.5625036590124762,
        0.5625539176150428,
        0.5572331684618123,
        0.5485212417739607,
        0.5456131657256524,
        0.540060895711996,
        0.5384776792271245,
        0.5325298112839504,
        0.5222410647552144,
        0.5202396738775005,
        0.5168414254536685,
        0.5127405490209541,
        0.5100440087558921,
        0.50711984442627,
        0.5042896073005682,
        0.5013959697030379,
        0.4961897259221575,
        0.4914478237113829,
        0.48571052433313705,
        0.4820982302575811,
        0.4776551485043659,
        0.4682253137830999,
        0.46912624306506934,
        0.4652049749994563,
        0.4621036693145566,
        0.45969798571592985,
        0.4561356005182957,
        0.45418189139835186,
        0.4515451651258398,
        0.44541885580442636,
        0.4452833907060621,
        0.44303755690672525,
        0.43939212779385645,
        0.4413175310749832,
        0.4336322023390991,
        0.4297053821023934,
        0.4284357423754355,
        0.4241077476619805,
        0.4222672729031064,
        0.4203436892852212,
        0.4193419518701644,
        0.41934732346075626,
        0.41758929420417745,
    ]
    forward = 356.73063159822254
    tte = 1.5917808219178082
    refPricesf = [
        337.9478782712897,
        333.2264008151271,
        310.74145637852655,
        306.2719712239312,
        288.3940506055495,
        266.219801810884,
        249.06397096223955,
        244.7750182500784,
        232.02358238485036,
        223.57092985061377,
        215.48527697171835,
        203.47284496330764,
        199.46870596050405,
        187.64870164975872,
        183.87579062925917,
        176.5074646794032,
        161.77083277969126,
        154.64429335245714,
        147.51776392522302,
        144.31801826019864,
        141.1182775951742,
        134.7188062651254,
        131.6082360685426,
        128.49767087195968,
        125.40239375195168,
        122.30712163194369,
        116.11658739192775,
        110.79059339934288,
        108.12760140305048,
        105.46461440675806,
        102.80163241046563,
        100.15226884869381,
        97.60223566948574,
        95.07799161470712,
        90.23581650058495,
        85.6198931055724,
        81.10708395817021,
        76.78697167463605,
        72.46686939110188,
        68.14677710756771,
        64.77986823082749,
        61.41296935408727,
        58.04608047734704,
        54.95662415902851,
        51.90375987138524,
        49.029996842756624,
        46.15624381412802,
        43.2825007854994,
        41.01535154006894,
        38.748212294638485,
        36.481083049208024,
        34.612533924958775,
        29.006916552211,
        24.412399354175687,
        22.88090362149725,
        21.349417888818817,
        16.324515763803383,
        14.545066178175531,
        13.74560498753116,
        12.997715379078853,
        12.249835770626547,
    ]
    w1 = ones(length(strikes))
    prices, weights = Collocation.weightedPrices(true, strikes, vols, w1, forward, 1.0, tte)
    strikes, pricesf = Collocation.filterConvexPrices(strikes, prices, w1, forward, tol = 1e-6)
    for (k, p, pf, rpf) in zip(strikes, prices, pricesf, refPricesf)
        println(k, " ", p, " ", pf, " ", pf - p)
        @test isapprox(rpf, pf, atol = 1e-5)
    end

    isoc, m = Collocation.makeIsotonicCollocation(strikes, pricesf, weights, tte, forward, 1.0, deg = 5)
    sol = Collocation.Polynomial(isoc)
    println("Solution ", sol, " ", coeffs(sol), " ", Collocation.stats(sol), " measure ", m)
    refCoeffs = [
        348.59726724651006,
        221.54300193865407,
        -24.275731591637737,
        -12.821670197699545,
        10.80303198111674,
        2.940110896855002,
    ]
    for (ciRef, ci) in zip(refCoeffs, coeffs(sol))
        @test isapprox(ciRef, ci, atol = 1e-2)
    end
end

@testset "BadRoots" begin
    strikes =
        Float64.([
            20,
            25,
            50,
            55,
            75,
            100,
            120,
            125,
            140,
            150,
            160,
            175,
            180,
            195,
            200,
            210,
            230,
            240,
            250,
            255,
            260,
            270,
            275,
            280,
            285,
            290,
            300,
            310,
            315,
            320,
            325,
            330,
            335,
            340,
            350,
            360,
            370,
            380,
            390,
            400,
            410,
            420,
            430,
            440,
            450,
            460,
            470,
            480,
            490,
            500,
            510,
            520,
            550,
            580,
            590,
            600,
            650,
            670,
            680,
            690,
            700,
        ])
    vols = [
        1.21744983334323,
        1.1529735541872308,
        1.0013512993166844,
        1.0087013871410198,
        0.9055919576135943,
        0.8196499269009432,
        0.779704840770866,
        0.753927847741657,
        0.7255349986293694,
        0.7036962946028743,
        0.6870907597202961,
        0.6631489459500445,
        0.6542809839143336,
        0.6310048431894977,
        0.6231979513191437,
        0.6154526014300009,
        0.5866214834144697,
        0.5783751483731193,
        0.5625036590124762,
        0.5625539176150428,
        0.5572331684618123,
        0.5485212417739607,
        0.5456131657256524,
        0.540060895711996,
        0.5384776792271245,
        0.5325298112839504,
        0.5222410647552144,
        0.5202396738775005,
        0.5168414254536685,
        0.5127405490209541,
        0.5100440087558921,
        0.50711984442627,
        0.5042896073005682,
        0.5013959697030379,
        0.4961897259221575,
        0.4914478237113829,
        0.48571052433313705,
        0.4820982302575811,
        0.4776551485043659,
        0.4682253137830999,
        0.46912624306506934,
        0.4652049749994563,
        0.4621036693145566,
        0.45969798571592985,
        0.4561356005182957,
        0.45418189139835186,
        0.4515451651258398,
        0.44541885580442636,
        0.4452833907060621,
        0.44303755690672525,
        0.43939212779385645,
        0.4413175310749832,
        0.4336322023390991,
        0.4297053821023934,
        0.4284357423754355,
        0.4241077476619805,
        0.4222672729031064,
        0.4203436892852212,
        0.4193419518701644,
        0.41934732346075626,
        0.41758929420417745,
    ]
    forward = 356.73063159822254
    tte = 1.5917808219178082
    w1 = ones(length(strikes))
    prices, weights = Collocation.weightedPrices(true, strikes, vols, w1, forward, 1.0, tte)
    isoc, m = Collocation.makeIsotonicCollocation(strikes, prices, weights, tte, forward, 1.0, deg = 11, degGuess = 1)
    sol = Collocation.Polynomial(isoc)
    k = collect(800:0.1:1000)
    #Halley/SuperHalley does not behave well between 900 and 950
    #LithBoonkkampIJzerman does not bethave well between 825 and 830 (requires ~ 64*3 iterations)
    ivk = @. Black.impliedVolatility(true, Collocation.priceEuropean(sol, true, k, forward, 1.0), forward, k, tte, 1.0)
    for iv in ivk
        @test iv > 0 && iv < 10.0
    end
end

@testset "jaeckel" begin
    strikes = [
        0.035123777453185,
        0.049095433048156,
        0.068624781300891,
        0.095922580089594,
        0.134078990076508,
        0.18741338653678,
        0.261963320525776,
        0.366167980681693,
        0.511823524787378,
        0.715418426368358,
        1.0,
        1.39778339939642,
        1.95379843162821,
        2.73098701349666,
        3.81732831143284,
        5.33579814376678,
        7.45829006788743,
        10.4250740447762,
        14.5719954372667,
        20.3684933182917,
        28.4707418310251,
    ]
    vols = [
        0.642412798191439,
        0.621682849924325,
        0.590577891369241,
        0.553137221952525,
        0.511398042127817,
        0.466699250819768,
        0.420225808661573,
        0.373296313420122,
        0.327557513727855,
        0.285106482185545,
        0.249328882881654,
        0.228967051575314,
        0.220857187809035,
        0.218762825294675,
        0.218742183617652,
        0.218432406892364,
        0.217198426268117,
        0.21573928902421,
        0.214619929462215,
        0.2141074555437,
        0.21457985392644,
    ]
    forward = 1.0
    tte = 5.07222222222222
    w1 = ones(length(strikes))
    prices, weights = Collocation.weightedPrices(true, strikes, vols, w1, forward, 1.0, tte, vegaFloor = 1e-5)
    isoc, m = Collocation.makeIsotonicCollocation(strikes, prices, weights, tte, forward, 1.0, deg = 7, degGuess = 1)
    sol = Collocation.Polynomial(isoc)
    ivstrikes = @. Black.impliedVolatility(
        true,
        Collocation.priceEuropean(sol, true, strikes, forward, 1.0),
        forward,
        strikes,
        tte,
        1.0,
    )
    rmse = StatsBase.rmsd(ivstrikes, vols)
    println("poly ", rmse)
    bspl, m = Collocation.makeExpBSplineCollocation(
        strikes,
        prices,
        weights,
        tte,
        forward,
        1.0,
        penalty = 0e-2,
        size = 0,
        minSlope = 1e-8,
        rawFit = true,
    )
    ivstrikes = @. Black.impliedVolatility(
        true,
        Collocation.priceEuropean(bspl, true, strikes, forward, 1.0),
        forward,
        strikes,
        tte,
        1.0,
    )
    rmse = StatsBase.rmsd(ivstrikes, vols)
    println("bspl ", rmse)
    allStrikes = vcat(0.0, strikes, 50.0)
    allPrices = vcat(forward ,prices, 0.0)
    leftB = Math.FirstDerivativeBoundary(-1.0)
    rightB = Math.FirstDerivativeBoundary(0.0)
    cs = Math.makeConvexSchabackRationalSpline(allStrikes, allPrices, leftB, rightB, iterations=128)
    ivstrikes = @. Black.impliedVolatility(
        true,
        cs(strikes),
        forward,
        strikes,
        tte,
        1.0,
    )
    rmse = StatsBase.rmsd(ivstrikes, vols)
    println("scha ", rmse)
end


function gatheralDenomFinite(w, y)
    dwdy = FiniteDifferences.central_fdm(3,1)(w, y)
    d2wdy2 = FiniteDifferences.central_fdm(3,2)(w, y)
    return 1-y/w(y)*dwdy+(dwdy)^2 * (-1/4 - 1/w(y) + y^2/w(y)^2) / 4 + d2wdy2 / 2
end
#plot(y,@.(gatheralDenomFinite(x->AQFED.TermStructure.varianceByLogmoneyness(slice,x)*tte,y)))
#plot(y,@.(gatheralDenomFinite(x->AQFED.TermStructure.varianceByLogmoneyness(slice,x)*tte,y)/sqrt(2*π*AQFED.TermStructure.varianceByLogmoneyness(slice,y)*tte)*exp(-0.5*(y/sqrt(AQFED.TermStructure.varianceByLogmoneyness(slice,y)*tte)+sqrt(AQFED.TermStructure.varianceByLogmoneyness(slice,y)*tte)/2)^2)  )  )
