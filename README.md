# AtomicLocks.jl

`AtomicLocks.jl` is a Julia package that provides a set of thread-safe, atomic-based locks, including traditional read-write locks, FIFO locks, synchronization locks and advanced debug tools for identifying lock contention issues in multithreaded environments. The package is designed for data management scenarios where short but frequent access to data is required and the percentage of data access times is still low compared to the overall computation time.

## Features

- **`AtomicLock`**: A simple atomic lock that provides mutual exclusion with a customizable wait time between attempts to acquire the lock.
- **`AtomicFIFOLock`**: A first-in-first-out (FIFO) atomic lock that ensures fairness by granting the lock to tasks in the order they request it.
- **`ReadWriteLock`**: A read-write lock that allows concurrent reads but exclusive writes.
- **`ReadWriteLockDebug`**: An enhanced version of `ReadWriteLock` with built-in debugging features to detect lock contention and long wait times. In particular, this is made for detecting errors in the usage of ReadWriteLock. Look at `runtests.jl` and play with the time parameters there for getting an insight into the exception management.
- **`SyncLock`**: An atomic synchronizer used to coordinate tasks, making them wait until all have reached a specific synchronization point.

---

## Installation

To install the package, use the Julia package manager:

```julia
] add AtomicLocks
```

## Usage

### 1. AtomicLock

AtomicLock is a simple atomic lock that functions similarly to a SpinLock. The parameter wait controls the time between attempts to acquire the lock.

```julia
using AtomicLocks

# Create an AtomicLock with optional argument 200 that performs approximately 200 simple calculations between two tries to acquire the lock
lock = AtomicLock(200)

# Acquire the lock
lock(lock)

# Release the lock
unlock(lock)
```

### 2. AtomicFIFOLock

AtomicFIFOLock works similarly to AtomicLock but follows a first-in, first-out (FIFO) order for lock acquisition.

```julia
using AtomicLocks

# Create a FIFO lock with optional argument 200 that performs approximately 200 simple calculations between two tries to acquire the lock
fifo_lock = AtomicFIFOLock(200)

# Acquire the lock
lock(fifo_lock)

# Release the lock
unlock(fifo_lock)
```

### 3. ReadWriteLock

ReadWriteLock allows multiple threads to read concurrently, but only one thread can write at any time. Read and write exclude each other. This is particularly useful for managing data with frequent reads and occasional writes, when data access takes only a very small percentage of the code.

The ReadWriteLock will avoid freuent yielding or context switching unless the ressources get stalled in one of the threads. This makes it possible to have many frequent readlocks or writelocks without creating much overhead to the computation.

you can provide the same arguments to ReadWriteLock functions as to ReadWriteLockDebug functions, they will simply be ignored in this context.

```julia
using AtomicLocks

# Create a ReadWriteLock
rw_lock = ReadWriteLock()

# Acquire a read lock
readlock(rw_lock)

# Release a read lock
readunlock(rw_lock)

# Acquire a write lock
writelock(rw_lock)

# Release a write lock
writeunlock(rw_lock)
```

### 4. ReadWriteLockDebug

ReadWriteLockDebug extends ReadWriteLock with debugging features. If a readlock or writelock waits for longer than `timelag` (default: 1 second), an error is raised. It also collects the last few lock operations for debugging purposes.

```julia
using AtomicLocks

# Create a debug read-write lock with traces enabled and 500ms lock-waiting-time before throwing an exception.
rw_lock_debug = ReadWriteLockDebug(traces=200, timelag=500000000, print=true, location="ModuleA")

# Acquire a read lock with trace ID
readlock(rw_lock_debug, 42) # this action will acquire the internal id 42

# Release the read lock
readunlock(rw_lock_debug, 43) # this action will acquire the internal id 42

# If a lock waits for too long, an RWLDebugError will be raised, with trace information:
try
    writelock(rw_lock_debug, 100)
catch e::RWLDebugError
    println("Lock wait exceeded timelag: ", e)
finally
    writeunlock(rw_lock_debug, 101)
end
```

### 5. SyncLock

SyncLock is an atomic synchronizer that ensures tasks wait until all other tasks have reached a specific point in their execution. I developed this lock because I had to implement a synchronized break deep inside my HighVoronoi.jl code and handing all responsibility back to the top would have been counter productive in terms of factorization of code. 

```julia
using AtomicLocks

# Create a SyncLock
sync_lock = SyncLock()


function do_stuff(sl)
  do_some_stuff()
  # Stall until 3 tasks reach this point
  synclock(sl) # wait for all threads having completed the first task
  do_some_more_stuff()
end
# Warning: The following can only work if there are really at least 3 threads available in Threads.nthreads() and there are three threads available in your OS!!
# Set the lock to wait for 3 tasks
add_sync!(sync_lock, 3)
Threads@threads for i in 1:3
  do_stuff(sync_lock)
end

```

