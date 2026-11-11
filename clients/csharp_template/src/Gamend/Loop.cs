// The inbox and the timers: how work reaches the game thread.
//
// There is no thread in here. A transport posts from wherever it completes,
// and everything else happens in `Drain`, on the thread that calls
// `Client.Poll()`. That is what lets the core run where there are no threads
// at all, as on Unity WebGL.
using System;
using System.Collections.Generic;
using System.Runtime.ExceptionServices;

namespace Gamend
{
    internal sealed class Loop
    {
        private sealed class Timer
        {
            public long Due;
            public long Id;
            public Action Task;
            public bool Cancelled;
        }

        /// <summary>Held by `Drain` and by every public method of the SDK, so those are safe to
        /// call from any thread and never run beside a task or a timer. Re-entrant: a task may
        /// call them too.</summary>
        internal readonly object Gate = new object();

        private readonly object _inboxLock = new object();
        private readonly Func<long> _clock;
        private List<Action> _inbox = new List<Action>();
        private List<Action> _spare = new List<Action>();
        private readonly List<Timer> _timers = new List<Timer>();
        private List<Timer> _firing;
        private long _nextTimer = 1;
        private volatile bool _closed;
        private int _depth;
        private ExceptionDispatchInfo _thrown;

        internal Loop(Func<long> clock)
        {
            _clock = clock;
        }

        /// <summary>From any thread: run `task` in the next `Drain`. Dropped once closed.</summary>
        internal void Post(Action task)
        {
            lock (_inboxLock)
            {
                if (_closed) return;
                _inbox.Add(task);
            }
        }

        /// <summary>Run `task` in this drain if one is under way, or in the next one otherwise,
        /// so that a task completes inside `Poll` whatever happened to finish it.</summary>
        internal void Deliver(Action task)
        {
            lock (Gate)
            {
                if (_depth > 0)
                {
                    Run(task);
                }
                else
                {
                    Post(task);
                }
            }
        }

        /// <summary>Run what was posted, in order, then the timers that are due. What a listener
        /// threw is rethrown at the end: the game hears about its bug, and the rest of the frame's
        /// work is not lost to it.</summary>
        internal void Drain()
        {
            lock (Gate)
            {
                _depth++;
                try
                {
                    RunInbox();
                    RunTimers();
                }
                finally
                {
                    _depth--;
                }
                if (_depth == 0 && _thrown != null)
                {
                    var thrown = _thrown;
                    _thrown = null;
                    thrown.Throw();
                }
            }
        }

        private void RunInbox()
        {
            List<Action> ready;
            lock (_inboxLock)
            {
                if (_closed || _inbox.Count == 0) return;
                ready = _inbox;
                _inbox = _spare ?? new List<Action>();
                _spare = null;
            }
            // A task posted while these run waits for the next drain, so a
            // callback that starts another call never runs that call's callback
            // inside itself.
            for (var i = 0; i < ready.Count && !_closed; i++) Run(ready[i]);
            ready.Clear();
            _spare = ready;
        }

        private void RunTimers()
        {
            if (_closed || _timers.Count == 0) return;
            var now = _clock();
            List<Timer> due = null;
            var kept = 0;
            for (var i = 0; i < _timers.Count; i++)
            {
                var timer = _timers[i];
                if (timer.Due > now)
                {
                    _timers[kept++] = timer;
                }
                else
                {
                    if (due == null) due = new List<Timer>();
                    due.Add(timer);
                }
            }
            if (due == null) return;
            _timers.RemoveRange(kept, _timers.Count - kept);
            due.Sort((a, b) => a.Due != b.Due ? a.Due.CompareTo(b.Due) : a.Id.CompareTo(b.Id));
            var outer = _firing;
            _firing = due;
            foreach (var timer in due)
            {
                if (!timer.Cancelled && !_closed) Run(timer.Task);
            }
            _firing = outer;
        }

        private void Run(Action task)
        {
            try
            {
                task();
            }
            catch (Exception e)
            {
                Keep(e);
            }
        }

        /// <summary>Remember what a listener threw, for the end of this drain. Only the first:
        /// a handler that throws every event says the same thing every frame.</summary>
        internal void Keep(Exception e)
        {
            lock (Gate)
            {
                if (_thrown == null) _thrown = ExceptionDispatchInfo.Capture(e);
            }
        }

        /// <summary>Run `task` in the first `Drain` at least `delayMs` from now. Answers an id for
        /// `Cancel`, never 0.</summary>
        internal long After(long delayMs, Action task)
        {
            lock (Gate)
            {
                var id = _nextTimer++;
                _timers.Add(new Timer { Due = _clock() + delayMs, Id = id, Task = task });
                return id;
            }
        }

        internal void Cancel(long id)
        {
            if (id == 0) return;
            lock (Gate)
            {
                for (var i = 0; i < _timers.Count; i++)
                {
                    if (_timers[i].Id == id)
                    {
                        _timers.RemoveAt(i);
                        return;
                    }
                }
                if (_firing == null) return;
                foreach (var timer in _firing)
                {
                    if (timer.Id == id) timer.Cancelled = true;
                }
            }
        }

        internal long Now()
        {
            return _clock();
        }

        /// <summary>Stop running anything.</summary>
        internal void Close()
        {
            lock (Gate)
            {
                lock (_inboxLock)
                {
                    _closed = true;
                    _inbox.Clear();
                }
                _timers.Clear();
            }
        }
    }
}
