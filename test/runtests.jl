using AtomicLocks
using Test
using Base.Threads

@testset "AtomicLocks.jl" begin

    function test_thread(_lock)
        for i in 1:10
            lock(_lock)
            print("1 ")
            r = rand(1:100)/1000
            print("$r -> ")
            sleep(r)
            print("2 ")
            unlock(_lock)
            print("3 ")
        end
    end
    function test_lock(lock)
        Threads.@threads for i in 1:Threads.nthreads()
            test_thread(lock)
        end
        return true
    end
    println("Test 1:")
    @test test_lock(AtomicLock())
    println("Test 1:")
    @test test_lock(AtomicFIFOLock())

    function sync_thread(slock,lock)
        test_thread(lock)
        Base.lock(slock)
        test_thread(lock)
    end

    function synctest()
        slock = SyncLock()
        lock = AtomicFIFOLock()
        add_sync!(slock,Threads.nthreads())
        Threads.@threads for i in 1:Threads.nthreads()
            sync_thread(slock,lock)
        end
        return true
    end
    println("Test sync:")
    @test synctest()

    function reader_task(rwl::ReadWriteLock, thread_id::Int)
        println("Thread $thread_id: attempting to acquire read lock.")
        readlock(rwl)
        println("Thread $thread_id: acquired read lock.")
        # Simulate read operation (e.g., with sleep)
        sleep(0.1)
        println("Thread $thread_id: releasing read lock.")
        readunlock(rwl)
    end
    
    function writer_task(rwl::ReadWriteLock, thread_id::Int)
        println("Thread $thread_id: attempting to acquire write lock.")
        writelock(rwl)
        println("Thread $thread_id: acquired write lock.")
        # Simulate write operation (e.g., with sleep)
        sleep(0.1)
        println("Thread $thread_id: releasing write lock.")
        writeunlock(rwl)
    end
    
    function test_read_write_lock()
        rwl = ReadWriteLock()
        println(typeof(rwl))
        # Start threads for read and write operations
        nthreads = Threads.nthreads()
        println("Using $nthreads threads")
    
        # Create threads that either read or write
        @threads for i in 1:nthreads
            if mod(i, 2) == 0
                reader_task(rwl, i)
            else
                writer_task(rwl, i)
            end
        end
        return true
    end
    
    @test test_read_write_lock()
    function test_read(_lock,ii)
        for i in 1:10
            readlock(_lock)
            r = rand(1:70)/1000
            sleep(r)
            readunlock(_lock)
        end
    end
    function test_write(_lock,ii)
        for i in 1:10
            writelock(_lock)
            r = rand(1:70)/1000
            sleep(r)
            writeunlock(_lock)
        end
    end

    function test_read_write_lock_debug()
        rwl = ReadWriteLockDebug(;timelag=50000000,print=true)
        println(typeof(rwl))
    
        # Start threads for read and write operations
        nthreads = Threads.nthreads()
        println("Using $nthreads threads")
        fail = 0
        # Create threads that either read or write
        @threads for i in 1:nthreads
            try
                if mod(i, 2) == 0
                    test_read(rwl, i)
                else
                    test_write(rwl, i)
                end
            catch e 
                fail += 1
                println(e)
            end
        end
        println("Fails: $fail")
        println(rwl.trace[1:rwl.tail[]])
        return true
    end
    @test test_read_write_lock_debug()
end
