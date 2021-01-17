require 'minitest'
require "minitest/spec"
require 'ldl'

describe "confirmed" do

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

      describe "unconfirmed downlink" do

        let(:msg){ SecureRandom.bytes(5) }
        let(:port){ rand(1..100) }

        let(:result){ TimeoutQueue.new }

        before do
          scenario.device.on_rx { |params| result.push(params) }
        end

        after do
        end

        it "shall complete" do

          $cs.send_downlink(scenario, msg, port: port)

          scenario.device.unconfirmed port, ""

          r = result.pop(timeout: 0)

          assert r[:data] == msg
          assert r[:port] == port

        end

        it "does not retry if lost" do

          $cs.send_downlink(scenario, msg, port: port)
          scenario.gw.reliability = [0,1]

          scenario.device.unconfirmed port, ""

          assert_raises ThreadError do
            result.pop(timeout: 0)
          end

          scenario.device.unconfirmed port, ""

          assert_raises ThreadError do
            result.pop(timeout: 0)
          end

        end

      end

      describe "confirmed downlink" do

        let(:msg){ SecureRandom.bytes(5) }
        let(:port){ rand(1..100) }

        let(:result){ TimeoutQueue.new }

        before do
          scenario.device.on_rx { |params| result.push(params) }
        end

        after do
        end

        it "shall complete" do

          $cs.send_downlink(scenario, msg, port: port, confirmed: true)

          scenario.device.unconfirmed port, ""

          r = result.pop(timeout: 0)

          assert r[:data] == msg
          assert r[:port] == port

        end

        it "retry if lost" do

          $cs.send_downlink(scenario, msg, port: port, confirmed: true)
          scenario.gw.reliability = [0,1]

          scenario.device.unconfirmed port, ""

          assert_raises ThreadError do
            result.pop(timeout: 0)
          end

          scenario.device.unconfirmed port, ""

          r = result.pop(timeout: 0)

          assert r[:data] == msg
          assert r[:port] == port

        end

      end

    end

  end

end
