#!/usr/bin/env ruby

require 'pathname'
require 'json'
require 'strscan'
require 'pathname'

class Param
  def initialize(dir)
    @dir = Pathname.new(dir)
    @macro = {}
    @var = {}
    @def = {}
    @param = {}
  end

  def run
    read_macro
    extract_all_macro
    retrieve_param
    to_json
  end

  def read_macro
    [
      "util/sys_defs.h",
      "global/mail_addr.h",
      "global/mail_proto.h",
      "global/server_acl.h",
      "global/mail_conf.h",
      "global/mail_params.h",
      "global/mail_version.h"
    ].each do |f|
      begin
        (@dir+"src/#{f}").read.gsub(/\/\*.*?\*\//m, '').scan(/^[ \t]*\#define(?:\\[\s\S]|.)*\n/) do |line|
          parse_macro line.gsub(/\\\n/, '')
        end
      rescue Errno::ENOENT
        # ignore
      end
    end
  end

  def parse_macro(line)
    if line.chomp =~ /\A#define\s+([A-Za-z0-9_]+)\s+(.+?)(\s*\/\*.*\*\/)?\z/
      n, v = $1, $2
      if @macro.key? n
        @macro[n].push v
        @macro[n].uniq!
      else
        @macro[n] = [v]
      end
    end
  end

  def extract_all_macro
    @macro.each do |k, v|
      @var[k] = extract_macro(k) if k =~ /\AVAR_/
      @def[k] = extract_macro(k) if k =~ /\ADEF_/
    end
  end

  def extract_macro(name)
    values = extract_macro_sub(name).uniq
    if values.size == 1
      values[0]
    else
      values
    end
  end

  def extract_macro_sub(name)
    unless @macro.key? name
      raise "undefined macro: #{name}"
    end
    if @macro[name].size == 1
      extract_value(@macro[name][0])
    else
      @macro[name].map{|_| extract_value(_)}.flatten
    end
  end

  def extract_value(value)
    val = []
    ss = StringScanner.new(value)
    until ss.eos?
      case
      when ss.scan(/\"(([^\"]|\\.)*)\"/)
        val.push [ss[1]]
      when ss.scan(/\'(.)\'/)
        val.push [ss[1].ord]
      when ss.scan(/(\d+)(?=\W|\z)/)
        val.push [ss[1].to_i]
      when ss.scan(/\s+/)
        nil # skip
      when ss.scan(/\w+/)
        val.push @macro.key?(ss[0]) ? extract_macro_sub(ss[0]) : [ss[0]]
      else
        val.push [ss.scan(/./)]
      end
    end
    [''].product(*val).map(&:join)
  end

  Parameter = Struct.new(:name, :type, :default, :min, :max)

  def retrieve_param
    ((@dir+'src/postconf/install_table.h').read.split(/[,\s]+/)-['']).each_slice(5) do |a|
      name, default, _, min, max = a
      next unless @var[name]
      @param[@var[name]] = Parameter.new(@var[name], 'STR', @def[default], min&.to_i, max&.to_i)
    end

    @dir.glob('src/*/*.c').each do |fname|
      c = File.read(fname).gsub(/\/\*.*?\*\//m, '')
      c.gsub!(/^#.*\n/, '')
      c.scan(/^ *(?:static +)?(?:const +)?CONFIG_([0-9A-Z_]+)_TABLE.*?\{(.*?)\}/m) do |type, values|
        cnt = type == 'BOOL' || type == 'NBOOL' ? 3 : 5
        (values.split(/[,\s]+/)-['']).each_slice(cnt) do |a|
          break if a == ['0']
          name, default, _, min, max = a
          next unless @var[name]
          @param[@var[name]] = Parameter.new(@var[name], type, @def[default], min&.to_i, max&.to_i)
        end
      end
    end
  end

  def to_json
    JSON.pretty_generate( @param.map do |_, p|
      [p.name, {type: p.type, default: p.default, min: p.min, max: p.max}]
    end.sort.to_h )
  end
end

dir, = ARGV
puts Param.new(dir).run
