# Deterministic concurrency helper for race-condition specs.
#
# Starting two threads and hoping their timing happens to overlap inside
# a locked critical section is not deterministic — a broken locking
# implementation can still pass by luck. Instead, this module takes the
# row lock *itself* first, waits (by polling pg_stat_activity — no
# arbitrary sleeps, no scheduling assumptions about which thread "wins")
# until every contending thread is provably blocked on that exact lock,
# and only then releases it. That proves real overlap happened before
# either thread was allowed to proceed; which one then wins the race is
# expected to be arbitrary.
module LockContention
  class TimeoutError < StandardError; end

  # Holds a `FOR UPDATE` lock on `record`, starts each proc in `jobs` on
  # its own checked-out connection, waits until all of them are observed
  # waiting on that lock, then releases it so they race for real.
  # Returns their return values in the same order as `jobs`.
  #
  # Thread cleanup runs in `ensure`, not just on the happy path: if the
  # wait for contention times out (or anything else raises) with the
  # threads already spawned, leaving them unjoined would let them keep
  # running — and holding locks — into whatever the example does next
  # (its own assertions, or the DatabaseCleaner truncation in an `after`
  # hook), which manifests as a confusing unrelated deadlock rather than
  # this method's own, clearly-labeled timeout.
  def run_under_forced_contention(record, jobs, timeout: 5)
    values = Array.new(jobs.size)
    threads = []

    begin
      # Explicitly own a connection for the arbiter's own transaction
      # rather than relying on implicit per-thread checkout: an HTTP
      # dispatch made earlier on this same thread (e.g. login_session's
      # warm-up requests) runs through ActionDispatch::Executor, which
      # releases the calling thread's active AR connection back to the
      # pool when the request completes — so without this, the "lock"
      # below can end up on a connection that's no longer reliably
      # pinned for the duration of the block.
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          record.class.lock.find(record.id)

          jobs.each_with_index do |job, i|
            threads << Thread.new do
              ActiveRecord::Base.connection_pool.with_connection { values[i] = job.call }
            end
          end

          wait_for_lock_waiters(jobs.size, timeout: timeout)
        end
      end
    ensure
      threads.each { |t| t.join(timeout) }
      if threads.any?(&:alive?)
        threads.each(&:kill)
        raise TimeoutError, "a contending job did not finish within #{timeout}s"
      end
    end

    values
  end

  # Polls pg_stat_activity until at least `min_waiters` *other* backends
  # are blocked on a lock (wait_event_type = 'Lock'). A backend waiting on
  # a row lock held by another transaction shows up here, not as an
  # ungranted row in pg_locks joined to the relation — Postgres represents
  # that wait as blocking on the lock holder's transaction id instead, so
  # a pg_locks-only query silently undercounts. Raises TimeoutError
  # instead of hanging forever if the expected contention never happens
  # (e.g. locking was removed).
  #
  # The brief sleep before the first check is a deliberate head start, not
  # a timing guess about the outcome: a poll loop that queries immediately
  # after spawning threads can end up hammering the GVL so persistently
  # (query, sleep briefly, query again) that MRI's scheduler never hands
  # the *brand new* threads a slice to even open their own connection and
  # issue their first query — starving them for the entire timeout instead
  # of the fraction of a second it actually takes them to get there.
  # Everything after that first yield is still fully condition-based:
  # this loops on the real lock-wait state with a real deadline, never on
  # a fixed total wait.
  def wait_for_lock_waiters(min_waiters, timeout: 5)
    sleep 0.05
    deadline = Time.now + timeout
    loop do
      waiting = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()
      SQL
      return true if waiting.to_i >= min_waiters

      if Time.now > deadline
        raise TimeoutError, "timed out waiting for #{min_waiters} lock waiter(s) (saw #{waiting})"
      end

      sleep 0.05
    end
  end

  # A one-time process warm-up for Devise/Warden's session (de)serializer.
  #
  # This environment's first-ever Devise session round-trip in a freshly
  # booted process is unreliable in two different ways that are otherwise
  # indistinguishable from a real locking bug: a real password POST to
  # /users/sign_in can spuriously 422 on the very first attempt (every
  # attempt after that in the same process succeeds), and the *second*
  # authenticated request on any one session can raise an ArgumentError
  # out of Devise::Models::Authenticatable#serialize_from_session (also
  # only ever on the first such round-trip in the process). Both vanish
  # permanently after one ordinary sign-in-then-two-requests cycle runs
  # once — so do exactly that, once per process, before any example here
  # opens its own concurrent sessions, rather than let either surface as
  # test flakiness.
  def warm_up_devise_session_serialization!
    return if LockContention.devise_warmed_up

    user = FactoryBot.create(:user)
    sign_in user
    get "/cart"
    get "/cart"
    LockContention.devise_warmed_up = true
  end

  class << self
    attr_accessor :devise_warmed_up
  end

  # An independent, already-authenticated session for `user`, built via
  # Rails' own `open_session` (the documented way to drive multiple
  # simultaneous sessions from one integration/request spec) rather than
  # a bare `ActionDispatch::Integration::Session.new`, so it inherits the
  # same app/session-store resolution the spec's own session uses.
  #
  # Login goes through Warden's sign-in test helper (`login_as`, the same
  # mechanism every plain `sign_in user` call in this suite already uses)
  # resolved into *this specific* session's cookies via one synchronous
  # warm-up request before any concurrent phase starts, rather than a
  # real password POST — see warm_up_devise_session_serialization! above
  # for why a real POST isn't used here.
  def login_session(user)
    warm_up_devise_session_serialization!

    session = open_session
    login_as(user, scope: :user)
    session.get("/cart")
    raise "warm-up sign-in failed (status=#{session.response.status})" unless session.response.status == 200
    session
  end
end
