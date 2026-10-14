// Runtime environment and 'made' CAD API module for JavaScriptCore (ADR-D6, #435).
// Adapted in part from the brepjs API shape (https://brepjs.dev, Apache-2.0).

(function (global) {
  'use strict';

  var OriginalDate = global.Date;

  // Remove any ambient host, timer, network, process, or filesystem globals.
  var FORBIDDEN_GLOBALS = [
    'fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource',
    'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval', 'setImmediate', 'clearImmediate',
    'process', 'fs', 'Deno', 'Bun', 'Worker', 'SharedWorker', 'navigator', 'window', 'document'
  ];
  for (var fg = 0; fg < FORBIDDEN_GLOBALS.length; fg++) {
    try {
      delete global[FORBIDDEN_GLOBALS[fg]];
    } catch (_) {}
    try {
      global[FORBIDDEN_GLOBALS[fg]] = undefined;
    } catch (_) {}
  }

  // Deterministic PRNG (Mulberry32) and fixed Date setup.
  global.__made_resetDeterministicEnv = function (seed, fixedTimeMs) {
    var state = (typeof seed === 'number' ? seed : 0x6D616465) >>> 0;
    Math.random = function () {
      state = (state + 0x6D2B79F5) >>> 0;
      var t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };

    var fixedMs = typeof fixedTimeMs === 'number' ? fixedTimeMs : 1704067200000; // 2024-01-01T00:00:00.000Z
    function DeterministicDate() {
      if (!(this instanceof DeterministicDate)) {
        return new OriginalDate(fixedMs).toString();
      }
      var args = Array.prototype.slice.call(arguments);
      if (args.length === 0) {
        return new OriginalDate(fixedMs);
      }
      if (args.length === 1) {
        return new OriginalDate(args[0]);
      }
      return new (Function.prototype.bind.apply(OriginalDate, [null].concat(args)))();
    }
    DeterministicDate.now = function () { return fixedMs; };
    DeterministicDate.parse = OriginalDate.parse.bind(OriginalDate);
    DeterministicDate.UTC = OriginalDate.UTC.bind(OriginalDate);
    DeterministicDate.prototype = OriginalDate.prototype;
    global.Date = DeterministicDate;
  };

  global.__made_resetDeterministicEnv(0x6D616465, 1704067200000);

  // Per-evaluation state
  var paramOverrides = {};
  var recordedParams = [];
  var recordedParamsByName = {};

  global.__made_beginEvaluation = function (overrides, seed, fixedTimeMs) {
    paramOverrides = overrides || {};
    recordedParams = [];
    recordedParamsByName = {};
    global.__made_resetDeterministicEnv(seed, fixedTimeMs);
  };

  global.__made_getRecordedParams = function () {
    return recordedParams;
  };

  function formatConsoleArgs(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var v = args[i];
      if (typeof v === 'string') {
        parts.push(v);
      } else {
        try {
          parts.push(JSON.stringify(v));
        } catch (_) {
          parts.push(String(v));
        }
      }
    }
    return parts.join(' ');
  }

  global.console = Object.freeze({
    log: function () {},
    info: function () {},
    debug: function () {},
    warn: function () {
      var msg = formatConsoleArgs(arguments);
      var stack = '';
      try {
        stack = (new Error()).stack || '';
      } catch (_) {}
      if (typeof global.__made_warn === 'function') {
        global.__made_warn(msg, stack);
      }
    },
    error: function () {
      var msg = formatConsoleArgs(arguments);
      var stack = '';
      try {
        stack = (new Error()).stack || '';
      } catch (_) {}
      if (typeof global.__made_warn === 'function') {
        global.__made_warn(msg, stack);
      }
    }
  });

  function toVec2(val, fallbackX, fallbackY) {
    if (Array.isArray(val)) {
      if (val.length < 2) {
        throw new TypeError('Expected a 2D vector [x, y]');
      }
      return [Number(val[0]), Number(val[1])];
    }
    if (val && typeof val === 'object' && ('x' in val || 'y' in val)) {
      return [
        'x' in val ? Number(val.x) : (fallbackX || 0),
        'y' in val ? Number(val.y) : (fallbackY || 0)
      ];
    }
    return [fallbackX || 0, fallbackY || 0];
  }

  function toVec3(val, fallbackX, fallbackY, fallbackZ) {
    if (Array.isArray(val)) {
      if (val.length < 3) {
        throw new TypeError('Expected a 3D vector [x, y, z]');
      }
      return [Number(val[0]), Number(val[1]), Number(val[2])];
    }
    if (val && typeof val === 'object' && ('x' in val || 'y' in val || 'z' in val)) {
      return [
        'x' in val ? Number(val.x) : (fallbackX || 0),
        'y' in val ? Number(val.y) : (fallbackY || 0),
        'z' in val ? Number(val.z) : (fallbackZ || 0)
      ];
    }
    return [fallbackX || 0, fallbackY || 0, fallbackZ || 0];
  }

  function normalizeVec3(v) {
    var len = Math.hypot(v[0], v[1], v[2]);
    if (len <= 1e-9) return [0, 0, 1];
    return [v[0] / len, v[1] / len, v[2] / len];
  }

  function makePlaneSpec(origin, normal, xAxis) {
    var o = toVec3(origin, 0, 0, 0);
    var n = toVec3(normal, 0, 0, 1);
    var x = toVec3(xAxis, 1, 0, 0);
    return {
      origin: o,
      normal: n,
      xAxis: x,
      offset: function (dist) {
        var d = Number(dist);
        var un = normalizeVec3(n);
        return makePlaneSpec(
          [o[0] + un[0] * d, o[1] + un[1] * d, o[2] + un[2] * d],
          un,
          x
        );
      }
    };
  }

  var Plane = {
    XY: makePlaneSpec([0, 0, 0], [0, 0, 1], [1, 0, 0]),
    XZ: makePlaneSpec([0, 0, 0], [0, -1, 0], [1, 0, 0]),
    YZ: makePlaneSpec([0, 0, 0], [1, 0, 0], [0, 1, 0]),
    offset: function (basePlane, distance) {
      var resolved = resolvePlane(basePlane);
      return resolved.offset(distance);
    },
    custom: function (origin, normal, xAxis) {
      return makePlaneSpec(origin, normal, xAxis || [1, 0, 0]);
    }
  };

  function resolvePlane(spec, offsetDistance) {
    var p;
    if (!spec || spec === 'XY' || spec === 'xy') {
      p = Plane.XY;
    } else if (spec === 'XZ' || spec === 'xz') {
      p = Plane.XZ;
    } else if (spec === 'YZ' || spec === 'yz') {
      p = Plane.YZ;
    } else if (typeof spec === 'object') {
      var o = spec.origin ? toVec3(spec.origin, 0, 0, 0) : [0, 0, 0];
      var n = spec.normal ? toVec3(spec.normal, 0, 0, 1) : [0, 0, 1];
      var x = (spec.xAxis || spec.xDir) ? toVec3(spec.xAxis || spec.xDir, 1, 0, 0) : [1, 0, 0];
      p = makePlaneSpec(o, n, x);
    } else {
      throw new TypeError('Invalid plane specification: ' + String(spec));
    }
    if (typeof offsetDistance === 'number' && offsetDistance !== 0) {
      return p.offset(offsetDistance);
    }
    return p;
  }

  function ensureShape(val, contextName) {
    if (!val || val.__madeShape !== true || !val.node) {
      throw new TypeError((contextName || 'Operation') + ' expected a Shape');
    }
    return val;
  }

  function makeShape(node) {
    var shape = {
      __madeShape: true,
      node: node,
      translate: function (a, b, c) {
        return translate(shape, a, b, c);
      },
      rotate: function (a, b) {
        return rotate(shape, a, b);
      },
      rotateX: function (deg) {
        return rotate(shape, Number(deg), [1, 0, 0]);
      },
      rotateY: function (deg) {
        return rotate(shape, Number(deg), [0, 1, 0]);
      },
      rotateZ: function (deg) {
        return rotate(shape, Number(deg), [0, 0, 1]);
      },
      scale: function (a, b, c) {
        return scale(shape, a, b, c);
      },
      union: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return union.apply(null, args);
      },
      fuse: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return union.apply(null, args);
      },
      subtract: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return subtract.apply(null, args);
      },
      cut: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return subtract.apply(null, args);
      },
      difference: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return subtract.apply(null, args);
      },
      intersect: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return intersect.apply(null, args);
      },
      common: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return intersect.apply(null, args);
      },
      intersection: function () {
        var args = [shape].concat(Array.prototype.slice.call(arguments));
        return intersect.apply(null, args);
      }
    };
    return shape;
  }

  function applyCenterOption(baseShape, centerOpt, defaultHalfExtents) {
    if (centerOpt === false) {
      return translate(baseShape, defaultHalfExtents);
    }
    if (Array.isArray(centerOpt) || (centerOpt && typeof centerOpt === 'object')) {
      var off = toVec3(centerOpt, 0, 0, 0);
      if (off[0] !== 0 || off[1] !== 0 || off[2] !== 0) {
        return translate(baseShape, off);
      }
    }
    return baseShape;
  }

  // Primitives
  function Box(a, b, c, d) {
    var width, depth, height, center;
    if (a && typeof a === 'object' && !Array.isArray(a)) {
      width = Number(a.width !== undefined ? a.width : a.x);
      depth = Number(a.depth !== undefined ? a.depth : a.y);
      height = Number(a.height !== undefined ? a.height : a.z);
      center = a.center;
    } else {
      width = Number(a);
      depth = Number(b !== undefined ? b : a);
      height = Number(c !== undefined ? c : a);
      center = d && typeof d === 'object' ? d.center : undefined;
    }
    var s = makeShape({
      kind: 'box',
      width: width,
      depth: depth,
      height: height
    });
    return applyCenterOption(s, center, [width / 2, depth / 2, height / 2]);
  }

  function Cylinder(a, b, c) {
    var radius, height, slices = 32, center;
    if (a && typeof a === 'object' && !Array.isArray(a)) {
      radius = a.radius !== undefined ? Number(a.radius) : Number(a.diameter) / 2;
      height = Number(a.height);
      if (a.slices !== undefined) slices = Math.round(Number(a.slices));
      center = a.center;
    } else {
      radius = Number(a);
      height = Number(b);
      if (c && typeof c === 'object') {
        if (c.slices !== undefined) slices = Math.round(Number(c.slices));
        center = c.center;
      } else if (typeof c === 'number') {
        slices = Math.round(c);
      }
    }
    var s = makeShape({
      kind: 'cylinder',
      radius: radius,
      height: height,
      slices: slices
    });
    return applyCenterOption(s, center, [0, 0, height / 2]);
  }

  function Sphere(a, b) {
    var radius, slices = 32, center;
    if (a && typeof a === 'object' && !Array.isArray(a)) {
      radius = a.radius !== undefined ? Number(a.radius) : Number(a.diameter) / 2;
      if (a.slices !== undefined) slices = Math.round(Number(a.slices));
      center = a.center;
    } else {
      radius = Number(a);
      if (b && typeof b === 'object') {
        if (b.slices !== undefined) slices = Math.round(Number(b.slices));
        center = b.center;
      } else if (typeof b === 'number') {
        slices = Math.round(b);
      }
    }
    var s = makeShape({
      kind: 'sphere',
      radius: radius,
      slices: slices
    });
    return applyCenterOption(s, center, [0, 0, radius]);
  }

  function Cone(a, b, c) {
    var bottomRadius, topRadius = 0, height, slices = 32, center;
    if (a && typeof a === 'object' && !Array.isArray(a)) {
      bottomRadius = Number(a.bottomRadius !== undefined ? a.bottomRadius : a.radius);
      topRadius = a.topRadius !== undefined ? Number(a.topRadius) : 0;
      height = Number(a.height);
      if (a.slices !== undefined) slices = Math.round(Number(a.slices));
      center = a.center;
    } else {
      bottomRadius = Number(a);
      height = Number(b);
      if (c && typeof c === 'object') {
        if (c.topRadius !== undefined) topRadius = Number(c.topRadius);
        if (c.slices !== undefined) slices = Math.round(Number(c.slices));
        center = c.center;
      } else if (typeof c === 'number') {
        slices = Math.round(c);
      }
    }
    var s = makeShape({
      kind: 'cone',
      bottomRadius: bottomRadius,
      topRadius: topRadius,
      height: height,
      slices: slices
    });
    return applyCenterOption(s, center, [0, 0, height / 2]);
  }

  // Transforms
  function translate(shape, a, b, c) {
    var s = ensureShape(shape, 'translate');
    var offset;
    if (Array.isArray(a) || (a && typeof a === 'object')) {
      offset = toVec3(a, 0, 0, 0);
    } else {
      offset = [
        a !== undefined ? Number(a) : 0,
        b !== undefined ? Number(b) : 0,
        c !== undefined ? Number(c) : 0
      ];
    }
    return makeShape({
      kind: 'translate',
      child: s.node,
      offset: offset
    });
  }

  function rotate(shape, a, b) {
    var s = ensureShape(shape, 'rotate');
    if (Array.isArray(a) || (a && typeof a === 'object')) {
      var angles = toVec3(a, 0, 0, 0);
      var current = s;
      if (angles[0] !== 0) {
        current = makeShape({ kind: 'rotate', child: current.node, axis: [1, 0, 0], angleDegrees: angles[0] });
      }
      if (angles[1] !== 0) {
        current = makeShape({ kind: 'rotate', child: current.node, axis: [0, 1, 0], angleDegrees: angles[1] });
      }
      if (angles[2] !== 0 || (angles[0] === 0 && angles[1] === 0)) {
        current = makeShape({ kind: 'rotate', child: current.node, axis: [0, 0, 1], angleDegrees: angles[2] });
      }
      return current;
    }
    var angleDeg = Number(a);
    var axis = b !== undefined ? toVec3(b, 0, 0, 1) : [0, 0, 1];
    return makeShape({
      kind: 'rotate',
      child: s.node,
      axis: axis,
      angleDegrees: angleDeg
    });
  }

  function scale(shape, a, b, c) {
    var s = ensureShape(shape, 'scale');
    var factor;
    if (Array.isArray(a) || (a && typeof a === 'object')) {
      factor = toVec3(a, 1, 1, 1);
    } else if (b === undefined && c === undefined) {
      var u = Number(a);
      factor = [u, u, u];
    } else {
      factor = [
        Number(a),
        b !== undefined ? Number(b) : Number(a),
        c !== undefined ? Number(c) : Number(a)
      ];
    }
    return makeShape({
      kind: 'scale',
      child: s.node,
      factor: factor
    });
  }

  // Booleans
  function foldBoolean(op, args) {
    if (args.length < 2) {
      throw new TypeError(op + ' requires at least two Shapes');
    }
    var acc = ensureShape(args[0], op);
    for (var i = 1; i < args.length; i++) {
      var rhs = ensureShape(args[i], op);
      acc = makeShape({
        kind: 'boolean',
        op: op,
        lhs: acc.node,
        rhs: rhs.node
      });
    }
    return acc;
  }

  function union() {
    return foldBoolean('union', Array.prototype.slice.call(arguments));
  }

  function subtract() {
    return foldBoolean('subtract', Array.prototype.slice.call(arguments));
  }

  function intersect() {
    return foldBoolean('intersect', Array.prototype.slice.call(arguments));
  }

  // 2D Sketches on Planes
  function makeRectPoints(width, height, centerOpt) {
    var w = Number(width);
    var h = Number(height);
    var cx = 0, cy = 0;
    if (centerOpt === false) {
      cx = w / 2;
      cy = h / 2;
    } else if (Array.isArray(centerOpt) || (centerOpt && typeof centerOpt === 'object')) {
      var c = toVec2(centerOpt, 0, 0);
      cx = c[0];
      cy = c[1];
    }
    var hw = w / 2, hh = h / 2;
    return [
      [cx - hw, cy - hh],
      [cx + hw, cy - hh],
      [cx + hw, cy + hh],
      [cx - hw, cy + hh]
    ];
  }

  function makeRoundedRectPoints(width, height, radius, detail, centerOpt) {
    var w = Number(width);
    var h = Number(height);
    var r = Math.min(Number(radius), w / 2, h / 2);
    if (r <= 0) {
      return makeRectPoints(w, h, centerOpt);
    }
    var segs = detail !== undefined ? Math.max(2, Math.round(Number(detail))) : 6;
    var cx = 0, cy = 0;
    if (centerOpt === false) {
      cx = w / 2;
      cy = h / 2;
    } else if (Array.isArray(centerOpt) || (centerOpt && typeof centerOpt === 'object')) {
      var c = toVec2(centerOpt, 0, 0);
      cx = c[0];
      cy = c[1];
    }
    var hw = w / 2, hh = h / 2;
    var corners = [
      { x: cx + hw - r, y: cy - hh + r, start: -Math.PI / 2, end: 0 },
      { x: cx + hw - r, y: cy + hh - r, start: 0, end: Math.PI / 2 },
      { x: cx - hw + r, y: cy + hh - r, start: Math.PI / 2, end: Math.PI },
      { x: cx - hw + r, y: cy - hh + r, start: Math.PI, end: 3 * Math.PI / 2 }
    ];
    var pts = [];
    for (var ci = 0; ci < corners.length; ci++) {
      var corner = corners[ci];
      for (var s = 0; s <= segs; s++) {
        var ang = corner.start + (s / segs) * (corner.end - corner.start);
        pts.push([corner.x + r * Math.cos(ang), corner.y + r * Math.sin(ang)]);
      }
    }
    return pts;
  }

  function makeCirclePoints(radius, segments, centerOpt) {
    var r = Number(radius);
    var segs = segments !== undefined ? Math.max(3, Math.round(Number(segments))) : 32;
    var c = centerOpt ? toVec2(centerOpt, 0, 0) : [0, 0];
    var pts = [];
    for (var i = 0; i < segs; i++) {
      var theta = (2 * Math.PI * i) / segs;
      pts.push([c[0] + r * Math.cos(theta), c[1] + r * Math.sin(theta)]);
    }
    return pts;
  }

  function makeSketchProfile(planeSpec, initialPoints) {
    var resolvedPlane = resolvePlane(planeSpec);
    var pts = (initialPoints || []).map(function (p) { return toVec2(p, 0, 0); });

    var profile = {
      __madeSketch: true,
      plane: resolvedPlane,
      points: pts,

      moveTo: function (x, y) {
        return makeSketchProfile(resolvedPlane, [[Number(x), Number(y)]]);
      },
      lineTo: function (x, y) {
        var next = pts.slice();
        next.push([Number(x), Number(y)]);
        return makeSketchProfile(resolvedPlane, next);
      },
      arcTo: function (endX, endY, radius, options) {
        var next = pts.slice();
        var startPt = next.length > 0 ? next[next.length - 1] : [0, 0];
        var ex = Number(endX), ey = Number(endY);
        var r = Math.abs(Number(radius));
        var segs = (options && options.segments) ? Math.max(2, Math.round(Number(options.segments))) : 12;
        var cw = !!(options && options.clockwise);
        var dx = ex - startPt[0], dy = ey - startPt[1];
        var chord = Math.hypot(dx, dy);
        if (chord <= 1e-9 || r <= chord / 2) {
          r = chord / 2;
        }
        var midX = (startPt[0] + ex) / 2;
        var midY = (startPt[1] + ey) / 2;
        var h = Math.sqrt(Math.max(0, r * r - (chord * chord) / 4));
        var nx = -dy / (chord || 1);
        var ny = dx / (chord || 1);
        var sign = cw ? -1 : 1;
        var cx = midX + sign * h * nx;
        var cy = midY + sign * h * ny;
        var a0 = Math.atan2(startPt[1] - cy, startPt[0] - cx);
        var a1 = Math.atan2(ey - cy, ex - cx);
        var delta = a1 - a0;
        if (cw && delta > 0) delta -= 2 * Math.PI;
        if (!cw && delta < 0) delta += 2 * Math.PI;
        for (var k = 1; k <= segs; k++) {
          var a = a0 + (k / segs) * delta;
          next.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
        }
        return makeSketchProfile(resolvedPlane, next);
      },
      close: function () {
        var next = pts.slice();
        if (next.length >= 2) {
          var first = next[0];
          var last = next[next.length - 1];
          if (Math.hypot(first[0] - last[0], first[1] - last[1]) < 1e-6) {
            next.pop();
          }
        }
        return makeSketchProfile(resolvedPlane, next);
      },
      rectangle: function (width, height, options) {
        return makeSketchProfile(resolvedPlane, makeRectPoints(width, height, options ? options.center : undefined));
      },
      rect: function (width, height, options) {
        return makeSketchProfile(resolvedPlane, makeRectPoints(width, height, options ? options.center : undefined));
      },
      roundedRectangle: function (width, height, radius, options) {
        return makeSketchProfile(
          resolvedPlane,
          makeRoundedRectPoints(width, height, radius, options ? options.detail : undefined, options ? options.center : undefined)
        );
      },
      roundedRect: function (width, height, radius, options) {
        return makeSketchProfile(
          resolvedPlane,
          makeRoundedRectPoints(width, height, radius, options ? options.detail : undefined, options ? options.center : undefined)
        );
      },
      circle: function (radius, options) {
        return makeSketchProfile(
          resolvedPlane,
          makeCirclePoints(radius, options ? options.segments : undefined, options ? options.center : undefined)
        );
      },
      polygon: function (polyPoints) {
        if (!Array.isArray(polyPoints)) {
          throw new TypeError('polygon expects an array of 2D points');
        }
        var mapped = polyPoints.map(function (pt) { return toVec2(pt, 0, 0); });
        if (mapped.length >= 2) {
          var f = mapped[0], l = mapped[mapped.length - 1];
          if (Math.hypot(f[0] - l[0], f[1] - l[1]) < 1e-6) {
            mapped.pop();
          }
        }
        return makeSketchProfile(resolvedPlane, mapped);
      },
      regularPolygon: function (radius, sides, options) {
        return makeSketchProfile(
          resolvedPlane,
          makeCirclePoints(radius, sides, options ? options.center : undefined)
        );
      },
      translate: function (a, b) {
        var off = (Array.isArray(a) || (a && typeof a === 'object'))
          ? toVec2(a, 0, 0)
          : [Number(a || 0), Number(b || 0)];
        var shifted = pts.map(function (p) { return [p[0] + off[0], p[1] + off[1]]; });
        return makeSketchProfile(resolvedPlane, shifted);
      },
      extrude: function (distOrOpts, opts) {
        return extrude(profile, distOrOpts, opts);
      },
      revolve: function (angleOrOpts, opts) {
        return revolve(profile, angleOrOpts, opts);
      }
    };
    return profile;
  }

  function Sketch(planeSpec) {
    return makeSketchProfile(planeSpec || Plane.XY, []);
  }

  function ensureSketch(val, contextName) {
    if (!val || val.__madeSketch !== true || !Array.isArray(val.points)) {
      throw new TypeError((contextName || 'Operation') + ' expected a SketchProfile');
    }
    return val;
  }

  function extrude(profile, distOrOpts, opts) {
    var sk = ensureSketch(profile, 'extrude');
    var distance;
    var centered = false;
    if (distOrOpts && typeof distOrOpts === 'object') {
      var dVal = distOrOpts.distance !== undefined ? distOrOpts.distance
               : (distOrOpts.height !== undefined ? distOrOpts.height : distOrOpts.depth);
      distance = Number(dVal);
      centered = !!distOrOpts.centered;
    } else {
      distance = Number(distOrOpts);
      if (opts && typeof opts === 'object') {
        centered = !!opts.centered;
      }
    }
    return makeShape({
      kind: 'extrude',
      profile: {
        plane: {
          origin: sk.plane.origin,
          normal: sk.plane.normal,
          xAxis: sk.plane.xAxis
        },
        points: sk.points
      },
      distance: distance,
      centered: centered
    });
  }

  function revolve(profile, angleOrOpts, opts) {
    var sk = ensureSketch(profile, 'revolve');
    var angleDegrees = 360;
    var slices = 32;
    if (angleOrOpts && typeof angleOrOpts === 'object') {
      if (angleOrOpts.angleDegrees !== undefined) angleDegrees = Number(angleOrOpts.angleDegrees);
      else if (angleOrOpts.angle !== undefined) angleDegrees = Number(angleOrOpts.angle);
      if (angleOrOpts.slices !== undefined) slices = Math.round(Number(angleOrOpts.slices));
    } else {
      if (angleOrOpts !== undefined) angleDegrees = Number(angleOrOpts);
      if (opts && typeof opts === 'object' && opts.slices !== undefined) {
        slices = Math.round(Number(opts.slices));
      }
    }
    return makeShape({
      kind: 'revolve',
      profile: {
        plane: {
          origin: sk.plane.origin,
          normal: sk.plane.normal,
          xAxis: sk.plane.xAxis
        },
        points: sk.points
      },
      angleDegrees: angleDegrees,
      slices: slices
    });
  }

  function rectangle(width, height, options) {
    var pl = options && options.plane ? options.plane : Plane.XY;
    return Sketch(pl).rectangle(width, height, options);
  }

  function roundedRectangle(width, height, radius, options) {
    var pl = options && options.plane ? options.plane : Plane.XY;
    return Sketch(pl).roundedRectangle(width, height, radius, options);
  }

  function circle(radius, options) {
    var pl = options && options.plane ? options.plane : Plane.XY;
    return Sketch(pl).circle(radius, options);
  }

  function polygon(points, options) {
    var pl = options && options.plane ? options.plane : Plane.XY;
    return Sketch(pl).polygon(points);
  }

  function regularPolygon(radius, sides, options) {
    var pl = options && options.plane ? options.plane : Plane.XY;
    return Sketch(pl).regularPolygon(radius, sides, options);
  }

  // Named parameters
  function param(name, defaultValue, options) {
    if (typeof name !== 'string' || name.trim().length === 0) {
      throw new TypeError('Parameter name must be a non-empty string');
    }
    var defVal = Number(defaultValue);
    if (!Number.isFinite(defVal)) {
      throw new RangeError('Parameter "' + name + '" default value must be finite');
    }
    var opts = options || {};
    var minVal = opts.min !== undefined ? Number(opts.min) : null;
    var maxVal = opts.max !== undefined ? Number(opts.max) : null;
    var stepVal = opts.step !== undefined ? Number(opts.step) : null;
    var unitVal = typeof opts.unit === 'string' ? opts.unit : null;
    var labelVal = typeof opts.label === 'string' ? opts.label : null;

    var actual = defVal;
    if (Object.prototype.hasOwnProperty.call(paramOverrides, name)) {
      var overrideNum = Number(paramOverrides[name]);
      if (!Number.isFinite(overrideNum)) {
        throw new RangeError('Override for parameter "' + name + '" must be a finite number');
      }
      actual = overrideNum;
    }
    if (minVal !== null && Number.isFinite(minVal) && actual < minVal) {
      actual = minVal;
    }
    if (maxVal !== null && Number.isFinite(maxVal) && actual > maxVal) {
      actual = maxVal;
    }

    var record = {
      name: name,
      defaultValue: defVal,
      value: actual,
      min: minVal,
      max: maxVal,
      step: stepVal,
      unit: unitVal,
      label: labelVal
    };
    if (Object.prototype.hasOwnProperty.call(recordedParamsByName, name)) {
      recordedParams[recordedParamsByName[name]] = record;
    } else {
      recordedParamsByName[name] = recordedParams.length;
      recordedParams.push(record);
    }
    return actual;
  }

  function defineParams(schema) {
    if (!schema || typeof schema !== 'object') {
      throw new TypeError('defineParams expects a parameter schema object');
    }
    var result = {};
    var keys = Object.keys(schema);
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      var spec = schema[key];
      if (typeof spec === 'number') {
        result[key] = param(key, spec);
      } else if (spec && typeof spec === 'object') {
        result[key] = param(key, spec.default, spec);
      } else {
        throw new TypeError('Invalid parameter definition for "' + key + '"');
      }
    }
    return result;
  }

  var madeModule = Object.freeze({
    Plane: Plane,
    plane: resolvePlane,
    Box: Box,
    box: Box,
    Cylinder: Cylinder,
    cylinder: Cylinder,
    Sphere: Sphere,
    sphere: Sphere,
    Cone: Cone,
    cone: Cone,
    Sketch: Sketch,
    sketch: Sketch,
    rectangle: rectangle,
    rect: rectangle,
    roundedRectangle: roundedRectangle,
    roundedRect: roundedRectangle,
    circle: circle,
    polygon: polygon,
    regularPolygon: regularPolygon,
    extrude: extrude,
    revolve: revolve,
    union: union,
    fuse: union,
    subtract: subtract,
    cut: subtract,
    difference: subtract,
    intersect: intersect,
    common: intersect,
    intersection: intersect,
    translate: translate,
    rotate: rotate,
    scale: scale,
    param: param,
    defineParams: defineParams
  });

  global.__made_module = madeModule;
})(globalThis);
