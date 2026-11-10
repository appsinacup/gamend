using System;
using System.Collections.Generic;

namespace Gamend
{
    /// <summary>Who hears a kind of news. A listener may add or remove listeners while it runs,
    /// so the list is replaced on a change and never edited, and firing walks what it found.</summary>
    internal sealed class Listeners<T>
    {
        private readonly Loop _loop;
        private KeyValuePair<long, Action<T>>[] _items = Array.Empty<KeyValuePair<long, Action<T>>>();

        internal Listeners(Loop loop)
        {
            _loop = loop;
        }

        internal void Add(long id, Action<T> listener)
        {
            var items = new KeyValuePair<long, Action<T>>[_items.Length + 1];
            Array.Copy(_items, items, _items.Length);
            items[_items.Length] = new KeyValuePair<long, Action<T>>(id, listener);
            _items = items;
        }

        internal void Remove(long id)
        {
            for (var i = 0; i < _items.Length; i++)
            {
                if (_items[i].Key != id) continue;
                var items = new KeyValuePair<long, Action<T>>[_items.Length - 1];
                Array.Copy(_items, 0, items, 0, i);
                Array.Copy(_items, i + 1, items, i, _items.Length - i - 1);
                _items = items;
                return;
            }
        }

        internal void Fire(T value)
        {
            var items = _items;
            for (var i = 0; i < items.Length; i++)
            {
                try
                {
                    items[i].Value(value);
                }
                catch (Exception e)
                {
                    // One game handler's bug must not cost the others their
                    // event, or the SDK its own.
                    _loop.Keep(e);
                }
            }
        }
    }
}
