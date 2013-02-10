root = window ? exports

root.Util =
  last: (arr) -> arr[arr.length - 1]

  isString: (s) -> typeof s == 'string' || s instanceof String

  defineNonEnumerable: (obj, k, v) ->
    Object.defineProperty obj, k,
      value: v
      writable: true
      enumerable: false
      configurable: true

if Map? # polyfill
  root.Map = Map
else
  class root.Map
    constructor: ->
      @cache = Object.create null
      @proto_cache = undefined
      @proto_set = false

    get: (key) ->
      key = key.toString()
      return @cache[key] unless key is '__proto__'
      return @proto_cache

    has: (key) ->
      key = key.toString()
      return key of @cache unless key is '__proto__'
      return @proto_set

    set: (key, value) ->
      unless key.toString() is '__proto__'
        @cache[key] = value
      else
        @proto_cache = value
        @proto_set = true
      value
