$:.unshift File.expand_path('../lib', __FILE__)
require 'dont-stall-my-process/version'

Gem::Specification.new do |s|
  s.name          = 'dont-stall-my-process'
  s.version       = DontStallMyProcess::VERSION
  s.license       = 'MIT'
  s.summary       = 'Fork/Watchdog jail your Ruby code and native extensions'
  s.description   = 'Executes code or native extensions in child processes and monitors their execution times'

  s.authors       = ['FlavourSys Technology GmbH']
  s.email         = 'technology@flavoursys.com'
  s.homepage      = 'http://github.com/flavoursys/dont-stall-my-process'

  s.require_paths = ['lib']
  s.files         = Dir.glob('lib/**/*.rb')
end
