# -*- encoding: us-ascii -*-

class String
  def self.allocate
    str = super()
    str.__data__ = Rubinius::ByteArray.new(1)
    str.num_bytes = 0
    str.force_encoding(Encoding::BINARY)
    str
  end

  def self.try_convert(obj)
    Rubinius::Type.try_convert obj, String, :to_str
  end

  def codepoints
    return to_enum :codepoints unless block_given?

    chars { |c| yield c.ord }
    self
  end

  alias_method :each_codepoint, :codepoints

  def encode!(to=undefined, from=undefined, options=nil)
    Rubinius.check_frozen

    # TODO
    if to.equal? undefined
      to = Encoding.default_internal
    else
      to = Rubinius::Type.coerce_to_encoding to
    end

    force_encoding to
    self
  end

  def encode(to=undefined, from=undefined, options=nil)
    dup.encode!(to, from, options)
  end

  def force_encoding(enc)
    @ascii_only = @valid_encoding = nil
    @encoding = Rubinius::Type.coerce_to_encoding enc
    self
  end

  def prepend(other)
    self[0,0] = other
    self
  end

  def upto(stop, exclusive=false)
    return to_enum :upto, stop, exclusive unless block_given?
    stop = StringValue(stop)
    return self if self > stop

    if stop.size == 1 && size == 1
      after_stop = stop.getbyte(0) + (exclusive ? 0 : 1)
      current = getbyte(0)
      until current == after_stop
        yield current.chr
        current += 1
      end
    else
      unless stop.size < size
        after_stop = exclusive ? stop : stop.succ
        current = self

        until current == after_stop
          yield current
          current = StringValue(current.succ)
          break if current.size > stop.size || current.size == 0
        end
      end
    end
    self
  end

  # Reverses <i>self</i> in place.
  def reverse!
    Rubinius.check_frozen

    return self if @num_bytes <= 1
    self.modify!

    @data.reverse(0, @num_bytes)
    self
  end

  # Squeezes <i>self</i> in place, returning either <i>self</i>, or
  # <code>nil</code> if no changes were made.
  def squeeze!(*strings)
    if strings.first =~ /.+\-.+/
      range = strings.first.gsub(/-/, '').split('')
      raise ArgumentError, "invalid range #{strings} in string transliteration" unless range == range.sort
    end

    return if @num_bytes == 0
    self.modify!

    table = count_table(*strings).__data__

    i, j, last = 1, 0, @data[0]
    while i < @num_bytes
      c = @data[i]
      unless c == last and table[c] == 1
        @data[j+=1] = last = c
      end
      i += 1
    end

    if (j += 1) < @num_bytes
      self.num_bytes = j
      self
    else
      nil
    end
  end

  # Performs the substitutions of <code>String#sub</code> in place,
  # returning <i>self</i>, or <code>nil</code> if no substitutions were
  # performed.
  #
  def sub!(pattern, replacement=undefined)
    # Copied mostly from sub to keep Regexp.last_match= working right.

    if replacement.equal?(undefined) and !block_given?
      raise ArgumentError, "wrong number of arguments (1 for 2)"
    end

    unless pattern
      raise ArgumentError, "wrong number of arguments (0 for 2)"
    end

    Rubinius.check_frozen

    if match = get_pattern(pattern, true).match_from(self, 0)
      out = match.pre_match

      Regexp.last_match = match

      if replacement.equal?(undefined)
        replacement = yield(match[0].dup).to_s
        out.taint if replacement.tainted?
        out.append(replacement).append(match.post_match)
      else
        out.taint if replacement.tainted?
        replacement = StringValue(replacement).to_sub_replacement(out, match)
        out.append(match.post_match)
      end

      # We have to reset it again to match the specs
      Regexp.last_match = match

      out.taint if self.tainted?
    else
      out = self
      Regexp.last_match = nil
      return nil
    end

    replace(out)

    return self
  end

  # Deletes the specified portion from <i>self</i>, and returns the portion
  # deleted. The forms that take a <code>Fixnum</code> will raise an
  # <code>IndexError</code> if the value is out of range; the <code>Range</code>
  # form will raise a <code>RangeError</code>, and the <code>Regexp</code> and
  # <code>String</code> forms will silently ignore the assignment.
  #
  #   string = "this is a string"
  #   string.slice!(2)        #=> 105
  #   string.slice!(3..6)     #=> " is "
  #   string.slice!(/s.*t/)   #=> "sa st"
  #   string.slice!("r")      #=> "r"
  #   string                  #=> "thing"
  def slice!(one, two=undefined)
    Rubinius.check_frozen
    # This is un-DRY, but it's a simple manual argument splitting. Keeps
    # the code fast and clean since the sequence are pretty short.
    #
    if two.equal?(undefined)
      result = slice(one)

      if one.kind_of? Regexp
        lm = Regexp.last_match
        self[one] = '' if result
        Regexp.last_match = lm
      else
        self[one] = '' if result
      end
    else
      result = slice(one, two)

      if one.kind_of? Regexp
        lm = Regexp.last_match
        self[one, two] = '' if result
        Regexp.last_match = lm
      else
        self[one, two] = '' if result
      end
    end

    result
  end

  # Equivalent to <code>String#succ</code>, but modifies the receiver in
  # place.
  #
  # TODO: make encoding aware.
  def succ!
    self.modify!

    return self if @num_bytes == 0

    carry = nil
    last_alnum = 0
    start = @num_bytes - 1

    ctype = Rubinius::CType

    while start >= 0
      s = @data[start]
      if ctype.isalnum(s)
        carry = 0
        if (48 <= s && s < 57) ||
           (97 <= s && s < 122) ||
           (65 <= s && s < 90)
          @data[start] += 1
        elsif s == 57
          @data[start] = 48
          carry = 49
        elsif s == 122
          @data[start] = carry = 97
        elsif s == 90
          @data[start] = carry = 65
        end

        break if carry == 0
        last_alnum = start
      end

      start -= 1
    end

    if carry.nil?
      start = length - 1
      carry = 1

      while start >= 0
        if @data[start] >= 255
          @data[start] = 0
        else
          @data[start] += 1
          break
        end

        start -= 1
      end
    end

    if start < 0
      splice! last_alnum, 1, carry.chr + @data[last_alnum].chr
    end

    return self
  end

  alias_method :next, :succ
  alias_method :next!, :succ!

  def to_c
    Complexifier.new(self).convert
  end

  def to_r
    Rationalizer.new(self).convert
  end

  ##
  #  call-seq:
  #     str.unpack(format)   => anArray
  #
  #  Decodes <i>str</i> (which may contain binary data) according to
  #  the format string, returning an array of each value
  #  extracted. The format string consists of a sequence of
  #  single-character directives, summarized in the table at the end
  #  of this entry.
  #
  #  Each directive may be followed by a number, indicating the number
  #  of times to repeat with this directive. An asterisk
  #  (``<code>*</code>'') will use up all remaining elements. The
  #  directives <code>sSiIlL</code> may each be followed by an
  #  underscore (``<code>_</code>'') to use the underlying platform's
  #  native size for the specified type; otherwise, it uses a
  #  platform-independent consistent size. Spaces are ignored in the
  #  format string. See also <code>Array#pack</code>.
  #
  #     "abc \0\0abc \0\0".unpack('A6Z6')   #=> ["abc", "abc "]
  #     "abc \0\0".unpack('a3a3')           #=> ["abc", " \000\000"]
  #     "abc \0abc \0".unpack('Z*Z*')       #=> ["abc ", "abc "]
  #     "aa".unpack('b8B8')                 #=> ["10000110", "01100001"]
  #     "aaa".unpack('h2H2c')               #=> ["16", "61", 97]
  #     "\xfe\xff\xfe\xff".unpack('sS')     #=> [-2, 65534]
  #     "now=20is".unpack('M*')             #=> ["now is"]
  #     "whole".unpack('xax2aX2aX1aX2a')    #=> ["h", "e", "l", "l", "o"]
  #
  #  This table summarizes the various formats and the Ruby classes
  #  returned by each.
  #
  #     Format | Returns | Function
  #     -------+---------+-----------------------------------------
  #       A    | String  | with trailing nulls and spaces removed
  #     -------+---------+-----------------------------------------
  #       a    | String  | string
  #     -------+---------+-----------------------------------------
  #       B    | String  | extract bits from each character (msb first)
  #     -------+---------+-----------------------------------------
  #       b    | String  | extract bits from each character (lsb first)
  #     -------+---------+-----------------------------------------
  #       C    | Fixnum  | extract a character as an unsigned integer
  #     -------+---------+-----------------------------------------
  #       c    | Fixnum  | extract a character as an integer
  #     -------+---------+-----------------------------------------
  #       d,D  | Float   | treat sizeof(double) characters as
  #            |         | a native double
  #     -------+---------+-----------------------------------------
  #       E    | Float   | treat sizeof(double) characters as
  #            |         | a double in little-endian byte order
  #     -------+---------+-----------------------------------------
  #       e    | Float   | treat sizeof(float) characters as
  #            |         | a float in little-endian byte order
  #     -------+---------+-----------------------------------------
  #       f,F  | Float   | treat sizeof(float) characters as
  #            |         | a native float
  #     -------+---------+-----------------------------------------
  #       G    | Float   | treat sizeof(double) characters as
  #            |         | a double in network byte order
  #     -------+---------+-----------------------------------------
  #       g    | Float   | treat sizeof(float) characters as a
  #            |         | float in network byte order
  #     -------+---------+-----------------------------------------
  #       H    | String  | extract hex nibbles from each character
  #            |         | (most significant first)
  #     -------+---------+-----------------------------------------
  #       h    | String  | extract hex nibbles from each character
  #            |         | (least significant first)
  #     -------+---------+-----------------------------------------
  #       I    | Integer | treat sizeof(int) (modified by _)
  #            |         | successive characters as an unsigned
  #            |         | native integer
  #     -------+---------+-----------------------------------------
  #       i    | Integer | treat sizeof(int) (modified by _)
  #            |         | successive characters as a signed
  #            |         | native integer
  #     -------+---------+-----------------------------------------
  #       L    | Integer | treat four (modified by _) successive
  #            |         | characters as an unsigned native
  #            |         | long integer
  #     -------+---------+-----------------------------------------
  #       l    | Integer | treat four (modified by _) successive
  #            |         | characters as a signed native
  #            |         | long integer
  #     -------+---------+-----------------------------------------
  #       M    | String  | quoted-printable
  #     -------+---------+-----------------------------------------
  #       m    | String  | base64-encoded
  #     -------+---------+-----------------------------------------
  #       N    | Integer | treat four characters as an unsigned
  #            |         | long in network byte order
  #     -------+---------+-----------------------------------------
  #       n    | Fixnum  | treat two characters as an unsigned
  #            |         | short in network byte order
  #     -------+---------+-----------------------------------------
  #       P    | String  | treat sizeof(char *) characters as a
  #            |         | pointer, and  return \emph{len} characters
  #            |         | from the referenced location
  #     -------+---------+-----------------------------------------
  #       p    | String  | treat sizeof(char *) characters as a
  #            |         | pointer to a  null-terminated string
  #     -------+---------+-----------------------------------------
  #       Q    | Integer | treat 8 characters as an unsigned
  #            |         | quad word (64 bits)
  #     -------+---------+-----------------------------------------
  #       q    | Integer | treat 8 characters as a signed
  #            |         | quad word (64 bits)
  #     -------+---------+-----------------------------------------
  #       S    | Fixnum  | treat two (different if _ used)
  #            |         | successive characters as an unsigned
  #            |         | short in native byte order
  #     -------+---------+-----------------------------------------
  #       s    | Fixnum  | Treat two (different if _ used)
  #            |         | successive characters as a signed short
  #            |         | in native byte order
  #     -------+---------+-----------------------------------------
  #       U    | Integer | UTF-8 characters as unsigned integers
  #     -------+---------+-----------------------------------------
  #       u    | String  | UU-encoded
  #     -------+---------+-----------------------------------------
  #       V    | Fixnum  | treat four characters as an unsigned
  #            |         | long in little-endian byte order
  #     -------+---------+-----------------------------------------
  #       v    | Fixnum  | treat two characters as an unsigned
  #            |         | short in little-endian byte order
  #     -------+---------+-----------------------------------------
  #       w    | Integer | BER-compressed integer (see Array.pack)
  #     -------+---------+-----------------------------------------
  #       X    | ---     | skip backward one character
  #     -------+---------+-----------------------------------------
  #       x    | ---     | skip forward one character
  #     -------+---------+-----------------------------------------
  #       Z    | String  | with trailing nulls removed
  #            |         | upto first null with *
  #     -------+---------+-----------------------------------------
  #       @    | ---     | skip to the offset given by the
  #            |         | length argument
  #     -------+---------+-----------------------------------------

  def unpack(directives)
    Rubinius.primitive :string_unpack19

    unless directives.kind_of? String
      return unpack(StringValue(directives))
    end

    raise ArgumentError, "invalid directives string: #{directives}"
  end

  # Removes trailing whitespace from <i>self</i>, returning <code>nil</code> if
  # no change was made. See also <code>String#lstrip!</code> and
  # <code>String#strip!</code>.
  #
  #   "  hello  ".rstrip   #=> "  hello"
  #   "hello".rstrip!      #=> nil
  def rstrip!
    Rubinius.check_frozen
    return if @num_bytes == 0

    stop = @num_bytes - 1

    ctype = Rubinius::CType

    while stop >= 0 && (@data[stop] == 0 || ctype.isspace(@data[stop]))
      stop -= 1
    end

    return if (stop += 1) == @num_bytes

    modify!
    self.num_bytes = stop
    self
  end

  # Removes leading whitespace from <i>self</i>, returning <code>nil</code> if no
  # change was made. See also <code>String#rstrip!</code> and
  # <code>String#strip!</code>.
  #
  #   "  hello  ".lstrip   #=> "hello  "
  #   "hello".lstrip!      #=> nil
  def lstrip!
    Rubinius.check_frozen
    return if @num_bytes == 0

    start = 0

    ctype = Rubinius::CType

    while start < @num_bytes && ctype.isspace(@data[start])
      start += 1
    end

    return if start == 0

    modify!
    self.num_bytes -= start
    @data.move_bytes start, @num_bytes, 0
    self
  end

  # Processes <i>self</i> as for <code>String#chop</code>, returning <i>self</i>,
  # or <code>nil</code> if <i>self</i> is the empty string.  See also
  # <code>String#chomp!</code>.
  def chop!
    Rubinius.check_frozen
    return if @num_bytes == 0

    self.modify!

    if @num_bytes > 1 and
        @data[@num_bytes-1] == 10 and @data[@num_bytes-2] == 13
      self.num_bytes -= 2
    else
      self.num_bytes -= 1
    end

    self
  end

  # Modifies <i>self</i> in place as described for <code>String#chomp</code>,
  # returning <i>self</i>, or <code>nil</code> if no modifications were made.
  #---
  # NOTE: TypeError is raised in String#replace and not in String#chomp! when
  # self is frozen. This is intended behaviour.
  #+++
  def chomp!(sep=undefined)
    Rubinius.check_frozen

    # special case for performance. No seperator is by far the most common usage.
    if sep.equal?(undefined)
      return if @num_bytes == 0

      c = @data[@num_bytes-1]
      if c == 10 # ?\n
        self.num_bytes -= 1 if @num_bytes > 1 && @data[@num_bytes-2] == 13 # ?\r
      elsif c != 13 # ?\r
        return
      end

      # don't use modify! because it will dup the data when we don't need to.
      @hash_value = nil
      self.num_bytes -= 1
      return self
    end

    return if sep.nil? || @num_bytes == 0
    sep = StringValue sep

    if (sep == $/ && sep == DEFAULT_RECORD_SEPARATOR) || sep == "\n"
      c = @data[@num_bytes-1]
      if c == 10 # ?\n
        self.num_bytes -= 1 if @num_bytes > 1 && @data[@num_bytes-2] == 13 # ?\r
      elsif c != 13 # ?\r
        return
      end

      # don't use modify! because it will dup the data when we don't need to.
      @hash_value = nil
      self.num_bytes -= 1
    elsif sep.size == 0
      size = @num_bytes
      while size > 0 && @data[size-1] == 10 # ?\n
        if size > 1 && @data[size-2] == 13 # ?\r
          size -= 2
        else
          size -= 1
        end
      end

      return if size == @num_bytes

      # don't use modify! because it will dup the data when we don't need to.
      @hash_value = nil
      self.num_bytes = size
    else
      size = sep.size
      return if size > @num_bytes || sep.compare_substring(self, -size, size) != 0

      # don't use modify! because it will dup the data when we don't need to.
      @hash_value = nil
      self.num_bytes -= size
    end

    return self
  end

  # Replaces the contents and taintedness of <i>string</i> with the corresponding
  # values in <i>other</i>.
  #
  #   s = "hello"         #=> "hello"
  #   s.replace "world"   #=> "world"
  def replace(other)
    Rubinius.check_frozen

    # If we're replacing with ourselves, then we have nothing to do
    return self if equal?(other)

    other = StringValue(other)

    @shared = true
    other.shared!
    @data = other.__data__
    self.num_bytes = other.num_bytes
    @hash_value = nil
    force_encoding(other.encoding)

    Rubinius::Type.infect(self, other)
  end
  alias_method :initialize_copy, :replace
  # private :initialize_copy

  def <<(other)
    modify!

    if other.kind_of? Integer
      if encoding == Encoding::US_ASCII and other >= 128 and other < 256
        force_encoding(Encoding::ASCII_8BIT)
      end

      other = other.chr(encoding)
    end
    unless other.kind_of? String
      other = StringValue(other)
    end

    unless other.encoding == encoding
      enc = Rubinius::Type.compatible_encoding self, other
      force_encoding enc
    end

    Rubinius::Type.infect(self, other)
    append(other)
  end
  alias_method :concat, :<<

  # Returns a one-character string at the beginning of the string.
  #
  #   a = "abcde"
  #   a.chr    #=> "a"
  def chr
    substring 0, 1
  end

  # Splits <i>self</i> using the supplied parameter as the record separator
  # (<code>$/</code> by default), passing each substring in turn to the supplied
  # block. If a zero-length record separator is supplied, the string is split on
  # <code>\n</code> characters, except that multiple successive newlines are
  # appended together.
  #
  #   print "Example one\n"
  #   "hello\nworld".each { |s| p s }
  #   print "Example two\n"
  #   "hello\nworld".each('l') { |s| p s }
  #   print "Example three\n"
  #   "hello\n\n\nworld".each('') { |s| p s }
  #
  # <em>produces:</em>
  #
  #   Example one
  #   "hello\n"
  #   "world"
  #   Example two
  #   "hel"
  #   "l"
  #   "o\nworl"
  #   "d"
  #   Example three
  #   "hello\n\n\n"
  #   "world"
  def lines(sep=$/)
    return to_enum(:lines, sep) unless block_given?

    # weird edge case.
    if sep.nil?
      yield self
      return self
    end

    sep = StringValue(sep)

    pos = 0

    size = @num_bytes
    orig_data = @data

    # If the separator is empty, we're actually in paragraph mode. This
    # is used so infrequently, we'll handle it completely separately from
    # normal line breaking.
    if sep.empty?
      sep = "\n\n"
      pat_size = 2

      while pos < size
        nxt = find_string(sep, pos)
        break unless nxt

        while @data[nxt] == 10 and nxt < @num_bytes
          nxt += 1
        end

        match_size = nxt - pos

        # string ends with \n's
        break if pos == @num_bytes

        str = byteslice pos, match_size
        yield str unless str.empty?

        # detect mutation within the block
        if !@data.equal?(orig_data) or @num_bytes != size
          raise RuntimeError, "string modified while iterating"
        end

        pos = nxt
      end

      # No more separates, but we need to grab the last part still.
      fin = byteslice pos, @num_bytes - pos
      yield fin if fin and !fin.empty?

    else

      # This is the normal case.
      pat_size = sep.size
      unmodified_self = clone

      while pos < size
        nxt = unmodified_self.find_string(sep, pos)
        break unless nxt

        match_size = nxt - pos
        str = unmodified_self.byteslice pos, match_size + pat_size
        yield str unless str.empty?

        pos = nxt + pat_size
      end

      # No more separates, but we need to grab the last part still.
      fin = unmodified_self.byteslice pos, @num_bytes - pos
      yield fin unless fin.empty?
    end

    self
  end

  alias_method :each_line, :lines

  # Returns a copy of <i>self</i> with <em>all</em> occurrences of <i>pattern</i>
  # replaced with either <i>replacement</i> or the value of the block. The
  # <i>pattern</i> will typically be a <code>Regexp</code>; if it is a
  # <code>String</code> then no regular expression metacharacters will be
  # interpreted (that is <code>/\d/</code> will match a digit, but
  # <code>'\d'</code> will match a backslash followed by a 'd').
  #
  # If a string is used as the replacement, special variables from the match
  # (such as <code>$&</code> and <code>$1</code>) cannot be substituted into it,
  # as substitution into the string occurs before the pattern match
  # starts. However, the sequences <code>\1</code>, <code>\2</code>, and so on
  # may be used to interpolate successive groups in the match.
  #
  # In the block form, the current match string is passed in as a parameter, and
  # variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
  # <code>$&</code>, and <code>$'</code> will be set appropriately. The value
  # returned by the block will be substituted for the match on each call.
  #
  # The result inherits any tainting andd trustiness in the original string or any supplied
  # replacement string.
  #
  #   "hello".gsub(/[aeiou]/, '*')              #=> "h*ll*"
  #   "hello".gsub(/([aeiou])/, '<\1>')         #=> "h<e>ll<o>"
  #   "hello".gsub(/./) { |s| s[0].to_s + ' ' } #=> "104 101 108 108 111 "
  def gsub(pattern, replacement=undefined)
    unless block_given? or replacement != undefined
      return to_enum(:gsub, pattern, replacement)
    end

    tainted = false
    untrusted = untrusted?

    if replacement.equal?(undefined)
      use_yield = true
    else
      tainted = replacement.tainted?
      untrusted ||= replacement.untrusted?
      hash = Rubinius::Type.check_convert_type(replacement, Hash, :to_hash)
      replacement = StringValue(replacement) unless hash
      tainted ||= replacement.tainted?
      untrusted ||= replacement.untrusted?
      use_yield = false
    end

    pattern = get_pattern(pattern, true)
    orig_len = @num_bytes
    orig_data = @data

    last_end = 0
    offset = nil
    ret = byteslice 0, 0 # Empty string and string subclass

    last_match = nil
    match = pattern.match_from self, last_end

    if match
      ma_range = match.full
      ma_start = ma_range.at(0)
      ma_end   = ma_range.at(1)

      offset = ma_start
    end

    while match
      nd = ma_start - 1
      pre_len = nd-last_end+1

      if pre_len > 0
        ret.append byteslice(last_end, pre_len)
      end

      if use_yield || hash
        Regexp.last_match = match

        if use_yield
          val = yield match.to_s
        else
          val = hash[match.to_s]
        end
        untrusted = true if val.untrusted?
        val = val.to_s unless val.kind_of?(String)

        tainted ||= val.tainted?
        ret.append val

        if !@data.equal?(orig_data) or @num_bytes != orig_len
          raise RuntimeError, "string modified"
        end
      else
        replacement.to_sub_replacement(ret, match)
      end

      tainted ||= val.tainted?

      last_end = ma_end

      if ma_start == ma_end
        if char = find_character(offset)
          offset += char.bytesize
        else
          offset += 1
        end
      else
        offset = ma_end
      end

      last_match = match

      match = pattern.match_from self, offset
      break unless match

      ma_range = match.full
      ma_start = ma_range.at(0)
      ma_end   = ma_range.at(1)

      offset = ma_start
    end

    Regexp.last_match = last_match

    str = byteslice last_end, @num_bytes-last_end+1
    ret.append str if str

    ret.taint if tainted || self.tainted?
    ret.untrust if untrusted
    return ret
  end

  # Returns <i>self</i> with <em>all</em> occurrences of <i>pattern</i>
  # replaced with either <i>replacement</i> or the value of the block. The
  # <i>pattern</i> will typically be a <code>Regexp</code>; if it is a
  # <code>String</code> then no regular expression metacharacters will be
  # interpreted (that is <code>/\d/</code> will match a digit, but
  # <code>'\d'</code> will match a backslash followed by a 'd').
  #
  # If a string is used as the replacement, special variables from the match
  # (such as <code>$&</code> and <code>$1</code>) cannot be substituted into it,
  # as substitution into the string occurs before the pattern match
  # starts. However, the sequences <code>\1</code>, <code>\2</code>, and so on
  # may be used to interpolate successive groups in the match.
  #
  # In the block form, the current match string is passed in as a parameter, and
  # variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
  # <code>$&</code>, and <code>$'</code> will be set appropriately. The value
  # returned by the block will be substituted for the match on each call.
  #
  # The result inherits any tainting andd trustiness in any supplied
  # replacement string.
  #
  #   "hello".gsub!(/[aeiou]/, '*')              #=> "h*ll*"
  #   "hello".gsub!(/([aeiou])/, '<\1>')         #=> "h<e>ll<o>"
  #   "hello".gsub!(/./) { |s| s[0].to_s + ' ' } #=> "104 101 108 108 111 "
  def gsub!(pattern, replacement=undefined)
    unless block_given? or replacement != undefined
      return to_enum(:gsub, pattern, replacement)
    end

    Rubinius.check_frozen

    tainted = false
    untrusted = untrusted?

    if replacement.equal?(undefined)
      use_yield = true
    else
      tainted = replacement.tainted?
      untrusted ||= replacement.untrusted?
      hash = Rubinius::Type.check_convert_type(replacement, Hash, :to_hash)
      replacement = StringValue(replacement) unless hash
      tainted ||= replacement.tainted?
      untrusted ||= replacement.untrusted?
      use_yield = false
    end

    pattern = get_pattern(pattern, true)
    orig_len = @num_bytes
    orig_data = @data

    last_end = 0
    offset = nil
    ret = byteslice 0, 0 # Empty string and string subclass

    last_match = nil
    match = pattern.match_from self, last_end

    if match
      ma_range = match.full
      ma_start = ma_range.at(0)
      ma_end   = ma_range.at(1)

      offset = ma_start
    else
      Regexp.last_match = nil
      return nil
    end

    while match
      nd = ma_start - 1
      pre_len = nd-last_end+1

      if pre_len > 0
        ret.append byteslice(last_end, pre_len)
      end

      if use_yield || hash
        Regexp.last_match = match

        if use_yield
          val = yield match.to_s
        else
          val = hash[match.to_s]
        end
        untrusted = true if val.untrusted?
        val = val.to_s unless val.kind_of?(String)

        tainted ||= val.tainted?
        ret.append val

        if !@data.equal?(orig_data) or @num_bytes != orig_len
          raise RuntimeError, "string modified"
        end
      else
        replacement.to_sub_replacement(ret, match)
      end

      tainted ||= val.tainted?

      last_end = ma_end

      if ma_start == ma_end
        if char = find_character(offset)
          offset += char.bytesize
        else
          offset += 1
        end
      else
        offset = ma_end
      end

      last_match = match

      match = pattern.match_from self, offset
      break unless match

      ma_range = match.full
      ma_start = ma_range.at(0)
      ma_end   = ma_range.at(1)

      offset = ma_start
    end

    Regexp.last_match = last_match

    str = byteslice last_end, @num_bytes-last_end+1
    ret.append str if str

    self.taint if tainted
    self.untrust if untrusted

    replace(ret)
    return self
  end

  # Converts <i>pattern</i> to a <code>Regexp</code> (if it isn't already one),
  # then invokes its <code>match</code> method on <i>self</i>. If the second
  # parameter is present, it specifies the position in the <i>self</i> to
  # begin the search.
  #
  #   'hello'.match('(.)\1')      #=> #<MatchData:0x401b3d30>
  #   'hello'.match('(.)\1')[0]   #=> "ll"
  #   'hello'.match(/(.)\1/)[0]   #=> "ll"
  #   'hello'.match('xx')         #=> nil
  def match(pattern, pos=0)
    match_data = get_pattern(pattern).search_region(self, pos, @num_bytes, true)
    Regexp.last_match = match_data
    return match_data
  end

  # call-seq:
  #   str[fixnum] = fixnum
  #   str[fixnum] = new_str
  #   str[fixnum, fixnum] = new_str
  #   str[range] = aString
  #   str[regexp] = new_str
  #   str[regexp, fixnum] = new_str
  #   str[other_str] = new_str
  #
  # Element Assignment --- Replaces some or all of the content of <i>self</i>. The
  # portion of the string affected is determined using the same criteria as
  # <code>String#[]</code>. If the replacement string is not the same length as
  # the text it is replacing, the string will be adjusted accordingly. If the
  # regular expression or string is used as the index doesn't match a position
  # in the string, <code>IndexError</code> is raised. If the regular expression
  # form is used, the optional second <code>Fixnum</code> allows you to specify
  # which portion of the match to replace (effectively using the
  # <code>MatchData</code> indexing rules. The forms that take a
  # <code>Fixnum</code> will raise an <code>IndexError</code> if the value is
  # out of range; the <code>Range</code> form will raise a
  # <code>RangeError</code>, and the <code>Regexp</code> and <code>String</code>
  # forms will silently ignore the assignment.
  def []=(index, replacement, three=undefined)
    unless three.equal?(undefined)
      if index.kind_of? Regexp
        subpattern_set index,
                       Rubinius::Type.coerce_to(replacement, Integer, :to_int),
                       three
      else
        start = Rubinius::Type.coerce_to(index, Integer, :to_int)
        fin =   Rubinius::Type.coerce_to(replacement, Integer, :to_int)

        splice! start, fin, three
      end

      return three
    end

    case index
    when Fixnum
      # Handle this first because it's the most common.
      # This is duplicated from the else branch, but don't dry it up.
      if index < 0
        index += @num_bytes
        if index < 0 or index >= @num_bytes
          raise IndexError, "index #{index} out of string"
        end
      else
        raise IndexError, "index #{index} out of string" if index > @num_bytes
      end

      if replacement.kind_of?(Fixnum)
        modify!
        @data[index] = replacement
      else
        splice! index, 1, replacement
      end
    when Regexp
      subpattern_set index, 0, replacement
    when String
      unless start = self.index(index)
        raise IndexError, "string not matched"
      end

      splice! start, index.length, replacement
    when Range
      start   = Rubinius::Type.coerce_to(index.first, Integer, :to_int)
      length  = Rubinius::Type.coerce_to(index.last, Integer, :to_int)

      start += @num_bytes if start < 0

      return nil if start < 0 || start > @num_bytes

      length = @num_bytes if length > @num_bytes
      length += @num_bytes if length < 0
      length += 1 unless index.exclude_end?

      length = length - start
      length = 0 if length < 0

      splice! start, length, replacement
    else
      index = Rubinius::Type.coerce_to(index, Integer, :to_int)
      raise IndexError, "index #{index} out of string" if @num_bytes <= index

      if index < 0
        raise IndexError, "index #{index} out of string" if -index > @num_bytes
        index += @num_bytes
      end

      if replacement.kind_of?(Fixnum)
        modify!
        @data[index] = replacement
      else
        splice! index, 1, replacement
      end
    end
    return replacement
  end
end
