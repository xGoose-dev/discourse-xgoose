# frozen_string_literal: true
require "yaml"
files = Dir["{app,lib,db,config}/**/*.rb"] + ["plugin.rb"]
abort "Ruby syntax check failed" unless files.all? { |file| system(RbConfig.ruby, "-c", file, out: File::NULL) }
Dir["config/**/*.yml"].each { |file| YAML.load_file(file) }
puts "Ruby syntax and YAML checks passed"
