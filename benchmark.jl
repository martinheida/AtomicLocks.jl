using Base.Threads
using BenchmarkTools  
using AtomicLocks     

## compares a given task for various lock-types



@inline rlock(lock::ReadWriteLock) = readlock(lock)
@inline wlock(lock::ReadWriteLock) = writelock(lock)
@inline runlock(lock::ReadWriteLock) = readunlock(lock)
@inline wunlock(lock::ReadWriteLock) = writeunlock(lock)

@inline rlock(lock) = Base.lock(lock)
@inline runlock(lock) = unlock(lock)
@inline wlock(lock) = Base.lock(lock)
@inline wunlock(lock) = unlock(lock)


struct SharedVector{T,L} <: AbstractVector{T}
    data :: Vector{T}   # eigentliche Datenhaltung
    lock :: L           # unser Lock
end

SharedVector{T}(lock::L) where {T,L} = SharedVector{T,L}(Vector{T}(), lock)


function Base.length(sv::SharedVector{T,L}) where {T,L}
    rlock(sv.lock)
    l = length(sv.data)
    runlock(sv.lock)
    return l
end

function Base.size(sv::SharedVector{T,L}) where {T,L}
    rlock(sv.lock)
    l = (length(sv.data),)
    runlock(sv.lock)
    return l
end

function Base.getindex(sv::SharedVector{T,L}, i::Int) where {T,L}
    rlock(sv.lock)
    val = sv.data[i]
    runlock(sv.lock)
    return val
end

function Base.setindex!(sv::SharedVector{T,L}, val, i::Int) where {T,L}
    wlock(sv.lock)
    sv.data[i] = val
    wunlock(sv.lock)
    return val
end

function Base.push!(sv::SharedVector{T,L}, val) where {T,L}
    wlock(sv.lock)
    push!(sv.data, val)
    wunlock(sv.lock)
    return sv
end

function get_adds(shared::SharedVector{T,L},count) where {T<:Real,L}
    rlock(shared.lock)
    data = shared.data
    l = length(data)
    m = min(l, count)
    s = 0
    for j in 0:(m - 1)
        s += data[l - j]
    end
    runlock(shared.lock)
    return s
end

function test_function_old(shared::SharedVector{T,L}, iters::Int) where {T<:Real,L}
    for _ in 1:iters
        push!(shared, get_adds(shared,100))
    end
end


function test_function(shared::SharedVector{T,L}, iters::Int, vec) where {T<:Real,L}
    for _ in 1:iters
        for __ in 1:rand(1:200)
            sum(vec)
        end
        aa = get_adds(shared,100)
        push!(shared, aa)
    end
end

function run_bench(lock_constructor, nthreads, iters_per_thread)
    lock = lock_constructor()
    shared = SharedVector{Int}(lock)
    push!(shared,1)

    @threads for _ in 1:nthreads
        test_function(shared, iters_per_thread,collect(1:100))
    end
    return shared.data[end]
end

locks_to_test = [
    ("Base.ReentrantLock", () -> ReentrantLock()),
    ("Base.SpinLock",      () -> SpinLock()),
    ("AtomicLock",         () -> AtomicLock()),
    ("AtomicFIFOLock",     () -> AtomicFIFOLock()),
    ("ReadWriteLock",     () -> ReadWriteLock()),
]

nthreads = min(Threads.nthreads(), 8)  # Oder Anzahl deiner CPU-Kerne
iters    = 100000                      # Beliebig wählen, evtl. hochskalieren

println("\nBenchmark Lock Overhead mit " * string(nthreads) * " Threads und " * string(iters) * " Iterationen pro Thread:")

for (label, constructor) in locks_to_test
    @btime run_bench($constructor, $nthreads, $iters)
    result = run_bench(constructor, nthreads, iters)
    println(label, " => Result: ", result)
end
