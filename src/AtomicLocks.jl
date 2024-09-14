module AtomicLocks
using Base.Threads


@inline function active_wait(i)
    ii = 0
    for _ in 1:rand(1:min(i,10))
        ii+=1
    end
end

##########################################################################################################################################################

## AtomicLock

##########################################################################################################################################################

"""
    struct AtomicLock

An atomic lock implementation based on atomic boolean flags. 
The `AtomicLock` struct provides a simple mechanism for controlling access to a shared resource using atomic operations. 
It is similar to `SpinLock`, but introduces a waiting period between acquisition attempts.

# Fields
- `locked::Atomic{Bool}`: A boolean flag indicating whether the lock is currently held. Uses atomic operations to prevent race conditions.
- `wait::Int64`: The wait time (in arbitrary units) between consecutive attempts to acquire the lock. A higher value of `wait` reduces CPU load by spacing out lock acquisition attempts.

# Constructor

    AtomicLock(wait=100)

Constructor for `AtomicLock`. Initializes the lock in the unlocked state and sets the `wait` parameter, 
which controls the interval between attempts to acquire the lock in the `lock` function.

# Arguments
- `wait`: Optional parameter specifying the delay between acquisition attempts. 
           Defaults to 100 if not provided. This value allows for some flexibility in 
           avoiding aggressive spinning in tight loops when attempting to acquire the lock.

# Example
```julia
lock = AtomicLock(200)  # Creates a lock with a custom wait time
"""

struct AtomicLock
    locked::Atomic{Bool}
    wait::Int64
    function AtomicLock(wait=100)
        new(Atomic{Bool}(false), wait)
    end
end


@inline function Base.lock(bl::AtomicLock)
    ii = UInt64(0)
    while atomic_cas!(bl.locked, false, true)
        active_wait(bl.wait)
        if mod(ii,100)==0 
            yield()
        end
    end
    println("lock on thread $(Threads.threadid())")
end

@inline Base.unlock(bl::AtomicLock) = atomic_xchg!(bl.locked,false) 

@inline Base.trylock(bl::AtomicLock) = !atomic_cas!(bl.locked, false, true)

@inline Base.islocked(bl::AtomicLock) = bl.locked[]


export AtomicLock


##########################################################################################################################################################

## AtomicFIFOLock

##########################################################################################################################################################

"""
    AtomicFIFOLock

An atomic lock that operates on a first-in, first-out (FIFO) basis. This ensures that requests to acquire the lock are handled in the order they are made, providing fairness in lock acquisition.


    AtomicFIFOLock(wait=100)

Constructs an `AtomicFIFOLock`, which behaves similarly to a `SpinLock` or `AtomicLock`, but enforces a first-in, first-out (FIFO) order for acquiring the lock. This ensures that the lock is granted in the order in which it was requested, preventing the possibility of starvation that can occur with traditional spinlocks.

# Arguments
- `wait`: Optional parameter that specifies the delay between attempts to acquire the lock. Defaults to 100 if not provided.

# Example
```julia
fifo_lock = AtomicFIFOLock(200)  # Creates a FIFO lock with a custom wait time
"""
struct AtomicFIFOLock
    head::Atomic{Int64}
    tail::Atomic{Int64}
    lock::AtomicLock
    wait::Int64
    function AtomicFIFOLock(wait=100)
        new(Atomic{Int64}(0), Atomic{Int64}(0),AtomicLock(),wait)
    end
end

@inline function Base.lock(bfl::AtomicFIFOLock)
    lock(bfl.lock)
    my_tail = atomic_add!(bfl.tail, 1)
    unlock(bfl.lock)
    i = 1
    while (my_tail != bfl.head[])
        active_wait(bfl.wait*i)
        i += 1
        if mod(i,100)==0
            yield()
        end
    end
end

@inline Base.unlock(bfl::AtomicFIFOLock) = atomic_add!(bfl.head,1)

@inline function Base.trylock(bfl::AtomicFIFOLock)
    if bfl.tail[] == bfl.head[] && trylock(bfl.lock)
        tail = atomic_add!(bfl.tail, 1)
        l = true
        if (bfl.head[] != tail)
            atomic_sub!(bfl.tail, 1)
            l = false
        end
        unlock(bfl.lock)
        return l
    else
        return false
    end
end

@inline Base.islocked(bfl::AtomicFIFOLock) = (bfl.head[]<bfl.tail[])

export AtomicFIFOLock

##########################################################################################################################################################

## ReadWriteLock

##########################################################################################################################################################

"""
    ReadWriteLock(; kwargs...)

Constructs a `ReadWriteLock`, which allows multiple threads to read in parallel, but only one thread to write at a time. 
This lock is designed for managing data that requires very short but frequent access times. It is particularly useful in scenarios where reading operations happen frequently and can occur simultaneously, but writing operations need to be exclusive.

# Keyword Arguments
- `kwargs...`: Currently unused, but allows for future customization of the lock’s behavior.

# Example
```julia
rw_lock = ReadWriteLock()  # Creates a new read-write lock
"""
""" ReadWriteLock

A lock that allows one write operation at a time, while multiple read operations can be performed concurrently. This is useful for data management situations with extremely short but frequent access times.

#Fields

    head::Threads.Atomic{Int64}: Tracks the current position in the lock queue for managing the order of operations.
    tail::Threads.Atomic{Int64}: Tracks the tail of the queue, representing the most recent operation in the queue.
    reads_count::Threads.Atomic{Int64}: Keeps track of the number of concurrent read operations. Only one write operation can proceed if no reads are active.

# This lock supports both read and write operations:

    readlock(): Acquires a read lock, allowing multiple readers to access the data concurrently.
    writelock(): Acquires a write lock, granting exclusive access to the data for writing.
    readunlock(): Releases a previously acquired read lock.
    writeunlock(): Releases a previously acquired write lock. 
"""
struct ReadWriteLock
    head::Threads.Atomic{Int64}
    tail::Threads.Atomic{Int64}
    reads_count::Threads.Atomic{Int64}
    ReadWriteLock(;kwargs...) = new(Threads.Atomic{Int64}(0),Threads.Atomic{Int64}(0),Threads.Atomic{Int64}(0))
end

@inline readlock(::Nothing) = nothing
@inline readunlock(::Nothing) = nothing
@inline writelock(::Nothing) = nothing
@inline writeunlock(::Nothing) = nothing
@inline ReadWriteLock(::T) where T = nothing


@inline function readlock(rwl::ReadWriteLock,args...)
    this_tail = atomic_add!(rwl.tail,1) 
    ii = 0
    while atomic_add!(rwl.head,0)!=this_tail
        active_wait(100)
        ii += 1
        mod(ii,100)==0 && yield()
    end
    atomic_add!(rwl.reads_count,1)
    atomic_add!(rwl.head,1)
end

@inline function writelock(rwl::ReadWriteLock,args...)
    this_tail = atomic_add!(rwl.tail,1) 
    ii = 0
    while atomic_add!(rwl.head,0)!=this_tail || atomic_add!(rwl.reads_count,0)>0
        active_wait(100)
        ii += 1
        mod(ii,100)==0 && yield()
    end
end

@inline readunlock(rwl::ReadWriteLock) = atomic_sub!(rwl.reads_count,1)

@inline writeunlock(rwl::ReadWriteLock) = atomic_add!(rwl.head,1)

@inline Base.lock(rwl::ReadWriteLock) = writelock(rwl)
@inline Base.unlock(rwl::ReadWriteLock) = writeunlock(rwl)

export ReadWriteLock
export readlock
export readunlock
export writelock
export writeunlock

##########################################################################################################################################################

## SyncLock

##########################################################################################################################################################


"""An atomic synchronizer. Used to stall tasks until all tasks have reached a particular point in their algorithm.""" 
struct SyncLock
    locks::Threads.Atomic{Int64}
    event::Event
    SyncLock() = new(Threads.Atomic{Int64}(0),Event())
end

"""Adds `i` counts to the SyncLock. Hence synclock(lock) will stall until synclock(lock) has been called `i` times.""" 
@inline add_sync!(lock::SyncLock,i) = atomic_add!(lock.locks,i)
@inline Base.lock(lock::SyncLock) = synclock(lock)
""" locks the SyncLock `lock` until all tasks have been completed """
@inline synclock(lock::SyncLock) = begin
    a = atomic_sub!(lock.locks,1)
    if a<=1
        notify(lock.event)
    else
        wait(lock.event)
    end
    return a
end

export SyncLock
export synclock
export add_sync!


##########################################################################################################################################################

## ReadWriteLockDebug

##########################################################################################################################################################



const RWLCounter = Threads.Atomic{Int64}(1)

struct RWLTrace
    thread::Int64
    OP::Int64
    all::Int64
    point_id::Int64
end
Base.show(io::IO, trace::RWLTrace) = print(io, "(", trace.thread, ",", trace.OP, ",", trace.all, ")")

struct RWLDebugError <: Exception
    index::Int64
    head::Int64
    tail::Int64
    reads_count::Int64
    trace::Vector{RWLTrace}
end

Base.showerror(io::IO, err::RWLDebugError) = print(io, "$(err.index): $(err.head), $(err.tail), $(err.reads_count), traces: $(err.trace)")


struct ReadWriteLockDebug
    head::Threads.Atomic{Int64}
    tail::Threads.Atomic{Int64}
    reads_count::Threads.Atomic{Int64}
    all::Threads.Atomic{Int64}
    index::Int64
    trace::Vector{RWLTrace}
    lock::SpinLock
    timelag::Int64
    function ReadWriteLockDebug(;traces::Int64=100,timelag::Int64=1000000000,print::Bool=false,location="")
        rwl = new(Threads.Atomic{Int64}(0),Threads.Atomic{Int64}(0),Threads.Atomic{Int64}(0),Threads.Atomic{Int64}(0),atomic_add!(AtomicLocks.RWLCounter,1),Vector{RWLTrace}(undef,traces),SpinLock(),timelag)#,cr,cw,ReentrantLock())
        if print
            println("Initialize ReadWriteLock $(rwl.index) at location: $location")
        end
        return rwl
    end
end

export ReadWriteLockDebug

@inline ReadWriteLockDebug(::T) where T = nothing


@inline function readlock(rwl::ReadWriteLockDebug,id=0)
    lock(rwl.lock)
    ti = time_ns()
    this_tail = atomic_add!(rwl.tail,1) 
    a = atomic_add!(rwl.all,1)
    rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),1,a,id)
    unlock(rwl.lock)
    ii = 0
    while atomic_add!(rwl.head,0)<this_tail
        active_wait(100)
        ii += 1
        mod(ii,100)==0 && yield()
        if time_ns()-ti>rwl.timelag 
            lock(rwl.lock)
            a = atomic_add!(rwl.all,1)
            rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),-1,a,id)
            tr = copy(rwl.trace)
            unlock(rwl.lock)
            throw(RWLDebugError(rwl.index, atomic_add!(rwl.head, 0), this_tail, atomic_add!(rwl.reads_count, 0), tr))
        end
    end
    println(time_ns()-ti)
    atomic_add!(rwl.reads_count,1)
    atomic_add!(rwl.head,1)
end

@inline function writelock(rwl::ReadWriteLockDebug,id=0)
    lock(rwl.lock)
    ti = time_ns()
    this_tail = atomic_add!(rwl.tail,1) 
    #print("$this_tail, $(rwl.head[]), $(rwl.reads_count[])")
    a = atomic_add!(rwl.all,1)
    rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),3,a,id)
    unlock(rwl.lock)
    ii = 0
    while atomic_add!(rwl.head,0)<this_tail || atomic_add!(rwl.reads_count,0)>0
        active_wait(100)
        ii += 1
        mod(ii,100)==0 && yield()
        if time_ns()-ti>rwl.timelag 
            lock(rwl.lock)
            a = atomic_add!(rwl.all,1)
            rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),-3,a,id)
            tr = copy(rwl.trace)
            unlock(rwl.lock)
            throw(RWLDebugError(rwl.index, atomic_add!(rwl.head, 0), this_tail, atomic_add!(rwl.reads_count, 0), tr))
        end
    end
    println(time_ns()-ti)
end

@inline function readunlock(rwl::ReadWriteLockDebug,id=0)
    lock(rwl.lock)
    atomic_sub!(rwl.reads_count,1)
    a = atomic_add!(rwl.all,1)
    rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),2,a,id)
    unlock(rwl.lock)

end

@inline function writeunlock(rwl::ReadWriteLockDebug,id=0)
    lock(rwl.lock)
    atomic_add!(rwl.head,1)
    a = atomic_add!(rwl.all,1)
    rwl.trace[mod(a,100)+1] = RWLTrace(Threads.threadid(),4,a,id)
    unlock(rwl.lock)
end

@inline Base.lock(rwl::ReadWriteLockDebug,id=0) = writelock(rwl,id)
@inline Base.unlock(rwl::ReadWriteLockDebug,id=0) = writeunlock(rwl,id)



end
