_ = require "underscore"
HasProperties = require "./has_properties"
svg_colors = require "./svg_colors"

class Property extends HasProperties

  initialize: (attrs, options) ->
    super(attrs, options)
    obj = @get('obj')
    attr = @get('attr')

    attr_value = obj.get(attr)

    if _.isObject(attr_value) and not _.isArray(attr_value)
      # use whichever the spec provides if there is a spec
      @spec = attr_value
      if @spec.value?
        @fixed_value = @spec.value
      else if @spec.field?
        @field = @spec.field
      else
        throw new Error("spec for property '#{attr}' needs one of 'value' or
                         'field'")
    else
      # otherwise if there is no spec use a default
      @fixed_value = attr_value

    if this.filed? and not _.isString(@field)
      throw new Error("field value for property '#{attr}' is not a string")

    if @fixed_value?
      @validate(@fixed_value, attr)

  value: () ->
    result = if @fixed_value? then @fixed_value else NaN
    return @transform([result])[0]

  array: (source) ->
    data = source.get('data')
    if @field? and (@field of data)
      result = source.get_column(@field)
    else
      length = source.get_length()
      length = 1 if not length?
      value = if @fixed_value? then @fixed_value else NaN
      result = (value for i in [0...length])
    return @transform(result)

  transform: (values) -> values

  validate: (value, attr) -> true

#
# Numeric Properties
#

class Numeric extends Property

  validate: (value, attr) ->
    if not _.isNumber(value)
      throw new Error("numeric property '#{attr}' given invalid value:
                       #{value}")

  transform: (values) ->
    result = new Float64Array(values.length)
    for i in [0...values.length]
      result[i] = values[i]

class Angle extends Numeric

  initialize: (attrs, options) ->
    super(attrs, options)
    obj = @get('obj')
    attr = @get('attr')
    spec = obj.get(attr)
    @units = @spec?.units ? obj.get("#{attr}_units") ? "rad"

  transform: (values) ->
    if @units == "deg"
      values = (x * Math.pi/180.0 for x in values)
    values = (-x for x in values)
    return super(values)

class Distance extends Numeric

  initialize: (attrs, options) ->
    super(attrs, options)
    obj = @get('obj')
    attr = @get('attr')
    @units = @spec?.units ? obj.get("#{attr}_units") ? "data"

#
# Basic Properties
#

class Array extends Property

  validate: (value, attr) ->
    if not _.isArray(value)
      throw new Error("array property '#{attr}' given invalid value: #{value}")

class Bool extends Property

  validate: (value, attr) ->
    if not _.isBoolean(value)
      throw new Error("boolean property '#{attr}' given invalid value:
                       #{value}")

class Coord extends Property

  validate: (value, attr) ->
    if not _.isNumber(value) and not _.isString(value)
      throw new Error("coordinate property '#{attr}' given invalid value:
                       #{value}")

class Color extends Property

  validate: (value, attr) ->
    if not svg_colors[value]? and value.substring(0, 1) != "#"
      throw new Error("color property '#{attr}' given invalid value: #{value}")

class Enum extends Property

  initialize: (attrs, options) ->
    @levels = attrs.values.split(" ")
    super(attrs, options)

  validate: (value, attr) ->
    if value not in @levels
      throw new Error("enum property '#{attr}' given invalid value: #{value},
                       valid values are: #{@levels}")

class Direction extends Enum

  initialize: (attrs, options) ->
    attrs.values = "anticlock clock"
    super(attrs, options)

  transform: (values) ->
    result = new Uint8Array(values.length)
    for i in [0...values.length]
      switch values[i]
        when 'clock'     then result[i] = false
        when 'anticlock' then result[i] = true
        else result[i] = false
    return result

class String extends Property

  validate: (value, attr) ->
    if not _.isString(value)
      throw new Error("string property '#{attr}' given invalid value: #{value}")

#
# Drawing Context Properties
#

class ContextProperties extends HasProperties

  initialize: (attrs, options) ->
    @cache = {}
    super(attrs, options)


  warm_cache: (source, attrs) ->
    for attr in attrs
      prop = @[attr]
      if prop.fixed_value?
        @cache[attr] = prop.fixed_value
      else
        @cache[attr+"_array"] = prop.array(source)

  cache_select: (attr, i) ->
    prop = @[attr]
    if prop.fixed_value?
      @cache[attr] = prop.fixed_value
    else
      @cache[attr] = @cache[attr+"_array"][i]

class Line extends ContextProperties

  initialize: (attrs, options) ->
    super(attrs, options)

    obj = @get('obj')
    prefix = @get('prefix')

    @color = new Color({obj: obj, attr: "#{prefix}line_color"})
    @width = new Numeric({obj: obj, attr: "#{prefix}line_width"})
    @alpha = new Numeric({obj: obj, attr: "#{prefix}line_alpha"})
    @join = new Enum
      obj: obj
      attr: "#{prefix}line_join"
      values: "miter round bevel"
    @cap = new Enum
      obj: obj
      attr: "#{prefix}line_cap"
      values: "butt round square"
    @dash = new Array({obj: obj, attr: "#{prefix}line_dash"})
    @dash_offset = new Numeric({obj: obj, attr: "#{prefix}line_dash_offset"})

    @do_stroke = true
    if not _.isUndefined(@color.fixed_value)
      if _.isNull(@color.fixed_value)
        @do_stroke = false

  warm_cache: (source) ->
    super(source,
          ["color", "width", "alpha", "join", "cap", "dash", "dash_offset"])

  set_value: (ctx) ->
    ctx.strokeStyle = @color.value()
    ctx.globalAlpha = @alpha.value()
    ctx.lineWidth   = @width.value()
    ctx.lineCap     = @join.value()
    ctx.lineCap     = @cap.value()
    ctx.setLineDash(@dash.value())
    ctx.setLineDashOffset(@dash_offset.value())

  set_vectorize: (ctx, i) ->
    if ctx.strokeStyle != @cache.fill
      @cache_select("color", i)
      ctx.strokeStyle = @cache.color

    if ctx.globalAlpha != @cache.alpha
      @cache_select("alpha", i)
      ctx.globalAlpha = @cache.alpha

    if ctx.lineWidth != @cache.width
      @cache_select("width", i)
      ctx.lineWidth = @cache.width

    if ctx.lineJoin != @cache.join
      @cache_select("join", i)
      ctx.lineJoin = @cache.join

    if ctx.lineCap != @cache.cap
      @cache_select("cap", i)
      ctx.lineCap = @cache.cap

    if ctx.getLineDash() != @cache.dash
      @cache_select("dash", i)
      ctx.setLineDash(@cache.dash)

    if ctx.getLineDashOffset() != @cache.dash_offset
      @cache_select("dash_offset", i)
      ctx.setLineDash(@cache.dash_offset)


class Fill extends ContextProperties

  initialize: (attrs, options) ->
    super(attrs, options)

    obj = @get('obj')
    prefix = @get('prefix')

    @color = new Color({obj: obj, attr: "#{prefix}fill_color"})
    @alpha = new Numeric({obj: obj, attr: "#{prefix}fill_alpha"})

    @do_fill = true
    if not _.isUndefined(@color.fixed_value)
      if _.isNull(@color.fixed_value)
        @do_fill = false

  warm_cache: (source) ->
    super(source, ["color", "alpha"])

  set_value: (ctx) ->
    ctx.fillStyle   = @color.value()
    ctx.globalAlpha = @alpha.value()

  set_vectorize: (ctx, i) ->
    if ctx.fillStyle != @cache.fill
      @cache_select("color", i)
      ctx.fillStyle = @cache.color

    if ctx.globalAlpha != @cache.alpha
      @cache_select("alpha", i)
      ctx.globalAlpha = @cache.alpha

class Text extends ContextProperties

  initialize: (attrs, options) ->
    super(attrs, options)

    obj = @get('obj')
    prefix = @get('prefix')

    @font = new String({obj: obj, attr: "#{prefix}text_font"})
    @font_size = new String({obj: obj, attr: "#{prefix}text_font_size"})
    @font_style = new Enum
      obj: obj
      attr: "#{prefix}text_font_style"
      values: "normal italic bold"
    @color = new Color({obj: obj, attr: "#{prefix}text_color"})
    @alpha = new Numeric({obj: obj, attr: "#{prefix}text_alpha"})
    @align = new Enum
      obj: obj
      attr: "#{prefix}line_align", values: "left right center"
    @baseline = new Enum
      obj: obj
      attr: "#{prefix}line_baseline"
      values: "top middle bottom alphabetic hanging"

  warm_cache: (source) ->
    super(source, ["color", "alpha", "align", "baseline"])
    if (@font.fixed_value? and @font_size.fixed_value? and
        @font_style.fixed_value?)
      @cache["font"] = @font_value()
    else
      @cache["font_array"] = @font_array(source)

  cache_select: (name, i) ->
    if name == "font"
      if @font.value? and @font_size.value? and @font_style.value?
        @cache.font = @font_value()
      else
        @cache.font = @cache.font_array[i]
      return
    super(name, i)

  font_value: () ->
    font       = @font.value()
    font_size  = @font_size.value()
    font_style = @font_style.value()
    return font_style + " " + font_size + " " + font

  font_array: (source) ->
    font       = @font.array(source)
    font_size  = @font_size.array(source)
    font_style = @font_style.array(source)
    result = []
    for i in [0...font.length]
      result.push(font_style[i] + " " + font_size[i] + " " + font[i])
    return result

  set_value: (ctx) ->
    ctx.font         = @font()
    ctx.fillStyle    = @color.value()
    ctx.globalAlpha  = @alpha.value()
    ctx.textAlign    = @align.value()
    ctx.textBaseline = @baseline.value()

  set_vectorize: (ctx, i) ->
    if ctx.font != @cache.font
      @cache_select("font", i)
      ctx.font = @cache.font

    if ctx.fillStyle != @cache.color
      @cache_select("color", i)
      ctx.fillStyle = @cache.color

    if ctx.globalAlpha != @cache.alpha
      @cache_select("alpha", i)
      ctx.globalAlpha = @cache.alpha

    if ctx.textAlign != @cache.align
      @cache_select("align", i)
      ctx.textAlign = @cache.align

    if ctx.textBaseline != @cache.baseline
      @cache_select("baseline", i)
      ctx.textBaseline = @cache.baseline

#
# convenience factory functions
#

angles = (model, attr="angles") ->
  result = {}
  for angle in model[attr]
    result[angle] = new Angle({obj: model, attr: angle})
  return result

coords = (model, attr="coords") ->
  result = {}
  for [x, y] in model[attr]
    result[x] = new Coord({obj: model, attr: x})
    result[y] = new Coord({obj: model, attr: y})
  return result

distances = (model, attr="distances") ->
  result = {}

  for dist in model[attr]

    if dist[0] == "?"
      dist = dist[1...]
      if not model.get(dist)?
        continue

    result[dist] = new Distance({obj: model, attr: dist})

  return result

fields = (model, attr="fields") ->
  result = {}

  for field in model[attr]
    type = "number"

    if field.indexOf(":") > -1
      [field, type, arg] = field.split(":")

    if field[0] == "?"
      field = field[1...]
      if not model.attributes[field]?
        continue

    switch type
      when "array" then result[field] = new Array({obj: model, attr: field})
      when "bool" then result[field] = new Boolean({obj: model, attr: field})
      when "color" then result[field] = new Color({obj: model, attr: field})
      when "direction"
        result[field] = new Direction({obj: model, attr: field})
      when "enum"
        result[field] = new Enum({obj: model, attr: field, values:arg})
      when "number" then result[field] = new Numeric({obj: model, attr: field})
      when "string" then result[field] = new String({obj: model, attr: field})

  return result


visuals = (model, attr="visuals") ->
  result = {}
  for prop in model[attr]
    prefix = ""
    if prop.indexOf(":") > -1
      [prop, prefix] = prop.split(":")
    name = "#{prefix}#{prop}"
    switch prop
      when "line" then result[name] = new Line({obj: model, prefix: prefix})
      when "fill" then result[name] = new Fill({obj: model, prefix: prefix})
      when "text" then result[name] = new Text({obj: model, prefix: prefix})
  return result

module.exports =
  Angle: Angle
  Array: Array
  Bool: Bool
  Color: Color
  Coord: Coord
  Direction: Direction
  Distance: Distance
  Enum: Enum
  Numeric: Numeric
  String: String

  Line: Line
  Fill: Fill
  Text: Text

  factories:
    coords: coords
    distances: distances
    angles: angles
    fields: fields
    visuals: visuals