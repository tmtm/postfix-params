require 'pathname'
require 'json'

dir = Pathname.new(__dir__)+'../json'
vers = dir.glob("[1-9]*.json").map {|f| f.basename('.json').to_s}.
         sort_by{|ver| ver.split('.').map(&:to_i) }
File.write(dir+'versions.json', {versions: vers}.to_json)
