require 'minitest'
require 'chirpstack_api'
require 'securerandom'
require 'logger'
require 'ldl'
require_relative "chirpstack"

#require_relative 'confirmed'
#require_relative 'unconfirmed'
require_relative 'otaa'

puts Minitest::Runnable.runnables

$logger = Logger.new(STDOUT)
$logger.formatter = LDL::LOG_FORMATTER

ChirpStack.run(logger: $logger) do |cs|

  $cs = cs

  Minitest.run

end
