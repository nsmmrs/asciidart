// Prepended to the compiled Dart core by tool/build-npm.sh: dart2js code
// expects a browser-like `self` with `scheduleImmediate`. Declared with var
// at the top of the module, it shadows any global `self` inside the bundle
// only.
var self = Object.create(globalThis);
self.scheduleImmediate =
  typeof setImmediate === 'function'
    ? function (callback) {
        setImmediate(callback);
      }
    : function (callback) {
        setTimeout(callback, 0);
      };
// dart2js reads `self.trustedTypes` when it loads a part on demand; on a
// window that is an accessor, which throws when called on this object.
// The package loads the parts itself (no script URL is used), so it has
// none. (Defined, not assigned: a window's is a getter.)
Object.defineProperty(self, 'trustedTypes', { value: undefined, writable: true });
