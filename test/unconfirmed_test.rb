require 'minitest'
require "minitest/spec"
require 'ldl'

describe "unconfirmed" do

  $regions.each do |region|

    describe(region) do

      let(:scenario){ LDL::Scenario.new(logger: $logger, otaa_dither: 0, region: region, port: $port) }

      before do

        $cs.add_scenario(scenario)
        scenario.start
        scenario.device.unlimited_duty_cycle = true
        scenario.device.otaa(timeout: 30)

      end

      after do

        scenario.stop
        $cs.remove_scenario(scenario)

      end

      describe "perfect reception" do

        let(:msg){ SecureRandom.bytes(rand(0..5)) }
        let(:port){ rand(1..100) }
        let(:result){ TimeoutQueue.new }
        let(:listener) do
          $cs.listen(scenario) do |value|
            result.push(value)
          end
        end

        before do
          listener
        end

        after do
          $cs.unlisten(listener)
        end

        it "shall complete" do

          scenario.device.unconfirmed(port, msg)
          value = result.pop(timeout: 0)

          assert_equal port, value[:port]
          assert_equal msg, value[:data]

        end

      end

      describe "drop first attempt" do

        # ensure the next packet disappears
        before do
          scenario.device.reliability = [0]
        end

        after do
          scenario.device.reliability = nil
        end

        it "shall complete after first attempt" do
          scenario.device.unconfirmed("hello world")
        end

        it "shall complete after second attempt" do
          scenario.device.unconfirmed("hello world", nbTrans: 2)
        end

      end

      describe "drop all attempts" do

        before do
          scenario.device.reliability = 0
        end

        after do
          scenario.device.reliability = nil
        end

        it "shall complete on first attempt" do
          scenario.device.unconfirmed("hello world")
        end

        it "shall complete after multiple attempts" do
          scenario.device.unconfirmed("hello world", nbTrans: 3)
        end

      end

    end

  end

end
