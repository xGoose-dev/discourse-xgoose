# frozen_string_literal: true
require "yaml"
files = Dir["{app,lib,db,config}/**/*.rb"] + ["plugin.rb"]
unless files.all? { |file| system(RbConfig.ruby, "-c", file, out: File::NULL) }
  abort "Ruby syntax check failed"
end
Dir["config/**/*.yml"].each { |file| YAML.load_file(file) }
puts "Ruby syntax and YAML checks passed"
