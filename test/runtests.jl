# using Languages
using SimilaritySearch, TextSearch
using Test, SparseArrays, LinearAlgebra, CategoricalArrays, StatsBase, Random, JSON3
const fit = TextSearch.fit

const text0 = "@user;) #jello.world"
const text1 = "hello world!! @user;) #jello.world :)"
const text2 = "a b c d e f g h i j k l m n o p q"
const corpus = ["hello world :)", "@user;) excellent!!", "#jello world."]

@testset "individual tokenizers" begin
    @show text0
    @test qgrams(text0, 1) == ["@", "u", "s", "e", "r", ";", ")", " ", "#", "j", "e", "l", "l", "o", ".", "w", "o", "r", "l", "d"] 
    @test qgrams(text0, 3) == ["@us", "use", "ser", "er;", "r;)", ";) ", ") #", " #j", "#je", "jel", "ell", "llo", "lo.", "o.w", ".wo", "wor", "orl", "rld"]
    @show text1
    @test unigrams(text0) == ["@user", ";)", "#jello", ".", "world"]
    @test unigrams(text1) == ["hello", "world", "!!", "@user", ";)", "#jello", ".", "world", ":)"]
    @test unigrams(corpus[1]) == ["hello", "world", ":)"]
    @test unigrams(corpus[2]) == ["@user", ";)", "excellent", "!!"]
    @test unigrams(corpus[3]) == ["#jello", "world", "."]
    @show corpus
end

@testset "Normalize and tokenize" begin
    config = TextConfig(del_punc=true, group_usr=true, nlist=[1, 2, 3])
    t = normalize_text(config, text1)
    @test t == [' ', 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', ' ', ' ', '_', 'u', 's', 'r', ' ', ' ', '#', 'j', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', ' ', ' ']
    @test tokenize(config, t) == ["hello", "world", "_usr", "#jello", "world", "hello world", "world _usr", "_usr #jello", "#jello world", "hello world _usr", "world _usr #jello", "_usr #jello world"]
    
    config_ = JSON3.read(JSON3.write(config), typeof(config))
    t = normalize_text(config_, text1)
    @test t == [' ', 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', ' ', ' ', '_', 'u', 's', 'r', ' ', ' ', '#', 'j', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', ' ', ' ']
    @test tokenize(config_, t) == ["hello", "world", "_usr", "#jello", "world", "hello world", "world _usr", "_usr #jello", "#jello world", "hello world _usr", "world _usr #jello", "_usr #jello world"]

end

@testset "Normalize and tokenize bigrams and trigrams" begin
    config = TextConfig(del_punc=true, group_usr=true, nlist=[2, 3])
    t = normalize_text(config, text1)
    @test tokenize(config, t) == ["hello world", "world _usr", "_usr #jello", "#jello world", "hello world _usr", "world _usr #jello", "_usr #jello world"]
end

@testset "Tokenize skipgrams" begin
    config = TextConfig(del_punc=false, group_usr=false, nlist=[1], slist=[])
    tokens = tokenize(config, normalize_text(config, text1))
    @info tokens
    @test tokens == ["hello", "world", "!!", "@user", ";)", "#jello", ".", "world", ":)"]

    config = TextConfig(del_punc=false, group_usr=false, nlist=[], slist=[Skipgram(2,1)])
    t = normalize_text(config, text1)
    @test tokenize(config, t) == ["hello !!", "world @user", "!! ;)", "@user #jello", ";) .", "#jello world", ". :)"]

    config = TextConfig(del_punc=false, group_usr=false, nlist=[], slist=[Skipgram(2,2)])
    tokens = tokenize(config, normalize_text(config, text1))
    @test tokens ==  ["hello @user", "world ;)", "!! #jello", "@user .", ";) world", "#jello :)"]

    config = TextConfig(del_punc=false, group_usr=false, nlist=[], slist=[Skipgram(3,1)])
    tokens = tokenize(config, normalize_text(config, text1))
    @info text1 tokens
    @test tokens == ["hello !! ;)", "world @user #jello", "!! ;) .", "@user #jello world", ";) . :)"]
end

@testset "Tokenizer, DVEC, and vectorize" begin # test_vmodel
    config = TextConfig(group_usr=true, nlist=[1])
    model = VectorModel(FreqWeighting(), compute_bow_multimessage(config, corpus))
    x = vectorize(model, compute_bow(config, text1))
    @show corpus
    @show text1
    @show text2
    @test nnz(x) == 8
    x = vectorize(model, compute_bow(config, text2))
    @test nnz(x) == 1 && first(keys(x)) < 0

    model_ = JSON3.read(JSON3.write(model), typeof(model))
    x = vectorize(model_, compute_bow(config, text1))
    @test nnz(x) == 8
end

const sentiment_corpus = ["me gusta", "me encanta", "lo odio", "odio esto", "me encanta esto LOL!"]
const sentiment_labels = categorical(["pos", "pos", "neg", "neg", "pos"])
const sentiment_msg = "lol, esto me encanta"

@testset "Weighting schemes" begin
    config = TextConfig(group_usr=true, nlist=[1])
    for p in [
            FreqWeighting() => 0.5,
            TfWeighting() => 0.5,
            IdfWeighting() => 0.3922,
            TfidfWeighting() => 0.4178,
            TpWeighting() => 0.5
        ]
        model = VectorModel(p.first, compute_bow_multimessage(config, sentiment_corpus))
        x = vectorize(model, compute_bow(config, sentiment_corpus[3]))
        y = vectorize(model, compute_bow(config, sentiment_corpus[4]))
        @test abs(dot(x, y) - p.second) < 1e-3
    end

    for p in [
            EntFreqWeighting() => 0.70681,
            EntTpWeighting() => 0.70681,
            EntTfWeighting() => 0.70681,
            EntWeighting() => 0.70681
        ]
        model = EntModel(
            p.first,
            compute_bow.(config, sentiment_corpus),
            sentiment_labels,
            smooth=0,
            minocc=1
        )
        x = vectorize(model, compute_bow(config, sentiment_corpus[3]))
        y = vectorize(model, compute_bow(config, sentiment_corpus[4]))
        @test abs(dot(x, y) - p.second) < 1e-3
    end

end


@testset "DistModel tests" begin
    config = TextConfig(nlist=[1])
    corpus_ = compute_bow_list(config, sentiment_corpus)
    @show corpus_
    dmodel = DistModel(corpus_, sentiment_labels)
    @show sentiment_msg
    @show dmodel
    # test?
end

@testset "EntModel tests" begin
    config = TextConfig(nlist=[1])
    dmodel = DistModel(compute_bow_list(config, sentiment_corpus), sentiment_labels, weights=:balance, smooth=1, minocc=1)
    emodel = EntModel(dmodel, EntWeighting())
    emodel_ = EntModel(EntWeighting(), compute_bow_list(config, sentiment_corpus), sentiment_labels, weights=:balance, smooth=1, minocc=1)
    a = vectorize(emodel, compute_bow_multimessage(config, sentiment_corpus))
    b = vectorize(emodel_, compute_bow_multimessage(config, sentiment_corpus))
    @test 0.999 < dot(a, b)

    model_ = JSON3.read(JSON3.write(emodel), typeof(emodel))
    c = vectorize(model_, compute_bow_multimessage(config, sentiment_corpus))
    @test 0.999 < dot(a, c)
end


@testset "distances" begin
    u = Dict(:el => 0.9, :hola => 0.1, :mundo => 0.2) |> normalize!
    v = Dict(:el => 0.4, :hola => 0.2, :mundo => 0.4) |> normalize!
    w = Dict(:xel => 0.4, :xhola => 0.2, :xmundo => 0.4) |> normalize!

    dist = AngleDistance()
    @test evaluate(dist, u, v) ≈ 0.5975474808029686
    @test evaluate(dist, u, u) <= eps(Float32)
    @test evaluate(dist, w, u) ≈ 1.5707963267948966
end

@testset "operations" begin
    u = Dict(:el => 0.1, :hola => 0.2, :mundo => 0.4)
    v = Dict(:el => 0.2, :hola => 0.4, :mundo => 0.8)
    w = Dict(:el => 0.1^2, :hola => 0.2^2, :mundo => 0.4^2)
    y = Dict(:el => 0.1/9, :hola => 0.2/9, :mundo => 0.4/9)
    @test u == u
    @test u != v
    @test u + u == v
    @test u * u == w
    @test u * (1/9) == y
    @test (1/9) * u == y
    @test dot(normalize!(u + v - v), normalize!(u)) > 0.99
end


_corpus = [
    "la casa roja",
    "la casa verde",
    "la casa azul",
    "la manzana roja",
    "la pera verde esta rica",
    "la manzana verde esta rica",
    "la hoja verde",
]

@testset "transpose bow" begin
    config = TextConfig(nlist=[1])
    model = VectorModel(FreqWeighting(), compute_bow_multimessage(config, _corpus))
    X = [vectorize(model, compute_bow(config, msg)) for msg in _corpus]
    dX = transpose(X)
end

function are_posting_lists_sorted(invindex)
    for (k, lists) in invindex.lists
        if issorted([p.id for p in lists]) == false
            return false
        end
    end

    true
end

@testset "intersection" begin
    Random.seed!(1)
    for i in 1:100
        A = shuffle!(collect(1:1000))[1:10] |> sort!
        B = shuffle!(collect(1:1000))[1:100] |> sort!
        C = intersection([A, B])
        C_ = sort!(intersect(A, B))
        @test C == C_
    end
end

@testset "invindex" begin
    config = TextConfig(nlist=[1])
    model = VectorModel(TfidfWeighting(), compute_bow_multimessage(config, _corpus))
    ψ(text) = vectorize(model, compute_bow(config, text))
    invindex = InvIndex([ψ(text) for text in _corpus])
    @test are_posting_lists_sorted(invindex)
    begin # searching
        q = ψ("la casa roja")
        res = search_with_union(invindex, q, KnnResult(4))
        @test sort([r.id for r in res]) == [1, 2, 3, 4]

        res = search_with_one_error(invindex, q, KnnResult(4))
        @info "ONE-ERROR" res
        res = search_with_intersection(invindex, q, KnnResult(4))
        @test [r.id for r in res] == [1]

        q = ψ("esta rica")
        res = search_with_intersection(invindex, q, KnnResult(4))
        @test [5, 6] == sort!([r.id for r in res])
    end

    shortindex = prune(invindex, 3)
    @test are_posting_lists_sorted(invindex)
    q = ψ("la casa roja")
    res = search_with_union(shortindex, q, KnnResult(4))
    @test sort!([r.id for r in res]) == [1, 2, 3, 4]

    begin # searching with intersection
        res = search_with_intersection(shortindex, q, KnnResult(4))
        @test [r.id for r in res] == [1]

        q = ψ("esta rica")
        res = search_with_intersection(shortindex, q, KnnResult(4))
        @info res
        @test [5, 6] == sort!([r.id for r in res])
    end
end

@testset "centroid computing" begin
    config = TextConfig(nlist=[1])
    model = VectorModel(FreqWeighting(), compute_bow_multimessage(config, _corpus))
    X = [vectorize(model, compute_bow(config, x)) for x in _corpus]
    x = sum(X) |> normalize!
    vec = bow(model, x)
    expected = Dict(:la => 0.7366651330405098,:verde => 0.39921969741172364,:azul => 0.11248181187626208,:pera => 0.08712803682959973,:esta => 0.17425607365919946,:roja => 0.22496362375252416,:hoja => 0.11248181187626208,:casa => 0.33744543562878626,:rica => 0.17425607365919946,:manzana => 0.19960984870586182)
    @test 0.999 < dot(vec, expected)
end

@testset "neardup" begin
    config = TextConfig(nlist=[1])

    function create_corpus()
        alphabet = Char.(97:100)
        corpus = String[]
        L = Char[]
        for i in 1:10000
            resize!(L, 0)
            for j in 1:7
                append!(L, rand(alphabet, 2))
                push!(L, ' ')
            end

            push!(corpus, join(L))
        end

        corpus
    end

    randcorpus = create_corpus()
    model = VectorModel(TfWeighting(), compute_bow_multimessage(config, randcorpus))
    @show randcorpus[1:10]
    X = [vectorize(model, compute_bow(config, x)) for x in randcorpus]
    L, D  = neardup(X, 0.2)
    @test length(X) > length(unique(L))
end
