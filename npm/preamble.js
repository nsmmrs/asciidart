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
