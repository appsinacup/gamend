using System;
using System.Diagnostics;
using System.Threading.Tasks;

namespace Gamend
{
    /// <summary>What `Client` owns, shared by every part of the SDK.</summary>
    internal sealed class Core
    {
        internal readonly Config Config;
        internal readonly string BaseUrl;
        internal readonly string RunId;
        internal readonly Loop Loop;
        internal readonly Rest Rest;
        internal readonly Auth Auth;
        internal readonly Realtime Realtime;
        internal readonly Api Api;
        internal readonly Kv Kv;
        internal readonly Presence Presence;
        internal readonly WebRtc WebRtc;

        internal Core(Config config)
        {
            Config = config;
            BaseUrl = (config.BaseUrl ?? "").TrimEnd('/');
            RunId = string.IsNullOrEmpty(config.RunId) ? Guid.NewGuid().ToString("N") : config.RunId;
            var clock = config.Clock;
            if (clock == null)
            {
                var watch = Stopwatch.StartNew();
                clock = () => watch.ElapsedMilliseconds;
            }
            Loop = new Loop(clock);
            Rest = new Rest(this);
            Auth = new Auth(this);
            Realtime = new Realtime(this);
            Api = new Api(Rest);
            Kv = new Kv(this);
            Presence = new Presence(this);
            WebRtc = new WebRtc(this);
        }

        internal object Gate
        {
            get { return Loop.Gate; }
        }

        internal void Post(Action task)
        {
            Loop.Post(task);
        }

        internal long UnixNow()
        {
            return Config.UnixClock != null ? Config.UnixClock() : DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        }

        internal void Log(LogLevel level, string line)
        {
            if (Config.Log == null) return;
            try
            {
                Config.Log(level, line);
            }
            catch (Exception e)
            {
                Loop.Keep(e);
            }
        }

        /// <summary>What finishes a public call's task. Whatever path reaches it, the task
        /// completes inside `Poll`, so `await` continues on the polling thread.</summary>
        internal Action<T> Completer<T>(TaskCompletionSource<T> source)
        {
            return value => Loop.Deliver(() => source.TrySetResult(value));
        }

        /// <summary>A task and what finishes it. Default options: a continuation runs inline, on
        /// the thread that polls.</summary>
        internal Task<T> Start<T>(Action<Action<T>> work)
        {
            var source = new TaskCompletionSource<T>();
            var done = Completer(source);
            lock (Gate)
            {
                work(done);
            }
            return source.Task;
        }
    }
}
