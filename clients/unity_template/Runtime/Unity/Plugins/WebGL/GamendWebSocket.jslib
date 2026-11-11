// The browser's WebSocket for UnityWebSocketTransport on WebGL.
//
// Each connection is kept under the id the C# side picked, until it closes or
// is closed; an event from one no longer kept reaches nobody. Text and bytes
// cross to C# as a pointer and a length into the heap, freed when the call
// returns, so a frame never has to be a NUL-terminated string.
var GamendWebSocketLibrary = {
  $GamendSockets: {
    connections: {},
    callbacks: null,
    encoder: null,

    utf8: function (text) {
      if (!GamendSockets.encoder) GamendSockets.encoder = new TextEncoder();
      return GamendSockets.encoder.encode(text);
    },

    // Run `call(pointer, length)` with `bytes` copied into the heap.
    withBytes: function (bytes, call) {
      var pointer = _malloc(Math.max(bytes.length, 1));
      HEAPU8.set(bytes, pointer);
      try {
        call(pointer, bytes.length);
      } finally {
        _free(pointer);
      }
    },

    error: function (id, message) {
      GamendSockets.withBytes(GamendSockets.utf8(message), function (pointer, length) {
        {{{ makeDynCall('viii', 'GamendSockets.callbacks.error') }}}(id, pointer, length);
      });
    }
  },

  GamendWebSocketInit: function (open, data, error, close) {
    GamendSockets.callbacks = { open: open, data: data, error: error, close: close };
  },

  GamendWebSocketOpen: function (id, url) {
    var socket;
    try {
      socket = new WebSocket(UTF8ToString(url));
    } catch (e) {
      // A malformed URL throws here instead of failing the connection. The C#
      // side is still inside Open, so it hears about it after.
      var message = String((e && e.message) || e);
      setTimeout(function () {
        GamendSockets.error(id, message);
      }, 0);
      return;
    }
    socket.binaryType = 'arraybuffer';
    GamendSockets.connections[id] = socket;

    socket.onopen = function () {
      if (GamendSockets.connections[id] !== socket) return;
      {{{ makeDynCall('vi', 'GamendSockets.callbacks.open') }}}(id);
    };

    socket.onmessage = function (event) {
      if (GamendSockets.connections[id] !== socket) return;
      var binary = typeof event.data !== 'string';
      var bytes = binary ? new Uint8Array(event.data) : GamendSockets.utf8(event.data);
      GamendSockets.withBytes(bytes, function (pointer, length) {
        {{{ makeDynCall('viiii', 'GamendSockets.callbacks.data') }}}(id, pointer, length, binary ? 1 : 0);
      });
    };

    socket.onerror = function () {
      if (GamendSockets.connections[id] !== socket) return;
      // The browser tells a page nothing more about why.
      GamendSockets.error(id, 'websocket error');
    };

    socket.onclose = function (event) {
      if (GamendSockets.connections[id] !== socket) return;
      delete GamendSockets.connections[id];
      GamendSockets.withBytes(GamendSockets.utf8(event.reason || ''), function (pointer, length) {
        {{{ makeDynCall('viiii', 'GamendSockets.callbacks.close') }}}(id, event.code, pointer, length);
      });
    };
  },

  GamendWebSocketSend: function (id, frame) {
    var socket = GamendSockets.connections[id];
    if (socket && socket.readyState === 1) socket.send(UTF8ToString(frame));
  },

  GamendWebSocketClose: function (id) {
    var socket = GamendSockets.connections[id];
    if (!socket) return;
    delete GamendSockets.connections[id];
    try {
      socket.close(1000);
    } catch (e) {
      // Closing is the goal, and a socket that cannot is closed already.
    }
  }
};

autoAddDeps(GamendWebSocketLibrary, '$GamendSockets');
mergeInto(LibraryManager.library, GamendWebSocketLibrary);
