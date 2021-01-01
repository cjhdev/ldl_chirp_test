require 'minitest'
require 'chirpstack_api'
require 'securerandom'
require 'logger'
require 'ldl'
require_relative "chirpstack"

require_relative 'test/confirmed_test'
require_relative 'test/unconfirmed_test'
require_relative 'test/otaa_test'

puts Minitest::Runnable.runnables

$logger = Logger.new(STDOUT)
$logger.formatter = LDL::LOG_FORMATTER

ChirpStack.run(logger: $logger) do |cs|

  $cs = cs

  Minitest.run

end
