require 'minitest'
require "minitest/spec"
require 'ldl'

describe "otaa timing" do

  $regions.each do |region|

    describe(region) do

      let(:dither){0}
      let(:scenario){ LDL::Scenario.new(logger: $logger, region: region, otaa_dither: dither, port: $port) }

      before do

        $cs.add_scenario(scenario)
        scenario.start

      end

      after do

        scenario.stop
        $cs.remove_scenario(scenario)

      end

      describe "join without dither" do

        before do
          scenario.device.reliability = 0
        end

        after do
          scenario.device.reliability = nil
        end

        it "does does not exceed duty cycle of 0.01 in first 60 seconds" do

          timeout = 60

          assert_raises ThreadError do
            scenario.device.otaa(timeout: timeout)
          end

          log = scenario.device.tx_log.get

          assert log.size > 2

          total_time = log.last[:time] - log.first[:time]

          # drop the last item to get true on-time vs off-time regardless
          # of the point we stop otaa
          log.pop

          tx_time = log.inject(0){|result, item| result += item[:air_time]}

          duty_cycle = tx_time/total_time

          assert duty_cycle <= 0.01, "actual duty cycle #{duty_cycle}"

        end

      end

    end

  end

end
