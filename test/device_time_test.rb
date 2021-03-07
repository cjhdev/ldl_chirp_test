require 'minitest'
require "minitest/spec"
require 'ldl'

describe "device time" do

  region = :EU_863_870

  let(:gps_epoch){Time.new(1980,1,6).utc.to_i}
  let(:gps_utc_offset){18}  # will break at next leap second update

  let(:time_now){Time.now.utc}


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

    def device_time_to_utc(second, fraction)
      Time.at((second + gps_epoch - gps_utc_offset).to_f + (fraction.to_f / 255.0))
    end

    describe "get device time" do

      let(:result){ TimeoutQueue.new }

      before do
        scenario.device.on_device_time do |obj|
          result.push(obj)
        end
      end

      it "shall complete" do

        scenario.device.unconfirmed("", time: true)

        value = result.pop(timeout: 0)

        expected = time_now
        actual = device_time_to_utc(value[:seconds], value[:fractions])
        difference = (actual > expected) ? (actual-expected) : (expected-actual)

        puts "expected: #{expected.to_f}"
        puts "actual: #{actual.to_f}"
        puts "difference: #{difference}"

        # ruby has too much jitter to test anything closer than the same
        # second, and even this fails sometimes.
        #
        # +/- 20ms is reported to have been achieved on real hardware.
        #
        assert ((expected-1.0) .. (expected+1.0)).include?(actual), "#{difference} > 0.5"

      end

    end

  end



end
